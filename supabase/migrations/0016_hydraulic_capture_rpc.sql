-- Bridata CMMS - captura hidráulica transaccional desde una grilla tipo formato de campo

create or replace function public.create_hydraulic_session(
  p_tenant_id uuid,
  p_site_id uuid,
  p_location_id uuid,
  p_occurred_at timestamptz,
  p_responsible_name text,
  p_notes text,
  p_rows jsonb,
  p_submit boolean default false
)
returns table(session_id uuid, session_code text, session_status text, reading_count bigint, out_of_range_count bigint)
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_session_id uuid;
  v_code text;
  v_status text;
  v_row jsonb;
  v_shift integer;
  v_location_id uuid;
  v_shift_sample_id uuid;
  v_location_sample_id uuid;
  v_hose uuid;
  v_valve uuid;
  v_pilot uuid;
  v_value numeric;
  v_param uuid;
  v_point uuid;
  v_unit uuid;
  v_seq integer := 0;
begin
  if public.tenant_role(p_tenant_id) not in ('owner','admin','planner','supervisor','technician') then
    raise exception 'Insufficient permissions to capture hydraulic measurements';
  end if;
  if p_site_id is null then raise exception 'Site/farm is required'; end if;
  if p_occurred_at is null then raise exception 'Measurement date is required'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then
    raise exception 'At least one hydraulic row is required';
  end if;

  if not exists (select 1 from public.sites where tenant_id=p_tenant_id and id=p_site_id) then
    raise exception 'Site does not belong to tenant';
  end if;
  if p_location_id is not null and not exists (
    select 1 from public.locations where tenant_id=p_tenant_id and site_id=p_site_id and id=p_location_id
  ) then raise exception 'Header location does not belong to site'; end if;

  insert into public.measurement_sessions(
    tenant_id, session_type, site_id, location_id, occurred_at,
    responsible_name, source_type, source_system, notes, created_by
  ) values (
    p_tenant_id, 'hydraulic_control', p_site_id, p_location_id, p_occurred_at,
    nullif(btrim(p_responsible_name),''), 'manual', 'bridata', nullif(btrim(p_notes),''), auth.uid()
  ) returning id, code, status into v_session_id, v_code, v_status;

  for v_row in select value from jsonb_array_elements(p_rows) loop
    v_seq := v_seq + 1;
    v_shift := nullif(v_row->>'shift_number','')::integer;
    if v_shift is null or v_shift <= 0 then raise exception 'Each row requires a positive shift number'; end if;

    -- Un solo sample de turno aunque el turno tenga varios lotes.
    select id into v_shift_sample_id from public.measurement_samples
    where tenant_id=p_tenant_id and session_id=v_session_id and sample_type='shift' and shift_number=v_shift;
    if v_shift_sample_id is null then
      insert into public.measurement_samples(tenant_id,session_id,sample_type,shift_number,sequence)
      values(p_tenant_id,v_session_id,'shift',v_shift,v_seq)
      returning id into v_shift_sample_id;
    end if;

    -- Helper inline: cada lectura de turno se inserta/actualiza si viene informada.
    if nullif(v_row->>'flow','') is not null then
      v_value := (v_row->>'flow')::numeric;
      select p.id,pt.id,p.default_unit_id into v_param,v_point,v_unit
      from public.measurement_parameters p join public.measurement_points pt on pt.tenant_id=p.tenant_id
      where p.tenant_id=p_tenant_id and p.code='flow' and pt.code='shift_flow';
      insert into public.operational_readings(tenant_id,session_id,sample_id,parameter_id,point_id,unit_id,value,measured_at)
      values(p_tenant_id,v_session_id,v_shift_sample_id,v_param,v_point,v_unit,v_value,p_occurred_at)
      on conflict(tenant_id,sample_id,parameter_id,point_id) do update set value=excluded.value,measured_at=excluded.measured_at;
    end if;

    if nullif(v_row->>'filter_before','') is not null then
      v_value := (v_row->>'filter_before')::numeric;
      select p.id,pt.id,p.default_unit_id into v_param,v_point,v_unit from public.measurement_parameters p join public.measurement_points pt on pt.tenant_id=p.tenant_id where p.tenant_id=p_tenant_id and p.code='pressure' and pt.code='filter_before';
      insert into public.operational_readings(tenant_id,session_id,sample_id,parameter_id,point_id,unit_id,value,measured_at) values(p_tenant_id,v_session_id,v_shift_sample_id,v_param,v_point,v_unit,v_value,p_occurred_at)
      on conflict(tenant_id,sample_id,parameter_id,point_id) do update set value=excluded.value,measured_at=excluded.measured_at;
    end if;
    if nullif(v_row->>'filter_after','') is not null then
      v_value := (v_row->>'filter_after')::numeric;
      select p.id,pt.id,p.default_unit_id into v_param,v_point,v_unit from public.measurement_parameters p join public.measurement_points pt on pt.tenant_id=p.tenant_id where p.tenant_id=p_tenant_id and p.code='pressure' and pt.code='filter_after';
      insert into public.operational_readings(tenant_id,session_id,sample_id,parameter_id,point_id,unit_id,value,measured_at) values(p_tenant_id,v_session_id,v_shift_sample_id,v_param,v_point,v_unit,v_value,p_occurred_at)
      on conflict(tenant_id,sample_id,parameter_id,point_id) do update set value=excluded.value,measured_at=excluded.measured_at;
    end if;
    if nullif(v_row->>'field_pressure','') is not null then
      v_value := (v_row->>'field_pressure')::numeric;
      select p.id,pt.id,p.default_unit_id into v_param,v_point,v_unit from public.measurement_parameters p join public.measurement_points pt on pt.tenant_id=p.tenant_id where p.tenant_id=p_tenant_id and p.code='pressure' and pt.code='field_pressure';
      insert into public.operational_readings(tenant_id,session_id,sample_id,parameter_id,point_id,unit_id,value,measured_at) values(p_tenant_id,v_session_id,v_shift_sample_id,v_param,v_point,v_unit,v_value,p_occurred_at)
      on conflict(tenant_id,sample_id,parameter_id,point_id) do update set value=excluded.value,measured_at=excluded.measured_at;
    end if;
    if nullif(v_row->>'field_valve','') is not null then
      v_value := (v_row->>'field_valve')::numeric;
      select p.id,pt.id,p.default_unit_id into v_param,v_point,v_unit from public.measurement_parameters p join public.measurement_points pt on pt.tenant_id=p.tenant_id where p.tenant_id=p_tenant_id and p.code='pressure' and pt.code='field_valve';
      insert into public.operational_readings(tenant_id,session_id,sample_id,parameter_id,point_id,unit_id,value,measured_at) values(p_tenant_id,v_session_id,v_shift_sample_id,v_param,v_point,v_unit,v_value,p_occurred_at)
      on conflict(tenant_id,sample_id,parameter_id,point_id) do update set value=excluded.value,measured_at=excluded.measured_at;
    end if;
    if nullif(v_row->>'field_relief','') is not null then
      v_value := (v_row->>'field_relief')::numeric;
      select p.id,pt.id,p.default_unit_id into v_param,v_point,v_unit from public.measurement_parameters p join public.measurement_points pt on pt.tenant_id=p.tenant_id where p.tenant_id=p_tenant_id and p.code='pressure' and pt.code='field_relief';
      insert into public.operational_readings(tenant_id,session_id,sample_id,parameter_id,point_id,unit_id,value,measured_at) values(p_tenant_id,v_session_id,v_shift_sample_id,v_param,v_point,v_unit,v_value,p_occurred_at)
      on conflict(tenant_id,sample_id,parameter_id,point_id) do update set value=excluded.value,measured_at=excluded.measured_at;
    end if;

    v_location_id := nullif(v_row->>'location_id','')::uuid;
    if v_location_id is null then continue; end if;
    if not exists (select 1 from public.locations where tenant_id=p_tenant_id and site_id=p_site_id and id=v_location_id) then
      raise exception 'Lot/location does not belong to selected site';
    end if;
    v_hose := nullif(v_row->>'hose_model_id','')::uuid;
    v_valve := nullif(v_row->>'valve_model_id','')::uuid;
    v_pilot := nullif(v_row->>'pilot_model_id','')::uuid;

    select id into v_location_sample_id from public.measurement_samples
    where tenant_id=p_tenant_id and session_id=v_session_id and sample_type='location' and shift_number=v_shift and location_id=v_location_id;
    if v_location_sample_id is null then
      insert into public.measurement_samples(tenant_id,session_id,sample_type,shift_number,location_id,sequence,hose_model_id,valve_model_id,pilot_model_id,notes)
      values(p_tenant_id,v_session_id,'location',v_shift,v_location_id,v_seq,v_hose,v_valve,v_pilot,nullif(v_row->>'notes',''))
      returning id into v_location_sample_id;
    else
      update public.measurement_samples set hose_model_id=v_hose,valve_model_id=v_valve,pilot_model_id=v_pilot,notes=nullif(v_row->>'notes','') where id=v_location_sample_id;
    end if;

    -- Lecturas de presión por lote. El trigger de operational_readings resuelve y congela el nominal vigente.
    if nullif(v_row->>'valve_before','') is not null then
      v_value := (v_row->>'valve_before')::numeric; select p.id,pt.id,p.default_unit_id into v_param,v_point,v_unit from public.measurement_parameters p join public.measurement_points pt on pt.tenant_id=p.tenant_id where p.tenant_id=p_tenant_id and p.code='pressure' and pt.code='valve_before';
      insert into public.operational_readings(tenant_id,session_id,sample_id,parameter_id,point_id,unit_id,location_id,value,measured_at) values(p_tenant_id,v_session_id,v_location_sample_id,v_param,v_point,v_unit,v_location_id,v_value,p_occurred_at) on conflict(tenant_id,sample_id,parameter_id,point_id) do update set value=excluded.value,measured_at=excluded.measured_at;
    end if;
    if nullif(v_row->>'valve_after','') is not null then
      v_value := (v_row->>'valve_after')::numeric; select p.id,pt.id,p.default_unit_id into v_param,v_point,v_unit from public.measurement_parameters p join public.measurement_points pt on pt.tenant_id=p.tenant_id where p.tenant_id=p_tenant_id and p.code='pressure' and pt.code='valve_after';
      insert into public.operational_readings(tenant_id,session_id,sample_id,parameter_id,point_id,unit_id,location_id,value,measured_at) values(p_tenant_id,v_session_id,v_location_sample_id,v_param,v_point,v_unit,v_location_id,v_value,p_occurred_at) on conflict(tenant_id,sample_id,parameter_id,point_id) do update set value=excluded.value,measured_at=excluded.measured_at;
    end if;
    if nullif(v_row->>'fd_right','') is not null then
      v_value := (v_row->>'fd_right')::numeric; select p.id,pt.id,p.default_unit_id into v_param,v_point,v_unit from public.measurement_parameters p join public.measurement_points pt on pt.tenant_id=p.tenant_id where p.tenant_id=p_tenant_id and p.code='pressure' and pt.code='fd_right';
      insert into public.operational_readings(tenant_id,session_id,sample_id,parameter_id,point_id,unit_id,location_id,value,measured_at) values(p_tenant_id,v_session_id,v_location_sample_id,v_param,v_point,v_unit,v_location_id,v_value,p_occurred_at) on conflict(tenant_id,sample_id,parameter_id,point_id) do update set value=excluded.value,measured_at=excluded.measured_at;
    end if;
    if nullif(v_row->>'fd_center','') is not null then
      v_value := (v_row->>'fd_center')::numeric; select p.id,pt.id,p.default_unit_id into v_param,v_point,v_unit from public.measurement_parameters p join public.measurement_points pt on pt.tenant_id=p.tenant_id where p.tenant_id=p_tenant_id and p.code='pressure' and pt.code='fd_center';
      insert into public.operational_readings(tenant_id,session_id,sample_id,parameter_id,point_id,unit_id,location_id,value,measured_at) values(p_tenant_id,v_session_id,v_location_sample_id,v_param,v_point,v_unit,v_location_id,v_value,p_occurred_at) on conflict(tenant_id,sample_id,parameter_id,point_id) do update set value=excluded.value,measured_at=excluded.measured_at;
    end if;
    if nullif(v_row->>'fd_left','') is not null then
      v_value := (v_row->>'fd_left')::numeric; select p.id,pt.id,p.default_unit_id into v_param,v_point,v_unit from public.measurement_parameters p join public.measurement_points pt on pt.tenant_id=p.tenant_id where p.tenant_id=p_tenant_id and p.code='pressure' and pt.code='fd_left';
      insert into public.operational_readings(tenant_id,session_id,sample_id,parameter_id,point_id,unit_id,location_id,value,measured_at) values(p_tenant_id,v_session_id,v_location_sample_id,v_param,v_point,v_unit,v_location_id,v_value,p_occurred_at) on conflict(tenant_id,sample_id,parameter_id,point_id) do update set value=excluded.value,measured_at=excluded.measured_at;
    end if;
    if nullif(v_row->>'fm_right','') is not null then
      v_value := (v_row->>'fm_right')::numeric; select p.id,pt.id,p.default_unit_id into v_param,v_point,v_unit from public.measurement_parameters p join public.measurement_points pt on pt.tenant_id=p.tenant_id where p.tenant_id=p_tenant_id and p.code='pressure' and pt.code='fm_right';
      insert into public.operational_readings(tenant_id,session_id,sample_id,parameter_id,point_id,unit_id,location_id,value,measured_at) values(p_tenant_id,v_session_id,v_location_sample_id,v_param,v_point,v_unit,v_location_id,v_value,p_occurred_at) on conflict(tenant_id,sample_id,parameter_id,point_id) do update set value=excluded.value,measured_at=excluded.measured_at;
    end if;
    if nullif(v_row->>'fm_center','') is not null then
      v_value := (v_row->>'fm_center')::numeric; select p.id,pt.id,p.default_unit_id into v_param,v_point,v_unit from public.measurement_parameters p join public.measurement_points pt on pt.tenant_id=p.tenant_id where p.tenant_id=p_tenant_id and p.code='pressure' and pt.code='fm_center';
      insert into public.operational_readings(tenant_id,session_id,sample_id,parameter_id,point_id,unit_id,location_id,value,measured_at) values(p_tenant_id,v_session_id,v_location_sample_id,v_param,v_point,v_unit,v_location_id,v_value,p_occurred_at) on conflict(tenant_id,sample_id,parameter_id,point_id) do update set value=excluded.value,measured_at=excluded.measured_at;
    end if;
    if nullif(v_row->>'fm_left','') is not null then
      v_value := (v_row->>'fm_left')::numeric; select p.id,pt.id,p.default_unit_id into v_param,v_point,v_unit from public.measurement_parameters p join public.measurement_points pt on pt.tenant_id=p.tenant_id where p.tenant_id=p_tenant_id and p.code='pressure' and pt.code='fm_left';
      insert into public.operational_readings(tenant_id,session_id,sample_id,parameter_id,point_id,unit_id,location_id,value,measured_at) values(p_tenant_id,v_session_id,v_location_sample_id,v_param,v_point,v_unit,v_location_id,v_value,p_occurred_at) on conflict(tenant_id,sample_id,parameter_id,point_id) do update set value=excluded.value,measured_at=excluded.measured_at;
    end if;
  end loop;

  if p_submit then
    update public.measurement_sessions set status='submitted' where id=v_session_id;
  end if;
  select status into v_status from public.measurement_sessions where id=v_session_id;

  return query
  select v_session_id,v_code,v_status,
    count(*)::bigint,
    count(*) filter(where compliance_status='out_of_range')::bigint
  from public.operational_readings where tenant_id=p_tenant_id and session_id=v_session_id;
end;
$$;

revoke all on function public.create_hydraulic_session(uuid,uuid,uuid,timestamptz,text,text,jsonb,boolean) from public,anon;
grant execute on function public.create_hydraulic_session(uuid,uuid,uuid,timestamptz,text,text,jsonb,boolean) to authenticated;
