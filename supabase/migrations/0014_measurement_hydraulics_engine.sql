-- Bridata CMMS - motor genérico de mediciones, nominales e inspecciones hidráulicas

-- La jerarquía de locations se amplía para representar la operación agrícola sin crear
-- una tabla por cada nivel. Sites sigue representando la sede/fundo principal.
alter table public.locations drop constraint if exists locations_location_type_check;
alter table public.locations
  add constraint locations_location_type_check
  check (location_type in (
    'farm','area','system','sector','parcel','lot','pumping_station','hydraulic_zone',
    'room','line','warehouse','other'
  ));

create table public.measurement_units (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  symbol text not null,
  quantity text not null,
  decimals smallint not null default 2 check (decimals between 0 and 6),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.measurement_units(code, name, symbol, quantity, decimals) values
  ('mca', 'Metros de columna de agua', 'm.c.a', 'pressure', 2),
  ('m3h', 'Metros cúbicos por hora', 'm³/h', 'flow', 2),
  ('ph', 'Potencial de hidrógeno', 'pH', 'ph', 2),
  ('uscm', 'Microsiemens por centímetro', 'µS/cm', 'conductivity', 2),
  ('m', 'Metro', 'm', 'length', 2)
on conflict (code) do nothing;

create table public.measurement_parameters (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null,
  name text not null,
  quantity text not null,
  default_unit_id uuid not null references public.measurement_units(id),
  hard_min_value numeric,
  hard_max_value numeric,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, code),
  constraint measurement_parameter_hard_range check (
    hard_min_value is null or hard_max_value is null or hard_min_value <= hard_max_value
  )
);
create unique index uq_measurement_parameters_tenant_id on public.measurement_parameters(tenant_id, id);

