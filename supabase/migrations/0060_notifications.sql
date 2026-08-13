create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  severity text not null default 'info' check(severity in('info','warning','high','critical')),
  title text not null,
  body text not null,
  entity_type text,
  entity_id uuid,
  source_rule_id uuid,
  source_event_id uuid,
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  foreign key(tenant_id,source_rule_id) references public.automation_rules(tenant_id,id) on delete set null,
  foreign key(tenant_id,source_event_id) references public.domain_events(tenant_id,id) on delete set null
);

alter table public.notifications enable row level security;