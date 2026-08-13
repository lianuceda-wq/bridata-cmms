-- Bridata CMMS - motor de planes de mantenimiento
-- Evoluciona el modelo inicial a Plan -> Activos -> Rutinas -> Actividades -> Programación.

-- 1) Plan como plantilla reusable dentro del tenant.
alter table public.maintenance_plans
  drop constraint if exists maintenance_plans_asset_id_fkey,
  drop constraint if exists maintenance_plans_tenant_asset_fk,
  drop constraint if exists maintenance_plans_trigger_type_check;

alter table public.maintenance_plans
  drop column if exists asset_id,
  drop column if exists trigger_type,
  drop column if exists interval_value,
  drop column if exists interval_unit,
  drop column if exists active,
  add column description text,
  add column status text not null default 'active'
    check (status in ('draft','active','paused','archived')),
  add column version integer not null default 1 check (version > 0),
  add column updated_at timestamptz not null default now();

drop trigger if exists maintenance_plans_updated_at on public.maintenance_plans;
create trigger maintenance_plans_updated_at
before update on public.maintenance_plans
for each row execute procedure public.set_updated_at();

-- 2) Medidores acumulativos por activo: horómetro, ciclos, distancia, volumen, etc.
create table public.asset_meters (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  asset_id uuid not null references public.assets(id) on delete cascade,
  code text not null,
  name text not null,
  meter_type text not null default 'hours'
    check (meter_type in ('hours','cycles','distance','volume','energy','custom')),
  unit text not null,
  current_value numeric(18,4) not null default 0 check (current_value >= 0),
  last_reading_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, asset_id, code)
);

create unique index uq_asset_meters_tenant_id on public.asset_meters(tenant_id, id);
create index idx_asset_meters_asset on public.asset_meters(tenant_id, asset_id);

alter table public.asset_meters
  add constraint asset_meters_tenant_asset_fk
  foreign key (tenant_id, asset_id)
  references public.assets(tenant_id, id)
  on delete cascade;

drop trigger if exists asset_meters_updated_at on public.asset_meters;
create trigger asset_meters_updated_at
before update on public.asset_meters
for each row execute procedure public.set_updated_at();

create table public.meter_readings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  meter_id uuid not null references public.asset_meters(id) on delete cascade,
  value numeric(18,4) not null check (value >= 0),
  recorded_at timestamptz not null default now(),
  recorded_by uuid references auth.users(id) on delete set null,
  source text not null default 'manual'
    check (source in ('manual','import','api','iot')),
  notes text,
  created_at timestamptz not null default now()
);

alter table public.meter_readings
  add constraint meter_readings_tenant_meter_fk
  foreign key (tenant_id, meter_id)
  references public.asset_meters(tenant_id, id)
  on delete cascade;

create index idx_meter_readings_meter_date
  on public.meter_readings(tenant_id, meter_id, recorded_at desc);
create index idx_meter_readings_recorded_by on public.meter_readings(recorded_by);

-- Mantiene el acumulado del medidor consistente. Se ejecuta solo como trigger.
create or replace function public.apply_meter_reading()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_current numeric(18,4);
begin
  select current_value
    into v_current
  from public.asset_meters
  where tenant_id = new.tenant_id
    and id = new.meter_id
  for update;

  if not found then
    raise exception 'Meter does not belong to tenant';
  end if;

  if new.value < v_current then
    raise exception 'Meter reading cannot be lower than current value';
  end if;

  update public.asset_meters
  set current_value = new.value,
      last_reading_at = new.recorded_at,
      updated_at = now()
  where tenant_id = new.tenant_id
    and id = new.meter_id;

  return new;
end;
$$;

revoke all on function public.apply_meter_reading() from public, anon, authenticated;

drop trigger if exists meter_reading_apply on public.meter_readings;
create trigger meter_reading_apply
before insert on public.meter_readings
for each row execute procedure public.apply_meter_reading();

-- 3) Un plan puede asignarse a uno o más activos.
create table public.maintenance_plan_assets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  plan_id uuid not null references public.maintenance_plans(id) on delete cascade,
  asset_id uuid not null references public.assets(id) on delete cascade,
  start_at timestamptz not null default now(),
  active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (tenant_id, plan_id, asset_id)
);

