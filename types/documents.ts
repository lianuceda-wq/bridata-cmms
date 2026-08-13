export type DocumentStatus = 'active' | 'archived'
export type DocumentEntityType = 'asset'|'work_order'|'failure'|'inspection'|'material'|'worker'|'maintenance_plan'|'supplier'|'purchase_order'

export interface DocumentRow {
  id:string
  tenant_id:string
  document_type_id:string|null
  code:string
  title:string
  description:string|null
  status:DocumentStatus
  current_version:number
  effective_from:string|null
  effective_to:string|null
  owner_worker_id:string|null
}

export interface DocumentVersionRow {
  id:string
  tenant_id:string
  document_id:string
  version_number:number
  storage_path:string
  file_name:string
  mime_type:string|null
  file_size:number|null
  checksum_sha256:string|null
  change_notes:string|null
  created_at:string
}
