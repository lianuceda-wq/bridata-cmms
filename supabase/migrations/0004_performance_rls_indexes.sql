-- Bridata CMMS - optimización de índices y políticas RLS

create index if not exists idx_assets_site_id on public.assets(site_id);
create index if not exists idx_assets_location_id on public.assets(location_id);
create index if not exists idx_assets_tenant_parent on public.assets(tenant_id, parent_asset_id);
create index if not exists idx_audit_logs_tenant_id on public.audit_logs(tenant_id);
create index if not exists idx_audit_logs_user_id on public.audit_logs(user_id);
create index if not exists idx_locations_site_id on public.locations(site_id);
create index if not exists idx_locations_tenant_parent on public.locations(tenant_id, parent_location_id);
create index if not exists idx_plan_tasks_tenant_id on public.maintenance_plan_tasks(tenant_id);
create index if not exists idx_plans_asset_id on public.maintenance_plans(asset_id);
create index if not exists idx_plans_tenant_asset on public.maintenance_plans(tenant_id, asset_id);
create index if not exists idx_tenant_members_user_id on public.tenant_members(user_id);
create index if not exists idx_work_orders_asset_id on public.work_orders(asset_id);
create index if not exists idx_work_orders_plan_id on public.work_orders(plan_id);
create index if not exists idx_work_orders_assigned_to on public.work_orders(assigned_to);
create index if not exists idx_work_orders_created_by on public.work_orders(created_by);
create index if not exists idx_work_orders_tenant_asset on public.work_orders(tenant_id, asset_id);
create index if not exists idx_work_orders_tenant_plan on public.work_orders(tenant_id, plan_id);

drop policy if exists profiles_self_select on public.profiles;
create policy profiles_self_select on public.profiles
for select to authenticated
using (id = (select auth.uid()));

drop policy if exists profiles_self_update on public.profiles;
create policy profiles_self_update on public.profiles
for update to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

drop policy if exists work_orders_insert_manager on public.work_orders;
drop policy if exists work_orders_insert_technician_request on public.work_orders;
create policy work_orders_insert on public.work_orders
for insert to authenticated
with check (
  public.can_manage_tenant(tenant_id)
  or (
    public.tenant_role(tenant_id) = 'technician'
    and created_by = (select auth.uid())
    and status = 'requested'
  )
);

drop policy if exists work_orders_update_manager on public.work_orders;
drop policy if exists work_orders_update_assignee on public.work_orders;
create policy work_orders_update on public.work_orders
for update to authenticated
using (
  public.can_manage_tenant(tenant_id)
  or (
    public.tenant_role(tenant_id) = 'technician'
    and assigned_to = (select auth.uid())
  )
)
with check (
  public.can_manage_tenant(tenant_id)
  or (
    public.tenant_role(tenant_id) = 'technician'
    and assigned_to = (select auth.uid())
  )
);