create table public.measurement_points (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null,
  name text not null,
  group_code text not null default 'general',
  scope_type text not null default 'location' check (scope_type in ('session','shift','location')),
  suggested_parameter_code text,
  sequence integer not null default 100,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, code)
);
create unique index uq_measurement_points_tenant_id on public.measurement_points(tenant_id, id);

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create or replace function private.seed_measurement_defaults(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_mca uuid;
  v_m3h uuid;
  v_ph uuid;
  v_uscm uuid;
  v_m uuid;
begin
  select id into v_mca from public.measurement_units where code = 'mca';
  select id into v_m3h from public.measurement_units where code = 'm3h';
  select id into v_ph from public.measurement_units where code = 'ph';
  select id into v_uscm from public.measurement_units where code = 'uscm';
  select id into v_m from public.measurement_units where code = 'm';

  insert into public.measurement_parameters(
    tenant_id, code, name, quantity, default_unit_id, hard_min_value, hard_max_value
  ) values
    (p_tenant_id, 'pressure', 'Presión', 'pressure', v_mca, 0, 250),
    (p_tenant_id, 'flow', 'Caudal', 'flow', v_m3h, 0, 10000),
    (p_tenant_id, 'ph', 'pH', 'ph', v_ph, 0, 14),
    (p_tenant_id, 'conductivity', 'Conductividad eléctrica', 'conductivity', v_uscm, 0, 200000),
    (p_tenant_id, 'water_level', 'Nivel de agua', 'length', v_m, -500, 500)
  on conflict (tenant_id, code) do nothing;

  insert into public.measurement_points(
    tenant_id, code, name, group_code, scope_type, suggested_parameter_code, sequence
  ) values
    (p_tenant_id, 'shift_flow', 'Caudal por turno', 'flow', 'shift', 'flow', 10),
    (p_tenant_id, 'filter_before', 'Antes de filtro', 'filtration', 'shift', 'pressure', 20),
    (p_tenant_id, 'filter_after', 'Después de filtro', 'filtration', 'shift', 'pressure', 30),
    (p_tenant_id, 'field_pressure', 'Presión a campo', 'filtration', 'shift', 'pressure', 40),
    (p_tenant_id, 'field_valve', 'Presión válvula de campo', 'field', 'shift', 'pressure', 50),
    (p_tenant_id, 'field_relief', 'Válvula de alivio en campo', 'field', 'shift', 'pressure', 60),
    (p_tenant_id, 'valve_before', 'Antes de válvula', 'dynamic', 'location', 'pressure', 100),
    (p_tenant_id, 'valve_after', 'Después de válvula', 'dynamic', 'location', 'pressure', 110),
    (p_tenant_id, 'fd_right', 'Final de divisora - Derecho', 'fd', 'location', 'pressure', 120),
    (p_tenant_id, 'fd_center', 'Final de divisora - Centro', 'fd', 'location', 'pressure', 130),
    (p_tenant_id, 'fd_left', 'Final de divisora - Izquierdo', 'fd', 'location', 'pressure', 140),
    (p_tenant_id, 'fm_right', 'Final de manguera - Derecho', 'fm', 'location', 'pressure', 150),
    (p_tenant_id, 'fm_center', 'Final de manguera - Centro', 'fm', 'location', 'pressure', 160),
    (p_tenant_id, 'fm_left', 'Final de manguera - Izquierdo', 'fm', 'location', 'pressure', 170),
    (p_tenant_id, 'adductor_flow', 'Caudal de aductor', 'flow', 'shift', 'flow', 180)
  on conflict (tenant_id, code) do nothing;
end;
$$;

revoke all on function private.seed_measurement_defaults(uuid) from public, anon, authenticated;

-- Sembrar catálogo para tenants existentes y para nuevos tenants.
do $$
declare
  r record;
begin
  for r in select id from public.tenants loop
    perform private.seed_measurement_defaults(r.id);
  end loop;
end $$;

create or replace function private.on_tenant_seed_measurements()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
begin
  perform private.seed_measurement_defaults(new.id);
  return new;
end;
$$;
revoke all on function private.on_tenant_seed_measurements() from public, anon, authenticated;

drop trigger if exists tenant_seed_measurements on public.tenants;
create trigger tenant_seed_measurements
after insert on public.tenants
for each row execute function private.on_tenant_seed_measurements();

create table public.hydraulic_component_models (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  component_type text not null check (component_type in ('hose','valve','pilot','filter')),
  code text,
  name text not null,
  manufacturer text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index uq_hydraulic_component_models_tenant_id on public.hydraulic_component_models(tenant_id, id);
create unique index uq_hydraulic_component_models_name
  on public.hydraulic_component_models(tenant_id, component_type, lower(name));

create table public.hydraulic_location_configs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  location_id uuid not null,
  hose_model_id uuid,
  valve_model_id uuid,
  pilot_model_id uuid,
  valid_from date not null default current_date,
  valid_to date,
  is_active boolean not null default true,
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint hydraulic_location_configs_dates check (valid_to is null or valid_to >= valid_from),
  foreign key (tenant_id, location_id) references public.locations(tenant_id, id) on delete cascade,
  foreign key (tenant_id, hose_model_id) references public.hydraulic_component_models(tenant_id, id) on delete set null,
  foreign key (tenant_id, valve_model_id) references public.hydraulic_component_models(tenant_id, id) on delete set null,
  foreign key (tenant_id, pilot_model_id) references public.hydraulic_component_models(tenant_id, id) on delete set null
);
create unique index uq_hydraulic_location_configs_tenant_id on public.hydraulic_location_configs(tenant_id, id);
create index idx_hydraulic_location_configs_location on public.hydraulic_location_configs(tenant_id, location_id, valid_from desc);

create table public.measurement_targets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  parameter_id uuid not null,
  point_id uuid,
  site_id uuid,
  location_id uuid,
  asset_id uuid,
  unit_id uuid not null references public.measurement_units(id),
  target_value numeric,
  min_value numeric,
  max_value numeric,
  tolerance_percent numeric check (tolerance_percent is null or tolerance_percent >= 0),
  valid_from date not null default current_date,
  valid_to date,
  is_active boolean not null default true,
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint measurement_targets_dates check (valid_to is null or valid_to >= valid_from),
  constraint measurement_targets_range check (min_value is null or max_value is null or min_value <= max_value),
  constraint measurement_targets_target_in_range check (
    target_value is null or
    ((min_value is null or target_value >= min_value) and (max_value is null or target_value <= max_value))
  ),
  foreign key (tenant_id, parameter_id) references public.measurement_parameters(tenant_id, id) on delete cascade,
  foreign key (tenant_id, point_id) references public.measurement_points(tenant_id, id) on delete cascade,
  foreign key (tenant_id, site_id) references public.sites(tenant_id, id) on delete cascade,
  foreign key (tenant_id, location_id) references public.locations(tenant_id, id) on delete cascade,
  foreign key (tenant_id, asset_id) references public.assets(tenant_id, id) on delete cascade
);
create unique index uq_measurement_targets_tenant_id on public.measurement_targets(tenant_id, id);
create index idx_measurement_targets_lookup
  on public.measurement_targets(tenant_id, parameter_id, point_id, site_id, location_id, asset_id, valid_from desc)
  where is_active = true;

