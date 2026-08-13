'use server'

import { revalidatePath } from 'next/cache'
import { requireTenant } from '@/lib/tenant'

const clean=(v:FormDataEntryValue|null)=>String(v??'').trim()
const nullable=(v:FormDataEntryValue|null)=>clean(v)||null
const number=(v:FormDataEntryValue|null)=>{const raw=clean(v);if(!raw)return null;const n=Number(raw.replace(',','.'));if(!Number.isFinite(n))throw new Error(`Número inválido: ${raw}`);return n}
const inventoryRoles=new Set(['owner','admin','planner','supervisor','warehouse'])

function refresh(){revalidatePath('/dashboard/inventory');revalidatePath('/dashboard/work-orders');revalidatePath('/dashboard')}

export async function createMaterialCategory(formData:FormData){
 const {supabase,tenant,role}=await requireTenant();if(!inventoryRoles.has(role))throw new Error('Sin permisos de inventario.')
 const code=clean(formData.get('code')),name=clean(formData.get('name'));if(!code||!name)throw new Error('Código y nombre son obligatorios.')
 const {error}=await supabase.from('material_categories').insert({tenant_id:tenant.id,code:code.toUpperCase(),name,parent_id:nullable(formData.get('parent_id'))});if(error)throw new Error(error.message);refresh()
}

export async function createMaterial(formData:FormData){
 const {supabase,tenant,role}=await requireTenant();if(!inventoryRoles.has(role))throw new Error('Sin permisos de inventario.')
 const code=clean(formData.get('code')),name=clean(formData.get('name')),unitId=clean(formData.get('unit_id'));if(!code||!name||!unitId)throw new Error('Código, nombre y unidad son obligatorios.')
 const {error}=await supabase.from('materials').insert({tenant_id:tenant.id,code:code.toUpperCase(),name,description:nullable(formData.get('description')),category_id:nullable(formData.get('category_id')),unit_id:unitId,manufacturer:nullable(formData.get('manufacturer')),manufacturer_part_number:nullable(formData.get('manufacturer_part_number')),standard_unit_cost:number(formData.get('standard_unit_cost')),cost_currency:(clean(formData.get('cost_currency'))||'PEN').toUpperCase()});if(error)throw new Error(error.message);refresh()
}

export async function createWarehouse(formData:FormData){
 const {supabase,tenant,role}=await requireTenant();if(!inventoryRoles.has(role))throw new Error('Sin permisos de inventario.')
 const code=clean(formData.get('code')),name=clean(formData.get('name'));if(!code||!name)throw new Error('Código y nombre son obligatorios.')
 const {error}=await supabase.from('warehouses').insert({tenant_id:tenant.id,code:code.toUpperCase(),name,site_id:nullable(formData.get('site_id')),location_id:nullable(formData.get('location_id'))});if(error)throw new Error(error.message);refresh()
}

export async function saveInventoryPolicy(formData:FormData){
 const {supabase,tenant,role}=await requireTenant();if(!inventoryRoles.has(role))throw new Error('Sin permisos de inventario.')
 const warehouseId=clean(formData.get('warehouse_id')),materialId=clean(formData.get('material_id'));if(!warehouseId||!materialId)throw new Error('Almacén y material son obligatorios.')
 const {error}=await supabase.from('inventory_policies').upsert({tenant_id:tenant.id,warehouse_id:warehouseId,material_id:materialId,minimum_stock:number(formData.get('minimum_stock'))??0,maximum_stock:number(formData.get('maximum_stock')),reorder_point:number(formData.get('reorder_point')),reorder_quantity:number(formData.get('reorder_quantity'))},{onConflict:'tenant_id,warehouse_id,material_id'});if(error)throw new Error(error.message);refresh()
}

export async function postMovement(formData:FormData){
 const {supabase,tenant}=await requireTenant();const warehouseId=clean(formData.get('warehouse_id')),materialId=clean(formData.get('material_id')),movementType=clean(formData.get('movement_type'));const quantity=number(formData.get('quantity'));if(!warehouseId||!materialId||!movementType||!quantity)throw new Error('Completa almacén, material, tipo y cantidad.')
 const {error}=await supabase.rpc('post_inventory_movement',{p_tenant_id:tenant.id,p_warehouse_id:warehouseId,p_material_id:materialId,p_movement_type:movementType,p_quantity:quantity,p_unit_cost:number(formData.get('unit_cost')),p_currency:(clean(formData.get('currency'))||'PEN').toUpperCase(),p_reason:nullable(formData.get('reason')),p_occurred_at:new Date().toISOString()});if(error)throw new Error(error.message);refresh()
}

export async function transferInventory(formData:FormData){
 const {supabase,tenant}=await requireTenant();const from=clean(formData.get('from_warehouse_id')),to=clean(formData.get('to_warehouse_id')),materialId=clean(formData.get('material_id'));const quantity=number(formData.get('quantity'));if(!from||!to||!materialId||!quantity)throw new Error('Completa origen, destino, material y cantidad.')
 const {error}=await supabase.rpc('transfer_inventory',{p_tenant_id:tenant.id,p_from_warehouse_id:from,p_to_warehouse_id:to,p_material_id:materialId,p_quantity:quantity,p_reason:nullable(formData.get('reason'))});if(error)throw new Error(error.message);refresh()
}

