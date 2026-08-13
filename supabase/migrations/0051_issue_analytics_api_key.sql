create or replace function public.issue_analytics_api_key(
  p_tenant_id uuid,
  p_name text,
  p_allowed_reports text[],
  p_expires_at timestamptz default null,
  p_rate_limit_per_hour integer default 120
)
returns table(api_key_id uuid,api_key text)
language plpgsql
security definer
set search_path=public,extensions,pg_temp
as $$
declare
  v_raw text;
  v_hash text;
  v_id uuid;
begin
  if public.tenant_role(p_tenant_id) not in('owner','admin') then raise exception 'Owner/admin role required'; end if;
  v_raw:='brd_live_'||encode(gen_random_bytes(32),'hex');
  v_hash:=encode(digest(v_raw,'sha256'),'hex');
  v_id:=public.register_analytics_api_key(
    p_tenant_id,p_name,left(v_raw,18),v_hash,p_allowed_reports,p_expires_at,p_rate_limit_per_hour
  );
  return query select v_id,v_raw;
end $$;
revoke all on function public.issue_analytics_api_key(uuid,text,text[],timestamptz,integer) from public,anon;
grant execute on function public.issue_analytics_api_key(uuid,text,text[],timestamptz,integer) to authenticated;
