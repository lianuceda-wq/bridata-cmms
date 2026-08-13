-- Bridata CMMS - proteger stock reservado y liberar reservas al cerrar OT

create or replace function private.available_unreserved_stock(p_tenant_id uuid,p_warehouse_id uuid,p_material_id uuid)
returns numeric language sql stable security definer set search_path=public,private,pg_temp as $$
  select private.current_stock(p_tenant_id,p_warehouse_id,p_material_id)
    - coalesce((select sum(quantity_reserved-quantity_consumed) from public.inventory_reservations
      where tenant_id=p_tenant_id and warehouse_id=p_warehouse_id and material_id=p_material_id and status='active'),0)
$$;
revoke all on function private.available_unreserved_stock(uuid,uuid,uuid) from public,anon,authenticated;

create or replace function public.post_inventory_movement(
 p_tenant_id uuid,p_warehouse_id uuid,p_material_id uuid,p_movement_type text,p_quantity numeric,p_unit_cost numeric default null,p_currency text default 'PEN',p_reason text default null,p_occurred_at timestamptz default now()
)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
 if not public.can_manage_inventory(p_tenant_id) then raise exception 'Insufficient inventory permissions';end if;
 if p_movement_type not in('receipt','return','adjustment_in','adjustment_out','issue') then raise exception 'Use the dedicated transfer/consumption operation for this movement type';end if;
 if p_movement_type in('adjustment_out','issue') and private.available_unreserved_stock(p_tenant_id,p_warehouse_id,p_material_id)<p_quantity then raise exception 'Movement would consume stock reserved for work orders';end if;
 return private.post_inventory_movement_core(p_tenant_id,p_warehouse_id,p_material_id,p_movement_type,p_quantity,p_unit_cost,p_currency,null,null,null,'manual',p_reason,p_occurred_at,auth.uid());
end $$;

create or replace function public.transfer_inventory(p_tenant_id uuid,p_from_warehouse_id uuid,p_to_warehouse_id uuid,p_material_id uuid,p_quantity numeric,p_reason text default null)
returns table(out_movement_id uuid,in_movement_id uuid) language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_out uuid;v_in uuid;v_cost numeric;v_currency text;v_status text;
begin
 if not public.can_manage_inventory(p_tenant_id) then raise exception 'Insufficient inventory permissions';end if;
 if p_from_warehouse_id=p_to_warehouse_id then raise exception 'Source and destination warehouses must differ';end if;
 if private.available_unreserved_stock(p_tenant_id,p_from_warehouse_id,p_material_id)<p_quantity then raise exception 'Transfer would consume stock reserved for work orders';end if;
 select x.unit_cost,x.currency,x.valuation_status into v_cost,v_currency,v_status from private.latest_material_unit_cost(p_tenant_id,p_from_warehouse_id,p_material_id)x;
 v_out:=private.post_inventory_movement_core(p_tenant_id,p_from_warehouse_id,p_material_id,'transfer_out',p_quantity,v_cost,v_currency,null,null,null,'manual',p_reason,now(),auth.uid());
 v_in:=private.post_inventory_movement_core(p_tenant_id,p_to_warehouse_id,p_material_id,'transfer_in',p_quantity,v_cost,v_currency,null,null,v_out,'manual',p_reason,now(),auth.uid());
 update public.inventory_movements set related_movement_id=v_in where id=v_out;
 return query select v_out,v_in;
end $$;