create or replace function private.validate_measurement_target()
returns trigger
language plpgsql
set search_path = public, private, pg_temp
as $$
begin
  if new.target_value is null and new.min_value is null and new.max_value is null then
    raise exception 'Target requires at least target, minimum or maximum value';
  end if;

  if exists (
    select 1
    from public.measurement_targets mt
    where mt.id <> new.id
      and mt.tenant_id = new.tenant_id
      and mt.parameter_id = new.parameter_id
      and mt.point_id is not distinct from new.point_id
      and mt.site_id is not distinct from new.site_id
      and mt.location_id is not distinct from new.location_id
      and mt.asset_id is not distinct from new.asset_id
      and mt.is_active = true
      and new.is_active = true
      and daterange(mt.valid_from, coalesce(mt.valid_to + 1, 'infinity'::date), '[)')
          && daterange(new.valid_from, coalesce(new.valid_to + 1, 'infinity'::date), '[)')
  ) then
    raise exception 'An active target already exists for this scope and validity period';
  end if;

  return new;
end;
$$;
revoke all on function private.validate_measurement_target() from public, anon, authenticated;

drop trigger if exists validate_measurement_target on public.measurement_targets;
create trigger validate_measurement_target
before insert or update on public.measurement_targets
for each row execute function private.validate_measurement_target();

create table public.measurement_session_sequences (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  year integer not null,
  session_type text not null,
  last_value integer not null default 0,
  primary key (tenant_id, year, session_type)
);

create or replace function private.next_measurement_session_code(
  p_tenant_id uuid,
  p_session_type text
)
returns text
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_year integer := extract(year from current_date)::integer;
  v_next integer;
  v_prefix text;
begin
  v_prefix := case p_session_type
    when 'hydraulic_control' then 'HYD'
    when 'water_quality' then 'WQ'
    when 'piezometer' then 'PZ'
    else 'MED'
  end;

  insert into public.measurement_session_sequences(tenant_id, year, session_type, last_value)
  values (p_tenant_id, v_year, p_session_type, 1)
  on conflict (tenant_id, year, session_type)
  do update set last_value = public.measurement_session_sequences.last_value + 1
  returning last_value into v_next;

  return format('%s-%s-%s', v_prefix, v_year, lpad(v_next::text, 6, '0'));
end;
$$;
revoke all on function private.next_measurement_session_code(uuid, text) from public, anon, authenticated;

create table public.measurement_sessions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text,
  session_type text not null default 'hydraulic_control'
    check (session_type in ('hydraulic_control','water_quality','piezometer','operational','other')),
  status text not null default 'draft'
    check (status in ('draft','submitted','validated','cancelled')),
  site_id uuid,
  location_id uuid,
  occurred_at timestamptz not null default now(),
  responsible_user_id uuid references auth.users(id) on delete set null,
  responsible_name text,
  source_type text not null default 'manual'
    check (source_type in ('manual','import','api','sensor')),
  source_system text not null default 'bridata',
  notes text,
  created_by uuid not null references auth.users(id) on delete restrict default auth.uid(),
  validated_by uuid references auth.users(id) on delete set null,
  validated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, code),
  foreign key (tenant_id, site_id) references public.sites(tenant_id, id) on delete set null,
  foreign key (tenant_id, location_id) references public.locations(tenant_id, id) on delete set null
);
create unique index uq_measurement_sessions_tenant_id on public.measurement_sessions(tenant_id, id);
create index idx_measurement_sessions_tenant_date on public.measurement_sessions(tenant_id, occurred_at desc);

