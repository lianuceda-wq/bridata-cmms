'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { requireTenant } from '@/lib/tenant'

const clean = (value: FormDataEntryValue | null) => String(value ?? '').trim()
const nullable = (value: FormDataEntryValue | null) => clean(value) || null

export async function createHydraulicControl(formData: FormData) {
  const { supabase, tenant } = await requireTenant()
  const siteId = clean(formData.get('site_id'))
  const occurredAt = clean(formData.get('occurred_at'))
  const rowsRaw = clean(formData.get('rows_json'))
  if (!siteId || !occurredAt || !rowsRaw) throw new Error('Fundo, fecha y lecturas son obligatorios.')

  let rows: unknown
  try {
    rows = JSON.parse(rowsRaw)
  } catch {
    throw new Error('No se pudo interpretar la grilla de lecturas.')
  }
  if (!Array.isArray(rows) || rows.length === 0) throw new Error('Agrega al menos una fila de control.')

  const { data, error } = await supabase.rpc('create_hydraulic_session', {
    p_tenant_id: tenant.id,
    p_site_id: siteId,
    p_location_id: nullable(formData.get('location_id')),
    p_occurred_at: new Date(occurredAt).toISOString(),
    p_responsible_name: nullable(formData.get('responsible_name')),
    p_notes: nullable(formData.get('notes')),
    p_rows: rows,
    p_submit: clean(formData.get('submit_mode')) === 'submit',
  })

  if (error) throw new Error(error.message)
  const result = Array.isArray(data) ? data[0] : null
  revalidatePath('/dashboard/hydraulics')
  redirect(`/dashboard/hydraulics?created=${encodeURIComponent(result?.session_code ?? 'ok')}`)
}

export async function changeHydraulicSessionStatus(formData: FormData) {
  const { supabase, tenant } = await requireTenant()
  const id = clean(formData.get('id'))
  const status = clean(formData.get('status'))
  if (!id || !status) return

  const { error } = await supabase
    .from('measurement_sessions')
    .update({ status })
    .eq('tenant_id', tenant.id)
    .eq('id', id)

  if (error) throw new Error(error.message)
  revalidatePath('/dashboard/hydraulics')
}
