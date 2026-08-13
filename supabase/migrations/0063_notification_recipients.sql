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

alter table public.notification_recipients enable row level security;