create or replace function private.assign_measurement_session_code()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
begin
  if new.code is null or btrim(new.code) = '' then
    new.code := private.next_measurement_session_code(new.tenant_id, new.session_type);
  end if;
  return new;
end;
$$;
revoke all on function private.assign_measurement_session_code() from public, anon, authenticated;

drop trigger if exists assign_measurement_session_code on public.measurement_sessions;
create trigger assign_measurement_session_code
before insert on public.measurement_sessions
for each row execute function private.assign_measurement_session_code();

create table public.measurement_samples (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  session_id uuid not null,
  sample_type text not null check (sample_type in ('shift','location')),
  shift_number integer not null check (shift_number > 0),
  location_id uuid,
  sequence integer not null default 1,
  hose_model_id uuid,
  valve_model_id uuid,
  pilot_model_id uuid,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (tenant_id, session_id) references public.measurement_sessions(tenant_id, id) on delete cascade,
  foreign key (tenant_id, location_id) references public.locations(tenant_id, id) on delete restrict,
  foreign key (tenant_id, hose_model_id) references public.hydraulic_component_models(tenant_id, id) on delete set null,
  foreign key (tenant_id, valve_model_id) references public.hydraulic_component_models(tenant_id, id) on delete set null,
  foreign key (tenant_id, pilot_model_id) references public.hydraulic_component_models(tenant_id, id) on delete set null,
  constraint measurement_samples_location_required check (
    (sample_type = 'shift' and location_id is null) or
    (sample_type = 'location' and location_id is not null)
  )
);
create unique index uq_measurement_samples_tenant_id on public.measurement_samples(tenant_id, id);
create unique index uq_measurement_shift_sample
  on public.measurement_samples(tenant_id, session_id, shift_number)
  where sample_type = 'shift';
create unique index uq_measurement_location_sample
  on public.measurement_samples(tenant_id, session_id, shift_number, location_id)
  where sample_type = 'location';
create index idx_measurement_samples_session on public.measurement_samples(tenant_id, session_id, sequence);

create or replace function private.resolve_measurement_target(
  p_tenant_id uuid,
  p_parameter_id uuid,
  p_point_id uuid,
  p_site_id uuid,
  p_location_id uuid,
  p_asset_id uuid,
  p_at date
)
returns public.measurement_targets
language sql
stable
security invoker
set search_path = public, private, pg_temp
as $$
  with recursive location_chain as (
    select l.id, l.parent_location_id, 0 as depth
    from public.locations l
    where l.tenant_id = p_tenant_id and l.id = p_location_id
    union all
    select parent.id, parent.parent_location_id, child.depth + 1
    from public.locations parent
    join location_chain child on child.parent_location_id = parent.id
    where parent.tenant_id = p_tenant_id
  )
  select mt
  from public.measurement_targets mt
  left join location_chain lc on lc.id = mt.location_id
  where mt.tenant_id = p_tenant_id
    and mt.parameter_id = p_parameter_id
    and (mt.point_id is null or mt.point_id = p_point_id)
    and (mt.site_id is null or mt.site_id = p_site_id)
    and (mt.location_id is null or lc.id is not null)
    and (mt.asset_id is null or mt.asset_id = p_asset_id)
    and mt.is_active = true
    and p_at >= mt.valid_from
    and (mt.valid_to is null or p_at <= mt.valid_to)
  order by
    (case when mt.asset_id is not null then 100000 else 0 end) +
    (case when mt.location_id = p_location_id then 50000
          when mt.location_id is not null then 40000 - coalesce(lc.depth, 999)
          else 0 end) +
    (case when mt.site_id is not null then 10000 else 0 end) +
    (case when mt.point_id is not null then 1000 else 0 end) desc,
    mt.valid_from desc,
    mt.created_at desc
  limit 1;
