'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { requireTenant } from '@/lib/tenant'
import { localDateTimeToIso } from '@/lib/datetime'

const clean = (value: FormDataEntryValue | null) => String(value ?? '').trim()
const nullable = (value: FormDataEntryValue | null) => clean(value) || null
const managers = new Set(['owner','admin','planner','supervisor'])

function refreshFailurePaths() {
  revalidatePath('/dashboard')
  revalidatePath('/dashboard/failures')
  revalidatePath('/dashboard/work-orders')
}

export async function reportFailure(formData: FormData) {
  const { supabase, tenant } = await requireTenant()
  const assetId = clean(formData.get('asset_id'))
  const occurredAt = clean(formData.get('occurred_at'))
  const description = clean(formData.get('description'))
  const severity = clean(formData.get('severity')) || 'medium'
  const offset = Number(clean(formData.get('timezone_offset_minutes')) || '0')

  if (!assetId || !occurredAt || !description) {
    throw new Error('Activo, fecha/hora y descripción son obligatorios.')
  }

  const { data, error } = await supabase.rpc('report_failure', {
    p_tenant_id: tenant.id,
    p_asset_id: assetId,
    p_occurred_at: localDateTimeToIso(occurredAt, offset),
    p_severity: severity,
    p_symptom: nullable(formData.get('symptom')),
    p_description: description,
    p_failure_mode_id: nullable(formData.get('failure_mode_id')),
    p_failure_cause_id: nullable(formData.get('failure_cause_id')),
    p_create_work_order: clean(formData.get('create_work_order')) !== 'false',
  })

  if (error) throw new Error(error.message)
  const row = Array.isArray(data) ? data[0] : null
  refreshFailurePaths()
  redirect(`/dashboard/failures?created=${encodeURIComponent(row?.failure_code ?? 'ok')}`)
}

export async function createFailureMode(formData: FormData) {
  const { supabase, tenant, role } = await requireTenant()
  if (!managers.has(role)) throw new Error('Tu rol no puede administrar modos de falla.')
  const code = clean(formData.get('code'))
  const name = clean(formData.get('name'))
  if (!code || !name) throw new Error('Código y nombre son obligatorios.')

  const { error } = await supabase.from('failure_modes').insert({
    tenant_id: tenant.id,
    code: code.toUpperCase(),
    name,
    category: nullable(formData.get('category')),
    description: nullable(formData.get('description')),
  })
  if (error) throw new Error(error.message)
  revalidatePath('/dashboard/failures')
}

export async function createFailureCause(formData: FormData) {
  const { supabase, tenant, role } = await requireTenant()
  if (!managers.has(role)) throw new Error('Tu rol no puede administrar causas de falla.')
  const code = clean(formData.get('code'))
  const name = clean(formData.get('name'))
  if (!code || !name) throw new Error('Código y nombre son obligatorios.')

  const { error } = await supabase.from('failure_causes').insert({
    tenant_id: tenant.id,
    failure_mode_id: nullable(formData.get('failure_mode_id')),
    code: code.toUpperCase(),
    name,
    category: nullable(formData.get('category')),
    description: nullable(formData.get('description')),
  })
  if (error) throw new Error(error.message)
  revalidatePath('/dashboard/failures')
}

export async function updateFailureDiagnosis(formData: FormData) {
  const { supabase, tenant, role } = await requireTenant()
  if (!managers.has(role)) throw new Error('Tu rol no puede diagnosticar fallas.')
  const id = clean(formData.get('id'))
  if (!id) throw new Error('Falla inválida.')

  const { error } = await supabase.from('failure_events').update({
    failure_mode_id: nullable(formData.get('failure_mode_id')),
    failure_cause_id: nullable(formData.get('failure_cause_id')),
    root_cause_notes: nullable(formData.get('root_cause_notes')),
  }).eq('tenant_id', tenant.id).eq('id', id)

  if (error) throw new Error(error.message)
  revalidatePath('/dashboard/failures')
}

export async function changeFailureStatus(formData: FormData) {
  const { supabase, tenant, role } = await requireTenant()
  if (!managers.has(role)) throw new Error('Tu rol no puede cambiar el estado de una falla.')
  const id = clean(formData.get('id'))
  const status = clean(formData.get('status'))
  if (!id || !status) throw new Error('Falla o estado inválido.')

  const payload: Record<string,string|null> = { status }
  if (status === 'cancelled') payload.cancellation_reason = nullable(formData.get('cancellation_reason'))

  const { error } = await supabase.from('failure_events').update(payload)
    .eq('tenant_id', tenant.id).eq('id', id)
  if (error) throw new Error(error.message)
  refreshFailurePaths()
}
