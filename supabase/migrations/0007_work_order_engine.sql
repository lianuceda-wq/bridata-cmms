-- Bridata CMMS - motor de órdenes de trabajo
-- Generación idempotente desde programación, snapshot de actividades, lifecycle y cierre.

-- 1) Secuencias por tenant/año para códigos OT sin colisiones concurrentes.
create table public.tenant_sequences (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  sequence_key text not null,
  value bigint not null default 0 check (value >= 0),
  updated_at timestamptz not null default now(),
  primary key (tenant_id, sequence_key)
);

alter table public.tenant_sequences enable row level security;
revoke all on table public.tenant_sequences from public, anon, authenticated;

create or replace function public.next_work_order_code(p_tenant_id uuid)
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

revoke all on function public.next_work_order_code(uuid) from public, anon, authenticated;

-- 2) Evolución de work_orders para enlazar la ocurrencia exacta del plan.
alter table public.maintenance_schedule_states
  add constraint maintenance_schedule_states_tenant_id_id_key unique (tenant_id, id);

alter table public.work_orders
  add column routine_id uuid,
  add column schedule_state_id uuid,
  add column source text not null default 'manual'
    check (source in ('manual','maintenance_plan','inspection','request')),
  add column occurrence_key text,
  add column due_at timestamptz,
  add column due_meter numeric(18,4),
  add column generated_at timestamptz,
  add column validated_at timestamptz,
  add column closed_at timestamptz,
  add column cancelled_at timestamptz,
  add column cancellation_reason text,
  add column actual_minutes integer check (actual_minutes is null or actual_minutes >= 0),
  add constraint work_orders_tenant_id_id_key unique (tenant_id, id),
  add constraint work_orders_tenant_routine_fk
    foreign key (tenant_id, routine_id)
    references public.maintenance_routines(tenant_id, id)
    on delete restrict,
  add constraint work_orders_tenant_schedule_state_fk
    foreign key (tenant_id, schedule_state_id)
    references public.maintenance_schedule_states(tenant_id, id)
    on delete restrict,
  add constraint work_orders_tenant_assignee_fk
    foreign key (tenant_id, assigned_to)
    references public.tenant_members(tenant_id, user_id)
    on delete restrict,
  add constraint work_orders_plan_source_check
    check (
      source <> 'maintenance_plan'
      or (
        plan_id is not null
        and routine_id is not null
        and schedule_state_id is not null
        and asset_id is not null
        and nullif(trim(occurrence_key), '') is not null
      )
    );

create unique index uq_work_orders_schedule_occurrence
  on public.work_orders(tenant_id, schedule_state_id, occurrence_key)
  where schedule_state_id is not null and occurrence_key is not null;
create index idx_work_orders_routine_id on public.work_orders(routine_id);
create index idx_work_orders_schedule_state_id on public.work_orders(schedule_state_id);
create index idx_work_orders_due_at on public.work_orders(tenant_id, status, due_at)
  where due_at is not null;
create index idx_work_orders_due_meter on public.work_orders(tenant_id, status, due_meter)
  where due_meter is not null;

-- 3) Snapshot de actividades. Una OT conserva el checklist emitido aunque cambie el plan.
create table public.work_order_tasks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  work_order_id uuid not null references public.work_orders(id) on delete cascade,
  routine_task_id uuid references public.maintenance_routine_tasks(id) on delete set null,
  sequence integer not null check (sequence > 0),
  title text not null,
  instructions text,
  estimated_minutes integer check (estimated_minutes is null or estimated_minutes >= 0),
  mandatory boolean not null default true,
  task_type text not null default 'task'
    check (task_type in ('task','inspection','measurement','safety')),
  requires_evidence boolean not null default false,
  measurement_unit text,
  min_value numeric(18,4),
  max_value numeric(18,4),
  status text not null default 'pending'
    check (status in ('pending','completed','skipped')),
  measurement_value numeric(18,4),
  result_status text
    check (result_status is null or result_status in ('passed','failed','out_of_range','not_applicable')),
  notes text,
  completed_by uuid references auth.users(id) on delete set null,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, work_order_id, id),
  check (min_value is null or max_value is null or min_value <= max_value)
);

alter table public.work_order_tasks
  add constraint work_order_tasks_tenant_work_order_fk
  foreign key (tenant_id, work_order_id)
  references public.work_orders(tenant_id, id)
  on delete cascade;

create index idx_work_order_tasks_work_order on public.work_order_tasks(tenant_id, work_order_id, sequence);
create index idx_work_order_tasks_routine_task on public.work_order_tasks(routine_task_id);
create index idx_work_order_tasks_completed_by on public.work_order_tasks(completed_by);

create trigger work_order_tasks_updated_at
before update on public.work_order_tasks
for each row execute procedure public.set_updated_at();