$$;
revoke all on function private.resolve_measurement_target(uuid, uuid, uuid, uuid, uuid, uuid, date) from public, anon, authenticated;

create table public.operational_readings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  session_id uuid not null,
  sample_id uuid not null,
  parameter_id uuid not null,
  point_id uuid not null,
  unit_id uuid not null references public.measurement_units(id),
  asset_id uuid,
  location_id uuid,
  value numeric not null,
  measured_at timestamptz not null default now(),
  source_type text not null default 'manual'
    check (source_type in ('manual','import','api','sensor')),
  source_system text not null default 'bridata',
  recorded_by uuid references auth.users(id) on delete set null default auth.uid(),
  measurement_target_id uuid,
  target_value_snapshot numeric,
  min_value_snapshot numeric,
  max_value_snapshot numeric,
  quality_status text not null default 'valid'
    check (quality_status in ('valid','suspect','invalid')),
  deviation_value numeric generated always as (
    case when target_value_snapshot is null then null else value - target_value_snapshot end
  ) stored,
  deviation_percent numeric generated always as (
    case when target_value_snapshot is null or target_value_snapshot = 0 then null
         else ((value - target_value_snapshot) / target_value_snapshot) * 100 end
  ) stored,
  compliance_status text generated always as (
    case
      when min_value_snapshot is null and max_value_snapshot is null then 'not_evaluated'
      when (min_value_snapshot is null or value >= min_value_snapshot)
       and (max_value_snapshot is null or value <= max_value_snapshot) then 'compliant'
      else 'out_of_range'
    end
  ) stored,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (tenant_id, session_id) references public.measurement_sessions(tenant_id, id) on delete cascade,
  foreign key (tenant_id, sample_id) references public.measurement_samples(tenant_id, id) on delete cascade,
  foreign key (tenant_id, parameter_id) references public.measurement_parameters(tenant_id, id) on delete restrict,
  foreign key (tenant_id, point_id) references public.measurement_points(tenant_id, id) on delete restrict,
  foreign key (tenant_id, asset_id) references public.assets(tenant_id, id) on delete set null,
  foreign key (tenant_id, location_id) references public.locations(tenant_id, id) on delete set null,
  foreign key (tenant_id, measurement_target_id) references public.measurement_targets(tenant_id, id) on delete set null,
  unique (tenant_id, sample_id, parameter_id, point_id)
);
create unique index uq_operational_readings_tenant_id on public.operational_readings(tenant_id, id);
create index idx_operational_readings_session on public.operational_readings(tenant_id, session_id);
create index idx_operational_readings_location_time on public.operational_readings(tenant_id, location_id, measured_at desc);
create index idx_operational_readings_parameter_time on public.operational_readings(tenant_id, parameter_id, measured_at desc);
create index idx_operational_readings_compliance on public.operational_readings(tenant_id, compliance_status, measured_at desc);

create or replace function private.prepare_operational_reading()
returns trigger
language plpgsql
set search_path = public, private, pg_temp
as $$
declare
  v_session public.measurement_sessions;
  v_sample public.measurement_samples;
  v_parameter public.measurement_parameters;
  v_target public.measurement_targets;
