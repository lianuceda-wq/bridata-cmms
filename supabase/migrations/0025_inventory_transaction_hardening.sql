-- Bridata CMMS - transacciones de inventario solo vía operaciones controladas

revoke insert,update,delete on public.inventory_movements from authenticated;
revoke insert,update,delete on public.inventory_reservations from authenticated;
revoke insert,update,delete on public.cost_entries from authenticated;

create or replace function public.post_inventory_movement(
 p_tenant_id uuid,p_warehouse_id uuid,p_material_id uuid,p_movement_type text,p_quantity numeric,p_unit_cost numeric default null,p_currency text default 'PEN',p_reason text default null,p_occurred_at timestamptz default now()
)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
 if not public.can_manage_inventory(p_tenant_id) then raise exception 'Insufficient inventory permissions';end if;
 if p_movement_type not in('receipt','return','adjustment_in','adjustment_out','issue') then raise exception 'Use the dedicated transfer/consumption operation for this movement type';end if;
 return private.post_inventory_movement_core(p_tenant_id,p_warehouse_id,p_material_id,p_movement_type,p_quantity,p_unit_cost,p_currency,null,null,null,'manual',p_reason,p_occurred_at,auth.uid());
end $$;

create or replace function public.transfer_inventory(p_tenant_id uuid,p_from_warehouse_id uuid,p_to_warehouse_id uuid,p_material_id uuid,p_quantity numeric,p_reason text default null)
returns table(out_movement_id uuid,in_movement_id uuid) language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_out uuid;v_in uuid;v_cost numeric;v_currency text;v_status text;
begin
 if not public.can_manage_inventory(p_tenant_id) then raise exception 'Insufficient inventory permissions';end if;
 if p_from_warehouse_id=p_to_warehouse_id then raise exception 'Source and destination warehouses must differ';end if;
 select x.unit_cost,x.currency,x.valuation_status into v_cost,v_currency,v_status from private.latest_material_unit_cost(p_tenant_id,p_from_warehouse_id,p_material_id)x;
 v_out:=private.post_inventory_movement_core(p_tenant_id,p_from_warehouse_id,p_material_id,'transfer_out',p_quantity,v_cost,v_currency,null,null,null,'manual',p_reason,now(),auth.uid());
 v_in:=private.post_inventory_movement_core(p_tenant_id,p_to_warehouse_id,p_material_id,'transfer_in',p_quantity,v_cost,v_currency,null,null,v_out,'manual',p_reason,now(),auth.uid());
 update public.inventory_movements set related_movement_id=v_in where id=v_out;
 return query select v_out,v_in;
end $$;

create or replace function public.reserve_work_order_material(p_tenant_id uuid,p_work_order_id uuid,p_warehouse_id uuid,p_material_id uuid,p_quantity numeric)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid;v_stock numeric;v_reserved numeric;v_role text;
begin
 v_role:=public.tenant_role(p_tenant_id);
 if v_role not in('owner','admin','planner','supervisor','warehouse') then raise exception 'Insufficient reservation permissions';end if;
 if p_quantity is null or p_quantity<=0 then raise exception 'Quantity must be greater than zero';end if;
 if not exists(select 1 from public.work_orders where tenant_id=p_tenant_id and id=p_work_order_id and status not in('closed','cancelled')) then raise exception 'Work order cannot receive reservations';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||p_warehouse_id::text||':'||p_material_id::text,0));
 v_stock:=private.current_stock(p_tenant_id,p_warehouse_id,p_material_id);
 select coalesce(sum(quantity_reserved-quantity_consumed),0) into v_reserved from public.inventory_reservations where tenant_id=p_tenant_id and warehouse_id=p_warehouse_id and material_id=p_material_id and status='active';
 if v_stock-v_reserved<p_quantity then raise exception 'Insufficient available stock after reservations. Available: %',v_stock-v_reserved;end if;
 insert into public.inventory_reservations(tenant_id,work_order_id,warehouse_id,material_id,quantity_reserved,created_by) values(p_tenant_id,p_work_order_id,p_warehouse_id,p_material_id,p_quantity,auth.uid()) returning id into v_id;
 return v_id;
end $$;

