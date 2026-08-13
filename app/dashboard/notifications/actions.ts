'use server'

import { revalidatePath } from 'next/cache'
import { requireTenant } from '@/lib/tenant'

function clean(value:FormDataEntryValue|null){return String(value??'').trim()}

export async function setNotificationRead(formData:FormData){
  const {supabase,tenant,user}=await requireTenant()
  const id=clean(formData.get('notification_id'))
  const read=clean(formData.get('read'))==='true'
  if(!id)throw new Error('Notificación inválida.')
  const {error}=await supabase.from('notification_recipients').update({read_at:read?new Date().toISOString():null}).eq('tenant_id',tenant.id).eq('notification_id',id).eq('user_id',user.id)
  if(error)throw new Error(error.message)
  revalidatePath('/dashboard/notifications')
}

export async function dismissNotification(formData:FormData){
  const {supabase,tenant,user}=await requireTenant()
  const id=clean(formData.get('notification_id'))
  if(!id)throw new Error('Notificación inválida.')
  const {error}=await supabase.from('notification_recipients').update({dismissed_at:new Date().toISOString()}).eq('tenant_id',tenant.id).eq('notification_id',id).eq('user_id',user.id)
  if(error)throw new Error(error.message)
  revalidatePath('/dashboard/notifications')
}
