-- Bridata CMMS - revalorización explícita de HH históricas sin tarifa

create or replace function public.revalue_labor_session(
  p_tenant_id uuid,
  p_session_id uuid
)
returns numeric
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_session public.work_order_labor_sessions;
  v_rate numeric;
  v_currency text;
  v_source text;
  v_amount numeric;
begin
  if public.tenant_role(p_tenant_id) not in ('owner','admin','planner') then
    raise exception 'Insufficient labor revaluation permissions';
  end if;

  select * into v_session
  from public.work_order_labor_sessions
  where tenant_id=p_tenant_id and id=p_session_id
  for update;

  if not found then raise exception 'Labor session not found'; end if;
  if v_session.ended_at is null then raise exception 'Active labor session cannot be revalued'; end if;

  select x.hourly_rate,x.currency,x.rate_source
  into v_rate,v_currency,v_source
  from private.resolve_labor_rate(
    p_tenant_id,v_session.worker_user_id,v_session.labor_role,v_session.started_at::date
  ) x;

  if v_rate is null then raise exception 'No labor rate exists for the session date'; end if;

  update public.work_order_labor_sessions
  set hourly_rate_snapshot=v_rate,
      rate_currency=v_currency,
      rate_source=v_source,
      updated_at=now()
  where tenant_id=p_tenant_id and id=p_session_id;

  v_amount:=round((extract(epoch from(v_session.ended_at-v_session.started_at))/3600.0)*v_rate,4);

  insert into public.audit_logs(tenant_id,user_id,entity_type,entity_id,action,metadata)
  values(
    p_tenant_id,auth.uid(),'work_order_labor_session',p_session_id,'labor_revalued',
    jsonb_build_object('hourly_rate',v_rate,'currency',v_currency,'amount',v_amount,'rate_source',v_source)
  );

  return v_amount;
end;
$$;
revoke all on function public.revalue_labor_session(uuid,uuid) from public,anon;
grant execute on function public.revalue_labor_session(uuid,uuid) to authenticated;
