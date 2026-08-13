'use server'

import { revalidatePath } from 'next/cache'
import { requireTenant } from '@/lib/tenant'

const clean=(v:FormDataEntryValue|null)=>String(v??'').trim()
const nullable=(v:FormDataEntryValue|null)=>clean(v)||null
const managers=new Set(['owner','admin','planner','supervisor'])
const refresh=()=>{revalidatePath('/dashboard/people');revalidatePath('/dashboard/resources')}

export async function createWorker(formData:FormData){
 const {supabase,tenant,role}=await requireTenant();if(!managers.has(role))throw new Error('Sin permisos para crear trabajadores.')
 const code=clean(formData.get('employee_code')),name=clean(formData.get('full_name'));if(!code||!name)throw new Error('Código y nombre son obligatorios.')
 const {error}=await supabase.from('workers').insert({tenant_id:tenant.id,user_id:nullable(formData.get('user_id')),supplier_id:nullable(formData.get('supplier_id')),employee_code:code.toUpperCase(),full_name:name,worker_type:clean(formData.get('worker_type'))||'employee',job_title:nullable(formData.get('job_title')),email:nullable(formData.get('email')),phone:nullable(formData.get('phone')),document_id:nullable(formData.get('document_id')),hire_date:nullable(formData.get('hire_date'))});if(error)throw new Error(error.message);refresh()
}

export async function createTeam(formData:FormData){
 const {supabase,tenant,role}=await requireTenant();if(!managers.has(role))throw new Error('Sin permisos para crear cuadrillas.')
 const code=clean(formData.get('code')),name=clean(formData.get('name'));if(!code||!name)throw new Error('Código y nombre son obligatorios.')
 const {error}=await supabase.from('teams').insert({tenant_id:tenant.id,code:code.toUpperCase(),name,supervisor_worker_id:nullable(formData.get('supervisor_worker_id'))});if(error)throw new Error(error.message);refresh()
}

export async function addTeamMember(formData:FormData){
 const {supabase,tenant,role}=await requireTenant();if(!managers.has(role))throw new Error('Sin permisos para gestionar cuadrillas.')
 const teamId=clean(formData.get('team_id')),workerId=clean(formData.get('worker_id'));if(!teamId||!workerId)throw new Error('Cuadrilla y trabajador son obligatorios.')
 const {error}=await supabase.from('team_memberships').insert({tenant_id:tenant.id,team_id:teamId,worker_id:workerId,valid_from:clean(formData.get('valid_from'))||new Date().toISOString().slice(0,10)});if(error)throw new Error(error.message);refresh()
}

export async function createSkill(formData:FormData){
 const {supabase,tenant,role}=await requireTenant();if(!managers.has(role))throw new Error('Sin permisos para crear competencias.')
 const code=clean(formData.get('code')),name=clean(formData.get('name'));if(!code||!name)throw new Error('Código y nombre son obligatorios.')
 const {error}=await supabase.from('skill_catalog').insert({tenant_id:tenant.id,code:code.toUpperCase(),name,category:nullable(formData.get('category'))});if(error)throw new Error(error.message);refresh()
}

export async function assignSkill(formData:FormData){
 const {supabase,tenant,role}=await requireTenant();if(!managers.has(role))throw new Error('Sin permisos para asignar competencias.')
 const workerId=clean(formData.get('worker_id')),skillId=clean(formData.get('skill_id'));if(!workerId||!skillId)throw new Error('Trabajador y competencia son obligatorios.')
 const {error}=await supabase.from('worker_skills').upsert({tenant_id:tenant.id,worker_id:workerId,skill_id:skillId,level:nullable(formData.get('level')),certified_at:nullable(formData.get('certified_at')),expires_at:nullable(formData.get('expires_at')),certificate_reference:nullable(formData.get('certificate_reference'))},{onConflict:'tenant_id,worker_id,skill_id'});if(error)throw new Error(error.message);refresh()
}

export async function recordAttendance(formData:FormData){
 const {supabase,tenant}=await requireTenant();const workerId=clean(formData.get('worker_id')),date=clean(formData.get('work_date')),status=clean(formData.get('status'));if(!workerId||!date||!status)throw new Error('Datos de asistencia incompletos.')
 const {error}=await supabase.rpc('record_worker_attendance',{p_tenant_id:tenant.id,p_worker_id:workerId,p_work_date:date,p_status:status,p_notes:nullable(formData.get('notes'))});if(error)throw new Error(error.message);refresh()
}
