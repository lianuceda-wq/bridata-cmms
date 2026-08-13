'use server'

import { revalidatePath } from 'next/cache'
import { requireTenant } from '@/lib/tenant'

const clean=(value:FormDataEntryValue|null)=>String(value??'').trim()
const nullable=(value:FormDataEntryValue|null)=>clean(value)||null
const numberValue=(value:FormDataEntryValue|null)=>{const raw=clean(value);if(!raw)return null;const valueNumber=Number(raw.replace(',','.'));if(!Number.isFinite(valueNumber))throw new Error(`Número inválido: ${raw}`);return valueNumber}
const managerRoles=new Set(['owner','admin','planner','supervisor'])

function refresh(runId?:string){
  revalidatePath('/dashboard/inspections')
  revalidatePath('/dashboard/failures')
  revalidatePath('/dashboard/work-orders')
  if(runId) revalidatePath(`/dashboard/inspections/${runId}`)
}

export async function createInspectionTemplate(formData:FormData){
  const {supabase,tenant,role}=await requireTenant()
  if(!managerRoles.has(role)) throw new Error('Tu rol no puede crear plantillas.')
  const itemsRaw=clean(formData.get('items_json'))
  if(!itemsRaw) throw new Error('Agrega al menos un punto de inspección.')
  let items:unknown
  try{items=JSON.parse(itemsRaw)}catch{throw new Error('No se pudieron interpretar los puntos de inspección.')}
  if(!Array.isArray(items)||items.length===0) throw new Error('Agrega al menos un punto de inspección.')
  const {error}=await supabase.rpc('create_inspection_template',{
    p_tenant_id:tenant.id,
    p_code:clean(formData.get('code')),
    p_name:clean(formData.get('name')),
    p_description:nullable(formData.get('description')),
    p_items:items,
  })
  if(error) throw new Error(error.message)
  refresh()
}

export async function changeInspectionTemplateStatus(formData:FormData){
  const {supabase,tenant}=await requireTenant()
  const templateId=clean(formData.get('template_id')),status=clean(formData.get('status'))
  if(!templateId||!status) throw new Error('Plantilla o estado inválido.')
  const {error}=await supabase.rpc('change_inspection_template_status',{p_tenant_id:tenant.id,p_template_id:templateId,p_status:status})
  if(error) throw new Error(error.message)
  refresh()
}

export async function createManualInspectionRun(formData:FormData){
  const {supabase,tenant,user,role}=await requireTenant()
  const templateId=clean(formData.get('template_id'))
  const assetId=nullable(formData.get('asset_id'))
  const locationId=nullable(formData.get('location_id'))
  let assignedTo=nullable(formData.get('assigned_to'))
  if(role==='technician') assignedTo=user.id
  if(!templateId||(!assetId&&!locationId)) throw new Error('Selecciona plantilla y activo/ubicación.')
  const scheduledRaw=clean(formData.get('scheduled_at'))
  const {data,error}=await supabase.rpc('create_manual_inspection_run',{
    p_tenant_id:tenant.id,p_template_id:templateId,p_asset_id:assetId,p_location_id:locationId,
    p_assigned_to:assignedTo,p_scheduled_at:scheduledRaw?new Date(scheduledRaw).toISOString():new Date().toISOString(),
  })
  if(error) throw new Error(error.message)
  refresh(String(data??''))
}

export async function updateInspectionItem(formData:FormData){
  const {supabase,tenant}=await requireTenant()
  const runId=clean(formData.get('run_id')),itemId=clean(formData.get('item_id')),responseType=clean(formData.get('response_type'))
  if(!runId||!itemId) throw new Error('Punto de inspección inválido.')
  let responseBoolean:boolean|null=null
  if(responseType==='boolean'){
    const raw=clean(formData.get('response_boolean'))
    responseBoolean=raw==='true'?true:raw==='false'?false:null
  }
  const {error}=await supabase.rpc('update_inspection_item',{
    p_tenant_id:tenant.id,
    p_run_item_id:itemId,
    p_response_boolean:responseBoolean,
    p_response_number:responseType==='number'?numberValue(formData.get('response_number')):null,
    p_response_text:['choice','text','photo'].includes(responseType)?nullable(formData.get('response_text')):null,
    p_result_status:nullable(formData.get('result_status')),
    p_notes:nullable(formData.get('notes')),
  })
  if(error) throw new Error(error.message)
  refresh(runId)
}

export async function transitionInspectionRun(formData:FormData){
  const {supabase,tenant}=await requireTenant()
  const runId=clean(formData.get('run_id')),status=clean(formData.get('status'))
  if(!runId||!status) throw new Error('Inspección o estado inválido.')
  const {error}=await supabase.rpc('transition_inspection_run',{
    p_tenant_id:tenant.id,p_run_id:runId,p_status:status,p_cancellation_reason:nullable(formData.get('cancellation_reason')),
  })
  if(error) throw new Error(error.message)
  refresh(runId)
}

export async function convertFindingToFailure(formData:FormData){
  const {supabase,tenant}=await requireTenant()
  const findingId=clean(formData.get('finding_id')),runId=clean(formData.get('run_id'))
  if(!findingId) throw new Error('Hallazgo inválido.')
  const {error}=await supabase.rpc('convert_inspection_finding_to_failure',{
    p_tenant_id:tenant.id,p_finding_id:findingId,p_create_work_order:clean(formData.get('create_work_order'))!=='false',
  })
  if(error) throw new Error(error.message)
  refresh(runId)
}

export async function linkTemplateToRoutine(formData:FormData){
  const {supabase,tenant}=await requireTenant()
  const routineId=clean(formData.get('routine_id')),templateId=clean(formData.get('template_id'))
  if(!routineId||!templateId) throw new Error('Rutina y plantilla son obligatorias.')
  const {error}=await supabase.rpc('link_inspection_template_to_routine',{p_tenant_id:tenant.id,p_routine_id:routineId,p_template_id:templateId})
  if(error) throw new Error(error.message)
  revalidatePath('/dashboard/plans')
  refresh()
}

export async function uploadInspectionEvidence(formData:FormData){
  const {supabase,tenant}=await requireTenant()
  const runId=clean(formData.get('run_id')),itemId=nullable(formData.get('item_id'))
  const file=formData.get('file')
  if(!runId||!(file instanceof File)||file.size===0) throw new Error('Selecciona un archivo.')
  if(file.size>10*1024*1024) throw new Error('El archivo no puede superar 10 MB.')
  const allowed=new Set(['image/jpeg','image/png','image/webp','application/pdf'])
  if(file.type&&!allowed.has(file.type)) throw new Error('Formato permitido: JPG, PNG, WEBP o PDF.')
  const safeName=(file.name||'evidencia').replace(/[^a-zA-Z0-9._-]+/g,'-').slice(-100)
  const objectPath=`${tenant.id}/${runId}/${itemId??'run'}/${crypto.randomUUID()}-${safeName}`
  const {error:uploadError}=await supabase.storage.from('inspection-evidence').upload(objectPath,file,{upsert:false,contentType:file.type||undefined})
  if(uploadError) throw new Error(uploadError.message)
  const {error:registerError}=await supabase.rpc('register_inspection_evidence',{
    p_tenant_id:tenant.id,p_run_id:runId,p_item_id:itemId,p_storage_path:objectPath,p_file_name:file.name,p_mime_type:file.type||null,p_file_size:file.size,p_caption:nullable(formData.get('caption')),
  })
  if(registerError){
    await supabase.storage.from('inspection-evidence').remove([objectPath])
    throw new Error(registerError.message)
  }
  refresh(runId)
}
