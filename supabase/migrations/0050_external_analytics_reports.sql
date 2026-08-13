-- External analytics report gateway. Raw keys are hashed by the API route before calling this RPC.
create or replace function public.fetch_analytics_report(
  p_key_hash text,
  p_report_key text,
  p_from date default null,
  p_to date default null,
  p_limit integer default 2000
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_auth record;
  v_rows jsonb;
  v_count integer;
  v_limit integer:=least(greatest(coalesce(p_limit,2000),1),5000);
  v_from date:=coalesce(p_from,current_date-365);
  v_to date:=coalesce(p_to,current_date);
begin
  if v_to<v_from then raise exception 'Invalid date range'; end if;
  select * into v_auth from public.authorize_analytics_api_key(lower(p_key_hash),p_report_key);
  if not found then raise exception 'Analytics API authorization failed'; end if;

  case p_report_key
    when 'maintenance' then
      select coalesce(jsonb_agg(to_jsonb(q) order by q.month),'[]'::jsonb) into v_rows
      from (select * from public.maintenance_kpis_monthly where tenant_id=v_auth.tenant_id and month::date between date_trunc('month',v_from)::date and date_trunc('month',v_to)::date order by month limit v_limit) q;
    when 'reliability' then
      select coalesce(jsonb_agg(to_jsonb(q) order by q.month),'[]'::jsonb) into v_rows
      from (select * from public.reliability_kpis_monthly where tenant_id=v_auth.tenant_id and month::date between date_trunc('month',v_from)::date and date_trunc('month',v_to)::date order by month limit v_limit) q;
    when 'hydraulics' then
      select coalesce(jsonb_agg(to_jsonb(q) order by q.month),'[]'::jsonb) into v_rows
      from (select * from public.hydraulic_kpis_monthly where tenant_id=v_auth.tenant_id and month::date between date_trunc('month',v_from)::date and date_trunc('month',v_to)::date order by month limit v_limit) q;
    when 'costs' then
      select coalesce(jsonb_agg(to_jsonb(q) order by q.month),'[]'::jsonb) into v_rows
      from (select * from public.maintenance_cost_kpis_monthly where tenant_id=v_auth.tenant_id and month::date between date_trunc('month',v_from)::date and date_trunc('month',v_to)::date order by month limit v_limit) q;
    when 'inventory' then
      select coalesce(jsonb_agg(to_jsonb(q) order by q.warehouse_code,q.material_code),'[]'::jsonb) into v_rows
      from (select * from public.inventory_status where tenant_id=v_auth.tenant_id order by warehouse_code,material_code limit v_limit) q;
    when 'purchases' then
      select coalesce(jsonb_agg(to_jsonb(q) order by q.expected_at nulls last,q.code),'[]'::jsonb) into v_rows
      from (select * from public.purchase_order_summary where tenant_id=v_auth.tenant_id order by expected_at nulls last,code limit v_limit) q;
    when 'budget' then
      select coalesce(jsonb_agg(to_jsonb(q) order by q.period_start,q.code),'[]'::jsonb) into v_rows
      from (select * from public.maintenance_budget_execution where tenant_id=v_auth.tenant_id and period_end>=v_from and period_start<=v_to order by period_start,code limit v_limit) q;
    when 'inspections' then
      select coalesce(jsonb_agg(to_jsonb(q) order by q.scheduled_at nulls last,q.code),'[]'::jsonb) into v_rows
      from (select * from public.inspection_run_kpis where tenant_id=v_auth.tenant_id and coalesce(scheduled_at,started_at,completed_at,validated_at)::date between v_from and v_to order by scheduled_at nulls last,code limit v_limit) q;
    when 'attendance' then
      select coalesce(jsonb_agg(to_jsonb(q) order by q.month),'[]'::jsonb) into v_rows
      from (select * from public.attendance_kpis_monthly where tenant_id=v_auth.tenant_id and month::date between date_trunc('month',v_from)::date and date_trunc('month',v_to)::date order by month limit v_limit) q;
    when 'work_orders' then
      select coalesce(jsonb_agg(to_jsonb(q) order by q.reference_at,q.code),'[]'::jsonb) into v_rows
      from (select * from public.maintenance_execution_facts where tenant_id=v_auth.tenant_id and reference_at::date between v_from and v_to order by reference_at,code limit v_limit) q;
    else raise exception 'Unknown analytics report';
  end case;

  v_count:=jsonb_array_length(v_rows);
  perform public.complete_analytics_api_request(v_auth.request_id,v_count,200,0);
  return jsonb_build_object('report',p_report_key,'generated_at',now(),'row_count',v_count,'rows',v_rows);
end;
$$;
revoke all on function public.fetch_analytics_report(text,text,date,date,integer) from public;
grant execute on function public.fetch_analytics_report(text,text,date,date,integer) to anon,authenticated;
