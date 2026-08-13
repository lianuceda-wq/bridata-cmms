-- Bridata CMMS - generación automática de OT con Supabase Cron.
-- La UI mantiene un RPC manager; el cron usa un worker privado multi-tenant.

create extension if not exists pg_cron;

create table public.maintenance_automation_runs (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  generated_count integer not null default 0 check (generated_count >= 0),
  status text not null default 'running' check (status in ('running','success','failed')),
  error_message text,
  created_at timestamptz not null default now()
);

create index idx_maintenance_automation_runs_tenant_started
  on public.maintenance_automation_runs(tenant_id, started_at desc);

alter table public.maintenance_automation_runs enable row level security;

create policy maintenance_automation_runs_select
on public.maintenance_automation_runs
for select to authenticated
using (public.is_tenant_member(tenant_id));

revoke insert, update, delete on public.maintenance_automation_runs from authenticated, anon;
grant select on public.maintenance_automation_runs to authenticated;

-- Núcleo interno: serializa por tenant y genera una sola ocurrencia por estado/umbral.
create or replace function private.generate_due_work_orders_core(
  p_tenant_id uuid,
  p_as_of timestamptz default now()
)
returns integer
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_count integer := 0;
  v_row record;
  v_work_order_id uuid;
  v_code text;
  v_occurrence_key text;
begin
  -- Evita carreras entre cron, botón manual u otros workers del mismo tenant.
  perform pg_advisory_xact_lock(hashtextextended('bridata-wo:' || p_tenant_id::text, 0));

  for v_row in
    select
      s.id as schedule_state_id,
      s.plan_id,
      s.routine_id,
      s.next_due_at,
      s.next_due_meter,
      s.meter_id,
      pa.asset_id,
      a.code as asset_code,
      r.code as routine_code,
      r.name as routine_name,
      r.description as routine_description,
      r.maintenance_type,
      r.priority,
      r.trigger_type,
      r.lead_time_days,
      m.current_value as meter_current_value
    from public.maintenance_schedule_states s
    join public.maintenance_plan_assets pa
      on pa.tenant_id = s.tenant_id
     and pa.id = s.plan_asset_id
     and pa.active = true
    join public.assets a
      on a.tenant_id = pa.tenant_id
     and a.id = pa.asset_id
     and a.is_active = true
    join public.maintenance_routines r
      on r.tenant_id = s.tenant_id
     and r.id = s.routine_id
     and r.active = true
    join public.maintenance_plans p
      on p.tenant_id = s.tenant_id
     and p.id = s.plan_id
     and p.status = 'active'
    left join public.asset_meters m
      on m.tenant_id = s.tenant_id
     and m.id = s.meter_id
    where s.tenant_id = p_tenant_id
      and s.status = 'active'
      and (
        (r.trigger_type = 'calendar'
          and s.next_due_at is not null
          and s.next_due_at <= p_as_of + (r.lead_time_days * interval '1 day'))
        or
        (r.trigger_type = 'meter'
          and s.next_due_meter is not null
          and m.current_value >= s.next_due_meter)
      )
    order by coalesce(s.next_due_at, p_as_of), s.next_due_meter nulls last
  loop
    v_occurrence_key := case
      when v_row.trigger_type = 'calendar'
        then 'calendar:' || extract(epoch from v_row.next_due_at)::bigint::text
      else 'meter:' || trim(to_char(v_row.next_due_meter, 'FM999999999999990.9999'))
    end;

    if exists (
      select 1
      from public.work_orders wo
      where wo.tenant_id = p_tenant_id
        and wo.schedule_state_id = v_row.schedule_state_id
        and wo.occurrence_key = v_occurrence_key
    ) then
      continue;
    end if;

    v_code := private.next_work_order_code(p_tenant_id);

    insert into public.work_orders (
      tenant_id, asset_id, plan_id, routine_id, schedule_state_id,
      code, title, description, maintenance_type, priority,
      status, source, occurrence_key, scheduled_at, due_at, due_meter,
      generated_at, created_by
    ) values (
      p_tenant_id, v_row.asset_id, v_row.plan_id, v_row.routine_id,
      v_row.schedule_state_id, v_code,
      v_row.routine_code || ' · ' || v_row.routine_name || ' · ' || v_row.asset_code,
      v_row.routine_description, v_row.maintenance_type, v_row.priority,
      'planned', 'maintenance_plan', v_occurrence_key,
      coalesce(v_row.next_due_at, p_as_of), v_row.next_due_at,
      v_row.next_due_meter, now(), auth.uid()
    )
    returning id into v_work_order_id;

    insert into public.work_order_tasks (
      tenant_id, work_order_id, routine_task_id, sequence, title,
      instructions, estimated_minutes, mandatory, task_type,
      requires_evidence, measurement_unit, min_value, max_value
    )
    select
      t.tenant_id, v_work_order_id, t.id, t.sequence, t.title,
      t.instructions, t.estimated_minutes, t.mandatory, t.task_type,
      t.requires_evidence, t.measurement_unit, t.min_value, t.max_value
    from public.maintenance_routine_tasks t
    where t.tenant_id = p_tenant_id
      and t.routine_id = v_row.routine_id
    order by t.sequence;

    update public.maintenance_schedule_states
    set last_work_order_id = v_work_order_id,
        updated_at = now()
    where tenant_id = p_tenant_id
      and id = v_row.schedule_state_id;

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

