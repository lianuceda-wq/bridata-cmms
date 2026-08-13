export type MetricFreshness = 'realtime' | 'near_realtime' | 'scheduled'
export type BudgetStatus = 'draft' | 'approved' | 'closed' | 'cancelled'

export interface MetricDefinitionRow {
  code: string
  name: string
  category: string
  unit: string | null
  freshness: MetricFreshness
  source_view: string
  formula_description: string
  drilldown_route: string | null
  description: string | null
  is_active: boolean
}

export interface MaintenanceKpiMonthlyRow {
  tenant_id: string
  month: string
  work_orders: number
  planned_orders: number
  executed_planned_orders: number
  calendar_planned_orders: number
  on_time_planned_orders: number
  late_planned_orders: number
  overdue_planned_orders: number
  preventive_orders: number
  corrective_orders: number
  compliance_percent: number | null
  on_time_percent: number | null
}

export interface ReliabilityKpiMonthlyRow {
  tenant_id: string
  month: string
  failure_count: number
  mttr_hours: number | null
  avg_downtime_hours: number | null
  avg_response_hours: number | null
}

export interface HydraulicKpiMonthlyRow {
  tenant_id: string
  month: string
  session_count: number
  total_readings: number
  evaluated_readings: number
  compliant_readings: number
  out_of_range_readings: number
  compliance_percent: number | null
  avg_pressure: number | null
  avg_flow: number | null
}

export interface MaintenanceCostKpiMonthlyRow {
  tenant_id: string
  month: string
  currency: string
  total_cost: number | null
  material_cost: number | null
  labor_cost: number | null
  external_cost: number | null
  preventive_cost: number | null
  corrective_cost: number | null
  missing_valuations: number
}

export interface LaborRateVersionRow {
  id: string
  tenant_id: string
  user_id: string | null
  labor_role: string | null
  hourly_rate: number
  currency: string
  valid_from: string
  valid_to: string | null
  is_active: boolean
}
