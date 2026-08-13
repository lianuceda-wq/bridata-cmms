'use server'

import { revalidatePath } from 'next/cache'
import { requireTenant } from '@/lib/tenant'

const clean=(v:FormDataEntryValue|null)=>String(v??'').trim()
const nullable=(v:FormDataEntryValue|null)=>clean(v)||null
const num=(v:FormDataEntryValue|null)=>{const raw=clean(v);if(!raw)return null;const n=Number(raw.replace(',','.'));if(!Number.isFinite(n))throw new Error(`Número inválido: ${raw}`);return n}
const toolRoles=new Set(['owner','admin','planner','supervisor','warehouse'])
const ppeRoles=new Set(['owner','admin','supervisor','warehouse'])
const refresh=()=>{revalidatePath('/dashboard/resources');revalidatePath('/dashboard/people');revalidatePath('/dashboard/inventory')}

export async function createTool(formData:FormData){
 const {supabase,tenant,role}=await requireTenant();if(!toolRoles.has(role))throw new Error('Sin permisos para herramientas.')
 const code=clean(formData.get('code')),name=clean(formData.get('name'));if(!code||!name)throw new Error('Código y nombre son obligatorios.')
 const {error}=await supabase.from('tools').insert({tenant_id:tenant.id,code:code.toUpperCase(),name,category:nullable(formData.get('category')),manufacturer:nullable(formData.get('manufacturer')),model:nullable(formData.get('model')),serial_number:nullable(formData.get('serial_number')),asset_tag:nullable(formData.get('asset_tag')),current_warehouse_id:nullable(formData.get('warehouse_id')),condition:clean(formData.get('condition'))||'good',acquired_at:nullable(formData.get('acquired_at'))});if(error)throw new Error(error.message);refresh()
}

export async function issueTool(formData:FormData){
 const {supabase,tenant}=await requireTenant();const toolId=clean(formData.get('tool_id')),workerId=clean(formData.get('worker_id'));if(!toolId||!workerId)throw new Error('Herramienta y trabajador son obligatorios.')
 const {error}=await supabase.rpc('issue_tool',{p_tenant_id:tenant.id,p_tool_id:toolId,p_worker_id:workerId,p_work_order_id:nullable(formData.get('work_order_id')),p_notes:nullable(formData.get('notes'))});if(error)throw new Error(error.message);refresh()
}

export async function returnTool(formData:FormData){
 const {supabase,tenant}=await requireTenant();const custodyId=clean(formData.get('custody_id'));if(!custodyId)throw new Error('Custodia inválida.')
 const {error}=await supabase.rpc('return_tool',{p_tenant_id:tenant.id,p_custody_id:custodyId,p_condition:clean(formData.get('condition'))||'good',p_outcome:clean(formData.get('outcome'))||'returned',p_notes:nullable(formData.get('notes'))});if(error)throw new Error(error.message);refresh()
}

export async function createPpe(formData:FormData){
 const {supabase,tenant,role}=await requireTenant();if(!ppeRoles.has(role))throw new Error('Sin permisos para EPP.')
 const code=clean(formData.get('code')),name=clean(formData.get('name'));if(!code||!name)throw new Error('Código y nombre son obligatorios.')
 const {error}=await supabase.from('ppe_catalog').insert({tenant_id:tenant.id,code:code.toUpperCase(),name,material_id:nullable(formData.get('material_id')),replacement_days:num(formData.get('replacement_days')),certification_standard:nullable(formData.get('certification_standard')),requires_size:clean(formData.get('requires_size'))==='on'});if(error)throw new Error(error.message);refresh()
}

export async function issuePpe(formData:FormData){
 const {supabase,tenant}=await requireTenant();const ppeId=clean(formData.get('ppe_id')),workerId=clean(formData.get('worker_id'));const quantity=num(formData.get('quantity'));if(!ppeId||!workerId||!quantity)throw new Error('EPP, trabajador y cantidad son obligatorios.')
 const {error}=await supabase.rpc('issue_ppe',{p_tenant_id:tenant.id,p_ppe_id:ppeId,p_worker_id:workerId,p_warehouse_id:nullable(formData.get('warehouse_id')),p_quantity:quantity,p_size:nullable(formData.get('size')),p_notes:nullable(formData.get('notes'))});if(error)throw new Error(error.message);refresh()
}

export async function closePpeIssue(formData:FormData){
 const {supabase,tenant}=await requireTenant();const issueId=clean(formData.get('issue_id')),status=clean(formData.get('status'));if(!issueId||!status)throw new Error('Entrega o estado inválido.')
 const {error}=await supabase.rpc('close_ppe_issue',{p_tenant_id:tenant.id,p_issue_id:issueId,p_status:status,p_notes:nullable(formData.get('notes'))});if(error)throw new Error(error.message);refresh()
}