-- 4) Evidencias desacopladas del proveedor de storage.
create table public.work_order_evidence (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  work_order_id uuid not null references public.work_orders(id) on delete cascade,
  task_id uuid references public.work_order_tasks(id) on delete cascade,
  storage_bucket text not null default 'work-order-evidence',
  storage_path text not null,
  file_name text,
  mime_type text,
  caption text,
  uploaded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (tenant_id, storage_bucket, storage_path)
);

alter table public.work_order_evidence
  add constraint work_order_evidence_tenant_work_order_fk
    foreign key (tenant_id, work_order_id)
    references public.work_orders(tenant_id, id)
    on delete cascade,
  add constraint work_order_evidence_tenant_task_fk
    foreign key (tenant_id, work_order_id, task_id)
    references public.work_order_tasks(tenant_id, work_order_id, id)
    on delete cascade;

create index idx_work_order_evidence_work_order on public.work_order_evidence(tenant_id, work_order_id);
create index idx_work_order_evidence_task on public.work_order_evidence(task_id);
create index idx_work_order_evidence_uploaded_by on public.work_order_evidence(uploaded_by);

-- 5) Historial inmutable de estados.
create table public.work_order_status_history (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  work_order_id uuid not null references public.work_orders(id) on delete cascade,
  from_status text,
  to_status text not null,
  changed_by uuid references auth.users(id) on delete set null,
  notes text,
  changed_at timestamptz not null default now()
);

alter table public.work_order_status_history
  add constraint work_order_history_tenant_work_order_fk
  foreign key (tenant_id, work_order_id)
  references public.work_orders(tenant_id, id)
  on delete cascade;

create index idx_work_order_history_work_order on public.work_order_status_history(tenant_id, work_order_id, changed_at desc);
create index idx_work_order_history_changed_by on public.work_order_status_history(changed_by);

-- 6) Validación de tareas al cambiar su ejecución.
create or replace function public.validate_work_order_task_execution()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if new.status = 'skipped' and new.mandatory then
    raise exception 'A mandatory task cannot be skipped';
  end if;

  if new.status = 'completed' then
    if new.task_type = 'measurement' and new.measurement_value is null then
      raise exception 'Measurement value is required';
    end if;

    if new.task_type = 'measurement' then
      if (new.min_value is not null and new.measurement_value < new.min_value)
         or (new.max_value is not null and new.measurement_value > new.max_value) then
        new.result_status := 'out_of_range';
      else
        new.result_status := coalesce(new.result_status, 'passed');
      end if;
    else
      new.result_status := coalesce(new.result_status, 'passed');
    end if;

    new.completed_by := coalesce(new.completed_by, auth.uid());
    new.completed_at := coalesce(new.completed_at, now());
  else
    new.completed_by := null;
    new.completed_at := null;
    if new.status = 'pending' then
      new.result_status := null;
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.validate_work_order_task_execution() from public, anon, authenticated;

create trigger work_order_task_execution_guard
before insert or update on public.work_order_tasks
for each row execute procedure public.validate_work_order_task_execution();

-- 7) Máquina de estados y protección de campos estructurales.
create or replace function public.validate_work_order_transition()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_role text;
  v_missing_tasks integer;
  v_missing_evidence integer;
