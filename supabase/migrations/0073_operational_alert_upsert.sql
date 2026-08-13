create or replace function private.upsert_operational_alert(
  p_tenant_id uuid,
  p_fingerprint text,
  p_alert_key text,
  p_entity_type text,
  p_entity_id uuid,
  p_severity text,
  p_title text,
  p_body text,
  p_details jsonb
)
returns table(alert_id uuid,should_notify boolean)
language plpgsql set search_path=public,private,pg_temp as $$
declare v_alert public.operational_alerts;v_notify boolean:=false;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||p_fingerprint,0));

  select * into v_alert
  from public.operational_alerts
  where tenant_id=p_tenant_id and fingerprint=p_fingerprint
  for update;

  if not found then
    insert into public.operational_alerts(tenant_id,fingerprint,alert_key,entity_type,entity_id,severity,title,body,details,state)
    values(p_tenant_id,p_fingerprint,p_alert_key,p_entity_type,p_entity_id,p_severity,p_title,p_body,coalesce(p_details,'{}'::jsonb),'open')
    returning * into v_alert;
    v_notify:=true;
  elsif v_alert.state='resolved' then
    update public.operational_alerts
    set alert_key=p_alert_key,entity_type=p_entity_type,entity_id=p_entity_id,severity=p_severity,title=p_title,body=p_body,
        details=coalesce(p_details,'{}'::jsonb),state='open',first_seen_at=now(),last_seen_at=now(),
        acknowledged_at=null,acknowledged_by=null,resolved_at=null,updated_at=now()
    where id=v_alert.id returning * into v_alert;
    v_notify:=true;
  else
    update public.operational_alerts
    set severity=p_severity,title=p_title,body=p_body,details=coalesce(p_details,'{}'::jsonb),last_seen_at=now(),updated_at=now()
    where id=v_alert.id returning * into v_alert;
  end if;

  alert_id:=v_alert.id;
  should_notify:=v_notify;
  return next;
end $$;

revoke all on function private.upsert_operational_alert(uuid,text,text,text,uuid,text,text,text,jsonb) from public,anon,authenticated;