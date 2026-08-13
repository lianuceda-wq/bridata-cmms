-- Bridata CMMS - índices de FKs y política explícita para tabla interna

create index if not exists idx_measurement_parameters_unit on public.measurement_parameters(default_unit_id);

create index if not exists idx_hydraulic_location_configs_created_by on public.hydraulic_location_configs(created_by);
create index if not exists idx_hydraulic_location_configs_hose on public.hydraulic_location_configs(tenant_id, hose_model_id);
create index if not exists idx_hydraulic_location_configs_valve on public.hydraulic_location_configs(tenant_id, valve_model_id);
create index if not exists idx_hydraulic_location_configs_pilot on public.hydraulic_location_configs(tenant_id, pilot_model_id);

create index if not exists idx_measurement_targets_created_by on public.measurement_targets(created_by);
create index if not exists idx_measurement_targets_asset on public.measurement_targets(tenant_id, asset_id);
create index if not exists idx_measurement_targets_location on public.measurement_targets(tenant_id, location_id);
create index if not exists idx_measurement_targets_point on public.measurement_targets(tenant_id, point_id);
create index if not exists idx_measurement_targets_site on public.measurement_targets(tenant_id, site_id);
create index if not exists idx_measurement_targets_unit on public.measurement_targets(unit_id);

create index if not exists idx_measurement_sessions_created_by on public.measurement_sessions(created_by);
create index if not exists idx_measurement_sessions_responsible on public.measurement_sessions(responsible_user_id);
create index if not exists idx_measurement_sessions_validator on public.measurement_sessions(validated_by);
create index if not exists idx_measurement_sessions_site on public.measurement_sessions(tenant_id, site_id);
create index if not exists idx_measurement_sessions_location on public.measurement_sessions(tenant_id, location_id);

create index if not exists idx_measurement_samples_location on public.measurement_samples(tenant_id, location_id);
create index if not exists idx_measurement_samples_hose on public.measurement_samples(tenant_id, hose_model_id);
create index if not exists idx_measurement_samples_valve on public.measurement_samples(tenant_id, valve_model_id);
create index if not exists idx_measurement_samples_pilot on public.measurement_samples(tenant_id, pilot_model_id);

create index if not exists idx_operational_readings_recorded_by on public.operational_readings(recorded_by);
create index if not exists idx_operational_readings_asset on public.operational_readings(tenant_id, asset_id);
create index if not exists idx_operational_readings_target on public.operational_readings(tenant_id, measurement_target_id);
create index if not exists idx_operational_readings_point on public.operational_readings(tenant_id, point_id);
create index if not exists idx_operational_readings_unit on public.operational_readings(unit_id);

create policy measurement_session_sequences_deny_authenticated
on public.measurement_session_sequences
for select to authenticated
using (false);
