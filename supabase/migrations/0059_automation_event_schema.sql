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

create table public.automation_rules (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null,
  name text not null,
  description text,
  trigger_type text not null default 'event' check(trigger_type in('event','scheduled')),
  event_key text,
  schedule_key text check(schedule_key is null or schedule_key in('hourly','daily')),
  conditions jsonb not null default '[]'::jsonb,
  action_type text not null default 'notify' check(action_type in('notify')),
  notification_title text not null,
  notification_body text not null,
  notification_severity text not null default 'info' check(notification_severity in('info','warning','high','critical')),
  target_roles text[] not null default array['owner','admin']::text[],
  is_system boolean not null default false,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,code),
  check((trigger_type='event' and event_key is not null and schedule_key is null) or (trigger_type='scheduled' and schedule_key is not null)),
  check(jsonb_typeof(conditions)='array'),
  check(cardinality(target_roles)>0)
);
create unique index uq_automation_rules_tenant_id on public.automation_rules(tenant_id,id);
create index idx_automation_rules_event on public.automation_rules(tenant_id,event_key,is_active) where trigger_type='event';
create index idx_automation_rules_schedule on public.automation_rules(tenant_id,schedule_key,is_active) where trigger_type='scheduled';
create index idx_automation_rules_created_by on public.automation_rules(created_by);

create table public.automation_runs (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  rule_id uuid not null,
  domain_event_id uuid,
  schedule_bucket text,
  status text not null default 'started' check(status in('started','completed','failed','skipped')),
  matched boolean,
  result jsonb not null default '{}'::jsonb,
  error text,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  foreign key(tenant_id,rule_id) references public.automation_rules(tenant_id,id) on delete cascade,
  foreign key(tenant_id,domain_event_id) references public.domain_events(tenant_id,id) on delete cascade,
  check(domain_event_id is not null or schedule_bucket is not null)
);
create unique index uq_automation_runs_event on public.automation_runs(rule_id,domain_event_id) where domain_event_id is not null;
create unique index uq_automation_runs_schedule on public.automation_runs(rule_id,schedule_bucket) where schedule_bucket is not null;
create index idx_automation_runs_tenant on public.automation_runs(tenant_id,started_at desc);
create index idx_automation_runs_status on public.automation_runs(tenant_id,status,started_at desc);

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
create unique index uq_notifications_tenant_id on public.notifications(tenant_id,id);
create index idx_notifications_tenant_time on public.notifications(tenant_id,created_at desc);
create index idx_notifications_entity on public.notifications(tenant_id,entity_type,entity_id,created_at desc);

create table public.notification_recipients (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  notification_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  read_at timestamptz,
  dismissed_at timestamptz,
  created_at timestamptz not null default now(),
  unique(notification_id,user_id),
  foreign key(tenant_id,notification_id) references public.notifications(tenant_id,id) on delete cascade
);
create index idx_notification_recipients_user on public.notification_recipients(tenant_id,user_id,read_at,created_at desc);

alter table public.domain_events enable row level security;
alter table public.automation_rules enable row level security;
alter table public.automation_runs enable row level security;
alter table public.notifications enable row level security;
alter table public.notification_recipients enable row level security;
