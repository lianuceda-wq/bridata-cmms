-- Bridata CMMS - gobernanza de tarifas y presupuestos

revoke insert,update,delete on public.labor_rate_versions from authenticated;
revoke insert,update,delete on public.maintenance_budgets from authenticated;
revoke insert,update,delete on public.maintenance_budget_lines from authenticated;

create or replace function public.create_maintenance_budget(
  p_tenant_id uuid,
  p_code text,
  p_name text,
  p_period_start date,
  p_period_end date,
  p_currency text,
  p_lines jsonb
)
returns uuid
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_id uuid;
  v_line jsonb;
begin
  if public.tenant_role(p_tenant_id) not in('owner','admin','planner') then
    raise exception 'Insufficient budget permissions';
  end if;
  if nullif(trim(coalesce(p_code,'')),'') is null or nullif(trim(coalesce(p_name,'')),'') is null then
    raise exception 'Budget code and name are required';
  end if;
  if p_period_start is null or p_period_end is null or p_period_end<p_period_start then
    raise exception 'Invalid budget period';
  end if;
  if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then
    raise exception 'Budget requires at least one line';
  end if;

  insert into public.maintenance_budgets(tenant_id,code,name,period_start,period_end,currency,status,created_by)
  values(p_tenant_id,upper(trim(p_code)),trim(p_name),p_period_start,p_period_end,upper(coalesce(p_currency,'PEN')),'draft',auth.uid())
  returning id into v_id;

  for v_line in select value from jsonb_array_elements(p_lines) loop
    if (v_line->>'amount')::numeric<0 then raise exception 'Budget amount cannot be negative'; end if;
    insert into public.maintenance_budget_lines(
      tenant_id,budget_id,site_id,asset_id,maintenance_type,category,amount
    ) values(
      p_tenant_id,v_id,
      nullif(v_line->>'site_id','')::uuid,
      nullif(v_line->>'asset_id','')::uuid,
      nullif(v_line->>'maintenance_type',''),
      coalesce(nullif(v_line->>'category',''),'other'),
      (v_line->>'amount')::numeric
    );
  end loop;
  return v_id;
end;
$$;
revoke all on function public.create_maintenance_budget(uuid,text,text,date,date,text,jsonb) from public,anon;
grant execute on function public.create_maintenance_budget(uuid,text,text,date,date,text,jsonb) to authenticated;

create or replace function public.change_maintenance_budget_status(
  p_tenant_id uuid,p_budget_id uuid,p_status text
)
returns void
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare v_current text;
begin
  if public.tenant_role(p_tenant_id) not in('owner','admin','planner') then
    raise exception 'Insufficient budget permissions';
  end if;
  select status into v_current from public.maintenance_budgets
  where tenant_id=p_tenant_id and id=p_budget_id for update;
  if v_current is null then raise exception 'Budget not found'; end if;
  if not (
    (v_current='draft' and p_status in('approved','cancelled')) or
    (v_current='approved' and p_status in('closed','cancelled'))
  ) then raise exception 'Invalid budget transition: % -> %',v_current,p_status; end if;
  update public.maintenance_budgets set status=p_status,updated_at=now()
  where tenant_id=p_tenant_id and id=p_budget_id;
end;
$$;
revoke all on function public.change_maintenance_budget_status(uuid,uuid,text) from public,anon;
grant execute on function public.change_maintenance_budget_status(uuid,uuid,text) to authenticated;

create or replace view public.maintenance_budget_execution
with(security_invoker=true)
as
with budget_amount as (
  select b.tenant_id,b.id budget_id,b.code,b.name,b.period_start,b.period_end,b.currency,b.status,
         bl.site_id,bl.asset_id,bl.maintenance_type,bl.category,sum(bl.amount) budget_amount
  from public.maintenance_budgets b
  join public.maintenance_budget_lines bl on bl.tenant_id=b.tenant_id and bl.budget_id=b.id
  where bl.category<>'total' and b.status in('approved','closed')
  group by b.tenant_id,b.id,b.code,b.name,b.period_start,b.period_end,b.currency,b.status,
           bl.site_id,bl.asset_id,bl.maintenance_type,bl.category
), actual as (
  select ba.tenant_id,ba.budget_id,ba.site_id,ba.asset_id,ba.maintenance_type,ba.category,
         sum(ce.amount) filter(where ce.valuation_status<>'missing') actual_amount,
         count(*) filter(where ce.valuation_status='missing') missing_valuations
  from budget_amount ba
  left join public.cost_entries ce on ce.tenant_id=ba.tenant_id and ce.currency=ba.currency
    and ce.occurred_at::date between ba.period_start and ba.period_end
    and ce.category=ba.category
  left join public.work_orders wo on wo.tenant_id=ce.tenant_id and wo.id=ce.work_order_id
  left join public.assets a on a.tenant_id=wo.tenant_id and a.id=wo.asset_id
  where (ba.site_id is null or a.site_id=ba.site_id)
    and (ba.asset_id is null or wo.asset_id=ba.asset_id)
    and (ba.maintenance_type is null or wo.maintenance_type=ba.maintenance_type)
  group by ba.tenant_id,ba.budget_id,ba.site_id,ba.asset_id,ba.maintenance_type,ba.category
)
select ba.*,
  coalesce(a.actual_amount,0) actual_amount,
  ba.budget_amount-coalesce(a.actual_amount,0) remaining_amount,
  round((100.0*coalesce(a.actual_amount,0)/nullif(ba.budget_amount,0))::numeric,2) execution_percent,
  coalesce(a.missing_valuations,0) missing_valuations
from budget_amount ba
left join actual a on a.tenant_id=ba.tenant_id and a.budget_id=ba.budget_id
  and a.site_id is not distinct from ba.site_id
  and a.asset_id is not distinct from ba.asset_id
  and a.maintenance_type is not distinct from ba.maintenance_type
  and a.category=ba.category;