begin
  select * into v_session
  from public.measurement_sessions
  where tenant_id = new.tenant_id and id = new.session_id;
  if not found then raise exception 'Measurement session not found'; end if;
  if v_session.status <> 'draft' then raise exception 'Measurements can only be edited while session is draft'; end if;

  select * into v_sample
  from public.measurement_samples
  where tenant_id = new.tenant_id and id = new.sample_id and session_id = new.session_id;
  if not found then raise exception 'Measurement sample does not belong to session'; end if;

  select * into v_parameter
  from public.measurement_parameters
  where tenant_id = new.tenant_id and id = new.parameter_id and is_active = true;
  if not found then raise exception 'Measurement parameter not found or inactive'; end if;

  if v_parameter.hard_min_value is not null and new.value < v_parameter.hard_min_value then
    raise exception 'Value % is below the valid physical range for %', new.value, v_parameter.name;
  end if;
  if v_parameter.hard_max_value is not null and new.value > v_parameter.hard_max_value then
    raise exception 'Value % is above the valid physical range for %', new.value, v_parameter.name;
  end if;

  if new.unit_id is null then new.unit_id := v_parameter.default_unit_id; end if;
  if new.location_id is null then new.location_id := coalesce(v_sample.location_id, v_session.location_id); end if;
  if new.measured_at is null then new.measured_at := v_session.occurred_at; end if;
  if new.source_type is null then new.source_type := v_session.source_type; end if;
  if new.source_system is null then new.source_system := v_session.source_system; end if;

  v_target := private.resolve_measurement_target(
    new.tenant_id, new.parameter_id, new.point_id,
    v_session.site_id, new.location_id, new.asset_id, new.measured_at::date
  );

  if v_target.id is not null then
    new.measurement_target_id := v_target.id;
    new.target_value_snapshot := v_target.target_value;
    new.min_value_snapshot := v_target.min_value;
    new.max_value_snapshot := v_target.max_value;
  else
    new.measurement_target_id := null;
    new.target_value_snapshot := null;
    new.min_value_snapshot := null;
    new.max_value_snapshot := null;
  end if;

  return new;
end;
$$;
revoke all on function private.prepare_operational_reading() from public, anon, authenticated;

drop trigger if exists prepare_operational_reading on public.operational_readings;
create trigger prepare_operational_reading
before insert or update of value, parameter_id, point_id, location_id, asset_id, measured_at
on public.operational_readings
for each row execute function private.prepare_operational_reading();

create or replace function private.assert_measurement_sample_editable()
returns trigger
language plpgsql
set search_path = public, private, pg_temp
as $$
declare
  v_tenant uuid := coalesce(new.tenant_id, old.tenant_id);
  v_session uuid := coalesce(new.session_id, old.session_id);
  v_status text;
begin
  select status into v_status
  from public.measurement_sessions
  where tenant_id = v_tenant and id = v_session;
  if v_status is distinct from 'draft' then
    raise exception 'Measurement session is immutable outside draft status';
  end if;
  return coalesce(new, old);
end;
$$;
revoke all on function private.assert_measurement_sample_editable() from public, anon, authenticated;

drop trigger if exists lock_measurement_samples on public.measurement_samples;
create trigger lock_measurement_samples
before insert or update or delete on public.measurement_samples
for each row execute function private.assert_measurement_sample_editable();

drop trigger if exists lock_operational_readings on public.operational_readings;
create trigger lock_operational_readings
before delete on public.operational_readings
for each row execute function private.assert_measurement_sample_editable();

create or replace function private.lock_validated_measurement_session()
returns trigger
language plpgsql
set search_path = public, private, pg_temp
as $$
begin
  if tg_op = 'DELETE' and old.status <> 'draft' then
    raise exception 'Only draft measurement sessions can be deleted';
  end if;
  if tg_op = 'UPDATE' and old.status in ('validated','cancelled') then
    raise exception 'Validated or cancelled measurement sessions are immutable';
  end if;
  return coalesce(new, old);
end;
$$;
revoke all on function private.lock_validated_measurement_session() from public, anon, authenticated;

drop trigger if exists lock_measurement_session on public.measurement_sessions;
create trigger lock_measurement_session
before update or delete on public.measurement_sessions
for each row execute function private.lock_validated_measurement_session();

-- Reusar updated_at común.
create trigger measurement_parameters_updated_at before update on public.measurement_parameters
for each row execute function public.set_updated_at();
create trigger measurement_points_updated_at before update on public.measurement_points
for each row execute function public.set_updated_at();
create trigger hydraulic_component_models_updated_at before update on public.hydraulic_component_models
for each row execute function public.set_updated_at();
create trigger hydraulic_location_configs_updated_at before update on public.hydraulic_location_configs
for each row execute function public.set_updated_at();
create trigger measurement_targets_updated_at before update on public.measurement_targets
for each row execute function public.set_updated_at();
create trigger measurement_sessions_updated_at before update on public.measurement_sessions
for each row execute function public.set_updated_at();
create trigger measurement_samples_updated_at before update on public.measurement_samples
for each row execute function public.set_updated_at();
create trigger operational_readings_updated_at before update on public.operational_readings
for each row execute function public.set_updated_at();

