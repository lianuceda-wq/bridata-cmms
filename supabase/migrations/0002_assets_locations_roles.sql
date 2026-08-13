-- Bridata CMMS - ubicaciones, onboarding y permisos por rol

create table public.locations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  site_id uuid not null references public.sites(id) on delete cascade,
  parent_location_id uuid references public.locations(id) on delete set null,
  code text,
  name text not null,
  location_type text not null default 'area' check (location_type in ('area','system','sector','room','line','warehouse','other')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, site_id, code)
);

alter table public.assets
  add column location_id uuid references public.locations(id) on delete set null,
  add column description text,
  add column is_active boolean not null default true;

create unique index if not exists uq_sites_tenant_id on public.sites(tenant_id, id);
create unique index if not exists uq_locations_tenant_id on public.locations(tenant_id, id);
create unique index if not exists uq_assets_tenant_id on public.assets(tenant_id, id);
create unique index if not exists uq_plans_tenant_id on public.maintenance_plans(tenant_id, id);

alter table public.locations
  add constraint locations_tenant_site_fk
  foreign key (tenant_id, site_id) references public.sites(tenant_id, id) on delete cascade;

alter table public.locations
  add constraint locations_tenant_parent_fk
  foreign key (tenant_id, parent_location_id) references public.locations(tenant_id, id) on delete set null;

alter table public.assets
  add constraint assets_tenant_site_fk
  foreign key (tenant_id, site_id) references public.sites(tenant_id, id) on delete set null;

alter table public.assets
  add constraint assets_tenant_location_fk
  foreign key (tenant_id, location_id) references public.locations(tenant_id, id) on delete set null;

alter table public.assets
  add constraint assets_tenant_parent_fk
  foreign key (tenant_id, parent_asset_id) references public.assets(tenant_id, id) on delete set null;

alter table public.maintenance_plans
  add constraint maintenance_plans_tenant_asset_fk
  foreign key (tenant_id, asset_id) references public.assets(tenant_id, id) on delete cascade;

alter table public.work_orders
  add constraint work_orders_tenant_asset_fk
  foreign key (tenant_id, asset_id) references public.assets(tenant_id, id) on delete set null;

alter table public.work_orders
  add constraint work_orders_tenant_plan_fk
  foreign key (tenant_id, plan_id) references public.maintenance_plans(tenant_id, id) on delete set null;

create index idx_locations_tenant_site on public.locations(tenant_id, site_id);
create index idx_locations_parent on public.locations(parent_location_id);
create index idx_assets_location on public.assets(tenant_id, location_id);
create index idx_assets_parent on public.assets(parent_asset_id);

