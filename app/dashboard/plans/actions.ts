'use server'

import { revalidatePath } from 'next/cache'
import { requireTenant } from '@/lib/tenant'

const managerRoles = new Set(['owner', 'admin', 'planner', 'supervisor'])
const readingRoles = new Set(['owner', 'admin', 'planner', 'supervisor', 'technician'])

const clean = (value: FormDataEntryValue | null) => String(value ?? '').trim()
const nullable = (value: FormDataEntryValue | null) => clean(value) || null

function requiredNumber(value: FormDataEntryValue | null, label: string) {
  const raw = clean(value)
  const number = Number(raw)
  if (!raw || !Number.isFinite(number)) throw new Error(`${label} debe ser numérico.`)
  return number
}

function optionalNumber(value: FormDataEntryValue | null) {
  const raw = clean(value)
  if (!raw) return null
  const number = Number(raw)
  if (!Number.isFinite(number)) throw new Error('Valor numérico inválido.')
  return number
}

function assertManager(role: string) {
  if (!managerRoles.has(role)) throw new Error('Tu rol no puede modificar planes de mantenimiento.')
}

async function syncPlan(supabase: Awaited<ReturnType<typeof requireTenant>>['supabase'], planId: string) {
  const { error } = await supabase.rpc('sync_maintenance_schedule', { p_plan_id: planId })
  if (error) throw new Error(error.message)
}

function refreshPlans() {
  revalidatePath('/dashboard/plans')
  revalidatePath('/dashboard')
}

export async function createPlan(formData: FormData) {
  const { supabase, tenant, role } = await requireTenant()
  assertManager(role)

  const code = clean(formData.get('code')).toUpperCase()
  const name = clean(formData.get('name'))
  if (!code || !name) throw new Error('Código y nombre del plan son obligatorios.')

  const { error } = await supabase.from('maintenance_plans').insert({
    tenant_id: tenant.id,
    code,
    name,
    description: nullable(formData.get('description')),
    status: clean(formData.get('status')) || 'active',
  })

  if (error) throw new Error(error.message)
  refreshPlans()
}

export async function assignAssetToPlan(formData: FormData) {
  const { supabase, tenant, user, role } = await requireTenant()
  assertManager(role)

  const planId = clean(formData.get('plan_id'))
  const assetId = clean(formData.get('asset_id'))
  if (!planId || !assetId) throw new Error('Plan y activo son obligatorios.')

  const { error } = await supabase.from('maintenance_plan_assets').insert({
    tenant_id: tenant.id,
    plan_id: planId,
    asset_id: assetId,
    created_by: user.id,
  })

  if (error) throw new Error(error.message)
  await syncPlan(supabase, planId)
  refreshPlans()
}

export async function createMeter(formData: FormData) {
  const { supabase, tenant, user, role } = await requireTenant()
  assertManager(role)

  const assetId = clean(formData.get('asset_id'))
  const code = clean(formData.get('code')).toUpperCase()
  const name = clean(formData.get('name'))
  const unit = clean(formData.get('unit'))
  const initialValue = optionalNumber(formData.get('current_value')) ?? 0

  if (!assetId || !code || !name || !unit) {
    throw new Error('Activo, código, nombre y unidad del medidor son obligatorios.')
  }
  if (initialValue < 0) throw new Error('La lectura inicial no puede ser negativa.')

  const { data: meter, error } = await supabase
    .from('asset_meters')
    .insert({
      tenant_id: tenant.id,
      asset_id: assetId,
      code,
      name,
      meter_type: clean(formData.get('meter_type')) || 'hours',
      unit,
    })
    .select('id')
    .single()

  if (error) throw new Error(error.message)

  if (initialValue > 0) {
    const { error: readingError } = await supabase.from('meter_readings').insert({
      tenant_id: tenant.id,
      meter_id: meter.id,
      value: initialValue,
      recorded_by: user.id,
      source: 'manual',
      notes: 'Lectura inicial',
    })
    if (readingError) throw new Error(readingError.message)
  }

  const { data: assignments } = await supabase
    .from('maintenance_plan_assets')
    .select('plan_id')
    .eq('tenant_id', tenant.id)
    .eq('asset_id', assetId)
    .eq('active', true)

  for (const assignment of assignments ?? []) {
    await syncPlan(supabase, assignment.plan_id)
  }

  refreshPlans()
}

