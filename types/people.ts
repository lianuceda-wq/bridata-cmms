export type WorkerType = 'employee' | 'contractor'
export type WorkerStatus = 'active' | 'inactive'
export type AttendanceStatus = 'present' | 'absent' | 'leave' | 'rest' | 'training'
export type ToolStatus = 'available' | 'assigned' | 'maintenance' | 'lost' | 'retired'
export type ToolCondition = 'good' | 'fair' | 'poor' | 'damaged'
export type PpeIssueStatus = 'active' | 'replaced' | 'returned' | 'lost' | 'disposed'

export interface WorkerRow {
  id: string
  tenant_id: string
  user_id: string | null
  supplier_id: string | null
  employee_code: string
  full_name: string
  worker_type: WorkerType
  job_title: string | null
  status: WorkerStatus
}

export interface ToolRow {
  id: string
  tenant_id: string
  code: string
  name: string
  status: ToolStatus
  condition: ToolCondition
  current_warehouse_id: string | null
}

export interface ToolCustodyRow {
  id: string
  tenant_id: string
  tool_id: string
  worker_id: string
  work_order_id: string | null
  status: 'active' | 'returned' | 'lost' | 'damaged'
  issued_at: string
  returned_at: string | null
}

export interface PpeIssueRow {
  id: string
  tenant_id: string
  ppe_id: string
  worker_id: string
  warehouse_id: string | null
  quantity: number
  size: string | null
  replacement_due: string | null
  status: PpeIssueStatus
}
