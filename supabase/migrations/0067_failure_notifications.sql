create or replace function private.notify_failure_event()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_notification uuid;
begin
  perform private.publish_domain_event(
    new.tenant_id,'failure.created','failure_event',new.id,
    jsonb_build_object('id',new.id,'code',new.code,'severity',new.severity,'status',new.status,'asset_id',new.asset_id,'description',new.description),
    null
  );

  if new.severity in('high','critical') then
    insert into public.notifications(tenant_id,severity,title,body,entity_type,entity_id)
    values(
      new.tenant_id,
      new.severity,
      'Falla '||upper(new.severity)||' · '||new.code,
      coalesce(new.description,new.symptom,'Falla reportada'),
      'failure_event',
      new.id
    ) returning id into v_notification;

    insert into public.notification_recipients(tenant_id,notification_id,user_id)
    select m.tenant_id,v_notification,m.user_id
    from public.tenant_members m
    where m.tenant_id=new.tenant_id
      and m.is_active=true
      and m.role in('owner','admin','planner','supervisor')
    on conflict(notification_id,user_id) do nothing;
  end if;

  return new;
end $$;

revoke all on function private.notify_failure_event() from public,anon,authenticated;

drop trigger if exists publish_failure_notification on public.failure_events;
create trigger publish_failure_notification
after insert on public.failure_events
for each row execute function private.notify_failure_event();