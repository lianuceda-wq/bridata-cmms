export type TenantRole = 'owner' | 'admin' | 'planner' | 'supervisor' | 'technician' | 'viewer'

export type WorkOrderStatus =
  | 'requested'
  | 'planned'
  | 'assigned'
  | 'in_progress'
  | 'paused'
  | 'completed'
  | 'validated'
  | 'closed'
  | 'cancelled'

export type AssetStatus = 'operational' | 'maintenance' | 'stopped' | 'retired'
export type AssetCriticality = 'low' | 'medium' | 'high' | 'critical'
export type LocationType = 'area' | 'system' | 'sector' | 'room' | 'line' | 'warehouse' | 'other'
export type MaintenanceTriggerType = 'calendar' | 'meter' | 'condition'

export interface TenantRow {
  id: string
  name: string
  slug: string
  status: 'active' | 'suspended' | 'cancelled'
  created_at: string
}

export interface SiteRow {
  id: string
  tenant_id: string
  name: string
  code: string | null
  created_at: string
}

export interface LocationRow {
  id: string
  tenant_id: string
  site_id: string
  parent_location_id: string | null
  code: string | null
  name: string
  location_type: LocationType
  created_at: string
  updated_at: string
}

export interface AssetRow {
  id: string
  tenant_id: string
  site_id: string | null
  location_id: string | null
  parent_asset_id: string | null
  code: string
  name: string
  description: string | null
  asset_type: string | null
  status: AssetStatus
  manufacturer: string | null
  model: string | null
  serial_number: string | null
  installed_at: string | null
  criticality: AssetCriticality | null
  is_active: boolean
  created_at: string
  updated_at: string
}

export interface MaintenancePlanRow {
  id: string
  tenant_id: string
  asset_id: string
  code: string
  name: string
  trigger_type: MaintenanceTriggerType
  interval_value: number | null
  interval_unit: string | null
  active: boolean
  created_at: string
}

export interface WorkOrderRow {
  id: string
  tenant_id: string
  asset_id: string | null
  plan_id: string | null
  code: string
  title: string
  description: string | null
  maintenance_type: 'preventive' | 'corrective' | 'predictive' | 'inspection' | 'improvement'
  priority: 'low' | 'medium' | 'high' | 'critical'
  status: WorkOrderStatus
  scheduled_at: string | null
  started_at: string | null
  completed_at: string | null
  assigned_to: string | null
  created_by: string | null
  created_at: string
  updated_at: string
}
