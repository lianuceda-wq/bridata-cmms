-- Bridata CMMS - Inventory, Materials & Cost Engine

alter table public.tenant_members drop constraint if exists tenant_members_role_check;
alter table public.tenant_members add constraint tenant_members_role_check
check (role in ('owner','admin','planner','supervisor','technician','warehouse','viewer'));

create table public.inventory_units (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  symbol text not null,
  decimals smallint not null default 2 check(decimals between 0 and 6),
  is_active boolean not null default true
);
insert into public.inventory_units(code,name,symbol,decimals) values
('unit','Unidad','und',0),('meter','Metro','m',2),('kg','Kilogramo','kg',3),('liter','Litro','L',2),('roll','Rollo','rollo',0),('box','Caja','caja',0),('pack','Paquete','paq',0)
on conflict(code) do nothing;

create table public.material_categories (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null,
  name text not null,
  parent_id uuid,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,code),
  foreign key(tenant_id,parent_id) references public.material_categories(tenant_id,id) on delete set null
);
create unique index uq_material_categories_tenant_id on public.material_categories(tenant_id,id);

create table public.materials (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null,
  name text not null,
  description text,
  category_id uuid,
  unit_id uuid not null references public.inventory_units(id),
  manufacturer text,
  manufacturer_part_number text,
  standard_unit_cost numeric check(standard_unit_cost is null or standard_unit_cost>=0),
  cost_currency text not null default 'PEN' check(length(cost_currency)=3),
  is_stock_item boolean not null default true,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,code),
  foreign key(tenant_id,category_id) references public.material_categories(tenant_id,id) on delete set null
);
create unique index uq_materials_tenant_id on public.materials(tenant_id,id);
create index idx_materials_category on public.materials(tenant_id,category_id);
create index idx_materials_unit on public.materials(unit_id);

create table public.warehouses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  site_id uuid,
  location_id uuid,
  code text not null,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,code),
  foreign key(tenant_id,site_id) references public.sites(tenant_id,id) on delete set null,
  foreign key(tenant_id,location_id) references public.locations(tenant_id,id) on delete set null
);
create unique index uq_warehouses_tenant_id on public.warehouses(tenant_id,id);
create index idx_warehouses_site on public.warehouses(tenant_id,site_id);
create index idx_warehouses_location on public.warehouses(tenant_id,location_id);

create table public.inventory_policies (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  warehouse_id uuid not null,
  material_id uuid not null,
  minimum_stock numeric not null default 0 check(minimum_stock>=0),
  maximum_stock numeric check(maximum_stock is null or maximum_stock>=minimum_stock),
  reorder_point numeric check(reorder_point is null or reorder_point>=0),
  reorder_quantity numeric check(reorder_quantity is null or reorder_quantity>0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,warehouse_id,material_id),
  foreign key(tenant_id,warehouse_id) references public.warehouses(tenant_id,id) on delete cascade,
  foreign key(tenant_id,material_id) references public.materials(tenant_id,id) on delete cascade
);
create unique index uq_inventory_policies_tenant_id on public.inventory_policies(tenant_id,id);
create index idx_inventory_policies_material on public.inventory_policies(tenant_id,material_id);

create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null,
  name text not null,
  tax_id text,
  email text,
  phone text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,code)
);
create unique index uq_suppliers_tenant_id on public.suppliers(tenant_id,id);

create table public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text,
  supplier_id uuid,
  status text not null default 'draft' check(status in ('draft','approved','ordered','partial','received','cancelled')),
  currency text not null default 'PEN' check(length(currency)=3),
  ordered_at timestamptz,
  expected_at timestamptz,
  external_reference text,
  notes text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  approved_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,code),
  foreign key(tenant_id,supplier_id) references public.suppliers(tenant_id,id) on delete set null
);
create unique index uq_purchase_orders_tenant_id on public.purchase_orders(tenant_id,id);
create index idx_purchase_orders_supplier on public.purchase_orders(tenant_id,supplier_id);
create index idx_purchase_orders_created_by on public.purchase_orders(created_by);
create index idx_purchase_orders_approved_by on public.purchase_orders(approved_by);