create or replace function public.consume_work_order_material(p_tenant_id uuid,p_work_order_id uuid,p_warehouse_id uuid,p_material_id uuid,p_quantity numeric,p_reservation_id uuid default null,p_notes text default null)
returns table(movement_id uuid,cost_entry_id uuid,cost_amount numeric,valuation_status text) language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_order public.work_orders;v_role text;v_move uuid;v_cost numeric;v_currency text;v_val_status text;v_cost_id uuid;v_unit_cost numeric;
begin
 v_role:=public.tenant_role(p_tenant_id);select * into v_order from public.work_orders where tenant_id=p_tenant_id and id=p_work_order_id;
 if not found or v_order.status in('closed','cancelled') then raise exception 'Work order not found or immutable';end if;
 if p_quantity is null or p_quantity<=0 then raise exception 'Quantity must be greater than zero';end if;
 if v_role='technician' then if v_order.assigned_to is distinct from auth.uid() then raise exception 'Work order is not assigned to technician';end if;elsif v_role not in('owner','admin','planner','supervisor','warehouse') then raise exception 'Insufficient consumption permissions';end if;
 if p_reservation_id is not null then
   if not exists(select 1 from public.inventory_reservations r where r.tenant_id=p_tenant_id and r.id=p_reservation_id and r.work_order_id=p_work_order_id and r.warehouse_id=p_warehouse_id and r.material_id=p_material_id and r.status='active' and r.quantity_reserved-r.quantity_consumed>=p_quantity) then raise exception 'Reservation is invalid or insufficient';end if;
 else
   if private.available_unreserved_stock(p_tenant_id,p_warehouse_id,p_material_id)<p_quantity then raise exception 'Insufficient unreserved stock';end if;
 end if;
 select x.unit_cost,x.currency,x.valuation_status into v_unit_cost,v_currency,v_val_status from private.latest_material_unit_cost(p_tenant_id,p_warehouse_id,p_material_id)x;
 v_move:=private.post_inventory_movement_core(p_tenant_id,p_warehouse_id,p_material_id,'issue',p_quantity,v_unit_cost,v_currency,p_work_order_id,null,null,'work_order',p_notes,now(),auth.uid());
 if p_reservation_id is not null then update public.inventory_reservations set quantity_consumed=quantity_consumed+p_quantity,status=case when quantity_consumed+p_quantity>=quantity_reserved then 'fulfilled' else status end,updated_at=now() where id=p_reservation_id;end if;
 if v_unit_cost is null then insert into public.cost_entries(tenant_id,work_order_id,category,source_entity,source_id,amount,currency,valuation_status,description,created_by) values(p_tenant_id,p_work_order_id,'material','inventory_movement',v_move,null,coalesce(v_currency,'PEN'),'missing',p_notes,auth.uid()) returning id into v_cost_id;v_cost:=null;else v_cost:=round(v_unit_cost*p_quantity,4);insert into public.cost_entries(tenant_id,work_order_id,category,source_entity,source_id,amount,currency,valuation_status,description,created_by) values(p_tenant_id,p_work_order_id,'material','inventory_movement',v_move,v_cost,v_currency,coalesce(v_val_status,'estimated'),p_notes,auth.uid()) returning id into v_cost_id;end if;
 return query select v_move,v_cost_id,v_cost,coalesce(v_val_status,'missing');
end $$;

create or replace function public.release_inventory_reservation(p_tenant_id uuid,p_reservation_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
 if not public.can_manage_inventory(p_tenant_id) then raise exception 'Insufficient inventory permissions';end if;
 update public.inventory_reservations set status='released',updated_at=now()
 where tenant_id=p_tenant_id and id=p_reservation_id and status='active';
end $$;
revoke all on function public.release_inventory_reservation(uuid,uuid) from public,anon;grant execute on function public.release_inventory_reservation(uuid,uuid) to authenticated;

create or replace function private.release_work_order_reservations()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
 if old.status is distinct from new.status and new.status in('closed','cancelled') then
   update public.inventory_reservations set status='released',updated_at=now()
   where tenant_id=new.tenant_id and work_order_id=new.id and status='active';
 end if;
 return new;
end $$;
revoke all on function private.release_work_order_reservations() from public,anon,authenticated;
create trigger release_work_order_reservations
after update of status on public.work_orders
for each row execute function private.release_work_order_reservations();
