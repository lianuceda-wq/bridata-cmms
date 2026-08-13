-- Bridata CMMS - concurrencia e índices finales de inventario

create index if not exists idx_material_categories_parent
  on public.material_categories(tenant_id,parent_id);
create index if not exists idx_inventory_movements_related_tenant
  on public.inventory_movements(tenant_id,related_movement_id);

create or replace function public.transfer_inventory(
 p_tenant_id uuid,
 p_from_warehouse_id uuid,
 p_to_warehouse_id uuid,
 p_material_id uuid,
 p_quantity numeric,
 p_reason text default null
)
returns table(out_movement_id uuid,in_movement_id uuid)
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_out uuid;
  v_in uuid;
  v_cost numeric;
  v_currency text;
  v_status text;
  v_lock_a text;
  v_lock_b text;
begin
  if not public.can_manage_inventory(p_tenant_id) then
    raise exception 'Insufficient inventory permissions';
  end if;
  if p_from_warehouse_id=p_to_warehouse_id then
    raise exception 'Source and destination warehouses must differ';
  end if;
  if p_quantity is null or p_quantity<=0 then
    raise exception 'Quantity must be greater than zero';
  end if;

  -- Orden global de locks para evitar deadlocks A→B vs B→A.
  v_lock_a:=least(p_from_warehouse_id::text,p_to_warehouse_id::text);
  v_lock_b:=greatest(p_from_warehouse_id::text,p_to_warehouse_id::text);
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||v_lock_a||':'||p_material_id::text,0));
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||v_lock_b||':'||p_material_id::text,0));

  if private.available_unreserved_stock(p_tenant_id,p_from_warehouse_id,p_material_id)<p_quantity then
    raise exception 'Transfer would consume stock reserved for work orders';
  end if;

  select x.unit_cost,x.currency,x.valuation_status
  into v_cost,v_currency,v_status
  from private.latest_material_unit_cost(p_tenant_id,p_from_warehouse_id,p_material_id)x;

  v_out:=private.post_inventory_movement_core(
    p_tenant_id,p_from_warehouse_id,p_material_id,'transfer_out',p_quantity,
    v_cost,v_currency,null,null,null,'manual',p_reason,now(),auth.uid()
  );
  v_in:=private.post_inventory_movement_core(
    p_tenant_id,p_to_warehouse_id,p_material_id,'transfer_in',p_quantity,
    v_cost,v_currency,null,null,v_out,'manual',p_reason,now(),auth.uid()
  );
  update public.inventory_movements
  set related_movement_id=v_in
  where tenant_id=p_tenant_id and id=v_out;

  return query select v_out,v_in;
end;
$$;
