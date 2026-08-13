'use server'

import { randomUUID } from 'node:crypto'
import { revalidatePath } from 'next/cache'
import { requireTenant } from '@/lib/tenant'

const managerRoles = new Set(['owner', 'admin', 'planner', 'supervisor'])
const executionRoles = new Set(['owner', 'admin', 'planner', 'supervisor', 'technician'])

const clean = (value: FormDataEntryValue | null) => String(value ?? '').trim()
const nullable = (value: FormDataEntryValue | null) => clean(value) || null

function assertManager(role: string) {
  if (!managerRoles.has(role)) throw new Error('Tu rol no puede administrar órdenes de trabajo.')
}

function refreshWorkOrders(id?: string) {
  revalidatePath('/dashboard')
  revalidatePath('/dashboard/work-orders')
  if (id) revalidatePath(`/dashboard/work-orders/${id}`)
}

export async function generateDueWorkOrders() {
  const { supabase, tenant, role } = await requireTenant()
  assertManager(role)

  const { error } = await supabase.rpc('generate_due_work_orders', {
    p_tenant_id: tenant.id,
    p_as_of: new Date().toISOString(),
  })

  if (error) throw new Error(error.message)
  refreshWorkOrders()
}

export async function assignWorkOrder(formData: FormData) {
  const { supabase, tenant, role } = await requireTenant()
  assertManager(role)

  const id = clean(formData.get('id'))
  const userId = nullable(formData.get('assigned_to'))
  if (!id) throw new Error('Orden de trabajo inválida.')

  const { data: order, error: orderError } = await supabase
    .from('work_orders')
    .select('status')
    .eq('tenant_id', tenant.id)
    .eq('id', id)
    .single()

  if (orderError) throw new Error(orderError.message)

  if (userId) {
    const { data: member, error: memberError } = await supabase
      .from('tenant_members')
      .select('user_id')
      .eq('tenant_id', tenant.id)
      .eq('user_id', userId)
      .eq('is_active', true)
      .maybeSingle()

    if (memberError) throw new Error(memberError.message)
    if (!member) throw new Error('El usuario seleccionado no pertenece a esta empresa.')
  }

  const nextStatus = userId
    ? (['requested', 'planned'].includes(order.status) ? 'assigned' : order.status)
    : (order.status === 'assigned' ? 'planned' : order.status)

  const { error } = await supabase
    .from('work_orders')
    .update({ assigned_to: userId, status: nextStatus })
    .eq('tenant_id', tenant.id)
    .eq('id', id)

  if (error) throw new Error(error.message)
  refreshWorkOrders(id)
}

export async function transitionWorkOrder(formData: FormData) {
  const { supabase, tenant, user, role } = await requireTenant()
  if (!executionRoles.has(role)) throw new Error('Tu rol no puede ejecutar órdenes de trabajo.')

  const id = clean(formData.get('id'))
  const status = clean(formData.get('status'))
  if (!id || !status) throw new Error('Orden o estado inválido.')

  const { data: order, error: readError } = await supabase
    .from('work_orders')
    .select('assigned_to,status')
    .eq('tenant_id', tenant.id)
    .eq('id', id)
    .single()

  if (readError) throw new Error(readError.message)
  if (role === 'technician' && order.assigned_to !== user.id) {
    throw new Error('Esta orden no está asignada a tu usuario.')
  }

  const payload: Record<string, string | null> = { status }
  if (status === 'cancelled') {
    payload.cancellation_reason = nullable(formData.get('cancellation_reason'))
  }

  const { error } = await supabase
    .from('work_orders')
    .update(payload)
    .eq('tenant_id', tenant.id)
    .eq('id', id)

  if (error) throw new Error(error.message)
  refreshWorkOrders(id)
}

export async function updateWorkOrderTask(formData: FormData) {
  const { supabase, tenant, user, role } = await requireTenant()
  if (!executionRoles.has(role)) throw new Error('Tu rol no puede ejecutar actividades.')

  const taskId = clean(formData.get('task_id'))
  const workOrderId = clean(formData.get('work_order_id'))
  const status = clean(formData.get('status')) || 'pending'
  if (!taskId || !workOrderId) throw new Error('Actividad inválida.')

  if (role === 'technician') {
    const { data: order, error: orderError } = await supabase
      .from('work_orders')
      .select('assigned_to')
      .eq('tenant_id', tenant.id)
      .eq('id', workOrderId)
      .single()
    if (orderError) throw new Error(orderError.message)
    if (order.assigned_to !== user.id) throw new Error('Esta OT no está asignada a tu usuario.')
  }

  const rawMeasurement = clean(formData.get('measurement_value'))
  const measurementValue = rawMeasurement === '' ? null : Number(rawMeasurement)
  if (rawMeasurement && !Number.isFinite(measurementValue)) {
    throw new Error('La medición debe ser numérica.')
  }

  const resultStatus = nullable(formData.get('result_status'))

  const { error } = await supabase
    .from('work_order_tasks')
    .update({
      status,
      measurement_value: measurementValue,
      result_status: resultStatus,
      notes: nullable(formData.get('notes')),
    })
    .eq('tenant_id', tenant.id)
    .eq('work_order_id', workOrderId)
    .eq('id', taskId)

  if (error) throw new Error(error.message)
  refreshWorkOrders(workOrderId)
}

function safeFileName(name: string) {
  return name
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-zA-Z0-9._-]+/g, '-')
    .replace(/-+/g, '-')
    .slice(-120) || 'evidence.bin'
}

export async function uploadWorkOrderEvidence(formData: FormData) {
  const { supabase, tenant, user, role } = await requireTenant()
  if (!executionRoles.has(role)) throw new Error('Tu rol no puede cargar evidencias.')

  const workOrderId = clean(formData.get('work_order_id'))
  const taskId = clean(formData.get('task_id'))
  const file = formData.get('file')

  if (!workOrderId || !taskId || !(file instanceof File) || file.size === 0) {
    throw new Error('Selecciona un archivo válido.')
  }
  if (file.size > 10 * 1024 * 1024) throw new Error('La evidencia no puede superar 10 MB.')
  if (!(file.type.startsWith('image/') || file.type === 'application/pdf')) {
    throw new Error('Solo se permiten imágenes o PDF.')
  }

  if (role === 'technician') {
    const { data: order, error: orderError } = await supabase
      .from('work_orders')
      .select('assigned_to')
      .eq('tenant_id', tenant.id)
      .eq('id', workOrderId)
      .single()
    if (orderError) throw new Error(orderError.message)
    if (order.assigned_to !== user.id) throw new Error('Esta OT no está asignada a tu usuario.')
  }

  const path = `${tenant.id}/${workOrderId}/${taskId}/${randomUUID()}-${safeFileName(file.name)}`
  const { error: uploadError } = await supabase.storage
    .from('work-order-evidence')
    .upload(path, file, { contentType: file.type, upsert: false })

  if (uploadError) throw new Error(uploadError.message)

  const { error: metadataError } = await supabase.from('work_order_evidence').insert({
    tenant_id: tenant.id,
    work_order_id: workOrderId,
    task_id: taskId,
    storage_bucket: 'work-order-evidence',
    storage_path: path,
    file_name: file.name,
    mime_type: file.type,
    caption: nullable(formData.get('caption')),
    uploaded_by: user.id,
  })

  if (metadataError) {
    await supabase.storage.from('work-order-evidence').remove([path])
    throw new Error(metadataError.message)
  }

  refreshWorkOrders(workOrderId)
}
