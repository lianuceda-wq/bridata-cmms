create or replace function private.create_hydraulic_notification(
  p_tenant_id uuid,
  p_session_id uuid,
  p_code text,
  p_out integer,
  p_total integer
)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_notification uuid;
begin
  insert into public.notifications(tenant_id,severity,title,body,entity_type,entity_id)
  values(
    p_tenant_id,
    'high',
    'No conformidad hidráulica · '||p_code,
    p_out::text||' de '||p_total::text||' lecturas están fuera de rango.',
    'measurement_session',
    p_session_id
  ) returning id into v_notification;

  insert into public.notification_recipients(tenant_id,notification_id,user_id)
  select m.tenant_id,v_notification,m.user_id
  from public.tenant_members m
  where m.tenant_id=p_tenant_id
    and m.is_active=true
    and m.role in('owner','admin','planner','supervisor')
  on conflict(notification_id,user_id) do nothing;
end $$;

revoke all on function private.create_hydraulic_notification(uuid,uuid,text,integer,integer) from public,anon,authenticated;