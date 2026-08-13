create or replace function private.validate_webhook_target(p_url text)
returns boolean language sql immutable set search_path=pg_catalog,pg_temp as $$
  select p_url ~ '^https://'
    and lower(p_url) !~ '^https://(localhost|127\.|0\.|10\.|169\.254\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|\[?::1\]?)([:/]|$)'
    and lower(p_url) !~ '^https://[^/]*\.(local|internal)([:/]|$)'
$$;
revoke all on function private.validate_webhook_target(text) from public,anon,authenticated;

create or replace function public.create_webhook_subscription(
  p_tenant_id uuid,p_connection_id uuid,p_event_key text,p_target_url text,p_signing_secret text,p_max_attempts integer default 8
)
returns uuid language plpgsql security definer set search_path=public,private,vault,pg_temp as $$
declare v_id uuid;v_secret uuid;
begin
  if not public.can_manage_integrations(p_tenant_id) then raise exception 'Owner/admin role required'; end if;
  if not private.validate_webhook_target(p_target_url) then raise exception 'Webhook target must be a public HTTPS URL'; end if;
  if not exists(select 1 from public.integration_connections where tenant_id=p_tenant_id and id=p_connection_id and provider='generic_webhook') then raise exception 'Generic webhook connection required'; end if;
  if nullif(trim(p_event_key),'') is null then raise exception 'Event key is required'; end if;
  if nullif(p_signing_secret,'') is not null then
    v_secret:=vault.create_secret(p_signing_secret,'bridata-webhook-'||gen_random_uuid()::text,'BRIDATA webhook signing secret');
  end if;
  insert into public.integration_event_subscriptions(tenant_id,connection_id,event_key,target_url,signing_secret_id,max_attempts)
  values(p_tenant_id,p_connection_id,trim(p_event_key),trim(p_target_url),v_secret,least(greatest(coalesce(p_max_attempts,8),1),20)) returning id into v_id;
  return v_id;
end $$;

create or replace function public.set_integration_subscription_active(p_tenant_id uuid,p_subscription_id uuid,p_active boolean)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not public.can_manage_integrations(p_tenant_id) then raise exception 'Owner/admin role required'; end if;
  update public.integration_event_subscriptions set is_active=p_active,updated_at=now() where tenant_id=p_tenant_id and id=p_subscription_id;
  if not found then raise exception 'Subscription not found'; end if;
end $$;
revoke all on function public.set_integration_subscription_active(uuid,uuid,boolean) from public,anon;
grant execute on function public.set_integration_subscription_active(uuid,uuid,boolean) to authenticated;

create or replace function public.rotate_integration_connection_secret(p_tenant_id uuid,p_connection_id uuid,p_secret text)
returns void language plpgsql security definer set search_path=public,vault,pg_temp as $$
declare v_secret uuid;
begin
  if not public.can_manage_integrations(p_tenant_id) then raise exception 'Owner/admin role required'; end if;
  if nullif(p_secret,'') is null then raise exception 'Secret is required'; end if;
  select secret_id into v_secret from public.integration_connections where tenant_id=p_tenant_id and id=p_connection_id for update;
  if not found then raise exception 'Connection not found'; end if;
  if v_secret is null then
    v_secret:=vault.create_secret(p_secret,'bridata-connection-'||p_connection_id::text,'BRIDATA integration credential');
    update public.integration_connections set secret_id=v_secret,updated_at=now() where id=p_connection_id;
  else
    perform vault.update_secret(v_secret,p_secret);
    update public.integration_connections set updated_at=now() where id=p_connection_id;
  end if;
end $$;
revoke all on function public.rotate_integration_connection_secret(uuid,uuid,text) from public,anon;
grant execute on function public.rotate_integration_connection_secret(uuid,uuid,text) to authenticated;

create or replace function private.cleanup_connection_secret()
returns trigger language plpgsql security definer set search_path=public,vault,pg_temp as $$
begin
  if old.secret_id is not null then perform vault.delete_secret(old.secret_id); end if;
  return old;
end $$;
revoke all on function private.cleanup_connection_secret() from public,anon,authenticated;
create trigger cleanup_connection_secret after delete on public.integration_connections for each row execute function private.cleanup_connection_secret();

create or replace function private.cleanup_subscription_secret()
returns trigger language plpgsql security definer set search_path=public,vault,pg_temp as $$
begin
  if old.signing_secret_id is not null then perform vault.delete_secret(old.signing_secret_id); end if;
  return old;
end $$;
revoke all on function private.cleanup_subscription_secret() from public,anon,authenticated;
create trigger cleanup_subscription_secret after delete on public.integration_event_subscriptions for each row execute function private.cleanup_subscription_secret();
