'use server'

import { revalidatePath } from 'next/cache'
import { requireTenant } from '@/lib/tenant'

const clean = (value: FormDataEntryValue | null) => String(value ?? '').trim()
const nullable = (value: FormDataEntryValue | null) => clean(value) || null
const num = (value: FormDataEntryValue | null) => {
  const raw = clean(value)
  if (!raw) return null
  const parsed = Number(raw.replace(',', '.'))
  if (!Number.isFinite(parsed)) throw new Error(`Valor numérico inválido: ${raw}`)
  return parsed
}

export async function createTargetVersion(formData: FormData) {
  const { supabase, tenant, role } = await requireTenant()
  if (!['owner', 'admin', 'planner', 'supervisor'].includes(role)) {
    throw new Error('No tienes permisos para configurar nominales.')
  }

  const parameterId = clean(formData.get('parameter_id'))
  const pointId = nullable(formData.get('point_id'))
  const siteId = nullable(formData.get('site_id'))
  const locationId = nullable(formData.get('location_id'))
  const assetId = nullable(formData.get('asset_id'))
  const unitId = clean(formData.get('unit_id'))
  const validFrom = clean(formData.get('valid_from'))

  if (!parameterId || !unitId || !validFrom) {
    throw new Error('Parámetro, unidad y fecha de vigencia son obligatorios.')
  }

  const targetValue = num(formData.get('target_value'))
  const minValue = num(formData.get('min_value'))
  const maxValue = num(formData.get('max_value'))
  if (targetValue === null && minValue === null && maxValue === null) {
    throw new Error('Ingresa al menos nominal, mínimo o máximo.')
  }

  const { error } = await supabase.rpc('create_measurement_target_version', {
    p_tenant_id: tenant.id,
    p_parameter_id: parameterId,
    p_point_id: pointId,
    p_site_id: siteId,
    p_location_id: locationId,
    p_asset_id: assetId,
    p_unit_id: unitId,
    p_target_value: targetValue,
    p_min_value: minValue,
    p_max_value: maxValue,
    p_tolerance_percent: num(formData.get('tolerance_percent')),
    p_valid_from: validFrom,
    p_notes: nullable(formData.get('notes')),
  })

  if (error) throw new Error(error.message)
  revalidatePath('/dashboard/settings/measurements')
  revalidatePath('/dashboard/hydraulics')
}

export async function createHydraulicComponentModel(formData: FormData) {
  const { supabase, tenant, role } = await requireTenant()
  if (!['owner', 'admin', 'planner', 'supervisor'].includes(role)) {
    throw new Error('No tienes permisos para administrar catálogos hidráulicos.')
  }

  const componentType = clean(formData.get('component_type'))
  const name = clean(formData.get('name'))
  if (!componentType || !name) throw new Error('Tipo y nombre son obligatorios.')

  const { error } = await supabase.from('hydraulic_component_models').insert({
    tenant_id: tenant.id,
    component_type: componentType,
    code: nullable(formData.get('code')),
    name,
    manufacturer: nullable(formData.get('manufacturer')),
  })

  if (error) throw new Error(error.message)
  revalidatePath('/dashboard/settings/measurements')
  revalidatePath('/dashboard/hydraulics')
}

export async function saveLocationHydraulicConfig(formData: FormData) {
  const { supabase, tenant, user, role } = await requireTenant()
  if (!['owner', 'admin', 'planner', 'supervisor'].includes(role)) {
    throw new Error('No tienes permisos para configurar lotes.')
  }

  const locationId = clean(formData.get('location_id'))
  const validFrom = clean(formData.get('valid_from'))
  if (!locationId || !validFrom) throw new Error('Ubicación y vigencia son obligatorias.')

  const { error } = await supabase.from('hydraulic_location_configs').insert({
    tenant_id: tenant.id,
    location_id: locationId,
    hose_model_id: nullable(formData.get('hose_model_id')),
    valve_model_id: nullable(formData.get('valve_model_id')),
    pilot_model_id: nullable(formData.get('pilot_model_id')),
    valid_from: validFrom,
    notes: nullable(formData.get('notes')),
    created_by: user.id,
  })

  if (error) throw new Error(error.message)
  revalidatePath('/dashboard/settings/measurements')
  revalidatePath('/dashboard/hydraulics')
}
