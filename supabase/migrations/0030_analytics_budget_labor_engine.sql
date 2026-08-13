-- Bridata CMMS - Analytics, Budget & Labor Valuation Engine

create table public.labor_rate_versions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  labor_role text,
  hourly_rate numeric not null check(hourly_rate>=0),
  currency text not null default 'PEN' check(length(currency)=3),
  valid_from date not null,
  valid_to date,
  is_active boolean not null default true,
  notes text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(valid_to is null or valid_to>=valid_from),
  check(user_id is null or nullif(trim(coalesce(labor_role,'')),'') is null)
);
create unique index uq_labor_rate_versions_tenant_id on public.labor_rate_versions(tenant_id,id);
create index idx_labor_rate_user_period on public.labor_rate_versions(tenant_id,user_id,valid_from desc) where user_id is not null and is_active=true;
create index idx_labor_rate_role_period on public.labor_rate_versions(tenant_id,labor_role,valid_from desc) where labor_role is not null and is_active=true;
create index idx_labor_rate_default_period on public.labor_rate_versions(tenant_id,valid_from desc) where user_id is null and labor_role is null and is_active=true;
create index idx_labor_rate_created_by on public.labor_rate_versions(created_by);

alter table public.work_order_labor_sessions
  add column if not exists hourly_rate_snapshot numeric check(hourly_rate_snapshot is null or hourly_rate_snapshot>=0),
  add column if not exists rate_currency text check(rate_currency is null or length(rate_currency)=3),
  add column if not exists rate_source text check(rate_source is null or rate_source in ('user','role','default','manual','missing'));

create or replace function private.validate_labor_rate_version()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  if exists(
    select 1 from public.labor_rate_versions r
    where r.id<>new.id and r.tenant_id=new.tenant_id and r.is_active=true and new.is_active=true
      and r.user_id is not distinct from new.user_id
      and coalesce(r.labor_role,'')=coalesce(new.labor_role,'')
      and daterange(r.valid_from,coalesce(r.valid_to+1,'infinity'::date),'[)')
          && daterange(new.valid_from,coalesce(new.valid_to+1,'infinity'::date),'[)')
  ) then raise exception 'An active labor rate already overlaps this scope and period'; end if;
  return new;
end $$;
revoke all on function private.validate_labor_rate_version() from public,anon,authenticated;
create trigger validate_labor_rate_version before insert or update on public.labor_rate_versions for each row execute function private.validate_labor_rate_version();

create or replace function private.resolve_labor_rate(p_tenant_id uuid,p_user_id uuid,p_labor_role text,p_date date)
returns table(hourly_rate numeric,currency text,rate_source text)
language sql stable security definer set search_path=public,private,pg_temp as $$
  select r.hourly_rate,r.currency,
    case when r.user_id is not null then 'user' when r.labor_role is not null then 'role' else 'default' end
  from public.labor_rate_versions r
  where r.tenant_id=p_tenant_id and r.is_active=true
    and p_date>=r.valid_from and (r.valid_to is null or p_date<=r.valid_to)
    and (
      (p_user_id is not null and r.user_id=p_user_id)
      or (r.user_id is null and r.labor_role is not null and r.labor_role=coalesce(p_labor_role,''))
      or (r.user_id is null and r.labor_role is null)
    )
  order by case when r.user_id is not null then 3 when r.labor_role is not null then 2 else 1 end desc,r.valid_from desc
  limit 1
$$;
revoke all on function private.resolve_labor_rate(uuid,uuid,text,date) from public,anon,authenticated;

create or replace function private.snapshot_labor_rate()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_rate numeric;v_currency text;v_source text;
begin
  if tg_op='INSERT' or old.started_at is distinct from new.started_at or old.worker_user_id is distinct from new.worker_user_id or old.labor_role is distinct from new.labor_role then
    if new.hourly_rate_snapshot is null or tg_op='UPDATE' then
      select x.hourly_rate,x.currency,x.rate_source into v_rate,v_currency,v_source
      from private.resolve_labor_rate(new.tenant_id,new.worker_user_id,new.labor_role,new.started_at::date)x;
      new.hourly_rate_snapshot:=v_rate;
      new.rate_currency:=coalesce(v_currency,'PEN');
      new.rate_source:=coalesce(v_source,'missing');
    end if;
  end if;
  return new;
