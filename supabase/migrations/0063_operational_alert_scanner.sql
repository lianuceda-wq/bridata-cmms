create or replace function private.observe_operational_alert(
  p_tenant_id uuid,p_alert_key text,p_alert_type text,p_severity text,p_title text,p_body text,
  p_entity_type text,p_entity_id uuid,p_details jsonb,p_observed_at timestamptz
)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_alert public.operational_alerts;v_id uuid;v_event_key text;
begin
  select * into v_alert from public.operational_alerts where tenant_id=p_tenant_id and alert_key=p_alert_key for update;
  if not found then
    insert into public.operational_alerts(tenant_id,alert_key,alert_type,severity,title,body,entity_type,entity_id,status,details,first_detected_at,last_observed_at)
    values(p_tenant_id,p_alert_key,p_alert_type,p_severity,p_title,p_body,p_entity_type,p_entity_id,'open',coalesce(p_details,'{}'::jsonb),p_observed_at,p_observed_at)
    returning id into v_id;
    v_event_key:='alert.'||p_alert_type||'.opened';
  elsif v_alert.status='resolved' then
    update public.operational_alerts set severity=p_severity,title=p_title,body=p_body,entity_type=p_entity_type,entity_id=p_entity_id,
      status='open',details=coalesce(p_details,'{}'::jsonb),first_detected_at=p_observed_at,last_observed_at=p_observed_at,
      acknowledged_at=null,acknowledged_by=null,resolved_at=null,updated_at=now()
    where id=v_alert.id returning id into v_id;
    v_event_key:='alert.'||p_alert_type||'.reopened';
  else
    update public.operational_alerts set severity=p_severity,title=p_title,body=p_body,details=coalesce(p_details,'{}'::jsonb),
      entity_type=p_entity_type,entity_id=p_entity_id,last_observed_at=p_observed_at,updated_at=now()
    where id=v_alert.id returning id into v_id;
  end if;

  if v_event_key is not null then
    perform private.publish_domain_event(p_tenant_id,v_event_key,'operational_alert',v_id,
      jsonb_build_object('alert_id',v_id,'alert_type',p_alert_type,'severity',p_severity,'title',p_title,'body',p_body,'entity_type',p_entity_type,'entity_id',p_entity_id)||coalesce(p_details,'{}'::jsonb),
      v_event_key||':'||v_id::text||':'||extract(epoch from p_observed_at)::bigint::text);
  end if;
  return v_id;
end $$;
revoke all on function private.observe_operational_alert(uuid,text,text,text,text,text,text,uuid,jsonb,timestamptz) from public,anon,authenticated;

create or replace function private.resolve_unobserved_alerts(p_alert_type text,p_scan_at timestamptz)
returns integer language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v record;v_count integer:=0;
begin
  for v in
    update public.operational_alerts
    set status='resolved',resolved_at=now(),updated_at=now()
    where alert_type=p_alert_type and status in('open','acknowledged') and last_observed_at<p_scan_at
    returning id,tenant_id,alert_type,severity,title,body,entity_type,entity_id,details
  loop
    v_count:=v_count+1;
    perform private.publish_domain_event(v.tenant_id,'alert.'||v.alert_type||'.resolved','operational_alert',v.id,
      jsonb_build_object('alert_id',v.id,'alert_type',v.alert_type,'severity',v.severity,'title',v.title,'body',v.body,'entity_type',v.entity_type,'entity_id',v.entity_id)||coalesce(v.details,'{}'::jsonb),null);
  end loop;
  return v_count;
end $$;
revoke all on function private.resolve_unobserved_alerts(text,timestamptz) from public,anon,authenticated;

