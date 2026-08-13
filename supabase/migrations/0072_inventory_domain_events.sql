create or replace function private.publish_inventory_movement_domain_event()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  perform private.publish_domain_event(
    new.tenant_id,
    'inventory.movement',
    'inventory_movement',
    new.id,
    jsonb_build_object('id',new.id,'warehouse_id',new.warehouse_id,'material_id',new.material_id,'movement_type',new.movement_type,'quantity',new.quantity,'unit_cost',new.unit_cost,'currency',new.currency,'work_order_id',new.work_order_id,'occurred_at',new.occurred_at),
    null
  );
  return new;
end $$;

revoke all on function private.publish_inventory_movement_domain_event() from public,anon,authenticated;
drop trigger if exists publish_inventory_movement_domain_event on public.inventory_movements;
create trigger publish_inventory_movement_domain_event after insert on public.inventory_movements for each row execute function private.publish_inventory_movement_domain_event();