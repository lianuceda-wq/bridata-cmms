-- Bridata CMMS - hardening del motor de mediciones e hidráulica

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

create or replace function private.assert_measurement_sample_editable()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_tenant uuid;
  v_session uuid;
  v_status text;
begin
  if tg_op = 'DELETE' then
    v_tenant := old.tenant_id;
    v_session := old.session_id;
  else
    v_tenant := new.tenant_id;
    v_session := new.session_id;
  end if;

  select status into v_status
  from public.measurement_sessions
  where tenant_id = v_tenant and id = v_session;

  if v_status is distinct from 'draft' then
    raise exception 'Measurement session is immutable outside draft status';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function private.assert_measurement_sample_editable() from public, anon, authenticated;

create or replace function private.enforce_measurement_session_lifecycle()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_is_manager boolean;
  v_uid uuid := auth.uid();
begin
  v_is_manager := public.can_manage_tenant(old.tenant_id);

  if tg_op = 'DELETE' then
    if old.status <> 'draft' then
      raise exception 'Only draft measurement sessions can be deleted';
    end if;
    if not v_is_manager and old.created_by <> v_uid then
      raise exception 'Insufficient permissions to delete this session';
    end if;
    return old;
  end if;

  if old.status in ('validated','cancelled') then
    raise exception 'Validated or cancelled measurement sessions are immutable';
  end if;

  if old.status = 'submitted' and new.status = 'submitted' and not v_is_manager then
    raise exception 'Submitted sessions can only be edited by a manager';
  end if;

  if new.status = old.status then
    return new;
  end if;

  if old.status = 'draft' and new.status = 'submitted' then
    if not v_is_manager and old.created_by <> v_uid then
      raise exception 'Only the creator or a manager can submit this session';
    end if;
    return new;
  end if;

  if old.status in ('draft','submitted') and new.status = 'validated' then
    if not v_is_manager then
      raise exception 'Only owner, admin, planner or supervisor can validate measurements';
    end if;
    new.validated_by := v_uid;
    new.validated_at := now();
    return new;
  end if;

  if old.status in ('draft','submitted') and new.status = 'cancelled' then
    if not v_is_manager and old.created_by <> v_uid then
      raise exception 'Only the creator or a manager can cancel this session';
    end if;
    return new;
  end if;

  if old.status = 'submitted' and new.status = 'draft' then
    if not v_is_manager then
      raise exception 'Only a manager can reopen a submitted session';
    end if;
    return new;
  end if;

  raise exception 'Invalid measurement session transition: % -> %', old.status, new.status;
end;
$$;
revoke all on function private.enforce_measurement_session_lifecycle() from public, anon, authenticated;

drop trigger if exists lock_measurement_session on public.measurement_sessions;
create trigger lock_measurement_session
before update or delete on public.measurement_sessions
for each row execute function private.enforce_measurement_session_lifecycle();

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
begin
  if not public.can_manage_tenant(p_tenant_id) then
    raise exception 'Insufficient permissions';
  end if;

  if p_valid_from is null then raise exception 'valid_from is required'; end if;

  if exists (
    select 1 from public.measurement_targets mt
    where mt.tenant_id = p_tenant_id
      and mt.parameter_id = p_parameter_id
      and mt.point_id is not distinct from p_point_id
      and mt.site_id is not distinct from p_site_id
      and mt.location_id is not distinct from p_location_id
      and mt.asset_id is not distinct from p_asset_id
      and mt.is_active = true
      and mt.valid_from >= p_valid_from
  ) then
    raise exception 'A target version already starts on or after this date for the same scope';
  end if;

  update public.measurement_targets mt
  set valid_to = p_valid_from - 1,
      updated_at = now()
  where mt.tenant_id = p_tenant_id
    and mt.parameter_id = p_parameter_id
    and mt.point_id is not distinct from p_point_id
    and mt.site_id is not distinct from p_site_id
    and mt.location_id is not distinct from p_location_id
    and mt.asset_id is not distinct from p_asset_id
    and mt.is_active = true
    and mt.valid_from < p_valid_from
    and (mt.valid_to is null or mt.valid_to >= p_valid_from);

  insert into public.measurement_targets(
    tenant_id, parameter_id, point_id, site_id, location_id, asset_id,
    unit_id, target_value, min_value, max_value, tolerance_percent,
    valid_from, notes, created_by
  ) values (
    p_tenant_id, p_parameter_id, p_point_id, p_site_id, p_location_id, p_asset_id,
    p_unit_id, p_target_value, p_min_value, p_max_value, p_tolerance_percent,
    p_valid_from, nullif(btrim(p_notes), ''), auth.uid()
  ) returning id into v_id;

  return v_id;
end;
$$;
revoke all on function public.create_measurement_target_version(uuid,uuid,uuid,uuid,uuid,uuid,uuid,numeric,numeric,numeric,numeric,date,text) from public, anon;
grant execute on function public.create_measurement_target_version(uuid,uuid,uuid,uuid,uuid,uuid,uuid,numeric,numeric,numeric,numeric,date,text) to authenticated;