create or replace function private.scan_operational_alerts()
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_scan timestamptz:=clock_timestamp();v record;v_observed integer:=0;v_resolved integer:=0;
begin
  for v in select * from public.inventory_status where stock_status in('below_minimum','reorder') loop
    perform private.observe_operational_alert(v.tenant_id,'inventory_low_stock:'||v.warehouse_id||':'||v.material_id,'inventory_low_stock',
      case when v.quantity_on_hand<=0 then 'high' else 'warning' end,
      'Stock bajo · '||v.material_code,
      v.material_name||' en '||v.warehouse_code||': disponible '||coalesce(v.available_quantity,0)||', mínimo '||coalesce(v.min_quantity,0)||'.',
      'material',v.material_id,jsonb_build_object('warehouse_id',v.warehouse_id,'warehouse_code',v.warehouse_code,'material_code',v.material_code,'available_quantity',v.available_quantity,'minimum_quantity',v.min_quantity),v_scan);
    v_observed:=v_observed+1;
  end loop;
  v_resolved:=v_resolved+private.resolve_unobserved_alerts('inventory_low_stock',v_scan);

  for v in select * from public.maintenance_execution_facts where overdue_flag=true loop
    perform private.observe_operational_alert(v.tenant_id,'work_order_overdue:'||v.id,'work_order_overdue',
      case when v.priority='critical' then 'critical' else 'high' end,
      'OT vencida · '||v.code,
      coalesce(v.title,'Orden de trabajo')||' venció '||coalesce(v.due_at::date::text,'sin fecha')||'.',
      'work_order',v.id,jsonb_build_object('code',v.code,'priority',v.priority,'due_at',v.due_at,'asset_id',v.asset_id),v_scan);
    v_observed:=v_observed+1;
  end loop;
  v_resolved:=v_resolved+private.resolve_unobserved_alerts('work_order_overdue',v_scan);

  for v in
    select pi.tenant_id,pi.id,pi.worker_id,pi.replacement_due,pc.code as ppe_code,pc.name as ppe_name,w.full_name
    from public.ppe_issues pi join public.ppe_catalog pc on pc.tenant_id=pi.tenant_id and pc.id=pi.ppe_id
    join public.workers w on w.tenant_id=pi.tenant_id and w.id=pi.worker_id
    where pi.status='active' and pi.replacement_due is not null and pi.replacement_due<=current_date
  loop
    perform private.observe_operational_alert(v.tenant_id,'ppe_due:'||v.id,'ppe_due','warning','EPP por reponer · '||v.ppe_code,
      v.ppe_name||' de '||v.full_name||' requiere reposición desde '||v.replacement_due::text||'.','ppe_issue',v.id,
      jsonb_build_object('worker_id',v.worker_id,'worker_name',v.full_name,'ppe_code',v.ppe_code,'replacement_due',v.replacement_due),v_scan);
    v_observed:=v_observed+1;
  end loop;
  v_resolved:=v_resolved+private.resolve_unobserved_alerts('ppe_due',v_scan);

  for v in
    select ws.tenant_id,ws.id,ws.worker_id,ws.expires_at,sc.code as skill_code,sc.name as skill_name,w.full_name
    from public.worker_skills ws join public.skill_catalog sc on sc.tenant_id=ws.tenant_id and sc.id=ws.skill_id
    join public.workers w on w.tenant_id=ws.tenant_id and w.id=ws.worker_id
    where w.status='active' and ws.expires_at between current_date and current_date+30
  loop
    perform private.observe_operational_alert(v.tenant_id,'certification_expiring:'||v.id,'certification_expiring','warning','Certificación por vencer · '||v.skill_code,
      v.skill_name||' de '||v.full_name||' vence '||v.expires_at::text||'.','worker',v.worker_id,
      jsonb_build_object('worker_id',v.worker_id,'worker_name',v.full_name,'skill_code',v.skill_code,'expires_at',v.expires_at),v_scan);
    v_observed:=v_observed+1;
  end loop;
  v_resolved:=v_resolved+private.resolve_unobserved_alerts('certification_expiring',v_scan);

  for v in
    select po.tenant_id,po.id,po.code,po.expected_at,po.status,s.name as supplier_name
    from public.purchase_orders po left join public.suppliers s on s.tenant_id=po.tenant_id and s.id=po.supplier_id
    where po.status not in('received','cancelled') and po.expected_at is not null and po.expected_at<now()
  loop
    perform private.observe_operational_alert(v.tenant_id,'purchase_overdue:'||v.id,'purchase_overdue','warning','Compra atrasada · '||v.code,
      'La OC '||v.code||' de '||coalesce(v.supplier_name,'proveedor')||' esperaba recepción '||v.expected_at::date::text||'.','purchase_order',v.id,
      jsonb_build_object('code',v.code,'supplier_name',v.supplier_name,'expected_at',v.expected_at,'status',v.status),v_scan);
    v_observed:=v_observed+1;
  end loop;
  v_resolved:=v_resolved+private.resolve_unobserved_alerts('purchase_overdue',v_scan);

  for v in select tenant_id,id,code,title,effective_to from public.documents where status='active' and effective_to between current_date and current_date+30 loop
    perform private.observe_operational_alert(v.tenant_id,'document_expiring:'||v.id,'document_expiring','warning','Documento por vencer · '||v.code,
      v.title||' vence '||v.effective_to::text||'.','document',v.id,jsonb_build_object('code',v.code,'title',v.title,'effective_to',v.effective_to),v_scan);
    v_observed:=v_observed+1;
  end loop;
  v_resolved:=v_resolved+private.resolve_unobserved_alerts('document_expiring',v_scan);

  for v in select * from public.maintenance_budget_execution where execution_percent>100 loop
    perform private.observe_operational_alert(v.tenant_id,
      'budget_overrun:'||v.budget_id||':'||coalesce(v.category,'all')||':'||coalesce(v.asset_id::text,'-')||':'||coalesce(v.site_id::text,'-'),
      'budget_overrun','high','Presupuesto excedido · '||v.code,
      coalesce(v.name,v.code)||' / '||v.category||': ejecución '||v.execution_percent||'%.','maintenance_budget',v.budget_id,
      jsonb_build_object('code',v.code,'category',v.category,'budget_amount',v.budget_amount,'actual_amount',v.actual_amount,'execution_percent',v.execution_percent,'asset_id',v.asset_id,'site_id',v.site_id),v_scan);
    v_observed:=v_observed+1;
  end loop;
  v_resolved:=v_resolved+private.resolve_unobserved_alerts('budget_overrun',v_scan);

  return jsonb_build_object('observed',v_observed,'resolved',v_resolved,'scanned_at',v_scan);
end $$;
revoke all on function private.scan_operational_alerts() from public,anon,authenticated;
