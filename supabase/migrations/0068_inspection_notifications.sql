create or replace function private.publish_inspection_finding_event()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_notification uuid;
begin
  perform private.publish_domain_event(
    new.tenant_id,'inspection.finding_created','inspection_finding',new.id,
    jsonb_build_object('id',new.id,'inspection_run_id',new.inspection_run_id,'severity',new.severity,'status',new.status,'title',new.title,'description',new.description),
    null
  );

  if new.severity in('high','critical') then
    insert into public.notifications(tenant_id,severity,title,body,entity_type,entity_id)
    values(new.tenant_id,new.severity,'Hallazgo '||upper(new.severity)||' · '||new.title,coalesce(new.description,'Hallazgo detectado en inspección'),'inspection_finding',new.id)
    returning id into v_notification;

    insert into public.notification_recipients(tenant_id,notification_id,user_id)
    select m.tenant_id,v_notification,m.user_id
    from public.tenant_members m
    where m.tenant_id=new.tenant_id and m.is_active=true and m.role in('owner','admin','planner','supervisor')
    on conflict(notification_id,user_id) do nothing;
  end if;

  return new;
end $$;

revoke all on function private.publish_inspection_finding_event() from public,anon,authenticated;
drop trigger if exists publish_inspection_finding_event on public.inspection_findings;
create trigger publish_inspection_finding_event after insert on public.inspection_findings for each row execute function private.publish_inspection_finding_event();