create table public.purchase_order_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  purchase_order_id uuid not null,
  material_id uuid not null,
  warehouse_id uuid,
  quantity_ordered numeric not null check(quantity_ordered>0),
  quantity_received numeric not null default 0 check(quantity_received>=0 and quantity_received<=quantity_ordered),
  unit_price numeric not null check(unit_price>=0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key(tenant_id,purchase_order_id) references public.purchase_orders(tenant_id,id) on delete cascade,
  foreign key(tenant_id,material_id) references public.materials(tenant_id,id) on delete restrict,
  foreign key(tenant_id,warehouse_id) references public.warehouses(tenant_id,id) on delete set null
);
create unique index uq_purchase_order_lines_tenant_id on public.purchase_order_lines(tenant_id,id);
create index idx_po_lines_order on public.purchase_order_lines(tenant_id,purchase_order_id);
create index idx_po_lines_material on public.purchase_order_lines(tenant_id,material_id);
create index idx_po_lines_warehouse on public.purchase_order_lines(tenant_id,warehouse_id);

create table public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text,
  warehouse_id uuid not null,
  material_id uuid not null,
  movement_type text not null check(movement_type in ('receipt','issue','return','adjustment_in','adjustment_out','transfer_in','transfer_out')),
  quantity_delta numeric not null check(quantity_delta<>0),
  unit_cost numeric check(unit_cost is null or unit_cost>=0),
  currency text not null default 'PEN' check(length(currency)=3),
  work_order_id uuid,
  purchase_order_line_id uuid,
  related_movement_id uuid references public.inventory_movements(id) on delete set null,
  source text not null default 'manual' check(source in ('manual','work_order','purchase','sap','import','api')),
  reason text,
  occurred_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  unique(tenant_id,code),
  foreign key(tenant_id,warehouse_id) references public.warehouses(tenant_id,id) on delete restrict,
  foreign key(tenant_id,material_id) references public.materials(tenant_id,id) on delete restrict,
  foreign key(tenant_id,work_order_id) references public.work_orders(tenant_id,id) on delete set null,
  foreign key(tenant_id,purchase_order_line_id) references public.purchase_order_lines(tenant_id,id) on delete set null,
  constraint inventory_movement_sign check(
    (movement_type in ('receipt','return','adjustment_in','transfer_in') and quantity_delta>0)
    or (movement_type in ('issue','adjustment_out','transfer_out') and quantity_delta<0)
  )
);
create unique index uq_inventory_movements_tenant_id on public.inventory_movements(tenant_id,id);
create index idx_inventory_movements_stock on public.inventory_movements(tenant_id,warehouse_id,material_id,occurred_at,id);
create index idx_inventory_movements_material on public.inventory_movements(tenant_id,material_id,occurred_at desc);
create index idx_inventory_movements_work_order on public.inventory_movements(tenant_id,work_order_id);
create index idx_inventory_movements_po_line on public.inventory_movements(tenant_id,purchase_order_line_id);
create index idx_inventory_movements_related on public.inventory_movements(related_movement_id);
create index idx_inventory_movements_created_by on public.inventory_movements(created_by);

create table public.inventory_reservations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  work_order_id uuid not null,
  warehouse_id uuid not null,
  material_id uuid not null,
  quantity_reserved numeric not null check(quantity_reserved>0),
  quantity_consumed numeric not null default 0 check(quantity_consumed>=0 and quantity_consumed<=quantity_reserved),
  status text not null default 'active' check(status in ('active','fulfilled','released','cancelled')),
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key(tenant_id,work_order_id) references public.work_orders(tenant_id,id) on delete cascade,
  foreign key(tenant_id,warehouse_id) references public.warehouses(tenant_id,id) on delete restrict,
  foreign key(tenant_id,material_id) references public.materials(tenant_id,id) on delete restrict
);
create unique index uq_inventory_reservations_tenant_id on public.inventory_reservations(tenant_id,id);
create index idx_inventory_reservations_lookup on public.inventory_reservations(tenant_id,warehouse_id,material_id,status);
create index idx_inventory_reservations_work_order on public.inventory_reservations(tenant_id,work_order_id);
create index idx_inventory_reservations_created_by on public.inventory_reservations(created_by);

create table public.cost_entries (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  work_order_id uuid,
  category text not null check(category in ('material','labor','service','contractor','purchase','other')),
  source_entity text,
  source_id uuid,
  amount numeric,
  currency text not null default 'PEN' check(length(currency)=3),
  valuation_status text not null default 'actual' check(valuation_status in ('actual','estimated','missing')),
  occurred_at timestamptz not null default now(),
  description text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  foreign key(tenant_id,work_order_id) references public.work_orders(tenant_id,id) on delete set null,
  constraint cost_amount_status check((valuation_status='missing' and amount is null) or (valuation_status<>'missing' and amount is not null and amount>=0))
);
create unique index uq_cost_entries_source on public.cost_entries(tenant_id,source_entity,source_id,category) where source_id is not null;
create index idx_cost_entries_work_order on public.cost_entries(tenant_id,work_order_id,occurred_at);
create index idx_cost_entries_created_by on public.cost_entries(created_by);

