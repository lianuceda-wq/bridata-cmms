-- Bridata CMMS - compras solo mediante operaciones transaccionales

alter table public.purchase_orders
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancellation_reason text;

revoke insert,update,delete on public.purchase_orders from authenticated;
revoke insert,update,delete on public.purchase_order_lines from authenticated;

alter table public.inventory_movements drop constraint if exists inventory_movements_related_movement_id_fkey;
alter table public.inventory_movements
  add constraint inventory_movements_related_movement_tenant_fk
  foreign key(tenant_id,related_movement_id)
  references public.inventory_movements(tenant_id,id) on delete set null;

create or replace function private.validate_purchase_order_line()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare v_status text;
begin
  select status into v_status from public.purchase_orders
  where tenant_id=new.tenant_id and id=new.purchase_order_id;
  if v_status is null then raise exception 'Purchase order not found'; end if;
  if tg_op='INSERT' and new.quantity_received<>0 then
    raise exception 'New purchase lines must start with zero received quantity';
  end if;
  if tg_op='UPDATE' and old.quantity_received is distinct from new.quantity_received
     and current_setting('bridata.inventory_receipt',true) is distinct from '1' then
    raise exception 'quantity_received can only change through receipt operation';
  end if;
  if v_status in('received','cancelled') then
    raise exception 'Purchase order lines are immutable after receipt/cancellation';
  end if;
  return new;
end;
$$;
revoke all on function private.validate_purchase_order_line() from public,anon,authenticated;
drop trigger if exists protect_purchase_received_quantity on public.purchase_order_lines;
create trigger validate_purchase_order_line
before insert or update on public.purchase_order_lines
for each row execute function private.validate_purchase_order_line();

create or replace function public.cancel_purchase_order(p_tenant_id uuid,p_purchase_order_id uuid,p_reason text)
returns void
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare v_status text;
begin
  if not public.can_manage_inventory(p_tenant_id) then raise exception 'Insufficient purchase permissions'; end if;
  if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'Cancellation reason is required'; end if;
  select status into v_status from public.purchase_orders where tenant_id=p_tenant_id and id=p_purchase_order_id for update;
  if v_status is null then raise exception 'Purchase order not found'; end if;
  if v_status='received' then raise exception 'A fully received purchase order cannot be cancelled'; end if;
  if v_status='cancelled' then return; end if;
  update public.purchase_orders set status='cancelled',cancelled_at=now(),cancellation_reason=trim(p_reason),updated_at=now()
  where tenant_id=p_tenant_id and id=p_purchase_order_id;
end;
$$;
revoke all on function public.cancel_purchase_order(uuid,uuid,text) from public,anon;
grant execute on function public.cancel_purchase_order(uuid,uuid,text) to authenticated;