create or replace function public.consume_work_order_material(p_tenant_id uuid,p_work_order_id uuid,p_warehouse_id uuid,p_material_id uuid,p_quantity numeric,p_reservation_id uuid default null,p_notes text default null)
returns table(movement_id uuid,cost_entry_id uuid,cost_amount numeric,valuation_status text) language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_order public.work_orders;v_role text;v_move uuid;v_cost numeric;v_currency text;v_val_status text;v_cost_id uuid;v_unit_cost numeric;
begin
 v_role:=public.tenant_role(p_tenant_id);select * into v_order from public.work_orders where tenant_id=p_tenant_id and id=p_work_order_id;
 if not found or v_order.status in('closed','cancelled') then raise exception 'Work order not found or immutable';end if;
 if v_role='technician' then if v_order.assigned_to is distinct from auth.uid() then raise exception 'Work order is not assigned to technician';end if;elsif v_role not in('owner','admin','planner','supervisor','warehouse') then raise exception 'Insufficient consumption permissions';end if;
 if p_reservation_id is not null and not exists(select 1 from public.inventory_reservations r where r.tenant_id=p_tenant_id and r.id=p_reservation_id and r.work_order_id=p_work_order_id and r.warehouse_id=p_warehouse_id and r.material_id=p_material_id and r.status='active' and r.quantity_reserved-r.quantity_consumed>=p_quantity) then raise exception 'Reservation is invalid or insufficient';end if;
 select x.unit_cost,x.currency,x.valuation_status into v_unit_cost,v_currency,v_val_status from private.latest_material_unit_cost(p_tenant_id,p_warehouse_id,p_material_id)x;
 v_move:=private.post_inventory_movement_core(p_tenant_id,p_warehouse_id,p_material_id,'issue',p_quantity,v_unit_cost,v_currency,p_work_order_id,null,null,'work_order',p_notes,now(),auth.uid());
 if p_reservation_id is not null then update public.inventory_reservations set quantity_consumed=quantity_consumed+p_quantity,status=case when quantity_consumed+p_quantity>=quantity_reserved then 'fulfilled' else status end,updated_at=now() where id=p_reservation_id;end if;
 if v_unit_cost is null then
   insert into public.cost_entries(tenant_id,work_order_id,category,source_entity,source_id,amount,currency,valuation_status,description,created_by) values(p_tenant_id,p_work_order_id,'material','inventory_movement',v_move,null,coalesce(v_currency,'PEN'),'missing',p_notes,auth.uid()) returning id into v_cost_id;v_cost:=null;
 else
   v_cost:=round(v_unit_cost*p_quantity,4);insert into public.cost_entries(tenant_id,work_order_id,category,source_entity,source_id,amount,currency,valuation_status,description,created_by) values(p_tenant_id,p_work_order_id,'material','inventory_movement',v_move,v_cost,v_currency,coalesce(v_val_status,'estimated'),p_notes,auth.uid()) returning id into v_cost_id;
 end if;
 return query select v_move,v_cost_id,v_cost,coalesce(v_val_status,'missing');
end $$;

create or replace function public.add_manual_cost(p_tenant_id uuid,p_work_order_id uuid,p_category text,p_amount numeric,p_currency text,p_description text,p_occurred_at timestamptz default now())
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid;
begin
 if public.tenant_role(p_tenant_id) not in('owner','admin','planner','supervisor','warehouse') then raise exception 'Insufficient cost permissions';end if;
 if p_amount is null or p_amount<0 then raise exception 'Cost amount must be non-negative';end if;
 if p_category not in('labor','service','contractor','other') then raise exception 'Manual category is not allowed';end if;
 insert into public.cost_entries(tenant_id,work_order_id,category,source_entity,amount,currency,valuation_status,occurred_at,description,created_by) values(p_tenant_id,p_work_order_id,p_category,'manual',p_amount,upper(p_currency),'actual',p_occurred_at,p_description,auth.uid()) returning id into v_id;
 return v_id;
end $$;

create or replace function private.protect_purchase_received_quantity()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
 if old.quantity_received is distinct from new.quantity_received and current_setting('bridata.inventory_receipt',true) is distinct from '1' then raise exception 'quantity_received can only change through receipt operation';end if;
 return new;
end $$;
revoke all on function private.protect_purchase_received_quantity() from public,anon,authenticated;
create trigger protect_purchase_received_quantity before update of quantity_received on public.purchase_order_lines for each row execute function private.protect_purchase_received_quantity();

