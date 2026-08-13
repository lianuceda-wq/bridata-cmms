export type InventoryMovementType =
  | 'receipt'
  | 'issue'
  | 'return'
  | 'adjustment_in'
  | 'adjustment_out'
  | 'transfer_in'
  | 'transfer_out'

export type InventoryStockStatus = 'ok' | 'reorder' | 'below_minimum'
export type PurchaseOrderStatus = 'draft' | 'approved' | 'ordered' | 'partial' | 'received' | 'cancelled'
export type CostCategory = 'material' | 'labor' | 'service' | 'contractor' | 'purchase' | 'other'
export type CostValuationStatus = 'actual' | 'estimated' | 'missing'

export interface MaterialRow {
  id: string
  tenant_id: string
  code: string
  name: string
  category_id: string | null
  unit_id: string
  standard_unit_cost: number | null
  cost_currency: string
  is_stock_item: boolean
  is_active: boolean
}

export interface WarehouseRow {
  id: string
  tenant_id: string
  site_id: string | null
  location_id: string | null
  code: string
  name: string
  is_active: boolean
}

export interface InventoryMovementRow {
  id: string
  tenant_id: string
  code: string | null
  warehouse_id: string
  material_id: string
  movement_type: InventoryMovementType
  quantity_delta: number
  unit_cost: number | null
  currency: string
  work_order_id: string | null
  source: 'manual' | 'work_order' | 'purchase' | 'sap' | 'import' | 'api'
  occurred_at: string
}

export interface InventoryStatusRow {
  tenant_id: string
  warehouse_id: string
  warehouse_code: string
  warehouse_name: string
  material_id: string
  material_code: string
  material_name: string
  unit_symbol: string
  quantity_on_hand: number
  reserved_quantity: number
  available_quantity: number
  minimum_stock: number
  maximum_stock: number | null
  reorder_point: number | null
  reorder_quantity: number | null
  stock_status: InventoryStockStatus
  standard_unit_cost: number | null
  cost_currency: string
  estimated_stock_value: number | null
}

export interface PurchaseOrderRow {
  id: string
  tenant_id: string
  code: string | null
  supplier_id: string | null
  status: PurchaseOrderStatus
  currency: string
  expected_at: string | null
  cancelled_at: string | null
  cancellation_reason: string | null
}

export interface WorkOrderCostSummaryRow {
  tenant_id: string
  work_order_id: string
  currency: string
  total_cost: number | null
  material_cost: number | null
  labor_cost: number | null
  external_cost: number | null
  missing_valuations: number
}
