-- Bridata CMMS - las HH son la única fuente de costo laboral interno

create or replace function public.add_manual_cost(
 p_tenant_id uuid,
 p_work_order_id uuid,
 p_category text,
 p_amount numeric,
 p_currency text,
 p_description text,
 p_occurred_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare v_id uuid;
begin
 if public.tenant_role(p_tenant_id) not in('owner','admin','planner','supervisor','warehouse') then
   raise exception 'Insufficient cost permissions';
 end if;
 if p_amount is null or p_amount<0 then raise exception 'Cost amount must be non-negative'; end if;
 if p_category not in('service','contractor','other') then
   raise exception 'Manual labor cost is not allowed; use labor sessions and labor rates';
 end if;
 if not exists(select 1 from public.work_orders where tenant_id=p_tenant_id and id=p_work_order_id) then
   raise exception 'Work order not found';
 end if;
 insert into public.cost_entries(
   tenant_id,work_order_id,category,source_entity,amount,currency,valuation_status,occurred_at,description,created_by
 ) values(
   p_tenant_id,p_work_order_id,p_category,'manual',p_amount,upper(p_currency),'actual',p_occurred_at,p_description,auth.uid()
 ) returning id into v_id;
 return v_id;
end;
$$;
