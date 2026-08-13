create or replace function public.claim_integration_deliveries(p_limit integer default 20)
returns table(
  delivery_id bigint,attempt_id bigint,tenant_id uuid,outbox_id bigint,event_id uuid,event_key text,
  target_url text,payload jsonb,signing_secret text
)
language plpgsql security definer set search_path=public,vault,pg_temp as $$
declare v record;v_attempt bigint;
begin
  for v in
    select d.id as delivery_id,d.tenant_id,d.outbox_id,d.subscription_id,d.attempt_count,
           o.event_id,o.event_key,o.payload,s.target_url,s.signing_secret_id
    from public.integration_deliveries d
    join public.integration_outbox o on o.id=d.outbox_id and o.tenant_id=d.tenant_id
    join public.integration_event_subscriptions s on s.id=d.subscription_id and s.tenant_id=d.tenant_id and s.is_active=true
    join public.integration_connections c on c.id=s.connection_id and c.tenant_id=s.tenant_id and c.status='active'
    where d.status in('pending','failed') and d.next_attempt_at<=now()
    order by d.next_attempt_at,d.id
    for update of d skip locked
    limit least(greatest(coalesce(p_limit,20),1),100)
  loop
    update public.integration_deliveries
      set status='processing',attempt_count=attempt_count+1,locked_at=now()
      where id=v.delivery_id;
    update public.integration_outbox set status='processing',locked_at=now() where id=v.outbox_id;
    insert into public.integration_delivery_attempts(
      tenant_id,outbox_id,subscription_id,attempt_number,status
    ) values(v.tenant_id,v.outbox_id,v.subscription_id,v.attempt_count+1,'started') returning id into v_attempt;

    delivery_id:=v.delivery_id;attempt_id:=v_attempt;tenant_id:=v.tenant_id;outbox_id:=v.outbox_id;
    event_id:=v.event_id;event_key:=v.event_key;target_url:=v.target_url;payload:=v.payload;
    signing_secret:=(select decrypted_secret from vault.decrypted_secrets where id=v.signing_secret_id);
    return next;
  end loop;
end $$;
revoke all on function public.claim_integration_deliveries(integer) from public,anon,authenticated;
grant execute on function public.claim_integration_deliveries(integer) to service_role;

create or replace function public.complete_integration_delivery(
  p_delivery_id bigint,p_attempt_id bigint,p_success boolean,p_http_status integer,p_duration_ms integer,p_error text default null
)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_delivery public.integration_deliveries;v_subscription public.integration_event_subscriptions;v_connection uuid;v_nonterminal integer;v_dead integer;v_delay integer;
begin
  select * into v_delivery from public.integration_deliveries where id=p_delivery_id for update;
  if not found or v_delivery.status<>'processing' then raise exception 'Delivery is not processing'; end if;
  select * into v_subscription from public.integration_event_subscriptions where tenant_id=v_delivery.tenant_id and id=v_delivery.subscription_id;
  select connection_id into v_connection from public.integration_event_subscriptions where id=v_delivery.subscription_id;

  update public.integration_delivery_attempts
    set status=case when p_success then 'delivered' else 'failed' end,http_status=p_http_status,
        duration_ms=greatest(coalesce(p_duration_ms,0),0),error=nullif(left(coalesce(p_error,''),2000),''),completed_at=now()
    where id=p_attempt_id and outbox_id=v_delivery.outbox_id and subscription_id=v_delivery.subscription_id;

  if p_success then
    update public.integration_deliveries set status='delivered',delivered_at=now(),locked_at=null,last_error=null where id=p_delivery_id;
    update public.integration_connections set last_success_at=now(),last_error=null,updated_at=now() where id=v_connection;
  else
    if v_delivery.attempt_count>=v_subscription.max_attempts then
      update public.integration_deliveries set status='dead_letter',locked_at=null,last_error=left(coalesce(p_error,'Delivery failed'),2000) where id=p_delivery_id;
    else
      v_delay:=least(3600,(30*power(2,greatest(v_delivery.attempt_count-1,0)))::integer);
      update public.integration_deliveries set status='failed',next_attempt_at=now()+make_interval(secs=>v_delay),locked_at=null,last_error=left(coalesce(p_error,'Delivery failed'),2000) where id=p_delivery_id;
    end if;
    update public.integration_connections set last_error_at=now(),last_error=left(coalesce(p_error,'Delivery failed'),2000),updated_at=now() where id=v_connection;
  end if;

  select count(*) filter(where status in('pending','processing','failed')),count(*) filter(where status='dead_letter')
    into v_nonterminal,v_dead from public.integration_deliveries where outbox_id=v_delivery.outbox_id;
  update public.integration_outbox set
    status=case when v_nonterminal=0 and v_dead=0 then 'delivered' when v_nonterminal=0 and v_dead>0 then 'dead_letter' else case when p_success then 'processing' else 'failed' end end,
    attempt_count=(select coalesce(sum(attempt_count),0) from public.integration_deliveries where outbox_id=v_delivery.outbox_id),
    delivered_at=case when v_nonterminal=0 and v_dead=0 then now() else null end,
    locked_at=null,last_error=case when p_success then last_error else left(coalesce(p_error,'Delivery failed'),2000) end
  where id=v_delivery.outbox_id;
end $$;
revoke all on function public.complete_integration_delivery(bigint,bigint,boolean,integer,integer,text) from public,anon,authenticated;
grant execute on function public.complete_integration_delivery(bigint,bigint,boolean,integer,integer,text) to service_role;

create or replace function public.requeue_integration_delivery(p_tenant_id uuid,p_delivery_id bigint)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not public.can_manage_integrations(p_tenant_id) then raise exception 'Owner/admin role required'; end if;
  update public.integration_deliveries set status='failed',next_attempt_at=now(),locked_at=null,last_error=null
    where tenant_id=p_tenant_id and id=p_delivery_id and status='dead_letter';
  if not found then raise exception 'Dead-letter delivery not found'; end if;
  update public.integration_outbox set status='failed',next_attempt_at=now(),last_error=null where id=(select outbox_id from public.integration_deliveries where id=p_delivery_id);
end $$;
revoke all on function public.requeue_integration_delivery(uuid,bigint) from public,anon;
grant execute on function public.requeue_integration_delivery(uuid,bigint) to authenticated;
