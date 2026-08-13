-- Bridata CMMS - estado de inventario solo para combinaciones reales/configuradas

create or replace view public.inventory_status
with(security_invoker=true)
as
with keys as (
  select tenant_id,warehouse_id,material_id from public.inventory_balances
  union
  select tenant_id,warehouse_id,material_id from public.inventory_policies
  union
  select tenant_id,warehouse_id,material_id from public.inventory_reservations where status='active'
), reserved as (
  select tenant_id,warehouse_id,material_id,
         sum(quantity_reserved-quantity_consumed) reserved_quantity
  from public.inventory_reservations
  where status='active'
  group by tenant_id,warehouse_id,material_id
)
select
  k.tenant_id,
  w.id warehouse_id,
  w.code warehouse_code,
  w.name warehouse_name,
  m.id material_id,
  m.code material_code,
  m.name material_name,
  u.symbol unit_symbol,
  coalesce(b.quantity_on_hand,0) quantity_on_hand,
  coalesce(r.reserved_quantity,0) reserved_quantity,
  coalesce(b.quantity_on_hand,0)-coalesce(r.reserved_quantity,0) available_quantity,
  coalesce(p.minimum_stock,0) minimum_stock,
  p.maximum_stock,
  p.reorder_point,
  p.reorder_quantity,
  case
    when coalesce(b.quantity_on_hand,0)-coalesce(r.reserved_quantity,0)<coalesce(p.minimum_stock,0) then 'below_minimum'
    when p.reorder_point is not null
      and coalesce(b.quantity_on_hand,0)-coalesce(r.reserved_quantity,0)<=p.reorder_point then 'reorder'
    else 'ok'
  end stock_status,
  m.standard_unit_cost,
  m.cost_currency,
  case when m.standard_unit_cost is null then null
       else round((coalesce(b.quantity_on_hand,0)*m.standard_unit_cost)::numeric,4)
  end estimated_stock_value,
  b.last_movement_at
from keys k
join public.materials m on m.tenant_id=k.tenant_id and m.id=k.material_id and m.is_active=true and m.is_stock_item=true
join public.warehouses w on w.tenant_id=k.tenant_id and w.id=k.warehouse_id and w.is_active=true
join public.inventory_units u on u.id=m.unit_id
left join public.inventory_balances b on b.tenant_id=k.tenant_id and b.material_id=k.material_id and b.warehouse_id=k.warehouse_id
left join public.inventory_policies p on p.tenant_id=k.tenant_id and p.material_id=k.material_id and p.warehouse_id=k.warehouse_id
left join reserved r on r.tenant_id=k.tenant_id and r.material_id=k.material_id and r.warehouse_id=k.warehouse_id;