begin
  if tg_op = 'INSERT' then
    return new;
  end if;

  v_role := public.tenant_role(new.tenant_id);

  if v_role = 'technician' then
    if old.tenant_id is distinct from new.tenant_id
       or old.code is distinct from new.code
       or old.asset_id is distinct from new.asset_id
       or old.plan_id is distinct from new.plan_id
       or old.routine_id is distinct from new.routine_id
       or old.schedule_state_id is distinct from new.schedule_state_id
       or old.source is distinct from new.source
       or old.occurrence_key is distinct from new.occurrence_key
       or old.maintenance_type is distinct from new.maintenance_type
       or old.priority is distinct from new.priority
       or old.due_at is distinct from new.due_at
       or old.due_meter is distinct from new.due_meter
       or old.assigned_to is distinct from new.assigned_to then
      raise exception 'Technicians cannot modify work order structural fields';
    end if;
  end if;

  if old.status is not distinct from new.status then
    return new;
  end if;

  if not (
    (old.status = 'requested' and new.status in ('planned','assigned','cancelled'))
    or (old.status = 'planned' and new.status in ('assigned','in_progress','cancelled'))
    or (old.status = 'assigned' and new.status in ('planned','in_progress','cancelled'))
    or (old.status = 'in_progress' and new.status in ('paused','completed','cancelled'))
    or (old.status = 'paused' and new.status in ('in_progress','completed','cancelled'))
    or (old.status = 'completed' and new.status in ('validated','in_progress'))
    or (old.status = 'validated' and new.status in ('closed','completed'))
    or (old.status = 'cancelled' and new.status = 'requested' and public.can_admin_tenant(new.tenant_id))
  ) then
    raise exception 'Invalid work order status transition: % -> %', old.status, new.status;
  end if;

  if v_role = 'technician' and new.status in ('planned','assigned','validated','closed','cancelled','requested') then
    raise exception 'Technician role cannot perform this status transition';
  end if;

  if new.status = 'in_progress' then
    new.started_at := coalesce(new.started_at, now());
  end if;

  if new.status = 'completed' then
    select count(*) into v_missing_tasks
    from public.work_order_tasks t
    where t.tenant_id = new.tenant_id
      and t.work_order_id = new.id
      and t.mandatory = true
      and t.status <> 'completed';

    if v_missing_tasks > 0 then
      raise exception 'Mandatory work order tasks remain incomplete';
    end if;

    select count(*) into v_missing_evidence
    from public.work_order_tasks t
    where t.tenant_id = new.tenant_id
      and t.work_order_id = new.id
      and t.requires_evidence = true
      and not exists (
        select 1
        from public.work_order_evidence e
        where e.tenant_id = t.tenant_id
          and e.work_order_id = t.work_order_id
          and e.task_id = t.id
      );

    if v_missing_evidence > 0 then
      raise exception 'Evidence is required for one or more completed tasks';
    end if;

    new.completed_at := coalesce(new.completed_at, now());
  end if;

  if new.status = 'validated' then
    new.validated_at := coalesce(new.validated_at, now());
  end if;

  if new.status = 'closed' then
    new.closed_at := coalesce(new.closed_at, now());
  end if;

  if new.status = 'cancelled' then
    new.cancelled_at := coalesce(new.cancelled_at, now());
    if nullif(trim(coalesce(new.cancellation_reason, '')), '') is null then
      raise exception 'Cancellation reason is required';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.validate_work_order_transition() from public, anon, authenticated;

create trigger work_order_transition_guard
before update on public.work_orders
for each row execute procedure public.validate_work_order_transition();

-- 8) Historial automático de estados, no insertable directamente por clientes.
create or replace function public.log_work_order_status()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.work_order_status_history (
      tenant_id, work_order_id, from_status, to_status, changed_by
    ) values (
      new.tenant_id, new.id, null, new.status, auth.uid()
    );
  elsif old.status is distinct from new.status then
    insert into public.work_order_status_history (
      tenant_id, work_order_id, from_status, to_status, changed_by
    ) values (
      new.tenant_id, new.id, old.status, new.status, auth.uid()
    );
  end if;
  return new;
end;
$$;

revoke all on function public.log_work_order_status() from public, anon, authenticated;

create trigger work_order_status_audit
 after insert or update of status on public.work_orders
 for each row execute procedure public.log_work_order_status();

-- 9) Al cerrar, avanza la programación exactamente una ocurrencia.
create or replace function public.advance_schedule_after_work_order_close()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_routine public.maintenance_routines%rowtype;
  v_state public.maintenance_schedule_states%rowtype;
  v_meter_value numeric(18,4);
begin
  if old.status is not distinct from new.status
     or new.status <> 'closed'
     or new.schedule_state_id is null
     or new.routine_id is null then
    return new;
  end if;

  select * into v_routine
  from public.maintenance_routines
  where tenant_id = new.tenant_id and id = new.routine_id;

  select * into v_state
  from public.maintenance_schedule_states
  where tenant_id = new.tenant_id and id = new.schedule_state_id
  for update;

  if not found then
    return new;
  end if;

  if v_routine.trigger_type = 'calendar' then
    update public.maintenance_schedule_states
    set last_completed_at = coalesce(new.completed_at, new.closed_at, now()),
        last_work_order_id = new.id,
        next_due_at = case v_routine.interval_unit
          when 'day' then coalesce(v_state.next_due_at, now()) + (v_routine.interval_value::double precision * interval '1 day')
          when 'week' then coalesce(v_state.next_due_at, now()) + (v_routine.interval_value::double precision * interval '1 week')
          when 'month' then coalesce(v_state.next_due_at, now()) + (v_routine.interval_value::double precision * interval '1 month')
          when 'year' then coalesce(v_state.next_due_at, now()) + (v_routine.interval_value::double precision * interval '1 year')
          else v_state.next_due_at
        end,
        updated_at = now()
    where tenant_id = new.tenant_id and id = new.schedule_state_id;
  else
    select current_value into v_meter_value
    from public.asset_meters
    where tenant_id = new.tenant_id and id = v_state.meter_id;

    update public.maintenance_schedule_states
    set last_completed_at = coalesce(new.completed_at, new.closed_at, now()),
        last_meter_value = v_meter_value,
        last_work_order_id = new.id,
        next_due_meter = coalesce(v_state.next_due_meter, v_meter_value) + v_routine.interval_value,
        updated_at = now()
    where tenant_id = new.tenant_id and id = new.schedule_state_id;
  end if;

  return new;
