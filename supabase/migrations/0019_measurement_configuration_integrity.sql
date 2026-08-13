-- Bridata CMMS - integridad de unidades, tolerancias y configuración hidráulica versionada

create or replace function private.validate_measurement_target()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_parameter_quantity text;
  v_unit_quantity text;
begin
  if new.target_value is null and new.min_value is null and new.max_value is null then
    raise exception 'Target requires at least target, minimum or maximum value';
  end if;

  select quantity into v_parameter_quantity
  from public.measurement_parameters
  where tenant_id = new.tenant_id and id = new.parameter_id;

  select quantity into v_unit_quantity
  from public.measurement_units
  where id = new.unit_id;

  if v_parameter_quantity is null or v_unit_quantity is null or v_parameter_quantity <> v_unit_quantity then
    raise exception 'Measurement unit is not compatible with the selected parameter';
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

create or replace function private.prepare_operational_reading()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_session public.measurement_sessions;
  v_sample public.measurement_samples;
  v_parameter public.measurement_parameters;
  v_target public.measurement_targets;
  v_unit_quantity text;
begin
  select * into v_session from public.measurement_sessions where tenant_id = new.tenant_id and id = new.session_id;
  if not found then raise exception 'Measurement session not found'; end if;
  if v_session.status <> 'draft' then raise exception 'Measurements can only be edited while session is draft'; end if;

  select * into v_sample from public.measurement_samples where tenant_id = new.tenant_id and id = new.sample_id and session_id = new.session_id;
  if not found then raise exception 'Measurement sample does not belong to session'; end if;

  select * into v_parameter from public.measurement_parameters where tenant_id = new.tenant_id and id = new.parameter_id and is_active = true;
  if not found then raise exception 'Measurement parameter not found or inactive'; end if;

  if new.unit_id is null then new.unit_id := v_parameter.default_unit_id; end if;
  select quantity into v_unit_quantity from public.measurement_units where id = new.unit_id and is_active = true;
  if v_unit_quantity is distinct from v_parameter.quantity then
    raise exception 'Reading unit is not compatible with parameter %', v_parameter.name;
  end if;

  if v_parameter.hard_min_value is not null and new.value < v_parameter.hard_min_value then
    raise exception 'Value % is below the valid physical range for %', new.value, v_parameter.name;
  end if;
  if v_parameter.hard_max_value is not null and new.value > v_parameter.hard_max_value then
    raise exception 'Value % is above the valid physical range for %', new.value, v_parameter.name;
  end if;

  if new.location_id is null then new.location_id := coalesce(v_sample.location_id, v_session.location_id); end if;

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

create or replace function public.create_measurement_target_version(
  p_tenant_id uuid,
  p_parameter_id uuid,
  p_point_id uuid,
  p_site_id uuid,
  p_location_id uuid,
  p_asset_id uuid,
  p_unit_id uuid,
  p_target_value numeric,
  p_min_value numeric,
  p_max_value numeric,
  p_tolerance_percent numeric,
  p_valid_from date,
  p_notes text default null
)
returns uuid
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
  v_min numeric := p_min_value;
  v_max numeric := p_max_value;
begin
  if not public.can_manage_tenant(p_tenant_id) then raise exception 'Insufficient permissions'; end if;
  if p_valid_from is null then raise exception 'valid_from is required'; end if;
  if p_tolerance_percent is not null and p_tolerance_percent < 0 then raise exception 'Tolerance cannot be negative'; end if;

  if p_target_value is not null and p_tolerance_percent is not null then
    if v_min is null then v_min := p_target_value * (1 - p_tolerance_percent / 100.0); end if;
    if v_max is null then v_max := p_target_value * (1 + p_tolerance_percent / 100.0); end if;
  end if;

  if exists (
    select 1 from public.measurement_targets mt
    where mt.tenant_id = p_tenant_id and mt.parameter_id = p_parameter_id
      and mt.point_id is not distinct from p_point_id and mt.site_id is not distinct from p_site_id
      and mt.location_id is not distinct from p_location_id and mt.asset_id is not distinct from p_asset_id
      and mt.is_active = true and mt.valid_from >= p_valid_from
  ) then raise exception 'A target version already starts on or after this date for the same scope'; end if;

  update public.measurement_targets mt
  set valid_to = p_valid_from - 1, updated_at = now()
  where mt.tenant_id = p_tenant_id and mt.parameter_id = p_parameter_id
    and mt.point_id is not distinct from p_point_id and mt.site_id is not distinct from p_site_id
    and mt.location_id is not distinct from p_location_id and mt.asset_id is not distinct from p_asset_id
    and mt.is_active = true and mt.valid_from < p_valid_from and (mt.valid_to is null or mt.valid_to >= p_valid_from);

  insert into public.measurement_targets(
    tenant_id,parameter_id,point_id,site_id,location_id,asset_id,unit_id,
    target_value,min_value,max_value,tolerance_percent,valid_from,notes,created_by
  ) values (
    p_tenant_id,p_parameter_id,p_point_id,p_site_id,p_location_id,p_asset_id,p_unit_id,
    p_target_value,v_min,v_max,p_tolerance_percent,p_valid_from,nullif(btrim(p_notes),''),auth.uid()
  ) returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.create_hydraulic_location_config_version(
  p_tenant_id uuid,
  p_location_id uuid,
  p_hose_model_id uuid,
  p_valve_model_id uuid,
  p_pilot_model_id uuid,
  p_valid_from date,
  p_notes text default null
)
returns uuid
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare v_id uuid;
begin
  if not public.can_manage_tenant(p_tenant_id) then raise exception 'Insufficient permissions'; end if;
  if p_valid_from is null then raise exception 'valid_from is required'; end if;
  if not exists(select 1 from public.locations l where l.tenant_id=p_tenant_id and l.id=p_location_id) then
    raise exception 'Location does not belong to tenant';
  end if;
  if exists(select 1 from public.hydraulic_location_configs c where c.tenant_id=p_tenant_id and c.location_id=p_location_id and c.is_active=true and c.valid_from>=p_valid_from) then
    raise exception 'A hydraulic configuration already starts on or after this date';
  end if;

  update public.hydraulic_location_configs c
  set valid_to=p_valid_from-1, updated_at=now()
  where c.tenant_id=p_tenant_id and c.location_id=p_location_id and c.is_active=true
    and c.valid_from<p_valid_from and (c.valid_to is null or c.valid_to>=p_valid_from);

  insert into public.hydraulic_location_configs(
    tenant_id,location_id,hose_model_id,valve_model_id,pilot_model_id,valid_from,notes,created_by
  ) values (
    p_tenant_id,p_location_id,p_hose_model_id,p_valve_model_id,p_pilot_model_id,p_valid_from,nullif(btrim(p_notes),''),auth.uid()
  ) returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.create_hydraulic_location_config_version(uuid,uuid,uuid,uuid,uuid,date,text) from public, anon;
grant execute on function public.create_hydraulic_location_config_version(uuid,uuid,uuid,uuid,uuid,date,text) to authenticated;
