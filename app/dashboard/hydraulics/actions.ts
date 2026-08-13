'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { requireTenant } from '@/lib/tenant'

const clean = (value: FormDataEntryValue | null) => String(value ?? '').trim()
const nullable = (value: FormDataEntryValue | null) => clean(value) || null

function localDateTimeToIso(value: string, offsetMinutes: number) {
  const match = value.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?$/)
  if (!match) throw new Error('Fecha/hora inválida.')
  const [, year, month, day, hour, minute, second = '0'] = match
  const localAsUtc = Date.UTC(Number(year), Number(month) - 1, Number(day), Number(hour), Number(minute), Number(second))
  return new Date(localAsUtc + offsetMinutes * 60_000).toISOString()
}

export async function createHydraulicControl(formData: FormData) {
  const { supabase, tenant } = await requireTenant()
  const siteId = clean(formData.get('site_id'))
  const occurredAt = clean(formData.get('occurred_at'))
  const rowsRaw = clean(formData.get('rows_json'))
  const offsetRaw = clean(formData.get('timezone_offset_minutes'))
  const timezoneOffset = Number(offsetRaw || '0')
  if (!Number.isFinite(timezoneOffset) || Math.abs(timezoneOffset) > 14 * 60) throw new Error('Zona horaria inválida.')
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
    p_occurred_at: localDateTimeToIso(occurredAt, timezoneOffset),
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