create table public.maintenance_budgets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null,
  name text not null,
  period_start date not null,
  period_end date not null,
  currency text not null default 'PEN' check(length(currency)=3),
  status text not null default 'draft' check(status in ('draft','approved','closed','cancelled')),
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,code),
  check(period_end>=period_start)
);
create unique index uq_maintenance_budgets_tenant_id on public.maintenance_budgets(tenant_id,id);
create index idx_maintenance_budgets_created_by on public.maintenance_budgets(created_by);

create table public.maintenance_budget_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  budget_id uuid not null,
  site_id uuid,
  asset_id uuid,
  maintenance_type text,
  category text not null check(category in ('material','labor','service','contractor','other','total')),
  amount numeric not null check(amount>=0),
  created_at timestamptz not null default now(),
  foreign key(tenant_id,budget_id) references public.maintenance_budgets(tenant_id,id) on delete cascade,
  foreign key(tenant_id,site_id) references public.sites(tenant_id,id) on delete set null,
  foreign key(tenant_id,asset_id) references public.assets(tenant_id,id) on delete set null
);
create index idx_budget_lines_budget on public.maintenance_budget_lines(tenant_id,budget_id);
create index idx_budget_lines_site on public.maintenance_budget_lines(tenant_id,site_id);
create index idx_budget_lines_asset on public.maintenance_budget_lines(tenant_id,asset_id);

create or replace function public.can_manage_inventory(p_tenant_id uuid)
returns boolean language sql stable security invoker set search_path=public,pg_temp as $$
  select coalesce(public.tenant_role(p_tenant_id) in ('owner','admin','planner','supervisor','warehouse'),false)
$$;
revoke all on function public.can_manage_inventory(uuid) from public,anon;
grant execute on function public.can_manage_inventory(uuid) to authenticated;

create schema if not exists private; revoke all on schema private from public,anon,authenticated;
create or replace function private.next_inventory_code(p_tenant_id uuid)
returns text language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_year text:=to_char(current_date,'YYYY'); v_value bigint;
begin
 insert into public.tenant_sequences(tenant_id,sequence_key,value) values(p_tenant_id,'inventory_'||v_year,1)
 on conflict(tenant_id,sequence_key) do update set value=public.tenant_sequences.value+1,updated_at=now() returning value into v_value;
 return 'MOV-'||v_year||'-'||lpad(v_value::text,7,'0');
end $$;
revoke all on function private.next_inventory_code(uuid) from public,anon,authenticated;

create or replace function private.next_purchase_order_code(p_tenant_id uuid)
returns text language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_year text:=to_char(current_date,'YYYY'); v_value bigint;
begin
 insert into public.tenant_sequences(tenant_id,sequence_key,value) values(p_tenant_id,'purchase_order_'||v_year,1)
 on conflict(tenant_id,sequence_key) do update set value=public.tenant_sequences.value+1,updated_at=now() returning value into v_value;
 return 'OC-'||v_year||'-'||lpad(v_value::text,6,'0');
end $$;
revoke all on function private.next_purchase_order_code(uuid) from public,anon,authenticated;

create or replace function private.assign_purchase_order_code()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$ begin if new.code is null or btrim(new.code)='' then new.code:=private.next_purchase_order_code(new.tenant_id); end if; return new; end $$;
revoke all on function private.assign_purchase_order_code() from public,anon,authenticated;
create trigger assign_purchase_order_code before insert on public.purchase_orders for each row execute function private.assign_purchase_order_code();

create or replace function private.current_stock(p_tenant_id uuid,p_warehouse_id uuid,p_material_id uuid)
returns numeric language sql stable security definer set search_path=public,private,pg_temp as $$
 select coalesce(sum(quantity_delta),0) from public.inventory_movements where tenant_id=p_tenant_id and warehouse_id=p_warehouse_id and material_id=p_material_id
$$;
revoke all on function private.current_stock(uuid,uuid,uuid) from public,anon,authenticated;

