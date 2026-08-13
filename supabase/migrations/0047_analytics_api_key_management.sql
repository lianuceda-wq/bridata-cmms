-- Bridata CMMS - Analytics API key management

create or replace function public.register_analytics_api_key(
  p_tenant_id uuid,
  p_name text,
  p_key_prefix text,
  p_key_hash text,
  p_allowed_reports text[],
  p_expires_at timestamptz default null,
  p_rate_limit_per_hour integer default 120
)
returns uuid
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_id uuid;
  v_allowed constant text[] := array[
    'maintenance','reliability','hydraulics','costs','inventory',
    'purchases','budget','inspections','attendance','work_orders'
  ];
begin
  if public.tenant_role(p_tenant_id) not in ('owner','admin') then
    raise exception 'Owner/admin role required to create analytics API keys';
  end if;
  if nullif(trim(coalesce(p_name,'')),'') is null then raise exception 'API key name is required'; end if;
  if p_key_hash !~ '^[0-9a-f]{64}$' then raise exception 'Invalid API key hash'; end if;
  if nullif(trim(coalesce(p_key_prefix,'')),'') is null then raise exception 'API key prefix is required'; end if;
  if p_allowed_reports is null or cardinality(p_allowed_reports)=0 or not (p_allowed_reports <@ v_allowed) then
    raise exception 'Invalid analytics report scope';
  end if;
  if p_expires_at is not null and p_expires_at <= now() then raise exception 'Expiration must be in the future'; end if;
  if p_rate_limit_per_hour is null or p_rate_limit_per_hour not between 1 and 5000 then raise exception 'Invalid rate limit'; end if;

  insert into public.analytics_api_keys(
    tenant_id,name,key_prefix,key_hash,allowed_reports,expires_at,rate_limit_per_hour,created_by
  ) values(
    p_tenant_id,trim(p_name),trim(p_key_prefix),lower(p_key_hash),p_allowed_reports,p_expires_at,p_rate_limit_per_hour,auth.uid()
  ) returning id into v_id;

  insert into public.audit_logs(tenant_id,user_id,entity_type,entity_id,action,metadata)
  values(p_tenant_id,auth.uid(),'analytics_api_key',v_id,'api_key_created',jsonb_build_object(
    'name',trim(p_name),'prefix',trim(p_key_prefix),'allowed_reports',p_allowed_reports,'expires_at',p_expires_at
  ));
  return v_id;
end;
$$;
revoke all on function public.register_analytics_api_key(uuid,text,text,text,text[],timestamptz,integer) from public,anon;
grant execute on function public.register_analytics_api_key(uuid,text,text,text,text[],timestamptz,integer) to authenticated;

create or replace function public.revoke_analytics_api_key(p_tenant_id uuid,p_api_key_id uuid)
returns void
language plpgsql
security definer
set search_path=public,pg_temp
as $$
begin
  if public.tenant_role(p_tenant_id) not in ('owner','admin') then
    raise exception 'Owner/admin role required to revoke analytics API keys';
  end if;
  update public.analytics_api_keys
    set revoked_at=coalesce(revoked_at,now())
    where tenant_id=p_tenant_id and id=p_api_key_id;
  if not found then raise exception 'Analytics API key not found'; end if;
  insert into public.audit_logs(tenant_id,user_id,entity_type,entity_id,action)
  values(p_tenant_id,auth.uid(),'analytics_api_key',p_api_key_id,'api_key_revoked');
end;
$$;
revoke all on function public.revoke_analytics_api_key(uuid,uuid) from public,anon;
grant execute on function public.revoke_analytics_api_key(uuid,uuid) to authenticated;

create or replace function public.list_analytics_api_keys(p_tenant_id uuid)
returns table(
  id uuid,name text,key_prefix text,allowed_reports text[],rate_limit_per_hour integer,
  expires_at timestamptz,revoked_at timestamptz,last_used_at timestamptz,created_at timestamptz
)
language plpgsql
security definer
set search_path=public,pg_temp
as $$
begin
  if public.tenant_role(p_tenant_id) not in ('owner','admin') then
    raise exception 'Owner/admin role required to list analytics API keys';
  end if;
  return query
    select k.id,k.name,k.key_prefix,k.allowed_reports,k.rate_limit_per_hour,k.expires_at,k.revoked_at,k.last_used_at,k.created_at
    from public.analytics_api_keys k
    where k.tenant_id=p_tenant_id
    order by k.created_at desc;
end;
$$;
revoke all on function public.list_analytics_api_keys(uuid) from public,anon;
grant execute on function public.list_analytics_api_keys(uuid) to authenticated;