export async function createSupplier(formData:FormData){
 const {supabase,tenant,role}=await requireTenant();if(!inventoryRoles.has(role))throw new Error('Sin permisos de compras.')
 const code=clean(formData.get('code')),name=clean(formData.get('name'));if(!code||!name)throw new Error('Código y nombre son obligatorios.')
 const {error}=await supabase.from('suppliers').insert({tenant_id:tenant.id,code:code.toUpperCase(),name,tax_id:nullable(formData.get('tax_id')),email:nullable(formData.get('email')),phone:nullable(formData.get('phone'))});if(error)throw new Error(error.message);refresh()
}

export async function createPurchaseOrderOneLine(formData:FormData){
 const {supabase,tenant}=await requireTenant();const materialId=clean(formData.get('material_id')),warehouseId=clean(formData.get('warehouse_id'));const quantity=number(formData.get('quantity')),unitPrice=number(formData.get('unit_price'));if(!materialId||!quantity||unitPrice===null)throw new Error('Material, cantidad y precio son obligatorios.')
 const {error}=await supabase.rpc('create_purchase_order',{p_tenant_id:tenant.id,p_supplier_id:nullable(formData.get('supplier_id')),p_currency:(clean(formData.get('currency'))||'PEN').toUpperCase(),p_expected_at:nullable(formData.get('expected_at'))?new Date(clean(formData.get('expected_at'))).toISOString():null,p_notes:nullable(formData.get('notes')),p_lines:[{material_id:materialId,warehouse_id:warehouseId,quantity,unit_price:unitPrice}]});if(error)throw new Error(error.message);refresh()
}

export async function receivePurchaseLine(formData:FormData){
 const {supabase,tenant}=await requireTenant();const lineId=clean(formData.get('line_id')),warehouseId=clean(formData.get('warehouse_id'));const quantity=number(formData.get('quantity'));if(!lineId||!warehouseId||!quantity)throw new Error('Línea, almacén y cantidad son obligatorios.')
 const {error}=await supabase.rpc('receive_purchase_order_line',{p_tenant_id:tenant.id,p_line_id:lineId,p_warehouse_id:warehouseId,p_quantity:quantity});if(error)throw new Error(error.message);refresh()
}

export async function reserveWorkOrderMaterial(formData:FormData){
 const {supabase,tenant}=await requireTenant();const workOrderId=clean(formData.get('work_order_id')),warehouseId=clean(formData.get('warehouse_id')),materialId=clean(formData.get('material_id'));const quantity=number(formData.get('quantity'));if(!workOrderId||!warehouseId||!materialId||!quantity)throw new Error('Datos de reserva incompletos.')
 const {error}=await supabase.rpc('reserve_work_order_material',{p_tenant_id:tenant.id,p_work_order_id:workOrderId,p_warehouse_id:warehouseId,p_material_id:materialId,p_quantity:quantity});if(error)throw new Error(error.message);revalidatePath(`/dashboard/work-orders/${workOrderId}`);refresh()
}

export async function consumeWorkOrderMaterial(formData:FormData){
 const {supabase,tenant}=await requireTenant();const workOrderId=clean(formData.get('work_order_id')),warehouseId=clean(formData.get('warehouse_id')),materialId=clean(formData.get('material_id'));const quantity=number(formData.get('quantity'));if(!workOrderId||!warehouseId||!materialId||!quantity)throw new Error('Datos de consumo incompletos.')
 const {error}=await supabase.rpc('consume_work_order_material',{p_tenant_id:tenant.id,p_work_order_id:workOrderId,p_warehouse_id:warehouseId,p_material_id:materialId,p_quantity:quantity,p_reservation_id:nullable(formData.get('reservation_id')),p_notes:nullable(formData.get('notes'))});if(error)throw new Error(error.message);revalidatePath(`/dashboard/work-orders/${workOrderId}`);refresh()
}

export async function releaseReservation(formData:FormData){
 const {supabase,tenant}=await requireTenant();const workOrderId=clean(formData.get('work_order_id')),id=clean(formData.get('reservation_id'));if(!id)throw new Error('Reserva inválida.');const {error}=await supabase.rpc('release_inventory_reservation',{p_tenant_id:tenant.id,p_reservation_id:id});if(error)throw new Error(error.message);if(workOrderId)revalidatePath(`/dashboard/work-orders/${workOrderId}`);refresh()
}

export async function addManualWorkOrderCost(formData:FormData){
 const {supabase,tenant}=await requireTenant();const workOrderId=clean(formData.get('work_order_id'));const amount=number(formData.get('amount'));if(!workOrderId||amount===null)throw new Error('OT y monto son obligatorios.');const {error}=await supabase.rpc('add_manual_cost',{p_tenant_id:tenant.id,p_work_order_id:workOrderId,p_category:clean(formData.get('category')),p_amount:amount,p_currency:(clean(formData.get('currency'))||'PEN').toUpperCase(),p_description:nullable(formData.get('description')),p_occurred_at:new Date().toISOString()});if(error)throw new Error(error.message);revalidatePath(`/dashboard/work-orders/${workOrderId}`);refresh()
}
