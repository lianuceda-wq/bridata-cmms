create table public.integration_connections (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  provider text not null check(provider in('generic_webhook','sap','talgil_dream2','gps','iot','power_bi','other')),
  name text not null,
  direction text not null default 'bidirectional' check(direction in('inbound','outbound','bidirectional')),
  status text not null default 'draft' check(status in('draft','active','paused','error','disabled')),
  base_url text,
  config jsonb not null default '{}'::jsonb,
  secret_id uuid,
  last_success_at timestamptz,
  last_error_at timestamptz,
  last_error text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,name)
);
create unique index uq_integration_connections_tenant_id on public.integration_connections(tenant_id,id);
create index idx_integration_connections_status on public.integration_connections(tenant_id,status,provider);
create index idx_integration_connections_created_by on public.integration_connections(created_by);

create table public.integration_event_subscriptions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  connection_id uuid not null,
  event_key text not null,
  target_url text not null,
  signing_secret_id uuid,
  is_active boolean not null default true,
  max_attempts integer not null default 8 check(max_attempts between 1 and 20),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,connection_id,event_key,target_url),
  foreign key(tenant_id,connection_id) references public.integration_connections(tenant_id,id) on delete cascade,
  check(target_url ~ '^https://')
);
create unique index uq_integration_subscriptions_tenant_id on public.integration_event_subscriptions(tenant_id,id);
create index idx_integration_subscriptions_event on public.integration_event_subscriptions(tenant_id,event_key,is_active);

create table public.integration_outbox (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  event_id uuid not null default gen_random_uuid(),
  event_key text not null,
  aggregate_type text not null,
  aggregate_id uuid,
  payload jsonb not null,
  occurred_at timestamptz not null default now(),
  status text not null default 'pending' check(status in('pending','processing','delivered','failed','dead_letter')),
  attempt_count integer not null default 0 check(attempt_count>=0),
  next_attempt_at timestamptz not null default now(),
  locked_at timestamptz,
  delivered_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  unique(tenant_id,event_id)
);
create index idx_integration_outbox_claim on public.integration_outbox(status,next_attempt_at,id) where status in('pending','failed');
create index idx_integration_outbox_tenant on public.integration_outbox(tenant_id,created_at desc);
create index idx_integration_outbox_aggregate on public.integration_outbox(tenant_id,aggregate_type,aggregate_id,created_at desc);

create table public.integration_delivery_attempts (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  outbox_id bigint not null references public.integration_outbox(id) on delete cascade,
  subscription_id uuid not null,
  attempt_number integer not null check(attempt_number>0),
  status text not null check(status in('started','delivered','failed')),
  http_status integer,
  duration_ms integer,
  error text,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  foreign key(tenant_id,subscription_id) references public.integration_event_subscriptions(tenant_id,id) on delete cascade
);
create index idx_integration_attempts_outbox on public.integration_delivery_attempts(outbox_id,attempt_number);
create index idx_integration_attempts_tenant on public.integration_delivery_attempts(tenant_id,started_at desc);

create table public.integration_inbound_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  connection_id uuid not null,
  external_event_id text not null,
  event_key text not null,
  payload jsonb not null,
  status text not null default 'accepted' check(status in('accepted','processed','rejected')),
  error text,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  unique(tenant_id,connection_id,external_event_id),
  foreign key(tenant_id,connection_id) references public.integration_connections(tenant_id,id) on delete cascade
);
create index idx_integration_inbound_status on public.integration_inbound_events(tenant_id,status,received_at);

alter table public.integration_connections enable row level security;
alter table public.integration_event_subscriptions enable row level security;
alter table public.integration_outbox enable row level security;
alter table public.integration_delivery_attempts enable row level security;
alter table public.integration_inbound_events enable row level security;