export async function recordMeterReading(formData: FormData) {
  const { supabase, tenant, user, role } = await requireTenant()
  if (!readingRoles.has(role)) throw new Error('Tu rol no puede registrar lecturas.')

  const meterId = clean(formData.get('meter_id'))
  const value = requiredNumber(formData.get('value'), 'La lectura')
  if (!meterId || value < 0) throw new Error('Medidor y lectura válida son obligatorios.')

  const { error } = await supabase.from('meter_readings').insert({
    tenant_id: tenant.id,
    meter_id: meterId,
    value,
    recorded_by: user.id,
    source: 'manual',
    notes: nullable(formData.get('notes')),
  })

  if (error) throw new Error(error.message)
  refreshPlans()
}

export async function createRoutine(formData: FormData) {
  const { supabase, tenant, role } = await requireTenant()
  assertManager(role)

  const planId = clean(formData.get('plan_id'))
  const code = clean(formData.get('code')).toUpperCase()
  const name = clean(formData.get('name'))
  const triggerType = clean(formData.get('trigger_type'))
  const intervalValue = requiredNumber(formData.get('interval_value'), 'La frecuencia')
  const intervalUnit = clean(formData.get('interval_unit'))
  const meterCode = nullable(formData.get('meter_code'))?.toUpperCase() ?? null
  const calendarUnits = new Set(['day', 'week', 'month', 'year'])
  const meterUnits = new Set(['hour', 'cycle', 'km', 'm3', 'unit'])

  if (!planId || !code || !name || intervalValue <= 0) {
    throw new Error('Plan, código, nombre y frecuencia son obligatorios.')
  }

  if (triggerType === 'calendar' && !calendarUnits.has(intervalUnit)) {
    throw new Error('Una rutina por calendario debe usar días, semanas, meses o años.')
  }
  if (triggerType === 'meter' && (!meterUnits.has(intervalUnit) || !meterCode)) {
    throw new Error('Una rutina por medidor requiere unidad de medidor y código de medidor.')
  }

  const estimatedMinutes = optionalNumber(formData.get('estimated_minutes'))
  const leadTimeDays = optionalNumber(formData.get('lead_time_days')) ?? 0

  const { error } = await supabase.from('maintenance_routines').insert({
    tenant_id: tenant.id,
    plan_id: planId,
    code,
    name,
    description: nullable(formData.get('description')),
    maintenance_type: clean(formData.get('maintenance_type')) || 'preventive',
    priority: clean(formData.get('priority')) || 'medium',
    trigger_type: triggerType,
    interval_value: intervalValue,
    interval_unit: intervalUnit,
    meter_code: triggerType === 'meter' ? meterCode : null,
    lead_time_days: leadTimeDays,
    estimated_minutes: estimatedMinutes,
  })

  if (error) throw new Error(error.message)
  await syncPlan(supabase, planId)
  refreshPlans()
}

export async function createRoutineTask(formData: FormData) {
  const { supabase, tenant, role } = await requireTenant()
  assertManager(role)

  const routineId = clean(formData.get('routine_id'))
  const title = clean(formData.get('title'))
  const sequence = requiredNumber(formData.get('sequence'), 'La secuencia')
  if (!routineId || !title || sequence < 1) throw new Error('Rutina, secuencia y actividad son obligatorias.')

  const { error } = await supabase.from('maintenance_routine_tasks').insert({
    tenant_id: tenant.id,
    routine_id: routineId,
    sequence,
    title,
    instructions: nullable(formData.get('instructions')),
    estimated_minutes: optionalNumber(formData.get('estimated_minutes')),
    mandatory: formData.get('mandatory') === 'on',
    task_type: clean(formData.get('task_type')) || 'task',
    requires_evidence: formData.get('requires_evidence') === 'on',
    measurement_unit: nullable(formData.get('measurement_unit')),
    min_value: optionalNumber(formData.get('min_value')),
    max_value: optionalNumber(formData.get('max_value')),
  })

  if (error) throw new Error(error.message)
  refreshPlans()
}

export async function updatePlanStatus(formData: FormData) {
  const { supabase, tenant, role } = await requireTenant()
  assertManager(role)

  const id = clean(formData.get('id'))
  const status = clean(formData.get('status'))
  if (!id || !status) return

  const { error } = await supabase
    .from('maintenance_plans')
    .update({ status })
    .eq('tenant_id', tenant.id)
    .eq('id', id)

  if (error) throw new Error(error.message)
  refreshPlans()
}