create or replace function public.tenant_role(p_tenant_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select tm.role
  from public.tenant_members tm
  where tm.tenant_id = p_tenant_id
    and tm.user_id = auth.uid()
    and tm.is_active = true
  limit 1;
$$;

create or replace function public.can_manage_tenant(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.tenant_role(p_tenant_id) in ('owner','admin','planner','supervisor'), false);
$$;

create or replace function public.can_admin_tenant(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.tenant_role(p_tenant_id) in ('owner','admin'), false);
$$;

create or replace function public.bootstrap_tenant(p_name text, p_slug text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_tenant_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if exists (
    select 1 from public.tenant_members
    where user_id = v_user_id and is_active = true
  ) then
    raise exception 'User already belongs to an active tenant';
  end if;

  insert into public.tenants(name, slug)
  values (trim(p_name), lower(trim(p_slug)))
  returning id into v_tenant_id;

  insert into public.tenant_members(tenant_id, user_id, role)
  values (v_tenant_id, v_user_id, 'owner');

  return v_tenant_id;
end;
$$;

grant execute on function public.bootstrap_tenant(text, text) to authenticated;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles(id, full_name, email)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'),
    new.email
  )
  on conflict (id) do update
    set email = excluded.email;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert or update of email on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists sites_updated_at on public.sites;
-- sites currently has no updated_at; keep trigger only on tables that do.
drop trigger if exists locations_updated_at on public.locations;
create trigger locations_updated_at
before update on public.locations
for each row execute procedure public.set_updated_at();

drop trigger if exists assets_updated_at on public.assets;
create trigger assets_updated_at
before update on public.assets
for each row execute procedure public.set_updated_at();

drop trigger if exists work_orders_updated_at on public.work_orders;
create trigger work_orders_updated_at
before update on public.work_orders
for each row execute procedure public.set_updated_at();

alter table public.locations enable row level security;

drop policy if exists sites_tenant_access on public.sites;
drop policy if exists assets_tenant_access on public.assets;
drop policy if exists maintenance_plans_tenant_access on public.maintenance_plans;
drop policy if exists maintenance_plan_tasks_tenant_access on public.maintenance_plan_tasks;
drop policy if exists work_orders_tenant_access on public.work_orders;

create policy sites_select on public.sites
for select to authenticated
using (public.is_tenant_member(tenant_id));
create policy sites_insert on public.sites
for insert to authenticated
with check (public.can_manage_tenant(tenant_id));
create policy sites_update on public.sites
for update to authenticated
using (public.can_manage_tenant(tenant_id))
with check (public.can_manage_tenant(tenant_id));
create policy sites_delete on public.sites
for delete to authenticated
using (public.can_admin_tenant(tenant_id));

create policy locations_select on public.locations
for select to authenticated
using (public.is_tenant_member(tenant_id));
create policy locations_insert on public.locations
for insert to authenticated
with check (public.can_manage_tenant(tenant_id));
create policy locations_update on public.locations
for update to authenticated
using (public.can_manage_tenant(tenant_id))
with check (public.can_manage_tenant(tenant_id));
create policy locations_delete on public.locations
for delete to authenticated
using (public.can_admin_tenant(tenant_id));

create policy assets_select on public.assets
for select to authenticated
using (public.is_tenant_member(tenant_id));
create policy assets_insert on public.assets
for insert to authenticated
with check (public.can_manage_tenant(tenant_id));
create policy assets_update on public.assets
for update to authenticated
using (public.can_manage_tenant(tenant_id))
with check (public.can_manage_tenant(tenant_id));
create policy assets_delete on public.assets
for delete to authenticated
using (public.can_admin_tenant(tenant_id));

create policy maintenance_plans_select on public.maintenance_plans
for select to authenticated
using (public.is_tenant_member(tenant_id));
create policy maintenance_plans_insert on public.maintenance_plans
for insert to authenticated
with check (public.can_manage_tenant(tenant_id));
create policy maintenance_plans_update on public.maintenance_plans
for update to authenticated
using (public.can_manage_tenant(tenant_id))
with check (public.can_manage_tenant(tenant_id));
create policy maintenance_plans_delete on public.maintenance_plans
for delete to authenticated
using (public.can_admin_tenant(tenant_id));

create policy maintenance_plan_tasks_select on public.maintenance_plan_tasks
for select to authenticated
using (public.is_tenant_member(tenant_id));
create policy maintenance_plan_tasks_insert on public.maintenance_plan_tasks
for insert to authenticated
with check (public.can_manage_tenant(tenant_id));
create policy maintenance_plan_tasks_update on public.maintenance_plan_tasks
for update to authenticated
using (public.can_manage_tenant(tenant_id))
with check (public.can_manage_tenant(tenant_id));
create policy maintenance_plan_tasks_delete on public.maintenance_plan_tasks
for delete to authenticated
using (public.can_admin_tenant(tenant_id));

create policy work_orders_select on public.work_orders
for select to authenticated
using (public.is_tenant_member(tenant_id));
create policy work_orders_insert_manager on public.work_orders
for insert to authenticated
with check (public.can_manage_tenant(tenant_id));
create policy work_orders_insert_technician_request on public.work_orders
for insert to authenticated
with check (
  public.tenant_role(tenant_id) = 'technician'
  and created_by = auth.uid()
  and status = 'requested'
);
create policy work_orders_update_manager on public.work_orders
for update to authenticated
using (public.can_manage_tenant(tenant_id))
with check (public.can_manage_tenant(tenant_id));
create policy work_orders_update_assignee on public.work_orders
for update to authenticated
using (
  public.tenant_role(tenant_id) = 'technician'
  and assigned_to = auth.uid()
)
with check (
  public.tenant_role(tenant_id) = 'technician'
  and assigned_to = auth.uid()
);
create policy work_orders_delete on public.work_orders
for delete to authenticated
using (public.can_admin_tenant(tenant_id));
