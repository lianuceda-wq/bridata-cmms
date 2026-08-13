export const REPORT_KEYS = [
  'maintenance','reliability','hydraulics','costs','inventory',
  'purchases','budget','inspections','attendance','work_orders',
] as const

export type ReportKey = typeof REPORT_KEYS[number]
export type RangeMode = 'month' | 'timestamp' | 'period_intersection' | 'none'

export interface ReportDefinition {
  key: ReportKey
  label: string
  description: string
  view: string
  rangeMode: RangeMode
  dateColumn?: string
  endDateColumn?: string
  orderColumn: string
}

export const REPORTS: Record<ReportKey, ReportDefinition> = {
  maintenance: { key:'maintenance', label:'Cumplimiento de mantenimiento', description:'OT planificadas, ejecutadas, vencidas y cumplimiento mensual.', view:'maintenance_kpis_monthly', rangeMode:'month', dateColumn:'month', orderColumn:'month' },
  reliability: { key:'reliability', label:'Confiabilidad', description:'Fallas, MTTR, downtime y tiempo de respuesta.', view:'reliability_kpis_monthly', rangeMode:'month', dateColumn:'month', orderColumn:'month' },
  hydraulics: { key:'hydraulics', label:'Control hidráulico', description:'Cumplimiento, presión y caudal desde lecturas validadas.', view:'hydraulic_kpis_monthly', rangeMode:'month', dateColumn:'month', orderColumn:'month' },
  costs: { key:'costs', label:'Costos de mantenimiento', description:'Materiales, HH, servicios y correctivos/preventivos.', view:'maintenance_cost_kpis_monthly', rangeMode:'month', dateColumn:'month', orderColumn:'month' },
  inventory: { key:'inventory', label:'Inventario', description:'Stock físico, reservado, disponible, mínimos y valorización.', view:'inventory_status', rangeMode:'none', orderColumn:'material_code' },
  purchases: { key:'purchases', label:'Compras', description:'Órdenes de compra, recepción y monto pendiente.', view:'purchase_order_summary', rangeMode:'none', orderColumn:'code' },
  budget: { key:'budget', label:'Presupuesto vs ejecución', description:'Presupuesto aprobado y ejecución real por categoría.', view:'maintenance_budget_execution', rangeMode:'period_intersection', dateColumn:'period_start', endDateColumn:'period_end', orderColumn:'period_start' },
  inspections: { key:'inspections', label:'Inspecciones', description:'Checklist, conformidad y hallazgos por ejecución.', view:'inspection_run_kpis', rangeMode:'timestamp', dateColumn:'scheduled_at', orderColumn:'scheduled_at' },
  attendance: { key:'attendance', label:'Asistencia', description:'Asistencia mensual del personal operativo.', view:'attendance_kpis_monthly', rangeMode:'month', dateColumn:'month', orderColumn:'month' },
  work_orders: { key:'work_orders', label:'Órdenes de trabajo', description:'Hechos operacionales de OT para drill-down y Power BI.', view:'maintenance_execution_facts', rangeMode:'timestamp', dateColumn:'reference_at', orderColumn:'reference_at' },
}

export function isReportKey(value: string): value is ReportKey {
  return (REPORT_KEYS as readonly string[]).includes(value)
}
