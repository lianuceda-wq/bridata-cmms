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
  check((trigger_type='event' and event_key is not null and schedule_key is null) or(trigger_type='scheduled' and schedule_key is not null)),
  check(jsonb_typeof(conditions)='array'),
  check(cardinality(target_roles)>0)
);

create unique index uq_automation_rules_tenant_id on public.automation_rules(tenant_id,id);
create index idx_automation_rules_event on public.automation_rules(tenant_id,event_key,is_active) where trigger_type='event';
create index idx_automation_rules_schedule on public.automation_rules(tenant_id,schedule_key,is_active) where trigger_type='scheduled';
create index idx_automation_rules_created_by on public.automation_rules(created_by);

alter table public.automation_rules enable row level security;