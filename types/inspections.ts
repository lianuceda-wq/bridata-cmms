export type InspectionTemplateStatus = 'draft' | 'active' | 'retired' | 'cancelled'
export type InspectionRunStatus = 'assigned' | 'in_progress' | 'completed' | 'validated' | 'cancelled'
export type InspectionResponseType = 'boolean' | 'number' | 'choice' | 'text' | 'photo'
export type InspectionResultStatus = 'pending' | 'compliant' | 'nonconforming' | 'not_applicable'
export type InspectionFindingStatus = 'open' | 'converted' | 'resolved' | 'dismissed'

export interface InspectionTemplateRow {
  id: string
  tenant_id: string
  code: string
  name: string
  description: string | null
  revision: number
  status: InspectionTemplateStatus
  supersedes_id: string | null
  created_at: string
  updated_at: string
}

export interface InspectionRunRow {
  id: string
  tenant_id: string
  code: string
  template_id: string
  template_revision: number
  work_order_id: string | null
  asset_id: string | null
  site_id: string | null
  location_id: string | null
  status: InspectionRunStatus
  assigned_to: string | null
  scheduled_at: string | null
  started_at: string | null
  completed_at: string | null
  validated_at: string | null
}

export interface InspectionRunItemRow {
  id: string
  tenant_id: string
  inspection_run_id: string
  sequence: number
  title: string
  response_type: InspectionResponseType
  mandatory: boolean
  requires_evidence: boolean
  result_status: InspectionResultStatus
  response_boolean: boolean | null
  response_number: number | null
  response_text: string | null
}

export interface InspectionFindingRow {
  id: string
  tenant_id: string
  inspection_run_id: string
  inspection_run_item_id: string
  severity: 'low' | 'medium' | 'high' | 'critical'
  status: InspectionFindingStatus
  title: string
  failure_event_id: string | null
  work_order_id: string | null
}
