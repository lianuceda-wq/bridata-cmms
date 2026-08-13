-- Bridata CMMS - índices de cobertura para FKs del motor de mantenimiento

create index if not exists idx_asset_meters_asset_id
  on public.asset_meters(asset_id);

create index if not exists idx_plan_assets_plan_id
  on public.maintenance_plan_assets(plan_id);
create index if not exists idx_plan_assets_asset_id
  on public.maintenance_plan_assets(asset_id);
create index if not exists idx_plan_assets_created_by
  on public.maintenance_plan_assets(created_by);

create index if not exists idx_routines_plan_id
  on public.maintenance_routines(plan_id);

create index if not exists idx_meter_readings_meter_id
  on public.meter_readings(meter_id);

create index if not exists idx_schedule_states_plan_id
  on public.maintenance_schedule_states(plan_id);
create index if not exists idx_schedule_states_plan_asset_id
  on public.maintenance_schedule_states(plan_asset_id);
create index if not exists idx_schedule_states_routine_id
  on public.maintenance_schedule_states(routine_id);
create index if not exists idx_schedule_states_meter_id
  on public.maintenance_schedule_states(meter_id);
create index if not exists idx_schedule_states_tenant_plan_asset
  on public.maintenance_schedule_states(tenant_id, plan_id, plan_asset_id);
create index if not exists idx_schedule_states_tenant_routine
  on public.maintenance_schedule_states(tenant_id, plan_id, routine_id);
