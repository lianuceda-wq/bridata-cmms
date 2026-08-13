'use server'

import { createClient } from '@/lib/supabase/server'

export type JoinState={error?:string;success?:string}

export async function acceptInvite(_state:JoinState,formData:FormData):Promise<JoinState>{
  const token=String(formData.get('token')??'').trim()
  if(!token) return {error:'Ingresa el código de invitación.'}
  const supabase=await createClient()
  const {data:{user}}=await supabase.auth.getUser()
  if(!user) return {error:'Primero inicia sesión con el correo al que fue enviada la invitación.'}
  const {error}=await supabase.rpc('accept_tenant_invitation',{p_token:token})
  if(error) return {error:error.message}
  return {success:'Invitación aceptada. Ya puedes entrar al dashboard de la empresa.'}
}
