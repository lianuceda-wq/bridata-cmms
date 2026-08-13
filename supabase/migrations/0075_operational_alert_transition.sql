create or replace function private.notify_operational_alert_transition()
returns trigger language plpgsql set search_path=public,private,pg_temp as $$
declare v_roles text[];
begin
  if tg_op='UPDATE' and not (old.state='resolved' and new.state='open') then
    return new;
  end if;

  v_roles:=case new.alert_key
    when 'inventory.low_stock' then array['owner','admin','planner','supervisor','warehouse']::text[]
    when 'ppe.replacement_due' then array['owner','admin','planner','supervisor','warehouse']::text[]
    when 'purchase.overdue' then array['owner','admin','planner','warehouse']::text[]
    when 'budget.exceeded' then array['owner','admin','planner']::text[]
    else array['owner','admin','planner','supervisor']::text[]
  end;

  perform private.create_operational_notification(
    new.tenant_id,new.entity_type,new.entity_id,new.severity,new.title,new.body,v_roles
  );

  return new;
end $$;

revoke all on function private.notify_operational_alert_transition() from public,anon,authenticated;

drop trigger if exists notify_operational_alert_transition on public.operational_alerts;
create trigger notify_operational_alert_transition
after insert or update of state on public.operational_alerts
for each row execute function private.notify_operational_alert_transition();