create or replace function private.latest_material_unit_cost(p_tenant_id uuid,p_warehouse_id uuid,p_material_id uuid)
returns table(unit_cost numeric,currency text,valuation_status text)
language sql stable security definer set search_path=public,private,pg_temp as $$
 select coalesce(mv.unit_cost,m.standard_unit_cost),coalesce(mv.currency,m.cost_currency),
        case when mv.unit_cost is not null then 'actual' when m.standard_unit_cost is not null then 'estimated' else 'missing' end
 from public.materials m
 left join lateral (
   select im.unit_cost,im.currency from public.inventory_movements im
   where im.tenant_id=p_tenant_id and im.warehouse_id=p_warehouse_id and im.material_id=p_material_id and im.quantity_delta>0 and im.unit_cost is not null
   order by im.occurred_at desc,im.created_at desc limit 1
 ) mv on true
 where m.tenant_id=p_tenant_id and m.id=p_material_id
$$;
revoke all on function private.latest_material_unit_cost(uuid,uuid,uuid) from public,anon,authenticated;

create or replace function private.post_inventory_movement_core(
 p_tenant_id uuid,p_warehouse_id uuid,p_material_id uuid,p_movement_type text,p_quantity numeric,p_unit_cost numeric,p_currency text,
 p_work_order_id uuid,p_purchase_order_line_id uuid,p_related_movement_id uuid,p_source text,p_reason text,p_occurred_at timestamptz,p_created_by uuid
)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid; v_delta numeric; v_stock numeric; v_code text; v_cost numeric:=p_unit_cost; v_currency text:=coalesce(p_currency,'PEN'); v_status text;
begin
 if p_quantity is null or p_quantity<=0 then raise exception 'Quantity must be greater than zero'; end if;
 if not exists(select 1 from public.warehouses where tenant_id=p_tenant_id and id=p_warehouse_id and is_active=true) then raise exception 'Warehouse not found or inactive'; end if;
 if not exists(select 1 from public.materials where tenant_id=p_tenant_id and id=p_material_id and is_active=true and is_stock_item=true) then raise exception 'Material not found, inactive or not stockable'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||p_warehouse_id::text||':'||p_material_id::text,0));
 v_delta:=case when p_movement_type in('receipt','return','adjustment_in','transfer_in') then p_quantity else -p_quantity end;
 v_stock:=private.current_stock(p_tenant_id,p_warehouse_id,p_material_id);
 if v_delta<0 and v_stock+v_delta<0 then raise exception 'Insufficient stock. Available: %, requested: %',v_stock,p_quantity; end if;
 if v_cost is null and p_movement_type in('issue','return','adjustment_out','transfer_out') then
   select x.unit_cost,x.currency,x.valuation_status into v_cost,v_currency,v_status from private.latest_material_unit_cost(p_tenant_id,p_warehouse_id,p_material_id) x;
 end if;
 v_code:=private.next_inventory_code(p_tenant_id);
 insert into public.inventory_movements(tenant_id,code,warehouse_id,material_id,movement_type,quantity_delta,unit_cost,currency,work_order_id,purchase_order_line_id,related_movement_id,source,reason,occurred_at,created_by)
 values(p_tenant_id,v_code,p_warehouse_id,p_material_id,p_movement_type,v_delta,v_cost,v_currency,p_work_order_id,p_purchase_order_line_id,p_related_movement_id,coalesce(p_source,'manual'),nullif(trim(p_reason),''),coalesce(p_occurred_at,now()),p_created_by)
 returning id into v_id;
 return v_id;
end $$;
revoke all on function private.post_inventory_movement_core(uuid,uuid,uuid,text,numeric,numeric,text,uuid,uuid,uuid,text,text,timestamptz,uuid) from public,anon,authenticated;

create or replace function public.post_inventory_movement(
 p_tenant_id uuid,p_warehouse_id uuid,p_material_id uuid,p_movement_type text,p_quantity numeric,p_unit_cost numeric default null,p_currency text default 'PEN',p_reason text default null,p_occurred_at timestamptz default now()
)
returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
begin
 if not public.can_manage_inventory(p_tenant_id) then raise exception 'Insufficient inventory permissions'; end if;
 if p_movement_type not in('receipt','return','adjustment_in','adjustment_out','issue') then raise exception 'Use the dedicated transfer/consumption operation for this movement type'; end if;
 return private.post_inventory_movement_core(p_tenant_id,p_warehouse_id,p_material_id,p_movement_type,p_quantity,p_unit_cost,p_currency,null,null,null,'manual',p_reason,p_occurred_at,auth.uid());