end $$;
revoke all on function private.snapshot_labor_rate() from public,anon,authenticated;
create trigger snapshot_labor_rate before insert or update of started_at,worker_user_id,labor_role on public.work_order_labor_sessions for each row execute function private.snapshot_labor_rate();

create or replace function private.sync_labor_cost_entry()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_hours numeric;v_amount numeric;v_status text;
begin
  if new.ended_at is null then return new; end if;
  v_hours:=extract(epoch from(new.ended_at-new.started_at))/3600.0;
  if new.hourly_rate_snapshot is null then v_amount:=null;v_status:='missing';
  else v_amount:=round(v_hours*new.hourly_rate_snapshot,4);v_status:='actual'; end if;

  update public.cost_entries
  set amount=v_amount,currency=coalesce(new.rate_currency,'PEN'),valuation_status=v_status,
      occurred_at=new.ended_at,description='Mano de obra · '||coalesce(new.worker_name,new.labor_role,'trabajador')
  where tenant_id=new.tenant_id and source_entity='labor_session' and source_id=new.id and category='labor';

  if not found then
    insert into public.cost_entries(tenant_id,work_order_id,category,source_entity,source_id,amount,currency,valuation_status,occurred_at,description,created_by)
    values(new.tenant_id,new.work_order_id,'labor','labor_session',new.id,v_amount,coalesce(new.rate_currency,'PEN'),v_status,new.ended_at,
      'Mano de obra · '||coalesce(new.worker_name,new.labor_role,'trabajador'),new.created_by);
  end if;
  return new;
end $$;
revoke all on function private.sync_labor_cost_entry() from public,anon,authenticated;
create trigger sync_labor_cost_entry after insert or update of ended_at,started_at,hourly_rate_snapshot,rate_currency on public.work_order_labor_sessions for each row execute function private.sync_labor_cost_entry();

create or replace function public.create_labor_rate_version(
  p_tenant_id uuid,p_user_id uuid,p_labor_role text,p_hourly_rate numeric,p_currency text,p_valid_from date,p_notes text default null
)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid;
begin
  if public.tenant_role(p_tenant_id) not in('owner','admin','planner') then raise exception 'Insufficient labor rate permissions'; end if;
  if p_valid_from is null or p_hourly_rate is null or p_hourly_rate<0 then raise exception 'Rate and validity are required'; end if;
  if p_user_id is not null and not exists(select 1 from public.tenant_members where tenant_id=p_tenant_id and user_id=p_user_id and is_active=true) then raise exception 'User does not belong to tenant'; end if;

  update public.labor_rate_versions r set valid_to=p_valid_from-1,updated_at=now()
  where r.tenant_id=p_tenant_id and r.is_active=true
    and r.user_id is not distinct from p_user_id and coalesce(r.labor_role,'')=coalesce(nullif(trim(p_labor_role),''),'')
    and r.valid_from<p_valid_from and (r.valid_to is null or r.valid_to>=p_valid_from);

  insert into public.labor_rate_versions(tenant_id,user_id,labor_role,hourly_rate,currency,valid_from,notes,created_by)
  values(p_tenant_id,p_user_id,nullif(trim(p_labor_role),''),p_hourly_rate,upper(coalesce(p_currency,'PEN')),p_valid_from,p_notes,auth.uid())
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.create_labor_rate_version(uuid,uuid,text,numeric,text,date,text) from public,anon;
grant execute on function public.create_labor_rate_version(uuid,uuid,text,numeric,text,date,text) to authenticated;

