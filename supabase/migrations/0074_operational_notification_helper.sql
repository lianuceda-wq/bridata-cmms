create or replace function private.create_operational_notification(
  p_tenant_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_severity text,
  p_title text,
  p_body text,
  p_target_roles text[]
)
returns uuid language plpgsql set search_path=public,private,pg_temp as $$
declare v_notification uuid;
begin
  insert into public.notifications(tenant_id,severity,title,body,entity_type,entity_id)
  values(p_tenant_id,p_severity,p_title,p_body,p_entity_type,p_entity_id)
  returning id into v_notification;

  insert into public.notification_recipients(tenant_id,notification_id,user_id)
  select m.tenant_id,v_notification,m.user_id
  from public.tenant_members m
  where m.tenant_id=p_tenant_id
    and m.is_active=true
    and m.role=any(p_target_roles)
  on conflict(notification_id,user_id) do nothing;

  return v_notification;
end $$;

revoke all on function private.create_operational_notification(uuid,text,uuid,text,text,text,text[]) from public,anon,authenticated;