create unique index uq_plan_assets_tenant_plan_id
  on public.maintenance_plan_assets(tenant_id, plan_id, id);
create index idx_plan_assets_asset on public.maintenance_plan_assets(tenant_id, asset_id);

alter table public.maintenance_plan_assets
  add constraint plan_assets_tenant_plan_fk
  foreign key (tenant_id, plan_id)
  references public.maintenance_plans(tenant_id, id)
  on delete cascade,
  add constraint plan_assets_tenant_asset_fk
  foreign key (tenant_id, asset_id)
  references public.assets(tenant_id, id)
  on delete cascade;

-- 4) Rutinas: cada plan puede tener distintas frecuencias.
create table public.maintenance_routines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  plan_id uuid not null references public.maintenance_plans(id) on delete cascade,
  code text not null,
  name text not null,
  description text,
  maintenance_type text not null default 'preventive'
    check (maintenance_type in ('preventive','predictive','inspection','improvement')),
  priority text not null default 'medium'
    check (priority in ('low','medium','high','critical')),
  trigger_type text not null
    check (trigger_type in ('calendar','meter')),
  interval_value numeric(12,4) not null check (interval_value > 0),
  interval_unit text not null
    check (interval_unit in ('day','week','month','year','hour','cycle','km','m3','unit')),
  meter_code text,
  lead_time_days integer not null default 0 check (lead_time_days >= 0),
  estimated_minutes integer check (estimated_minutes is null or estimated_minutes >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, plan_id, code),
  check (
    (trigger_type = 'calendar'
      and meter_code is null
      and interval_unit in ('day','week','month','year'))
    or
    (trigger_type = 'meter'
      and nullif(trim(meter_code), '') is not null
      and interval_unit in ('hour','cycle','km','m3','unit'))
  )
);

create unique index uq_routines_tenant_plan_id
  on public.maintenance_routines(tenant_id, plan_id, id);
create unique index uq_routines_tenant_id
  on public.maintenance_routines(tenant_id, id);
create index idx_routines_plan on public.maintenance_routines(tenant_id, plan_id, active);

alter table public.maintenance_routines
  add constraint routines_tenant_plan_fk
  foreign key (tenant_id, plan_id)
  references public.maintenance_plans(tenant_id, id)
  on delete cascade;

drop trigger if exists maintenance_routines_updated_at on public.maintenance_routines;
create trigger maintenance_routines_updated_at
before update on public.maintenance_routines
for each row execute procedure public.set_updated_at();

-- 5) Las actividades pasan a pertenecer a una rutina concreta.
alter table public.maintenance_plan_tasks rename to maintenance_routine_tasks;

alter table public.maintenance_routine_tasks
  drop constraint if exists maintenance_plan_tasks_plan_id_fkey;

alter table public.maintenance_routine_tasks
  drop column if exists plan_id,
  add column routine_id uuid not null,
  add column task_type text not null default 'task'
    check (task_type in ('task','inspection','measurement','safety')),
  add column requires_evidence boolean not null default false,
  add column measurement_unit text,
  add column min_value numeric(18,4),
  add column max_value numeric(18,4),
  add constraint routine_tasks_value_range_check
    check (min_value is null or max_value is null or min_value <= max_value),
  add constraint routine_tasks_tenant_routine_fk
    foreign key (tenant_id, routine_id)
    references public.maintenance_routines(tenant_id, id)
    on delete cascade;

create index idx_routine_tasks_routine
  on public.maintenance_routine_tasks(tenant_id, routine_id, sequence);

-- 6) Estado independiente de programación por combinación activo/rutina.
create table public.maintenance_schedule_states (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  plan_id uuid not null references public.maintenance_plans(id) on delete cascade,
  plan_asset_id uuid not null references public.maintenance_plan_assets(id) on delete cascade,
  routine_id uuid not null references public.maintenance_routines(id) on delete cascade,
  meter_id uuid references public.asset_meters(id) on delete set null,
  status text not null default 'active'
    check (status in ('active','paused','blocked')),
  blocked_reason text,
  last_completed_at timestamptz,
  next_due_at timestamptz,
  last_meter_value numeric(18,4),
  next_due_meter numeric(18,4),
  last_work_order_id uuid references public.work_orders(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, plan_asset_id, routine_id)
);

