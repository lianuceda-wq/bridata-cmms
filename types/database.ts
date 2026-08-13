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
export type LocationType =
  | 'farm'
  | 'area'
  | 'system'
  | 'sector'
  | 'parcel'
  | 'lot'
  | 'pumping_station'
  | 'hydraulic_zone'
  | 'room'
  | 'line'
  | 'warehouse'
  | 'other'
export type MaintenanceTriggerType = 'calendar' | 'meter' | 'condition'
export type MeasurementSourceType = 'manual' | 'import' | 'api' | 'sensor'
export type MeasurementSessionStatus = 'draft' | 'submitted' | 'validated' | 'cancelled'
export type MeasurementComplianceStatus = 'not_evaluated' | 'compliant' | 'out_of_range'
export type FailureSeverity = 'low' | 'medium' | 'high' | 'critical'
export type FailureStatus = 'open' | 'in_repair' | 'restored' | 'closed' | 'cancelled'
export type FailureSource = 'manual' | 'inspection' | 'work_order' | 'api' | 'sensor'
export type LaborWorkerType = 'employee' | 'contractor' | 'external'

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

export interface MeasurementParameterRow {
  id: string
  tenant_id: string
  code: string
  name: string
  quantity: string
  default_unit_id: string
  hard_min_value: number | null
  hard_max_value: number | null
  is_active: boolean
}

export interface MeasurementPointRow {
  id: string
  tenant_id: string
  code: string
  name: string
  group_code: string
  scope_type: 'session' | 'shift' | 'location'
  suggested_parameter_code: string | null
  sequence: number
  is_active: boolean
}

export interface MeasurementTargetRow {
  id: string
  tenant_id: string
  parameter_id: string
  point_id: string | null
  site_id: string | null
  location_id: string | null
  asset_id: string | null
  unit_id: string
  target_value: number | null
  min_value: number | null
  max_value: number | null
  tolerance_percent: number | null
  valid_from: string
  valid_to: string | null
  is_active: boolean
}

export interface MeasurementSessionRow {
  id: string
  tenant_id: string
  code: string | null
  session_type: 'hydraulic_control' | 'water_quality' | 'piezometer' | 'operational' | 'other'
  status: MeasurementSessionStatus
  site_id: string | null
  location_id: string | null
  occurred_at: string
  responsible_name: string | null
  source_type: MeasurementSourceType
  source_system: string
  created_by: string
  validated_by: string | null
  validated_at: string | null
}

export interface OperationalReadingRow {
  id: string
  tenant_id: string
  session_id: string
  sample_id: string
  parameter_id: string
  point_id: string
  unit_id: string
  location_id: string | null
  value: number
  measured_at: string
  source_type: MeasurementSourceType
  source_system: string
  target_value_snapshot: number | null
  min_value_snapshot: number | null
  max_value_snapshot: number | null
  deviation_value: number | null
  deviation_percent: number | null
  compliance_status: MeasurementComplianceStatus
}

export interface FailureEventRow {
  id: string
  tenant_id: string
  code: string | null
  asset_id: string
  site_id: string | null
  location_id: string | null
  failure_mode_id: string | null
  failure_cause_id: string | null
  severity: FailureSeverity
  status: FailureStatus
  source: FailureSource
  symptom: string | null
  description: string
  occurred_at: string
  reported_at: string
  repair_started_at: string | null
  restored_at: string | null
  closed_at: string | null
  root_cause_notes: string | null
  created_by: string | null
}

export interface WorkOrderLaborSessionRow {
  id: string
  tenant_id: string
  work_order_id: string
  worker_user_id: string | null
  worker_name: string | null
  worker_type: LaborWorkerType
  started_at: string
  ended_at: string | null
  labor_role: string | null
  notes: string | null
  created_by: string | null
}
