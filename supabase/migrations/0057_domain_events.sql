create table public.domain_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  event_key text not null,
  aggregate_type text not null,
  aggregate_id uuid,
  payload jsonb not null default '{}'::jsonb,
  dedupe_key text,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique(tenant_id,dedupe_key)
);

create unique index uq_domain_events_tenant_id on public.domain_events(tenant_id,id);
create index idx_domain_events_tenant_time on public.domain_events(tenant_id,occurred_at desc);
create index idx_domain_events_key_time on public.domain_events(tenant_id,event_key,occurred_at desc);
create index idx_domain_events_aggregate on public.domain_events(tenant_id,aggregate_type,aggregate_id,occurred_at desc);

alter table public.domain_events enable row level security;