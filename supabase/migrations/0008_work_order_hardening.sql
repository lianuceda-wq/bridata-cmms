-- Bridata CMMS - hardening del motor de OT.

-- Helper privado para secuencias: no queda expuesto por la API REST pública.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated, service_role;

create or replace function private.next_work_order_code(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_year text := to_char(current_date, 'YYYY');
  v_value bigint;
begin
  insert into public.tenant_sequences (tenant_id, sequence_key, value)
  values (p_tenant_id, 'work_order_' || v_year, 1)
  on conflict (tenant_id, sequence_key)
  do update set value = public.tenant_sequences.value + 1,
                updated_at = now()
  returning value into v_value;

  return 'OT-' || v_year || '-' || lpad(v_value::text, 6, '0');
end;
$$;

revoke all on function private.next_work_order_code(uuid) from public, anon;
grant execute on function private.next_work_order_code(uuid) to authenticated, service_role;

drop function if exists public.next_work_order_code(uuid);

-- Política explícita de denegación. La tabla además mantiene privileges revocados.
create policy tenant_sequences_deny_clients
on public.tenant_sequences
for all to authenticated
using (false)
with check (false);

-- El generador vuelve a SECURITY INVOKER: RLS se aplica al usuario que lo llama.
create or replace function public.generate_due_work_orders(
  p_tenant_id uuid,
  p_as_of timestamptz default now()
)
returns integer
language plpgsql
security invoker
set search_path = public, private, pg_temp
as $$
declare
  v_count integer := 0;
  v_row record;
  v_work_order_id uuid;
  v_code text;
  v_occurrence_key text;
begin
  if coalesce(auth.role(), '') <> 'service_role'
     and not public.can_manage_tenant(p_tenant_id) then
    raise exception 'Insufficient permissions';
  end if;

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
      select 1 from public.work_orders wo
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
    ) returning id into v_work_order_id;

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

revoke all on function public.generate_due_work_orders(uuid, timestamptz) from public, anon;
grant execute on function public.generate_due_work_orders(uuid, timestamptz) to authenticated, service_role;

-- Índices de cobertura de FKs detectados por el advisor.
create index if not exists idx_work_orders_tenant_assigned_to
  on public.work_orders(tenant_id, assigned_to);
create index if not exists idx_work_orders_tenant_routine
  on public.work_orders(tenant_id, routine_id);
create index if not exists idx_work_order_tasks_work_order_id
  on public.work_order_tasks(work_order_id);
create index if not exists idx_work_order_evidence_work_order_id
  on public.work_order_evidence(work_order_id);
create index if not exists idx_work_order_evidence_tenant_wo_task
  on public.work_order_evidence(tenant_id, work_order_id, task_id);
create index if not exists idx_work_order_history_work_order_id
  on public.work_order_status_history(work_order_id);
