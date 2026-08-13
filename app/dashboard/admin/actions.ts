'use server'

import { revalidatePath } from 'next/cache'
import { requireTenant } from '@/lib/tenant'

const clean=(value:FormDataEntryValue|null)=>String(value??'').trim()
const refresh=()=>revalidatePath('/dashboard/admin')

export type InviteState={token?:string;error?:string;email?:string}

export async function createInvitation(_state:InviteState,formData:FormData):Promise<InviteState>{
  try{
    const {supabase,tenant}=await requireTenant()
    const email=clean(formData.get('email')).toLowerCase()
    const role=clean(formData.get('role'))
    const days=Number(clean(formData.get('expires_days'))||'7')
    const {data,error}=await supabase.rpc('create_tenant_invitation',{p_tenant_id:tenant.id,p_email:email,p_role:role,p_expires_days:days})
    if(error) throw new Error(error.message)
    refresh()
    return {token:String(data),email}
  }catch(error){return {error:error instanceof Error?error.message:'No se pudo crear la invitación.'}}
}

export async function setMemberRole(formData:FormData){
  const {supabase,tenant}=await requireTenant()
  const userId=clean(formData.get('user_id')),role=clean(formData.get('role'))
  if(!userId||!role) throw new Error('Miembro o rol inválido.')
  const {error}=await supabase.rpc('set_tenant_member_role',{p_tenant_id:tenant.id,p_user_id:userId,p_role:role})
  if(error) throw new Error(error.message)
  refresh()
}

export async function setMemberActive(formData:FormData){
  const {supabase,tenant}=await requireTenant()
  const userId=clean(formData.get('user_id')),active=clean(formData.get('active'))==='true'
  if(!userId) throw new Error('Miembro inválido.')
  const {error}=await supabase.rpc('set_tenant_member_active',{p_tenant_id:tenant.id,p_user_id:userId,p_active:active})
  if(error) throw new Error(error.message)
  refresh()
}

export async function revokeInvitation(formData:FormData){
  const {supabase,tenant}=await requireTenant()
  const id=clean(formData.get('invitation_id'))
  if(!id) throw new Error('Invitación inválida.')
  const {error}=await supabase.rpc('revoke_tenant_invitation',{p_tenant_id:tenant.id,p_invitation_id:id})
  if(error) throw new Error(error.message)
  refresh()
}

export async function updateTenantSettings(formData:FormData){
  const {supabase,tenant}=await requireTenant()
  const {error}=await supabase.rpc('update_tenant_settings',{
    p_tenant_id:tenant.id,
    p_timezone:clean(formData.get('timezone'))||'America/Lima',
    p_default_currency:(clean(formData.get('default_currency'))||'PEN').toUpperCase(),
    p_locale:clean(formData.get('locale'))||'es-PE',
    p_measurement_system:clean(formData.get('measurement_system'))||'metric',
    p_require_supervisor_validation:clean(formData.get('require_supervisor_validation'))==='on',
    p_hydraulic_capture_mode:clean(formData.get('hydraulic_capture_mode'))||'manual',
  })
  if(error) throw new Error(error.message)
  refresh()
}
