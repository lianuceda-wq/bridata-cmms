create table public.operational_alerts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  fingerprint text not null,
  alert_key text not null,
  entity_type text not null,
  entity_id uuid,
  severity text not null default 'warning' check(severity in('info','warning','high','critical')),
  title text not null,
  body text not null,
  details jsonb not null default '{}'::jsonb,
  state text not null default 'open' check(state in('open','acknowledged','resolved')),
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  acknowledged_at timestamptz,
  acknowledged_by uuid references auth.users(id) on delete set null,
  resolved_at timestamptz,
  last_notification_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,fingerprint),
  foreign key(tenant_id,last_notification_id) references public.notifications(tenant_id,id) on delete set null
);

create index idx_operational_alerts_state on public.operational_alerts(tenant_id,state,severity,last_seen_at desc);
create index idx_operational_alerts_acknowledged_by on public.operational_alerts(acknowledged_by) where acknowledged_by is not null;
create index idx_operational_alerts_last_notification on public.operational_alerts(tenant_id,last_notification_id) where last_notification_id is not null;

alter table public.operational_alerts enable row level security;