create or replace function public.create_purchase_order(
 p_tenant_id uuid,p_supplier_id uuid,p_currency text,p_expected_at timestamptz,p_notes text,p_lines jsonb
)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_order uuid;v_line jsonb;
begin
 if not public.can_manage_inventory(p_tenant_id) then raise exception 'Insufficient purchase permissions';end if;
 if p_supplier_id is not null and not exists(select 1 from public.suppliers where tenant_id=p_tenant_id and id=p_supplier_id and is_active=true) then raise exception 'Supplier not found or inactive';end if;
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'Purchase order requires at least one line';end if;
 insert into public.purchase_orders(tenant_id,supplier_id,status,currency,ordered_at,expected_at,notes,created_by) values(p_tenant_id,p_supplier_id,'ordered',upper(coalesce(p_currency,'PEN')),now(),p_expected_at,p_notes,auth.uid()) returning id into v_order;
 for v_line in select value from jsonb_array_elements(p_lines) loop
   if (v_line->>'quantity')::numeric<=0 or (v_line->>'unit_price')::numeric<0 then raise exception 'Invalid purchase line quantity or price';end if;
   insert into public.purchase_order_lines(tenant_id,purchase_order_id,material_id,warehouse_id,quantity_ordered,unit_price)
   values(p_tenant_id,v_order,(v_line->>'material_id')::uuid,nullif(v_line->>'warehouse_id','')::uuid,(v_line->>'quantity')::numeric,(v_line->>'unit_price')::numeric);
 end loop;
 return v_order;
end $$;
revoke all on function public.create_purchase_order(uuid,uuid,text,timestamptz,text,jsonb) from public,anon;grant execute on function public.create_purchase_order(uuid,uuid,text,timestamptz,text,jsonb) to authenticated;

create or replace function public.receive_purchase_order_line(p_tenant_id uuid,p_line_id uuid,p_warehouse_id uuid,p_quantity numeric)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_line public.purchase_order_lines;v_order public.purchase_orders;v_move uuid;v_new_received numeric;v_all_received boolean;
begin
 if not public.can_manage_inventory(p_tenant_id) then raise exception 'Insufficient receipt permissions';end if;
 select * into v_line from public.purchase_order_lines where tenant_id=p_tenant_id and id=p_line_id for update;if not found then raise exception 'Purchase line not found';end if;
 select * into v_order from public.purchase_orders where tenant_id=p_tenant_id and id=v_line.purchase_order_id for update;if not found or v_order.status in('received','cancelled') then raise exception 'Purchase order cannot receive more material';end if;
 if p_quantity is null or p_quantity<=0 or v_line.quantity_received+p_quantity>v_line.quantity_ordered then raise exception 'Receipt exceeds pending quantity';end if;
 v_move:=private.post_inventory_movement_core(p_tenant_id,p_warehouse_id,v_line.material_id,'receipt',p_quantity,v_line.unit_price,v_order.currency,null,v_line.id,null,'purchase','Recepción '||v_order.code,now(),auth.uid());
 perform set_config('bridata.inventory_receipt','1',true);v_new_received:=v_line.quantity_received+p_quantity;update public.purchase_order_lines set quantity_received=v_new_received,warehouse_id=coalesce(warehouse_id,p_warehouse_id),updated_at=now() where id=v_line.id;
 select bool_and(quantity_received>=quantity_ordered) into v_all_received from public.purchase_order_lines where tenant_id=p_tenant_id and purchase_order_id=v_order.id;
 update public.purchase_orders set status=case when v_all_received then 'received' else 'partial' end,updated_at=now() where id=v_order.id;
 return v_move;
end $$;
revoke all on function public.receive_purchase_order_line(uuid,uuid,uuid,numeric) from public,anon;grant execute on function public.receive_purchase_order_line(uuid,uuid,uuid,numeric) to authenticated;

-- Las funciones públicas de transacción son SECURITY DEFINER de forma intencional; todas validan tenant/rol internamente.
revoke all on function public.post_inventory_movement(uuid,uuid,uuid,text,numeric,numeric,text,text,timestamptz) from public,anon;
grant execute on function public.post_inventory_movement(uuid,uuid,uuid,text,numeric,numeric,text,text,timestamptz) to authenticated;
revoke all on function public.transfer_inventory(uuid,uuid,uuid,uuid,numeric,text) from public,anon;grant execute on function public.transfer_inventory(uuid,uuid,uuid,uuid,numeric,text) to authenticated;
revoke all on function public.reserve_work_order_material(uuid,uuid,uuid,uuid,numeric) from public,anon;grant execute on function public.reserve_work_order_material(uuid,uuid,uuid,uuid,numeric) to authenticated;
revoke all on function public.consume_work_order_material(uuid,uuid,uuid,uuid,numeric,uuid,text) from public,anon;grant execute on function public.consume_work_order_material(uuid,uuid,uuid,uuid,numeric,uuid,text) to authenticated;
revoke all on function public.add_manual_cost(uuid,uuid,text,numeric,text,text,timestamptz) from public,anon;grant execute on function public.add_manual_cost(uuid,uuid,text,numeric,text,text,timestamptz) to authenticated;
