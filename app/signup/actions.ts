'use server'

import { createClient } from '@/lib/supabase/server'

export type SignupState={error?:string;success?:string}

export async function signup(_state:SignupState,formData:FormData):Promise<SignupState>{
  const fullName=String(formData.get('full_name')??'').trim()
  const email=String(formData.get('email')??'').trim().toLowerCase()
  const password=String(formData.get('password')??'')
  if(!fullName||!email||password.length<8) return {error:'Nombre, correo y contraseña de al menos 8 caracteres son obligatorios.'}
  const supabase=await createClient()
  const {data,error}=await supabase.auth.signUp({email,password,options:{data:{full_name:fullName}}})
  if(error) return {error:error.message}
  if(data.session) return {success:'Cuenta creada e iniciada. Ya puedes aceptar tu código de invitación.'}
  return {success:'Cuenta creada. Revisa tu correo para confirmar la cuenta y luego inicia sesión.'}
}
