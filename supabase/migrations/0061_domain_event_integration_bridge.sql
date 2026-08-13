create or replace function private.publish_domain_event(
  p_tenant_id uuid,p_event_key text,p_aggregate_type text,p_aggregate_id uuid,p_payload jsonb,p_dedupe_key text default null
)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_event uuid;v_outbox bigint;
begin
  insert into public.domain_events(tenant_id,event_key,aggregate_type,aggregate_id,payload,dedupe_key)
  values(p_tenant_id,trim(p_event_key),trim(p_aggregate_type),p_aggregate_id,coalesce(p_payload,'{}'::jsonb),nullif(p_dedupe_key,''))
  on conflict(tenant_id,dedupe_key) do nothing
  returning id into v_event;

  if v_event is null and p_dedupe_key is not null then
    select id into v_event from public.domain_events where tenant_id=p_tenant_id and dedupe_key=p_dedupe_key;
    return v_event;
  end if;

  if exists(
    select 1 from public.integration_event_subscriptions s
    join public.integration_connections c on c.tenant_id=s.tenant_id and c.id=s.connection_id
    where s.tenant_id=p_tenant_id and s.event_key=p_event_key and s.is_active=true and c.status='active'
      and c.direction in('outbound','bidirectional')
  ) then
    insert into public.integration_outbox(tenant_id,event_id,event_key,aggregate_type,aggregate_id,payload)
    values(p_tenant_id,v_event,p_event_key,p_aggregate_type,p_aggregate_id,coalesce(p_payload,'{}'::jsonb)) returning id into v_outbox;

    insert into public.integration_deliveries(tenant_id,outbox_id,subscription_id)
    select s.tenant_id,v_outbox,s.id
    from public.integration_event_subscriptions s
    join public.integration_connections c on c.tenant_id=s.tenant_id and c.id=s.connection_id
    where s.tenant_id=p_tenant_id and s.event_key=p_event_key and s.is_active=true and c.status='active'
      and c.direction in('outbound','bidirectional');
  end if;

  return v_event;
end $$;
revoke all on function private.publish_domain_event(uuid,text,text,uuid,jsonb,text) from public,anon,authenticated;

create or replace function private.enqueue_integration_event(
  p_tenant_id uuid,p_event_key text,p_aggregate_type text,p_aggregate_id uuid,p_payload jsonb
)
returns bigint language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_event uuid;v_outbox bigint;
begin
  v_event:=private.publish_domain_event(p_tenant_id,p_event_key,p_aggregate_type,p_aggregate_id,p_payload,null);
  select id into v_outbox from public.integration_outbox where tenant_id=p_tenant_id and event_id=v_event order by id desc limit 1;
  return v_outbox;
end $$;
revoke all on function private.enqueue_integration_event(uuid,text,text,uuid,jsonb) from public,anon,authenticated;

create or replace function private.publish_inspection_finding_event()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  perform private.publish_domain_event(new.tenant_id,'inspection.finding_created','inspection_finding',new.id,
    jsonb_build_object('id',new.id,'inspection_run_id',new.inspection_run_id,'severity',new.severity,'status',new.status,'title',new.title,'description',new.description),null);
  return new;
end $$;
revoke all on function private.publish_inspection_finding_event() from public,anon,authenticated;
create trigger publish_inspection_finding_event after insert on public.inspection_findings for each row execute function private.publish_inspection_finding_event();

create or replace function private.publish_hydraulic_nonconformance_event()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_out integer;v_total integer;
begin
  if old.status is distinct from new.status and new.status='validated' and new.session_type='hydraulic_control' then
    select count(*) filter(where compliance_status='out_of_range'),count(*) into v_out,v_total
    from public.operational_readings where tenant_id=new.tenant_id and session_id=new.id;
    if v_out>0 then
      perform private.publish_domain_event(new.tenant_id,'hydraulic.nonconforming','measurement_session',new.id,
        jsonb_build_object('id',new.id,'code',new.code,'out_of_range',v_out,'total_readings',v_total,'site_id',new.site_id,'location_id',new.location_id,'occurred_at',new.occurred_at),null);
    end if;
  end if;
  return new;
end $$;
revoke all on function private.publish_hydraulic_nonconformance_event() from public,anon,authenticated;
create trigger publish_hydraulic_nonconformance_event after update of status on public.measurement_sessions for each row execute function private.publish_hydraulic_nonconformance_event();