alter table public.maintenance_schedule_states
  add constraint schedule_states_tenant_plan_asset_fk
  foreign key (tenant_id, plan_id, plan_asset_id)
  references public.maintenance_plan_assets(tenant_id, plan_id, id)
  on delete cascade,
  add constraint schedule_states_tenant_routine_fk
  foreign key (tenant_id, plan_id, routine_id)
  references public.maintenance_routines(tenant_id, plan_id, id)
  on delete cascade,
  add constraint schedule_states_tenant_meter_fk
  foreign key (tenant_id, meter_id)
  references public.asset_meters(tenant_id, id)
  on delete set null;

create index idx_schedule_states_due_date
  on public.maintenance_schedule_states(tenant_id, status, next_due_at)
  where next_due_at is not null;
create index idx_schedule_states_due_meter
  on public.maintenance_schedule_states(tenant_id, status, next_due_meter)
  where next_due_meter is not null;
create index idx_schedule_states_meter on public.maintenance_schedule_states(tenant_id, meter_id);
create index idx_schedule_states_last_wo on public.maintenance_schedule_states(last_work_order_id);

drop trigger if exists schedule_states_updated_at on public.maintenance_schedule_states;
create trigger schedule_states_updated_at
before update on public.maintenance_schedule_states
for each row execute procedure public.set_updated_at();

-- Crea combinaciones de programación faltantes sin resetear estados ya avanzados.
create or replace function public.sync_maintenance_schedule(p_plan_id uuid)
returns integer
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_tenant_id uuid;
  v_inserted integer := 0;
begin
  select tenant_id into v_tenant_id
  from public.maintenance_plans
  where id = p_plan_id;

  if v_tenant_id is null then
    raise exception 'Maintenance plan not found';
  end if;

  if not public.can_manage_tenant(v_tenant_id) then
    raise exception 'Insufficient permissions';
  end if;

  insert into public.maintenance_schedule_states (
    tenant_id,
    plan_id,
    plan_asset_id,
    routine_id,
    meter_id,
    status,
    blocked_reason,
    next_due_at,
    next_due_meter
  )
  select
    pa.tenant_id,
    pa.plan_id,
    pa.id,
    r.id,
    m.id,
    case
      when r.trigger_type = 'meter' and m.id is null then 'blocked'
      else 'active'
    end,
    case
      when r.trigger_type = 'meter' and m.id is null
        then 'Falta medidor con código ' || r.meter_code || ' en el activo'
      else null
    end,
    case r.interval_unit
      when 'day' then pa.start_at + (r.interval_value::double precision * interval '1 day')
      when 'week' then pa.start_at + (r.interval_value::double precision * interval '1 week')
      when 'month' then pa.start_at + (r.interval_value::double precision * interval '1 month')
      when 'year' then pa.start_at + (r.interval_value::double precision * interval '1 year')
      else null
    end,
    case
      when r.trigger_type = 'meter' and m.id is not null
        then m.current_value + r.interval_value
      else null
    end
  from public.maintenance_plan_assets pa
  join public.maintenance_routines r
    on r.tenant_id = pa.tenant_id
   and r.plan_id = pa.plan_id
   and r.active = true
  left join lateral (
    select am.id, am.current_value
    from public.asset_meters am
    where am.tenant_id = pa.tenant_id
      and am.asset_id = pa.asset_id
      and lower(am.code) = lower(r.meter_code)
    order by am.created_at
    limit 1
  ) m on r.trigger_type = 'meter'
  where pa.plan_id = p_plan_id
    and pa.active = true
  on conflict (tenant_id, plan_asset_id, routine_id)
  do update set
    meter_id = coalesce(public.maintenance_schedule_states.meter_id, excluded.meter_id),
    status = case
      when public.maintenance_schedule_states.status = 'blocked'
       and excluded.meter_id is not null then 'active'
      else public.maintenance_schedule_states.status
    end,
    blocked_reason = case
      when public.maintenance_schedule_states.status = 'blocked'
       and excluded.meter_id is not null then null
      else public.maintenance_schedule_states.blocked_reason
    end,
    updated_at = now();

  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$$;

