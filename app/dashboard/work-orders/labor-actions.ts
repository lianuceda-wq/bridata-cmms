'use server'

import { revalidatePath } from 'next/cache'
import { requireTenant } from '@/lib/tenant'
import { localDateTimeToIso } from '@/lib/datetime'

const clean = (value: FormDataEntryValue | null) => String(value ?? '').trim()
const nullable = (value: FormDataEntryValue | null) => clean(value) || null
const managers = new Set(['owner','admin','planner','supervisor'])

function refresh(id: string) {
  revalidatePath(`/dashboard/work-orders/${id}`)
  revalidatePath('/dashboard/work-orders')
  revalidatePath('/dashboard/failures')
}

export async function addLaborSession(formData: FormData) {
  const { supabase, tenant, user, role } = await requireTenant()
  const workOrderId = clean(formData.get('work_order_id'))
  if (!workOrderId) throw new Error('Orden de trabajo inválida.')

  const { data: order, error: orderError } = await supabase
    .from('work_orders')
    .select('id,status,assigned_to')
    .eq('tenant_id', tenant.id)
    .eq('id', workOrderId)
    .single()
  if (orderError) throw new Error(orderError.message)
  if (['closed','cancelled'].includes(order.status)) throw new Error('La OT ya no admite horas-hombre.')

  let workerUserId = nullable(formData.get('worker_user_id'))
  let workerName = nullable(formData.get('worker_name'))
  if (role === 'technician') {
    if (order.assigned_to !== user.id) throw new Error('Esta OT no está asignada a tu usuario.')
    workerUserId = user.id
    workerName = null
  } else if (!managers.has(role)) {
    throw new Error('Tu rol no puede registrar horas-hombre.')
  }

  if (workerUserId) {
    const { data: member, error } = await supabase.from('tenant_members')
      .select('user_id').eq('tenant_id', tenant.id).eq('user_id', workerUserId).eq('is_active', true).maybeSingle()
    if (error) throw new Error(error.message)
    if (!member) throw new Error('El trabajador seleccionado no pertenece a la empresa.')
  }
  if (!workerUserId && !workerName) throw new Error('Selecciona un trabajador o ingresa un nombre externo.')

  const startRaw = clean(formData.get('started_at'))
  const endRaw = clean(formData.get('ended_at'))
  const offset = Number(clean(formData.get('timezone_offset_minutes')) || '0')
  if (!startRaw) throw new Error('La hora de inicio es obligatoria.')

  const { error } = await supabase.from('work_order_labor_sessions').insert({
    tenant_id: tenant.id,
    work_order_id: workOrderId,
    worker_user_id: workerUserId,
    worker_name: workerName,
    worker_type: clean(formData.get('worker_type')) || 'employee',
    started_at: localDateTimeToIso(startRaw, offset),
    ended_at: endRaw ? localDateTimeToIso(endRaw, offset) : null,
    labor_role: nullable(formData.get('labor_role')),
    notes: nullable(formData.get('notes')),
    created_by: user.id,
  })
  if (error) throw new Error(error.message)
  refresh(workOrderId)
}

export async function closeLaborSession(formData: FormData) {
  const { supabase, tenant, user, role } = await requireTenant()
  const id = clean(formData.get('id'))
  const workOrderId = clean(formData.get('work_order_id'))
  if (!id || !workOrderId) throw new Error('Sesión de trabajo inválida.')

  const { data: session, error: readError } = await supabase.from('work_order_labor_sessions')
    .select('worker_user_id,created_by,ended_at')
    .eq('tenant_id',tenant.id).eq('work_order_id',workOrderId).eq('id',id).single()
  if (readError) throw new Error(readError.message)
  if (session.ended_at) return
  if (!managers.has(role) && session.worker_user_id !== user.id && session.created_by !== user.id) {
    throw new Error('No puedes cerrar la sesión de otro trabajador.')
  }

  const { error } = await supabase.from('work_order_labor_sessions')
    .update({ ended_at: new Date().toISOString() })
    .eq('tenant_id',tenant.id).eq('work_order_id',workOrderId).eq('id',id)
  if (error) throw new Error(error.message)
  refresh(workOrderId)
}
