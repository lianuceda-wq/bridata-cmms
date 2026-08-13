create schema if not exists private;
revoke all on schema private from public,anon,authenticated;

create or replace function private.enqueue_integration_event(
  p_tenant_id uuid,p_event_key text,p_aggregate_type text,p_aggregate_id uuid,p_payload jsonb
)
returns bigint language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_outbox bigint;
begin
  if not exists(
    select 1 from public.integration_event_subscriptions s
    join public.integration_connections c on c.tenant_id=s.tenant_id and c.id=s.connection_id
    where s.tenant_id=p_tenant_id and s.event_key=p_event_key and s.is_active=true and c.status='active'
      and c.direction in('outbound','bidirectional')
  ) then return null; end if;

  insert into public.integration_outbox(tenant_id,event_key,aggregate_type,aggregate_id,payload)
  values(p_tenant_id,p_event_key,p_aggregate_type,p_aggregate_id,p_payload) returning id into v_outbox;

  insert into public.integration_deliveries(tenant_id,outbox_id,subscription_id)
  select s.tenant_id,v_outbox,s.id
  from public.integration_event_subscriptions s
  join public.integration_connections c on c.tenant_id=s.tenant_id and c.id=s.connection_id
  where s.tenant_id=p_tenant_id and s.event_key=p_event_key and s.is_active=true and c.status='active'
    and c.direction in('outbound','bidirectional');
  return v_outbox;
end $$;
revoke all on function private.enqueue_integration_event(uuid,text,text,uuid,jsonb) from public,anon,authenticated;

create or replace function private.publish_work_order_integration_event()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  if tg_op='INSERT' then
    perform private.enqueue_integration_event(new.tenant_id,'work_order.created','work_order',new.id,to_jsonb(new));
  elsif old.status is distinct from new.status then
    perform private.enqueue_integration_event(new.tenant_id,'work_order.status_changed','work_order',new.id,
      jsonb_build_object('id',new.id,'code',new.code,'previous_status',old.status,'status',new.status,'asset_id',new.asset_id,'updated_at',new.updated_at));
  end if;
  return new;
end $$;
create trigger publish_work_order_integration_event after insert or update of status on public.work_orders for each row execute function private.publish_work_order_integration_event();

create or replace function private.publish_failure_integration_event()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  if tg_op='INSERT' then
    perform private.enqueue_integration_event(new.tenant_id,'failure.created','failure',new.id,to_jsonb(new));
  elsif old.status is distinct from new.status then
    perform private.enqueue_integration_event(new.tenant_id,'failure.status_changed','failure',new.id,
      jsonb_build_object('id',new.id,'code',new.code,'previous_status',old.status,'status',new.status,'asset_id',new.asset_id));
  end if;
  return new;
end $$;
create trigger publish_failure_integration_event after insert or update of status on public.failure_events for each row execute function private.publish_failure_integration_event();

create or replace function private.publish_hydraulic_integration_event()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  if old.status is distinct from new.status and new.status='validated' and new.session_type='hydraulic_control' then
    perform private.enqueue_integration_event(new.tenant_id,'hydraulic.validated','measurement_session',new.id,
      jsonb_build_object('id',new.id,'code',new.code,'occurred_at',new.occurred_at,'site_id',new.site_id,'location_id',new.location_id,'validated_at',new.validated_at));
  end if;
  return new;
end $$;
create trigger publish_hydraulic_integration_event after update of status on public.measurement_sessions for each row execute function private.publish_hydraulic_integration_event();

create or replace function private.publish_inventory_integration_event()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  perform private.enqueue_integration_event(new.tenant_id,'inventory.movement','inventory_movement',new.id,to_jsonb(new));
  return new;
end $$;
create trigger publish_inventory_integration_event after insert on public.inventory_movements for each row execute function private.publish_inventory_integration_event();

create or replace function private.publish_inspection_integration_event()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  if old.status is distinct from new.status and new.status in('completed','validated') then
    perform private.enqueue_integration_event(new.tenant_id,'inspection.'||new.status,'inspection_run',new.id,
      jsonb_build_object('id',new.id,'code',new.code,'status',new.status,'asset_id',new.asset_id,'completed_at',new.completed_at,'validated_at',new.validated_at));
  end if;
  return new;
end $$;
create trigger publish_inspection_integration_event after update of status on public.inspection_runs for each row execute function private.publish_inspection_integration_event();
