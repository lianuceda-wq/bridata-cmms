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
create index idx_automation_runs_tenant_event on public.automation_runs(tenant_id,domain_event_id) where domain_event_id is not null;
create index idx_automation_runs_tenant_rule on public.automation_runs(tenant_id,rule_id);

alter table public.automation_runs enable row level security;