-- Fact view: one row per OT with flags reusable by analytics and drill-down.
create or replace view public.maintenance_execution_facts with(security_invoker=true) as
select
  wo.tenant_id,wo.id work_order_id,wo.code,wo.asset_id,wo.plan_id,wo.routine_id,wo.source,wo.maintenance_type,wo.priority,wo.status,
  wo.scheduled_at,wo.due_at,wo.started_at,wo.completed_at,wo.validated_at,wo.closed_at,wo.created_at,
  coalesce(wo.due_at,wo.scheduled_at,wo.created_at) reference_at,
  (wo.source='maintenance_plan') planned_flag,
  (wo.status in('completed','validated','closed')) executed_flag,
  (wo.status in('completed','validated','closed') and wo.completed_at is not null and wo.due_at is not null and wo.completed_at<=wo.due_at) on_time_flag,
  (wo.status in('completed','validated','closed') and wo.completed_at is not null and wo.due_at is not null and wo.completed_at>wo.due_at) late_flag,
  (wo.status not in('completed','validated','closed','cancelled') and wo.due_at is not null and wo.due_at<now()) overdue_flag,
  case when wo.started_at is not null then extract(epoch from(wo.started_at-wo.created_at))/60.0 end response_minutes,
  case when wo.started_at is not null and wo.completed_at is not null then extract(epoch from(wo.completed_at-wo.started_at))/60.0 end elapsed_execution_minutes
from public.work_orders wo;

create or replace view public.maintenance_kpis_monthly with(security_invoker=true) as
select
  tenant_id,date_trunc('month',reference_at) month,
  count(*) work_orders,
  count(*) filter(where planned_flag) planned_orders,
  count(*) filter(where planned_flag and executed_flag) executed_planned_orders,
  count(*) filter(where planned_flag and on_time_flag) on_time_planned_orders,
  count(*) filter(where planned_flag and late_flag) late_planned_orders,
  count(*) filter(where planned_flag and overdue_flag) overdue_planned_orders,
  count(*) filter(where maintenance_type='preventive') preventive_orders,
  count(*) filter(where maintenance_type='corrective') corrective_orders,
  round((100.0*count(*) filter(where planned_flag and executed_flag)/nullif(count(*) filter(where planned_flag),0))::numeric,2) compliance_percent,
  round((100.0*count(*) filter(where planned_flag and on_time_flag)/nullif(count(*) filter(where planned_flag),0))::numeric,2) on_time_percent
from public.maintenance_execution_facts
group by tenant_id,date_trunc('month',reference_at);

create or replace view public.reliability_kpis_monthly with(security_invoker=true) as
select
  f.tenant_id,date_trunc('month',f.occurred_at) month,
  count(*) filter(where f.status<>'cancelled') failure_count,
  round(avg(f.repair_minutes/60.0) filter(where f.repair_minutes is not null)::numeric,2) mttr_hours,
  round(avg(f.downtime_minutes/60.0) filter(where f.downtime_minutes is not null)::numeric,2) avg_downtime_hours,
  round(avg(f.response_minutes/60.0) filter(where f.response_minutes is not null)::numeric,2) avg_response_hours
from public.failure_event_metrics f
group by f.tenant_id,date_trunc('month',f.occurred_at);

create or replace view public.hydraulic_kpis_monthly with(security_invoker=true) as
select
  h.tenant_id,date_trunc('month',h.occurred_at) month,
  count(*) session_count,
  sum(h.total_readings) total_readings,
  sum(h.evaluated_readings) evaluated_readings,
  sum(h.compliant_readings) compliant_readings,
  sum(h.out_of_range_readings) out_of_range_readings,
  round((100.0*sum(h.compliant_readings)/nullif(sum(h.evaluated_readings),0))::numeric,2) compliance_percent,
  round(avg(h.avg_pressure)::numeric,2) avg_pressure,
  round(avg(h.avg_flow)::numeric,2) avg_flow
from public.hydraulic_session_kpis h
where h.status='validated'
group by h.tenant_id,date_trunc('month',h.occurred_at);