revoke all on function private.generate_due_work_orders_core(uuid, timestamptz) from public, anon;
grant execute on function private.generate_due_work_orders_core(uuid, timestamptz) to authenticated, service_role;

-- RPC usado por la aplicación. Conserva autorización manager + RLS de sesión.
create or replace function public.generate_due_work_orders(
  p_tenant_id uuid,
  p_as_of timestamptz default now()
)
returns integer
language plpgsql
security invoker
set search_path = public, private, pg_temp
as $$
begin
  if coalesce(auth.role(), '') <> 'service_role'
     and not public.can_manage_tenant(p_tenant_id) then
    raise exception 'Insufficient permissions';
  end if;

  return private.generate_due_work_orders_core(p_tenant_id, p_as_of);
end;
$$;

revoke all on function public.generate_due_work_orders(uuid, timestamptz) from public, anon;
grant execute on function public.generate_due_work_orders(uuid, timestamptz) to authenticated, service_role;

-- Worker del cron. Aísla errores por tenant: un cliente defectuoso no bloquea a los demás.
create or replace function private.run_work_order_automation(
  p_as_of timestamptz default now()
)
returns integer
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_tenant record;
  v_run_id bigint;
  v_generated integer;
  v_total integer := 0;
begin
  for v_tenant in
    select id
    from public.tenants
    where status = 'active'
    order by id
  loop
    insert into public.maintenance_automation_runs (tenant_id, started_at, status)
    values (v_tenant.id, now(), 'running')
    returning id into v_run_id;

    begin
      v_generated := private.generate_due_work_orders_core(v_tenant.id, p_as_of);
      v_total := v_total + v_generated;

      update public.maintenance_automation_runs
      set completed_at = now(),
          generated_count = v_generated,
          status = 'success',
          error_message = null
      where id = v_run_id;
    exception when others then
      update public.maintenance_automation_runs
      set completed_at = now(),
          status = 'failed',
          error_message = left(sqlerrm, 1000)
      where id = v_run_id;
    end;
  end loop;

  return v_total;
end;
$$;

revoke all on function private.run_work_order_automation(timestamptz) from public, anon, authenticated;

-- Cada 5 minutos: latencia máxima razonable para planes calendario/medidor sin servidor adicional.
select cron.schedule(
  'bridata-generate-due-work-orders',
  '*/5 * * * *',
  $$ select private.run_work_order_automation(); $$
);
