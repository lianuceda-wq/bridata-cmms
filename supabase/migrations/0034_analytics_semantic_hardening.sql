-- Bridata CMMS - semántica de KPIs sin falsas penalizaciones

create or replace view public.maintenance_kpis_monthly
with(security_invoker=true)
as
select
  tenant_id,
  date_trunc('month',reference_at) month,
  count(*) work_orders,
  count(*) filter(where planned_flag) planned_orders,
  count(*) filter(where planned_flag and executed_flag) executed_planned_orders,
  count(*) filter(where planned_flag and due_at is not null) calendar_planned_orders,
  count(*) filter(where planned_flag and due_at is not null and on_time_flag) on_time_planned_orders,
  count(*) filter(where planned_flag and due_at is not null and late_flag) late_planned_orders,
  count(*) filter(where planned_flag and overdue_flag) overdue_planned_orders,
  count(*) filter(where maintenance_type='preventive') preventive_orders,
  count(*) filter(where maintenance_type='corrective') corrective_orders,
  round((100.0*count(*) filter(where planned_flag and executed_flag)
    /nullif(count(*) filter(where planned_flag),0))::numeric,2) compliance_percent,
  round((100.0*count(*) filter(where planned_flag and due_at is not null and on_time_flag)
    /nullif(count(*) filter(where planned_flag and due_at is not null),0))::numeric,2) on_time_percent
from public.maintenance_execution_facts
group by tenant_id,date_trunc('month',reference_at);

create or replace view public.hydraulic_kpis_monthly
with(security_invoker=true)
as
with session_months as (
  select s.tenant_id,date_trunc('month',s.occurred_at) month,count(*) session_count
  from public.measurement_sessions s
  where s.session_type='hydraulic_control' and s.status='validated'
  group by s.tenant_id,date_trunc('month',s.occurred_at)
), reading_months as (
  select
    s.tenant_id,date_trunc('month',s.occurred_at) month,
    count(r.id) total_readings,
    count(r.id) filter(where r.compliance_status<>'not_evaluated') evaluated_readings,
    count(r.id) filter(where r.compliance_status='compliant') compliant_readings,
    count(r.id) filter(where r.compliance_status='out_of_range') out_of_range_readings,
    avg(r.value) filter(where p.code='pressure') avg_pressure,
    avg(r.value) filter(where p.code='flow') avg_flow
  from public.measurement_sessions s
  join public.operational_readings r on r.tenant_id=s.tenant_id and r.session_id=s.id
  join public.measurement_parameters p on p.tenant_id=r.tenant_id and p.id=r.parameter_id
  where s.session_type='hydraulic_control' and s.status='validated'
  group by s.tenant_id,date_trunc('month',s.occurred_at)
)
select
  sm.tenant_id,sm.month,sm.session_count,
  coalesce(rm.total_readings,0) total_readings,
  coalesce(rm.evaluated_readings,0) evaluated_readings,
  coalesce(rm.compliant_readings,0) compliant_readings,
  coalesce(rm.out_of_range_readings,0) out_of_range_readings,
  round((100.0*coalesce(rm.compliant_readings,0)/nullif(rm.evaluated_readings,0))::numeric,2) compliance_percent,
  round(rm.avg_pressure::numeric,2) avg_pressure,
  round(rm.avg_flow::numeric,2) avg_flow
from session_months sm
left join reading_months rm on rm.tenant_id=sm.tenant_id and rm.month=sm.month;

update public.metric_definitions
set formula_description='OT planificadas calendario completadas antes o en due_at / OT planificadas calendario × 100',
    description='Solo incluye OT con vencimiento por fecha. Las rutinas por medidor requieren trazabilidad del valor de medidor al completar.'
where code='maintenance_on_time';