-- Separar SELECT de escrituras evita políticas permisivas duplicadas.
drop policy if exists measurement_parameters_manage on public.measurement_parameters;
create policy measurement_parameters_insert on public.measurement_parameters for insert to authenticated with check (public.can_admin_tenant(tenant_id));
create policy measurement_parameters_update on public.measurement_parameters for update to authenticated using (public.can_admin_tenant(tenant_id)) with check (public.can_admin_tenant(tenant_id));
create policy measurement_parameters_delete on public.measurement_parameters for delete to authenticated using (public.can_admin_tenant(tenant_id));

drop policy if exists measurement_points_manage on public.measurement_points;
create policy measurement_points_insert on public.measurement_points for insert to authenticated with check (public.can_admin_tenant(tenant_id));
create policy measurement_points_update on public.measurement_points for update to authenticated using (public.can_admin_tenant(tenant_id)) with check (public.can_admin_tenant(tenant_id));
create policy measurement_points_delete on public.measurement_points for delete to authenticated using (public.can_admin_tenant(tenant_id));

drop policy if exists hydraulic_component_models_manage on public.hydraulic_component_models;
create policy hydraulic_component_models_insert on public.hydraulic_component_models for insert to authenticated with check (public.can_manage_tenant(tenant_id));
create policy hydraulic_component_models_update on public.hydraulic_component_models for update to authenticated using (public.can_manage_tenant(tenant_id)) with check (public.can_manage_tenant(tenant_id));
create policy hydraulic_component_models_delete on public.hydraulic_component_models for delete to authenticated using (public.can_manage_tenant(tenant_id));

drop policy if exists hydraulic_location_configs_manage on public.hydraulic_location_configs;
create policy hydraulic_location_configs_insert on public.hydraulic_location_configs for insert to authenticated with check (public.can_manage_tenant(tenant_id));
create policy hydraulic_location_configs_update on public.hydraulic_location_configs for update to authenticated using (public.can_manage_tenant(tenant_id)) with check (public.can_manage_tenant(tenant_id));
create policy hydraulic_location_configs_delete on public.hydraulic_location_configs for delete to authenticated using (public.can_manage_tenant(tenant_id));

drop policy if exists measurement_targets_manage on public.measurement_targets;
create policy measurement_targets_insert on public.measurement_targets for insert to authenticated with check (public.can_manage_tenant(tenant_id));
create policy measurement_targets_update on public.measurement_targets for update to authenticated using (public.can_manage_tenant(tenant_id)) with check (public.can_manage_tenant(tenant_id));
create policy measurement_targets_delete on public.measurement_targets for delete to authenticated using (public.can_admin_tenant(tenant_id));

drop policy if exists measurement_samples_write on public.measurement_samples;
create policy measurement_samples_insert on public.measurement_samples for insert to authenticated with check (
  public.can_manage_tenant(tenant_id) or exists (
    select 1 from public.measurement_sessions ms
    where ms.tenant_id = measurement_samples.tenant_id and ms.id = measurement_samples.session_id
      and ms.created_by = (select auth.uid()) and ms.status = 'draft'
  )
);
create policy measurement_samples_update on public.measurement_samples for update to authenticated using (
  public.can_manage_tenant(tenant_id) or exists (
    select 1 from public.measurement_sessions ms
    where ms.tenant_id = measurement_samples.tenant_id and ms.id = measurement_samples.session_id
      and ms.created_by = (select auth.uid()) and ms.status = 'draft'
  )
) with check (
  public.can_manage_tenant(tenant_id) or exists (
    select 1 from public.measurement_sessions ms
    where ms.tenant_id = measurement_samples.tenant_id and ms.id = measurement_samples.session_id
      and ms.created_by = (select auth.uid()) and ms.status = 'draft'
  )
);
create policy measurement_samples_delete on public.measurement_samples for delete to authenticated using (
  public.can_manage_tenant(tenant_id) or exists (
    select 1 from public.measurement_sessions ms
    where ms.tenant_id = measurement_samples.tenant_id and ms.id = measurement_samples.session_id
      and ms.created_by = (select auth.uid()) and ms.status = 'draft'
  )
);

drop policy if exists operational_readings_write on public.operational_readings;
create policy operational_readings_insert on public.operational_readings for insert to authenticated with check (
  public.can_manage_tenant(tenant_id) or exists (
    select 1 from public.measurement_sessions ms
    where ms.tenant_id = operational_readings.tenant_id and ms.id = operational_readings.session_id
      and ms.created_by = (select auth.uid()) and ms.status = 'draft'
  )
);
create policy operational_readings_update on public.operational_readings for update to authenticated using (
  public.can_manage_tenant(tenant_id) or exists (
    select 1 from public.measurement_sessions ms
    where ms.tenant_id = operational_readings.tenant_id and ms.id = operational_readings.session_id
      and ms.created_by = (select auth.uid()) and ms.status = 'draft'
  )
) with check (
  public.can_manage_tenant(tenant_id) or exists (
    select 1 from public.measurement_sessions ms
    where ms.tenant_id = operational_readings.tenant_id and ms.id = operational_readings.session_id
      and ms.created_by = (select auth.uid()) and ms.status = 'draft'
  )
);
create policy operational_readings_delete on public.operational_readings for delete to authenticated using (
  public.can_manage_tenant(tenant_id) or exists (
    select 1 from public.measurement_sessions ms
    where ms.tenant_id = operational_readings.tenant_id and ms.id = operational_readings.session_id
      and ms.created_by = (select auth.uid()) and ms.status = 'draft'
  )
);