end $$;
revoke all on function public.post_inventory_movement(uuid,uuid,uuid,text,numeric,numeric,text,text,timestamptz) from public,anon;
grant execute on function public.post_inventory_movement(uuid,uuid,uuid,text,numeric,numeric,text,text,timestamptz) to authenticated;

create or replace function public.transfer_inventory(
 p_tenant_id uuid,p_from_warehouse_id uuid,p_to_warehouse_id uuid,p_material_id uuid,p_quantity numeric,p_reason text default null
)
returns table(out_movement_id uuid,in_movement_id uuid)
language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_out uuid;v_in uuid;v_cost numeric;v_currency text;v_status text;
begin
 if not public.can_manage_inventory(p_tenant_id) then raise exception 'Insufficient inventory permissions'; end if;
 if p_from_warehouse_id=p_to_warehouse_id then raise exception 'Source and destination warehouses must differ'; end if;
 select x.unit_cost,x.currency,x.valuation_status into v_cost,v_currency,v_status from private.latest_material_unit_cost(p_tenant_id,p_from_warehouse_id,p_material_id)x;
 v_out:=private.post_inventory_movement_core(p_tenant_id,p_from_warehouse_id,p_material_id,'transfer_out',p_quantity,v_cost,v_currency,null,null,null,'manual',p_reason,now(),auth.uid());
 v_in:=private.post_inventory_movement_core(p_tenant_id,p_to_warehouse_id,p_material_id,'transfer_in',p_quantity,v_cost,v_currency,null,null,v_out,'manual',p_reason,now(),auth.uid());
 update public.inventory_movements set related_movement_id=v_in where id=v_out;
 return query select v_out,v_in;
end $$;
revoke all on function public.transfer_inventory(uuid,uuid,uuid,uuid,numeric,text) from public,anon;
grant execute on function public.transfer_inventory(uuid,uuid,uuid,uuid,numeric,text) to authenticated;

create or replace function public.reserve_work_order_material(
 p_tenant_id uuid,p_work_order_id uuid,p_warehouse_id uuid,p_material_id uuid,p_quantity numeric
)
returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_id uuid;v_stock numeric;v_reserved numeric;v_role text;
begin
 v_role:=public.tenant_role(p_tenant_id);
 if v_role not in('owner','admin','planner','supervisor','warehouse') then raise exception 'Insufficient reservation permissions'; end if;
 if not exists(select 1 from public.work_orders where tenant_id=p_tenant_id and id=p_work_order_id and status not in('closed','cancelled')) then raise exception 'Work order cannot receive reservations'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||p_warehouse_id::text||':'||p_material_id::text,0));
 v_stock:=private.current_stock(p_tenant_id,p_warehouse_id,p_material_id);
 select coalesce(sum(quantity_reserved-quantity_consumed),0) into v_reserved from public.inventory_reservations where tenant_id=p_tenant_id and warehouse_id=p_warehouse_id and material_id=p_material_id and status='active';
 if v_stock-v_reserved<p_quantity then raise exception 'Insufficient available stock after reservations. Available: %',v_stock-v_reserved; end if;
 insert into public.inventory_reservations(tenant_id,work_order_id,warehouse_id,material_id,quantity_reserved,created_by)
 values(p_tenant_id,p_work_order_id,p_warehouse_id,p_material_id,p_quantity,auth.uid()) returning id into v_id;
 return v_id;
end $$;
revoke all on function public.reserve_work_order_material(uuid,uuid,uuid,uuid,numeric) from public,anon;
grant execute on function public.reserve_work_order_material(uuid,uuid,uuid,uuid,numeric) to authenticated;

