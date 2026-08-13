create or replace function private.publish_domain_event(
  p_tenant_id uuid,
  p_event_key text,
  p_aggregate_type text,
  p_aggregate_id uuid,
  p_payload jsonb,
  p_dedupe_key text default null
)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_event uuid;
begin
  insert into public.domain_events(tenant_id,event_key,aggregate_type,aggregate_id,payload,dedupe_key)
  values(p_tenant_id,trim(p_event_key),trim(p_aggregate_type),p_aggregate_id,coalesce(p_payload,'{}'::jsonb),nullif(p_dedupe_key,''))
  on conflict(tenant_id,dedupe_key) do nothing
  returning id into v_event;

  if v_event is null and p_dedupe_key is not null then
    select id into v_event
    from public.domain_events
    where tenant_id=p_tenant_id and dedupe_key=p_dedupe_key;
  end if;

  return v_event;
end $$;

revoke all on function private.publish_domain_event(uuid,text,text,uuid,jsonb,text) from public,anon,authenticated;