end;
$$;

revoke all on function public.advance_schedule_after_work_order_close() from public, anon, authenticated;

create trigger work_order_close_advance_schedule
 after update of status on public.work_orders
 for each row execute procedure public.advance_schedule_after_work_order_close();

-- 10) Generador idempotente. Puede ejecutarlo un manager o backend con service_role.
create or replace function public.generate_due_work_orders(
  p_tenant_id uuid,
  p_as_of timestamptz default now()
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
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
      a.name as asset_name,
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

    v_code := public.next_work_order_code(p_tenant_id);

    insert into public.work_orders (
      tenant_id,
      asset_id,
      plan_id,
      routine_id,
      schedule_state_id,
      code,
      title,
      description,
      maintenance_type,
      priority,
      status,
      source,
      occurrence_key,
      scheduled_at,
      due_at,
      due_meter,
      generated_at,
      created_by
    ) values (
      p_tenant_id,
      v_row.asset_id,
      v_row.plan_id,
      v_row.routine_id,
      v_row.schedule_state_id,
      v_code,
      v_row.routine_code || ' · ' || v_row.routine_name || ' · ' || v_row.asset_code,
      v_row.routine_description,
      v_row.maintenance_type,
      v_row.priority,
      'planned',
      'maintenance_plan',
      v_occurrence_key,
      coalesce(v_row.next_due_at, p_as_of),
      v_row.next_due_at,
      v_row.next_due_meter,
      now(),
      auth.uid()
    )
    returning id into v_work_order_id;

    insert into public.work_order_tasks (
      tenant_id,
      work_order_id,
      routine_task_id,
      sequence,
      title,
      instructions,
      estimated_minutes,
      mandatory,
      task_type,
      requires_evidence,
      measurement_unit,
      min_value,
      max_value
    )
    select
      t.tenant_id,
      v_work_order_id,
      t.id,
      t.sequence,
      t.title,
      t.instructions,
      t.estimated_minutes,
      t.mandatory,
      t.task_type,
      t.requires_evidence,
      t.measurement_unit,
      t.min_value,
      t.max_value
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

-- 11) RLS para ejecución.
alter table public.work_order_tasks enable row level security;
alter table public.work_order_evidence enable row level security;
alter table public.work_order_status_history enable row level security;

create policy work_order_tasks_select on public.work_order_tasks
for select to authenticated
using (public.is_tenant_member(tenant_id));

create policy work_order_tasks_insert on public.work_order_tasks
for insert to authenticated
with check (public.can_manage_tenant(tenant_id));

create policy work_order_tasks_update on public.work_order_tasks
for update to authenticated
using (
  public.can_manage_tenant(tenant_id)
  or exists (
    select 1 from public.work_orders wo
    where wo.tenant_id = work_order_tasks.tenant_id
      and wo.id = work_order_tasks.work_order_id
      and wo.assigned_to = (select auth.uid())
      and public.tenant_role(work_order_tasks.tenant_id) = 'technician'
  )
)
with check (
  public.can_manage_tenant(tenant_id)
  or exists (
    select 1 from public.work_orders wo
    where wo.tenant_id = work_order_tasks.tenant_id
      and wo.id = work_order_tasks.work_order_id
      and wo.assigned_to = (select auth.uid())
      and public.tenant_role(work_order_tasks.tenant_id) = 'technician'
  )
);

create policy work_order_tasks_delete on public.work_order_tasks
for delete to authenticated
using (public.can_admin_tenant(tenant_id));

create policy work_order_evidence_select on public.work_order_evidence
for select to authenticated
using (public.is_tenant_member(tenant_id));

create policy work_order_evidence_insert on public.work_order_evidence
for insert to authenticated
with check (
  public.can_manage_tenant(tenant_id)
  or exists (
    select 1 from public.work_orders wo
    where wo.tenant_id = work_order_evidence.tenant_id
      and wo.id = work_order_evidence.work_order_id
      and wo.assigned_to = (select auth.uid())
      and public.tenant_role(work_order_evidence.tenant_id) = 'technician'
  )
);

create policy work_order_evidence_delete on public.work_order_evidence
for delete to authenticated
using (public.can_manage_tenant(tenant_id));

create policy work_order_history_select on public.work_order_status_history
for select to authenticated
using (public.is_tenant_member(tenant_id));

-- Historial solo por trigger.
revoke insert, update, delete on public.work_order_status_history from authenticated, anon;

-- Las tablas operativas deben ser accesibles por PostgREST bajo RLS.
grant select, insert, update, delete on public.work_order_tasks to authenticated;
grant select, insert, delete on public.work_order_evidence to authenticated;
grant select on public.work_order_status_history to authenticated;