-- RLS
alter table public.measurement_units enable row level security;
alter table public.measurement_parameters enable row level security;
alter table public.measurement_points enable row level security;
alter table public.hydraulic_component_models enable row level security;
alter table public.hydraulic_location_configs enable row level security;
alter table public.measurement_targets enable row level security;
alter table public.measurement_session_sequences enable row level security;
alter table public.measurement_sessions enable row level security;
alter table public.measurement_samples enable row level security;
alter table public.operational_readings enable row level security;

create policy measurement_units_select on public.measurement_units
for select to authenticated using (true);

create policy measurement_parameters_select on public.measurement_parameters
for select to authenticated using (public.is_tenant_member(tenant_id));
create policy measurement_parameters_manage on public.measurement_parameters
for all to authenticated
using (public.can_admin_tenant(tenant_id))
with check (public.can_admin_tenant(tenant_id));

create policy measurement_points_select on public.measurement_points
for select to authenticated using (public.is_tenant_member(tenant_id));
create policy measurement_points_manage on public.measurement_points
for all to authenticated
using (public.can_admin_tenant(tenant_id))
with check (public.can_admin_tenant(tenant_id));

create policy hydraulic_component_models_select on public.hydraulic_component_models
for select to authenticated using (public.is_tenant_member(tenant_id));
create policy hydraulic_component_models_manage on public.hydraulic_component_models
for all to authenticated
using (public.can_manage_tenant(tenant_id))
with check (public.can_manage_tenant(tenant_id));

create policy hydraulic_location_configs_select on public.hydraulic_location_configs
for select to authenticated using (public.is_tenant_member(tenant_id));
create policy hydraulic_location_configs_manage on public.hydraulic_location_configs
for all to authenticated
using (public.can_manage_tenant(tenant_id))
with check (public.can_manage_tenant(tenant_id));

create policy measurement_targets_select on public.measurement_targets
for select to authenticated using (public.is_tenant_member(tenant_id));
create policy measurement_targets_manage on public.measurement_targets
for all to authenticated
using (public.can_manage_tenant(tenant_id))
with check (public.can_manage_tenant(tenant_id));

create policy measurement_sessions_select on public.measurement_sessions
for select to authenticated using (public.is_tenant_member(tenant_id));
create policy measurement_sessions_insert on public.measurement_sessions
for insert to authenticated
with check (
  public.tenant_role(tenant_id) in ('owner','admin','planner','supervisor','technician')
  and created_by = (select auth.uid())
);
create policy measurement_sessions_update on public.measurement_sessions
for update to authenticated
using (
  public.can_manage_tenant(tenant_id) or created_by = (select auth.uid())
)
with check (public.is_tenant_member(tenant_id));
create policy measurement_sessions_delete on public.measurement_sessions
for delete to authenticated
using (public.can_manage_tenant(tenant_id) or created_by = (select auth.uid()));

create policy measurement_samples_select on public.measurement_samples
for select to authenticated using (public.is_tenant_member(tenant_id));
create policy measurement_samples_write on public.measurement_samples
for all to authenticated
using (
  public.can_manage_tenant(tenant_id) or exists (
    select 1 from public.measurement_sessions ms
    where ms.tenant_id = measurement_samples.tenant_id
      and ms.id = measurement_samples.session_id
      and ms.created_by = (select auth.uid())
      and ms.status = 'draft'
  )
)
with check (
  public.can_manage_tenant(tenant_id) or exists (
    select 1 from public.measurement_sessions ms
    where ms.tenant_id = measurement_samples.tenant_id
      and ms.id = measurement_samples.session_id
      and ms.created_by = (select auth.uid())
      and ms.status = 'draft'
  )
);

