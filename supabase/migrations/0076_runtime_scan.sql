create or replace function private.scan_work_order_alerts(p_marker timestamptz)
returns integer language plpgsql set search_path=public,private,pg_temp as $$
declare v record;v_id uuid;v_count integer:=0;
begin
  for v in
    select tenant_id,id,code,title,priority,due_at
    from public.work_orders
    where due_at is not null
      and due_at<now()
      and status not in('completed','validated','closed','cancelled')
  loop
    select alert_id into v_id
    from private.upsert_operational_alert(
      v.tenant_id,
      'work_order.overdue:'||v.id::text,
      'work_order.overdue',
      'work_order',
      v.id,
      case when v.priority in('high','critical') then 'high' else 'warning' end,
      'OT vencida · '||v.code,
      coalesce(v.title,'Orden de trabajo')||' venció el '||to_char(v.due_at,'YYYY-MM-DD HH24:MI'),
      jsonb_build_object('code',v.code,'priority',v.priority,'due_at',v.due_at)
    );
    update public.operational_alerts set last_seen_at=p_marker,updated_at=p_marker where id=v_id;
    v_count:=v_count+1;
  end loop;

  update public.operational_alerts
  set state='resolved',resolved_at=p_marker,updated_at=p_marker
  where state<>'resolved' and alert_key='work_order.overdue' and last_seen_at<p_marker;

  return v_count;
end $$;

revoke all on function private.scan_work_order_alerts(timestamptz) from public,anon,authenticated;