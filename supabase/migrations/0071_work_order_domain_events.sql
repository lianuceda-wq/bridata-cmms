create or replace function private.publish_work_order_domain_event()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  if tg_op='INSERT' then
    perform private.publish_domain_event(new.tenant_id,'work_order.created','work_order',new.id,to_jsonb(new),null);
  elsif old.status is distinct from new.status then
    perform private.publish_domain_event(
      new.tenant_id,
      'work_order.status_changed',
      'work_order',
      new.id,
      jsonb_build_object('id',new.id,'code',new.code,'old_status',old.status,'status',new.status,'priority',new.priority,'asset_id',new.asset_id,'assigned_to',new.assigned_to,'due_at',new.due_at),
      null
    );
  end if;
  return new;
end $$;

revoke all on function private.publish_work_order_domain_event() from public,anon,authenticated;
drop trigger if exists publish_work_order_domain_event on public.work_orders;
create trigger publish_work_order_domain_event after insert or update of status on public.work_orders for each row execute function private.publish_work_order_domain_event();