create or replace function public.consume_work_order_material(
 p_tenant_id uuid,p_work_order_id uuid,p_warehouse_id uuid,p_material_id uuid,p_quantity numeric,p_reservation_id uuid default null,p_notes text default null
)
returns table(movement_id uuid,cost_entry_id uuid,cost_amount numeric,valuation_status text)
language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_order public.work_orders;v_role text;v_move uuid;v_cost numeric;v_currency text;v_val_status text;v_cost_id uuid;v_unit_cost numeric;
begin
 v_role:=public.tenant_role(p_tenant_id);
 select * into v_order from public.work_orders where tenant_id=p_tenant_id and id=p_work_order_id;
 if not found or v_order.status in('closed','cancelled') then raise exception 'Work order not found or immutable'; end if;
 if v_role='technician' then if v_order.assigned_to is distinct from auth.uid() then raise exception 'Work order is not assigned to technician'; end if;
 elsif v_role not in('owner','admin','planner','supervisor','warehouse') then raise exception 'Insufficient consumption permissions'; end if;

 if p_reservation_id is not null then
   if not exists(select 1 from public.inventory_reservations r where r.tenant_id=p_tenant_id and r.id=p_reservation_id and r.work_order_id=p_work_order_id and r.warehouse_id=p_warehouse_id and r.material_id=p_material_id and r.status='active' and r.quantity_reserved-r.quantity_consumed>=p_quantity) then raise exception 'Reservation is invalid or insufficient'; end if;
 end if;
 select x.unit_cost,x.currency,x.valuation_status into v_unit_cost,v_currency,v_val_status from private.latest_material_unit_cost(p_tenant_id,p_warehouse_id,p_material_id)x;
 v_move:=private.post_inventory_movement_core(p_tenant_id,p_warehouse_id,p_material_id,'issue',p_quantity,v_unit_cost,v_currency,p_work_order_id,null,null,'work_order',p_notes,now(),auth.uid());
 if p_reservation_id is not null then
   update public.inventory_reservations set quantity_consumed=quantity_consumed+p_quantity,
     status=case when quantity_consumed+p_quantity>=quantity_reserved then 'fulfilled' else status end,updated_at=now()
   where id=p_reservation_id;
 end if;
 if v_unit_cost is null then
   insert into public.cost_entries(tenant_id,work_order_id,category,source_entity,source_id,amount,currency,valuation_status,description,created_by)
   values(p_tenant_id,p_work_order_id,'material','inventory_movement',v_move,null,coalesce(v_currency,'PEN'),'missing',p_notes,auth.uid()) returning id into v_cost_id;
   v_cost:=null;
 else
   v_cost:=round(v_unit_cost*p_quantity,4);
   insert into public.cost_entries(tenant_id,work_order_id,category,source_entity,source_id,amount,currency,valuation_status,description,created_by)
   values(p_tenant_id,p_work_order_id,'material','inventory_movement',v_move,v_cost,v_currency,coalesce(v_val_status,'estimated'),p_notes,auth.uid()) returning id into v_cost_id;
 end if;
 return query select v_move,v_cost_id,v_cost,coalesce(v_val_status,'missing');
end $$;
revoke all on function public.consume_work_order_material(uuid,uuid,uuid,uuid,numeric,uuid,text) from public,anon;
grant execute on function public.consume_work_order_material(uuid,uuid,uuid,uuid,numeric,uuid,text) to authenticated;

create or replace function public.add_manual_cost(
 p_tenant_id uuid,p_work_order_id uuid,p_category text,p_amount numeric,p_currency text,p_description text,p_occurred_at timestamptz default now()
)
returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_id uuid;
begin
 if public.tenant_role(p_tenant_id) not in('owner','admin','planner','supervisor','warehouse') then raise exception 'Insufficient cost permissions'; end if;
 if p_amount is null or p_amount<0 then raise exception 'Cost amount must be non-negative'; end if;
 if p_category not in('labor','service','contractor','other') then raise exception 'Manual category is not allowed'; end if;
 insert into public.cost_entries(tenant_id,work_order_id,category,source_entity,amount,currency,valuation_status,occurred_at,description,created_by)
 values(p_tenant_id,p_work_order_id,p_category,'manual',p_amount,upper(p_currency),'actual',p_occurred_at,p_description,auth.uid()) returning id into v_id;
 return v_id;
end $$;
revoke all on function public.add_manual_cost(uuid,uuid,text,numeric,text,text,timestamptz) from public,anon;
grant execute on function public.add_manual_cost(uuid,uuid,text,numeric,text,text,timestamptz) to authenticated;

-- Vistas: el saldo siempre se deriva del ledger; no existe una tabla Stock_Hist.
create or replace view public.inventory_balances with(security_invoker=true) as
select im.tenant_id,im.warehouse_id,im.material_id,sum(im.quantity_delta) quantity_on_hand,max(im.occurred_at) last_movement_at
from public.inventory_movements im group by im.tenant_id,im.warehouse_id,im.material_id;