create policy operational_readings_select on public.operational_readings
for select to authenticated using (public.is_tenant_member(tenant_id));
create policy operational_readings_write on public.operational_readings
for all to authenticated
using (
  public.can_manage_tenant(tenant_id) or exists (
    select 1 from public.measurement_sessions ms
    where ms.tenant_id = operational_readings.tenant_id
      and ms.id = operational_readings.session_id
      and ms.created_by = (select auth.uid())
      and ms.status = 'draft'
  )
)
with check (
  public.can_manage_tenant(tenant_id) or exists (
    select 1 from public.measurement_sessions ms
    where ms.tenant_id = operational_readings.tenant_id
      and ms.id = operational_readings.session_id
      and ms.created_by = (select auth.uid())
      and ms.status = 'draft'
  )
);

-- La secuencia es interna; usuarios autenticados no acceden directamente.
revoke all on public.measurement_session_sequences from anon, authenticated;

-- Vistas analíticas trazables. security_invoker mantiene RLS de las tablas base.
create or replace view public.hydraulic_reading_results
with (security_invoker = true)
as
select
  r.id,
  r.tenant_id,
  r.session_id,
  s.code as session_code,
  s.occurred_at,
  s.site_id,
  r.location_id,
  sm.shift_number,
  mp.code as parameter_code,
  mp.name as parameter_name,
  pt.code as point_code,
  pt.name as point_name,
  r.value,
  u.code as unit_code,
  u.symbol as unit_symbol,
  r.target_value_snapshot as target_value,
  r.min_value_snapshot as min_value,
  r.max_value_snapshot as max_value,
  r.deviation_value,
  r.deviation_percent,
  r.compliance_status,
  r.quality_status,
  r.source_type,
  r.source_system,
  r.measured_at,
  r.recorded_by
from public.operational_readings r
join public.measurement_sessions s
  on s.tenant_id = r.tenant_id and s.id = r.session_id
join public.measurement_samples sm
  on sm.tenant_id = r.tenant_id and sm.id = r.sample_id
join public.measurement_parameters mp
  on mp.tenant_id = r.tenant_id and mp.id = r.parameter_id
join public.measurement_points pt
  on pt.tenant_id = r.tenant_id and pt.id = r.point_id
join public.measurement_units u on u.id = r.unit_id
where s.session_type = 'hydraulic_control';

create or replace view public.hydraulic_session_kpis
with (security_invoker = true)
as
select
  s.tenant_id,
  s.id as session_id,
  s.code,
  s.occurred_at,
  s.site_id,
  s.location_id,
  count(r.id) as total_readings,
  count(r.id) filter (where r.compliance_status <> 'not_evaluated') as evaluated_readings,
  count(r.id) filter (where r.compliance_status = 'compliant') as compliant_readings,
  count(r.id) filter (where r.compliance_status = 'out_of_range') as out_of_range_readings,
  round(
    100.0 * count(r.id) filter (where r.compliance_status = 'compliant') /
    nullif(count(r.id) filter (where r.compliance_status <> 'not_evaluated'), 0),
    2
  ) as compliance_percent,
  round(avg(r.value) filter (where mp.code = 'pressure'), 2) as avg_pressure,
  round(avg(r.value) filter (where mp.code = 'flow'), 2) as avg_flow
from public.measurement_sessions s
left join public.operational_readings r
  on r.tenant_id = s.tenant_id and r.session_id = s.id and r.quality_status = 'valid'
left join public.measurement_parameters mp
  on mp.tenant_id = r.tenant_id and mp.id = r.parameter_id
where s.session_type = 'hydraulic_control'
group by s.tenant_id, s.id, s.code, s.occurred_at, s.site_id, s.location_id;

grant select on public.hydraulic_reading_results to authenticated;
grant select on public.hydraulic_session_kpis to authenticated;

grant select on public.measurement_units to authenticated;
grant select on public.measurement_parameters, public.measurement_points,
  public.hydraulic_component_models, public.hydraulic_location_configs,
  public.measurement_targets, public.measurement_sessions, public.measurement_samples,
  public.operational_readings to authenticated;
grant insert, update, delete on public.measurement_parameters, public.measurement_points,
  public.hydraulic_component_models, public.hydraulic_location_configs,
  public.measurement_targets, public.measurement_sessions, public.measurement_samples,
  public.operational_readings to authenticated;