revoke all on function public.sync_maintenance_schedule(uuid) from public, anon;
grant execute on function public.sync_maintenance_schedule(uuid) to authenticated;

-- 7) RLS de las nuevas entidades.
alter table public.asset_meters enable row level security;
alter table public.meter_readings enable row level security;
alter table public.maintenance_plan_assets enable row level security;
alter table public.maintenance_routines enable row level security;
alter table public.maintenance_routine_tasks enable row level security;
alter table public.maintenance_schedule_states enable row level security;

-- La tabla renombrada conserva políticas con nombres antiguos; se reemplazan.
drop policy if exists maintenance_plan_tasks_select on public.maintenance_routine_tasks;
drop policy if exists maintenance_plan_tasks_insert on public.maintenance_routine_tasks;
drop policy if exists maintenance_plan_tasks_update on public.maintenance_routine_tasks;
drop policy if exists maintenance_plan_tasks_delete on public.maintenance_routine_tasks;

create policy asset_meters_select on public.asset_meters
for select to authenticated
using (public.is_tenant_member(tenant_id));
create policy asset_meters_insert on public.asset_meters
for insert to authenticated
with check (public.can_manage_tenant(tenant_id));
create policy asset_meters_update on public.asset_meters
for update to authenticated
using (public.can_manage_tenant(tenant_id))
with check (public.can_manage_tenant(tenant_id));
create policy asset_meters_delete on public.asset_meters
for delete to authenticated
using (public.can_manage_tenant(tenant_id));

create policy meter_readings_select on public.meter_readings
for select to authenticated
using (public.is_tenant_member(tenant_id));
create policy meter_readings_insert on public.meter_readings
for insert to authenticated
with check (
  public.tenant_role(tenant_id) in ('owner','admin','planner','supervisor','technician')
  and recorded_by = (select auth.uid())
);
create policy meter_readings_delete on public.meter_readings
for delete to authenticated
using (public.can_admin_tenant(tenant_id));

create policy plan_assets_select on public.maintenance_plan_assets
for select to authenticated
using (public.is_tenant_member(tenant_id));
create policy plan_assets_insert on public.maintenance_plan_assets
for insert to authenticated
with check (public.can_manage_tenant(tenant_id));
create policy plan_assets_update on public.maintenance_plan_assets
for update to authenticated
using (public.can_manage_tenant(tenant_id))
with check (public.can_manage_tenant(tenant_id));
create policy plan_assets_delete on public.maintenance_plan_assets
for delete to authenticated
using (public.can_manage_tenant(tenant_id));

create policy routines_select on public.maintenance_routines
for select to authenticated
using (public.is_tenant_member(tenant_id));
create policy routines_insert on public.maintenance_routines
for insert to authenticated
with check (public.can_manage_tenant(tenant_id));
create policy routines_update on public.maintenance_routines
for update to authenticated
using (public.can_manage_tenant(tenant_id))
with check (public.can_manage_tenant(tenant_id));
create policy routines_delete on public.maintenance_routines
for delete to authenticated
using (public.can_manage_tenant(tenant_id));

create policy routine_tasks_select on public.maintenance_routine_tasks
for select to authenticated
using (public.is_tenant_member(tenant_id));
create policy routine_tasks_insert on public.maintenance_routine_tasks
for insert to authenticated
with check (public.can_manage_tenant(tenant_id));
create policy routine_tasks_update on public.maintenance_routine_tasks
for update to authenticated
using (public.can_manage_tenant(tenant_id))
with check (public.can_manage_tenant(tenant_id));
create policy routine_tasks_delete on public.maintenance_routine_tasks
for delete to authenticated
using (public.can_manage_tenant(tenant_id));

create policy schedule_states_select on public.maintenance_schedule_states
for select to authenticated
using (public.is_tenant_member(tenant_id));
create policy schedule_states_insert on public.maintenance_schedule_states
for insert to authenticated
with check (public.can_manage_tenant(tenant_id));
create policy schedule_states_update on public.maintenance_schedule_states
for update to authenticated
using (public.can_manage_tenant(tenant_id))
with check (public.can_manage_tenant(tenant_id));
create policy schedule_states_delete on public.maintenance_schedule_states
for delete to authenticated
using (public.can_manage_tenant(tenant_id));