create or replace view public.inventory_status with(security_invoker=true) as
select m.tenant_id,w.id warehouse_id,w.code warehouse_code,w.name warehouse_name,m.id material_id,m.code material_code,m.name material_name,u.symbol unit_symbol,
 coalesce(b.quantity_on_hand,0) quantity_on_hand,
 coalesce(r.reserved_quantity,0) reserved_quantity,
 coalesce(b.quantity_on_hand,0)-coalesce(r.reserved_quantity,0) available_quantity,
 coalesce(p.minimum_stock,0) minimum_stock,p.maximum_stock,p.reorder_point,p.reorder_quantity,
 case when coalesce(b.quantity_on_hand,0)-coalesce(r.reserved_quantity,0)<coalesce(p.minimum_stock,0) then 'below_minimum'
      when p.reorder_point is not null and coalesce(b.quantity_on_hand,0)-coalesce(r.reserved_quantity,0)<=p.reorder_point then 'reorder'
      else 'ok' end stock_status,
 m.standard_unit_cost,m.cost_currency,
 case when m.standard_unit_cost is null then null else round((coalesce(b.quantity_on_hand,0)*m.standard_unit_cost)::numeric,4) end estimated_stock_value,
 b.last_movement_at
from public.materials m
cross join public.warehouses w
join public.inventory_units u on u.id=m.unit_id
left join public.inventory_balances b on b.tenant_id=m.tenant_id and b.material_id=m.id and b.warehouse_id=w.id
left join public.inventory_policies p on p.tenant_id=m.tenant_id and p.material_id=m.id and p.warehouse_id=w.id
left join lateral (select sum(ir.quantity_reserved-ir.quantity_consumed) reserved_quantity from public.inventory_reservations ir where ir.tenant_id=m.tenant_id and ir.material_id=m.id and ir.warehouse_id=w.id and ir.status='active') r on true
where w.tenant_id=m.tenant_id and w.is_active=true and m.is_active=true and m.is_stock_item=true;

create or replace view public.material_consumptions with(security_invoker=true) as
select im.id,im.tenant_id,im.code movement_code,im.work_order_id,im.warehouse_id,im.material_id,abs(im.quantity_delta) quantity,im.unit_cost,im.currency,
 case when im.unit_cost is null then null else abs(im.quantity_delta)*im.unit_cost end total_cost,im.occurred_at,im.created_by
from public.inventory_movements im where im.movement_type='issue' and im.work_order_id is not null;

create or replace view public.work_order_cost_summary with(security_invoker=true) as
select ce.tenant_id,ce.work_order_id,ce.currency,
 sum(ce.amount) filter(where ce.valuation_status<>'missing') total_cost,
 sum(ce.amount) filter(where ce.category='material' and ce.valuation_status<>'missing') material_cost,
 sum(ce.amount) filter(where ce.category='labor' and ce.valuation_status<>'missing') labor_cost,
 sum(ce.amount) filter(where ce.category in('service','contractor') and ce.valuation_status<>'missing') external_cost,
 count(*) filter(where ce.valuation_status='missing') missing_valuations
from public.cost_entries ce where ce.work_order_id is not null group by ce.tenant_id,ce.work_order_id,ce.currency;

create or replace view public.purchase_order_summary with(security_invoker=true) as
select po.tenant_id,po.id purchase_order_id,po.code,po.supplier_id,po.status,po.currency,po.expected_at,
 coalesce(sum(pol.quantity_ordered*pol.unit_price),0) order_amount,
 coalesce(sum(pol.quantity_received*pol.unit_price),0) received_amount,
 coalesce(sum((pol.quantity_ordered-pol.quantity_received)*pol.unit_price),0) pending_amount
from public.purchase_orders po left join public.purchase_order_lines pol on pol.tenant_id=po.tenant_id and pol.purchase_order_id=po.id
group by po.tenant_id,po.id,po.code,po.supplier_id,po.status,po.currency,po.expected_at;

-- updated_at
create trigger material_categories_updated_at before update on public.material_categories for each row execute function public.set_updated_at();
create trigger materials_updated_at before update on public.materials for each row execute function public.set_updated_at();
create trigger warehouses_updated_at before update on public.warehouses for each row execute function public.set_updated_at();
create trigger inventory_policies_updated_at before update on public.inventory_policies for each row execute function public.set_updated_at();
create trigger suppliers_updated_at before update on public.suppliers for each row execute function public.set_updated_at();
create trigger purchase_orders_updated_at before update on public.purchase_orders for each row execute function public.set_updated_at();
create trigger purchase_order_lines_updated_at before update on public.purchase_order_lines for each row execute function public.set_updated_at();
create trigger inventory_reservations_updated_at before update on public.inventory_reservations for each row execute function public.set_updated_at();
create trigger maintenance_budgets_updated_at before update on public.maintenance_budgets for each row execute function public.set_updated_at();