create or replace view public.maintenance_cost_kpis_monthly with(security_invoker=true) as
select
  ce.tenant_id,date_trunc('month',ce.occurred_at) month,ce.currency,
  sum(ce.amount) filter(where ce.valuation_status<>'missing') total_cost,
  sum(ce.amount) filter(where ce.category='material' and ce.valuation_status<>'missing') material_cost,
  sum(ce.amount) filter(where ce.category='labor' and ce.valuation_status<>'missing') labor_cost,
  sum(ce.amount) filter(where ce.category in('service','contractor') and ce.valuation_status<>'missing') external_cost,
  sum(ce.amount) filter(where wo.maintenance_type='preventive' and ce.valuation_status<>'missing') preventive_cost,
  sum(ce.amount) filter(where wo.maintenance_type='corrective' and ce.valuation_status<>'missing') corrective_cost,
  count(*) filter(where ce.valuation_status='missing') missing_valuations
from public.cost_entries ce
left join public.work_orders wo on wo.tenant_id=ce.tenant_id and wo.id=ce.work_order_id
group by ce.tenant_id,date_trunc('month',ce.occurred_at),ce.currency;

create or replace view public.maintenance_budget_execution with(security_invoker=true) as
with budget_amount as (
  select b.tenant_id,b.id budget_id,b.code,b.name,b.period_start,b.period_end,b.currency,b.status,
         bl.site_id,bl.asset_id,bl.maintenance_type,bl.category,sum(bl.amount) budget_amount
  from public.maintenance_budgets b
  join public.maintenance_budget_lines bl on bl.tenant_id=b.tenant_id and bl.budget_id=b.id
  where bl.category<>'total'
  group by b.tenant_id,b.id,b.code,b.name,b.period_start,b.period_end,b.currency,b.status,bl.site_id,bl.asset_id,bl.maintenance_type,bl.category
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
  and a.site_id is not distinct from ba.site_id and a.asset_id is not distinct from ba.asset_id
  and a.maintenance_type is not distinct from ba.maintenance_type and a.category=ba.category;

create or replace view public.inventory_kpis with(security_invoker=true) as
select tenant_id,
  count(*) sku_warehouse_combinations,
  count(*) filter(where stock_status='below_minimum') below_minimum_count,
  count(*) filter(where stock_status='reorder') reorder_count,
  sum(quantity_on_hand) total_units_on_hand,
  sum(reserved_quantity) total_reserved,
  sum(available_quantity) total_available,
  sum(estimated_stock_value) filter(where cost_currency='PEN') estimated_stock_value_pen
from public.inventory_status group by tenant_id;

create or replace view public.purchase_kpis with(security_invoker=true) as
select tenant_id,currency,
  count(*) filter(where status not in('received','cancelled')) open_purchase_orders,
  sum(pending_amount) filter(where status not in('received','cancelled')) pending_amount,
  count(*) filter(where status not in('received','cancelled') and expected_at<now()) overdue_purchase_orders
from public.purchase_order_summary
group by tenant_id,currency;

create trigger labor_rate_versions_updated_at before update on public.labor_rate_versions for each row execute function public.set_updated_at();
alter table public.labor_rate_versions enable row level security;
create policy labor_rates_select on public.labor_rate_versions for select to authenticated using(public.is_tenant_member(tenant_id));
create policy labor_rates_write on public.labor_rate_versions for all to authenticated
using(public.tenant_role(tenant_id) in('owner','admin','planner'))
with check(public.tenant_role(tenant_id) in('owner','admin','planner'));
grant select,insert,update,delete on public.labor_rate_versions to authenticated;
grant select on public.maintenance_execution_facts,public.maintenance_kpis_monthly,public.reliability_kpis_monthly,public.hydraulic_kpis_monthly,public.maintenance_cost_kpis_monthly,public.maintenance_budget_execution,public.inventory_kpis,public.purchase_kpis to authenticated;
