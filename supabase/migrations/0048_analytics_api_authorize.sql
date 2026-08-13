create or replace function public.authorize_analytics_api_key(p_key_hash text,p_report_key text)
returns table(tenant_id uuid,api_key_id uuid,request_id bigint)
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_key public.analytics_api_keys;v_count integer;v_request_id bigint;
begin
 if p_key_hash !~ '^[0-9a-f]{64}$' then raise exception 'Invalid API key';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_key_hash,0));
 select * into v_key from public.analytics_api_keys
 where key_hash=lower(p_key_hash) and revoked_at is null and(expires_at is null or expires_at>now()) for update;
 if not found then raise exception 'Invalid or inactive API key';end if;
 if not(p_report_key=any(v_key.allowed_reports)) then raise exception 'Report is not allowed for this API key';end if;
 select count(*) into v_count from public.analytics_api_requests where api_key_id=v_key.id and requested_at>=now()-interval '1 hour';
 if v_count>=v_key.rate_limit_per_hour then raise exception 'Analytics API rate limit exceeded';end if;
 insert into public.analytics_api_requests(tenant_id,api_key_id,report_key,status_code)
 values(v_key.tenant_id,v_key.id,p_report_key,102) returning id into v_request_id;
 update public.analytics_api_keys set last_used_at=now() where id=v_key.id;
 return query select v_key.tenant_id,v_key.id,v_request_id;
end $$;
revoke all on function public.authorize_analytics_api_key(text,text) from public,anon,authenticated;
grant execute on function public.authorize_analytics_api_key(text,text) to service_role;