-- RLS
alter table public.inventory_units enable row level security;alter table public.material_categories enable row level security;alter table public.materials enable row level security;alter table public.warehouses enable row level security;alter table public.inventory_policies enable row level security;alter table public.suppliers enable row level security;alter table public.purchase_orders enable row level security;alter table public.purchase_order_lines enable row level security;alter table public.inventory_movements enable row level security;alter table public.inventory_reservations enable row level security;alter table public.cost_entries enable row level security;alter table public.maintenance_budgets enable row level security;alter table public.maintenance_budget_lines enable row level security;
create policy inventory_units_select on public.inventory_units for select to authenticated using(true);
create policy material_categories_select on public.material_categories for select to authenticated using(public.is_tenant_member(tenant_id));create policy material_categories_write on public.material_categories for all to authenticated using(public.can_manage_inventory(tenant_id)) with check(public.can_manage_inventory(tenant_id));
create policy materials_select on public.materials for select to authenticated using(public.is_tenant_member(tenant_id));create policy materials_write on public.materials for all to authenticated using(public.can_manage_inventory(tenant_id)) with check(public.can_manage_inventory(tenant_id));
create policy warehouses_select on public.warehouses for select to authenticated using(public.is_tenant_member(tenant_id));create policy warehouses_write on public.warehouses for all to authenticated using(public.can_manage_inventory(tenant_id)) with check(public.can_manage_inventory(tenant_id));
create policy inventory_policies_select on public.inventory_policies for select to authenticated using(public.is_tenant_member(tenant_id));create policy inventory_policies_write on public.inventory_policies for all to authenticated using(public.can_manage_inventory(tenant_id)) with check(public.can_manage_inventory(tenant_id));
create policy suppliers_select on public.suppliers for select to authenticated using(public.is_tenant_member(tenant_id));create policy suppliers_write on public.suppliers for all to authenticated using(public.can_manage_inventory(tenant_id)) with check(public.can_manage_inventory(tenant_id));
create policy purchase_orders_select on public.purchase_orders for select to authenticated using(public.is_tenant_member(tenant_id));create policy purchase_orders_write on public.purchase_orders for all to authenticated using(public.can_manage_inventory(tenant_id)) with check(public.can_manage_inventory(tenant_id));
create policy purchase_order_lines_select on public.purchase_order_lines for select to authenticated using(public.is_tenant_member(tenant_id));create policy purchase_order_lines_write on public.purchase_order_lines for all to authenticated using(public.can_manage_inventory(tenant_id)) with check(public.can_manage_inventory(tenant_id));
create policy inventory_movements_select on public.inventory_movements for select to authenticated using(public.is_tenant_member(tenant_id));
create policy inventory_reservations_select on public.inventory_reservations for select to authenticated using(public.is_tenant_member(tenant_id));create policy inventory_reservations_update on public.inventory_reservations for update to authenticated using(public.can_manage_inventory(tenant_id)) with check(public.can_manage_inventory(tenant_id));
create policy cost_entries_select on public.cost_entries for select to authenticated using(public.is_tenant_member(tenant_id));
create policy budgets_select on public.maintenance_budgets for select to authenticated using(public.is_tenant_member(tenant_id));create policy budgets_write on public.maintenance_budgets for all to authenticated using(public.tenant_role(tenant_id) in('owner','admin','planner')) with check(public.tenant_role(tenant_id) in('owner','admin','planner'));
create policy budget_lines_select on public.maintenance_budget_lines for select to authenticated using(public.is_tenant_member(tenant_id));create policy budget_lines_write on public.maintenance_budget_lines for all to authenticated using(public.tenant_role(tenant_id) in('owner','admin','planner')) with check(public.tenant_role(tenant_id) in('owner','admin','planner'));

grant select on public.inventory_units,public.material_categories,public.materials,public.warehouses,public.inventory_policies,public.suppliers,public.purchase_orders,public.purchase_order_lines,public.inventory_movements,public.inventory_reservations,public.cost_entries,public.maintenance_budgets,public.maintenance_budget_lines to authenticated;
grant insert,update,delete on public.material_categories,public.materials,public.warehouses,public.inventory_policies,public.suppliers,public.purchase_orders,public.purchase_order_lines,public.maintenance_budgets,public.maintenance_budget_lines to authenticated;
grant update on public.inventory_reservations to authenticated;
grant select on public.inventory_balances,public.inventory_status,public.material_consumptions,public.work_order_cost_summary,public.purchase_order_summary to authenticated;
