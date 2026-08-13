create table public.integration_deliveries (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  outbox_id bigint not null references public.integration_outbox(id) on delete cascade,
  subscription_id uuid not null,
  status text not null default 'pending' check(status in('pending','processing','delivered','failed','dead_letter')),
  attempt_count integer not null default 0 check(attempt_count>=0),
  next_attempt_at timestamptz not null default now(),
  locked_at timestamptz,
  delivered_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  unique(outbox_id,subscription_id),
  foreign key(tenant_id,subscription_id) references public.integration_event_subscriptions(tenant_id,id) on delete cascade
);
create index idx_integration_deliveries_claim on public.integration_deliveries(status,next_attempt_at,id) where status in('pending','failed');
create index idx_integration_deliveries_outbox on public.integration_deliveries(outbox_id,status);
alter table public.integration_deliveries enable row level security;

create or replace function public.can_manage_integrations(p_tenant_id uuid)
returns boolean language sql stable set search_path=public,pg_temp as $$
  select coalesce(public.tenant_role(p_tenant_id) in('owner','admin'),false)
$$;
revoke all on function public.can_manage_integrations(uuid) from public,anon;
grant execute on function public.can_manage_integrations(uuid) to authenticated;

create policy integration_connections_select on public.integration_connections for select to authenticated using(public.is_tenant_member(tenant_id));
create policy integration_subscriptions_select on public.integration_event_subscriptions for select to authenticated using(public.is_tenant_member(tenant_id));
create policy integration_outbox_select on public.integration_outbox for select to authenticated using(public.is_tenant_member(tenant_id));
create policy integration_attempts_select on public.integration_delivery_attempts for select to authenticated using(public.is_tenant_member(tenant_id));
create policy integration_inbound_select on public.integration_inbound_events for select to authenticated using(public.is_tenant_member(tenant_id));
create policy integration_deliveries_select on public.integration_deliveries for select to authenticated using(public.is_tenant_member(tenant_id));

create or replace function public.create_integration_connection(
  p_tenant_id uuid,p_provider text,p_name text,p_direction text,p_base_url text,p_config jsonb,p_secret text default null
)
returns uuid language plpgsql security definer set search_path=public,vault,pg_temp as $$
declare v_id uuid;v_secret uuid;
begin
  if not public.can_manage_integrations(p_tenant_id) then raise exception 'Owner/admin role required'; end if;
  if nullif(trim(coalesce(p_name,'')),'') is null then raise exception 'Connection name is required'; end if;
  insert into public.integration_connections(tenant_id,provider,name,direction,base_url,config,status,created_by)
  values(p_tenant_id,p_provider,trim(p_name),p_direction,nullif(trim(p_base_url),''),coalesce(p_config,'{}'::jsonb),'draft',auth.uid()) returning id into v_id;
  if nullif(p_secret,'') is not null then
    v_secret:=vault.create_secret(p_secret,'bridata-connection-'||v_id::text,'BRIDATA integration credential');
    update public.integration_connections set secret_id=v_secret where id=v_id;
  end if;
  return v_id;
end $$;
revoke all on function public.create_integration_connection(uuid,text,text,text,text,jsonb,text) from public,anon;
grant execute on function public.create_integration_connection(uuid,text,text,text,text,jsonb,text) to authenticated;

create or replace function public.create_webhook_subscription(
  p_tenant_id uuid,p_connection_id uuid,p_event_key text,p_target_url text,p_signing_secret text,p_max_attempts integer default 8
)
returns uuid language plpgsql security definer set search_path=public,vault,pg_temp as $$
declare v_id uuid;v_secret uuid;
begin
  if not public.can_manage_integrations(p_tenant_id) then raise exception 'Owner/admin role required'; end if;
  if p_target_url !~ '^https://' then raise exception 'Webhook target must use HTTPS'; end if;
  if nullif(trim(coalesce(p_event_key,'')),'') is null then raise exception 'Event key is required'; end if;
  if not exists(select 1 from public.integration_connections where tenant_id=p_tenant_id and id=p_connection_id and provider='generic_webhook') then raise exception 'Generic webhook connection required'; end if;
  if nullif(p_signing_secret,'') is not null then
    v_secret:=vault.create_secret(p_signing_secret,'bridata-webhook-'||gen_random_uuid()::text,'BRIDATA webhook signing secret');
  end if;
  insert into public.integration_event_subscriptions(tenant_id,connection_id,event_key,target_url,signing_secret_id,max_attempts)
  values(p_tenant_id,p_connection_id,trim(p_event_key),trim(p_target_url),v_secret,least(greatest(coalesce(p_max_attempts,8),1),20)) returning id into v_id;
  return v_id;
end $$;
revoke all on function public.create_webhook_subscription(uuid,uuid,text,text,text,integer) from public,anon;
grant execute on function public.create_webhook_subscription(uuid,uuid,text,text,text,integer) to authenticated;

create or replace function public.set_integration_connection_status(p_tenant_id uuid,p_connection_id uuid,p_status text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not public.can_manage_integrations(p_tenant_id) then raise exception 'Owner/admin role required'; end if;
  if p_status not in('active','paused','disabled') then raise exception 'Invalid integration status'; end if;
  update public.integration_connections set status=p_status,updated_at=now() where tenant_id=p_tenant_id and id=p_connection_id;
  if not found then raise exception 'Integration connection not found'; end if;
end $$;
revoke all on function public.set_integration_connection_status(uuid,uuid,text) from public,anon;
grant execute on function public.set_integration_connection_status(uuid,uuid,text) to authenticated;
