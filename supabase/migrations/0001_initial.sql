-- Bridata CMMS - núcleo multi-tenant inicial
create extension if not exists pgcrypto;

create table public.tenants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  status text not null default 'active' check (status in ('active','suspended','cancelled')),
  created_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  email text,
  created_at timestamptz not null default now()
);

create table public.tenant_members (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'technician' check (role in ('owner','admin','planner','supervisor','technician','viewer')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (tenant_id, user_id)
);

create table public.sites (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  code text,
  created_at timestamptz not null default now(),
  unique (tenant_id, code)
);

create table public.assets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  site_id uuid references public.sites(id) on delete set null,
  parent_asset_id uuid references public.assets(id) on delete set null,
  code text not null,
  name text not null,
  asset_type text,
  status text not null default 'operational' check (status in ('operational','maintenance','stopped','retired')),
  manufacturer text,
  model text,
  serial_number text,
  installed_at date,
  criticality text default 'medium' check (criticality in ('low','medium','high','critical')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, code)
);

create table public.maintenance_plans (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  asset_id uuid not null references public.assets(id) on delete cascade,
  code text not null,
  name text not null,
  trigger_type text not null default 'calendar' check (trigger_type in ('calendar','meter','condition')),
  interval_value numeric,
  interval_unit text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (tenant_id, code)
);

create table public.maintenance_plan_tasks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  plan_id uuid not null references public.maintenance_plans(id) on delete cascade,
  sequence integer not null default 1,
  title text not null,
  instructions text,
  estimated_minutes integer,
  mandatory boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.work_orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  asset_id uuid references public.assets(id) on delete set null,
  plan_id uuid references public.maintenance_plans(id) on delete set null,
  code text not null,
  title text not null,
  description text,
  maintenance_type text not null default 'preventive' check (maintenance_type in ('preventive','corrective','predictive','inspection','improvement')),
  priority text not null default 'medium' check (priority in ('low','medium','high','critical')),
  status text not null default 'requested' check (status in ('requested','planned','assigned','in_progress','paused','completed','validated','closed','cancelled')),
  scheduled_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  assigned_to uuid references auth.users(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, code)
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  tenant_id uuid references public.tenants(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  entity_type text not null,
  entity_id uuid,
  action text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index idx_assets_tenant_site on public.assets(tenant_id, site_id);
create index idx_assets_tenant_status on public.assets(tenant_id, status);
create index idx_work_orders_tenant_status on public.work_orders(tenant_id, status);
create index idx_work_orders_tenant_schedule on public.work_orders(tenant_id, scheduled_at);
create index idx_plan_tasks_plan on public.maintenance_plan_tasks(plan_id, sequence);

create or replace function public.is_tenant_member(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.tenant_members tm
    where tm.tenant_id = p_tenant_id
      and tm.user_id = auth.uid()
      and tm.is_active = true
  );
$$;

alter table public.tenants enable row level security;
alter table public.profiles enable row level security;
alter table public.tenant_members enable row level security;
alter table public.sites enable row level security;
alter table public.assets enable row level security;
alter table public.maintenance_plans enable row level security;
alter table public.maintenance_plan_tasks enable row level security;
alter table public.work_orders enable row level security;
alter table public.audit_logs enable row level security;

create policy tenants_select on public.tenants
for select to authenticated
using (public.is_tenant_member(id));

create policy profiles_self_select on public.profiles
for select to authenticated
using (id = auth.uid());

create policy profiles_self_update on public.profiles
for update to authenticated
using (id = auth.uid())
with check (id = auth.uid());

create policy tenant_members_select on public.tenant_members
for select to authenticated
using (public.is_tenant_member(tenant_id));

create policy sites_tenant_access on public.sites
for all to authenticated
using (public.is_tenant_member(tenant_id))
with check (public.is_tenant_member(tenant_id));

create policy assets_tenant_access on public.assets
for all to authenticated
using (public.is_tenant_member(tenant_id))
with check (public.is_tenant_member(tenant_id));

create policy maintenance_plans_tenant_access on public.maintenance_plans
for all to authenticated
using (public.is_tenant_member(tenant_id))
with check (public.is_tenant_member(tenant_id));

create policy maintenance_plan_tasks_tenant_access on public.maintenance_plan_tasks
for all to authenticated
using (public.is_tenant_member(tenant_id))
with check (public.is_tenant_member(tenant_id));

create policy work_orders_tenant_access on public.work_orders
for all to authenticated
using (public.is_tenant_member(tenant_id))
with check (public.is_tenant_member(tenant_id));

create policy audit_logs_select on public.audit_logs
for select to authenticated
using (public.is_tenant_member(tenant_id));
