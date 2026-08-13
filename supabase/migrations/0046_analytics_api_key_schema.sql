-- Bridata CMMS - Analytics API key schema

create table public.analytics_api_keys (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  key_prefix text not null,
  key_hash text not null unique,
  allowed_reports text[] not null,
  rate_limit_per_hour integer not null default 120 check(rate_limit_per_hour between 1 and 5000),
  expires_at timestamptz,
  revoked_at timestamptz,
  last_used_at timestamptz,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  check(cardinality(allowed_reports) > 0),
  check(expires_at is null or expires_at > created_at)
);

create unique index uq_analytics_api_keys_tenant_id
  on public.analytics_api_keys(tenant_id,id);
create index idx_analytics_api_keys_tenant_active
  on public.analytics_api_keys(tenant_id,revoked_at,expires_at);
create index idx_analytics_api_keys_created_by
  on public.analytics_api_keys(created_by);

create table public.analytics_api_requests (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  api_key_id uuid not null,
  report_key text not null,
  row_count integer not null default 0 check(row_count >= 0),
  status_code integer not null check(status_code between 100 and 599),
  duration_ms integer check(duration_ms is null or duration_ms >= 0),
  requested_at timestamptz not null default now(),
  foreign key(tenant_id,api_key_id)
    references public.analytics_api_keys(tenant_id,id) on delete cascade
);

create index idx_analytics_api_requests_rate
  on public.analytics_api_requests(api_key_id,requested_at desc);
create index idx_analytics_api_requests_tenant
  on public.analytics_api_requests(tenant_id,requested_at desc);

alter table public.analytics_api_keys enable row level security;
alter table public.analytics_api_requests enable row level security;
revoke all on public.analytics_api_keys,public.analytics_api_requests from anon,authenticated;
