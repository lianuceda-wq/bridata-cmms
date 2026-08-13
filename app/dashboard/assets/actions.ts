'use server'

import { revalidatePath } from 'next/cache'
import { requireTenant } from '@/lib/tenant'

const clean = (value: FormDataEntryValue | null) => String(value ?? '').trim()
const nullable = (value: FormDataEntryValue | null) => clean(value) || null

export async function createSite(formData: FormData) {
  const { supabase, tenant } = await requireTenant()
  const name = clean(formData.get('name'))
  const code = nullable(formData.get('code'))
  if (!name) throw new Error('El nombre del fundo/sede es obligatorio.')

  const { error } = await supabase.from('sites').insert({ tenant_id: tenant.id, name, code })
  if (error) throw new Error(error.message)
  revalidatePath('/dashboard/assets')
}

export async function createLocation(formData: FormData) {
  const { supabase, tenant } = await requireTenant()
  const siteId = clean(formData.get('site_id'))
  const name = clean(formData.get('name'))
  if (!siteId || !name) throw new Error('Fundo/sede y nombre son obligatorios.')

  const { error } = await supabase.from('locations').insert({
    tenant_id: tenant.id,
    site_id: siteId,
    parent_location_id: nullable(formData.get('parent_location_id')),
    code: nullable(formData.get('code')),
    name,
    location_type: clean(formData.get('location_type')) || 'area',
  })
  if (error) throw new Error(error.message)
  revalidatePath('/dashboard/assets')
}

export async function createAsset(formData: FormData) {
  const { supabase, tenant } = await requireTenant()
  const code = clean(formData.get('code'))
  const name = clean(formData.get('name'))
  const siteId = clean(formData.get('site_id'))
  if (!code || !name || !siteId) throw new Error('Código, nombre y fundo/sede son obligatorios.')

  const { error } = await supabase.from('assets').insert({
    tenant_id: tenant.id,
    site_id: siteId,
    location_id: nullable(formData.get('location_id')),
    parent_asset_id: nullable(formData.get('parent_asset_id')),
    code,
    name,
    asset_type: nullable(formData.get('asset_type')),
    manufacturer: nullable(formData.get('manufacturer')),
    model: nullable(formData.get('model')),
    criticality: clean(formData.get('criticality')) || 'medium',
  })
  if (error) throw new Error(error.message)
  revalidatePath('/dashboard/assets')
  revalidatePath('/dashboard')
}

export async function updateAssetStatus(formData: FormData) {
  const { supabase, tenant } = await requireTenant()
  const id = clean(formData.get('id'))
  const status = clean(formData.get('status'))
  if (!id || !status) return

  const { error } = await supabase
    .from('assets')
    .update({ status })
    .eq('tenant_id', tenant.id)
    .eq('id', id)

  if (error) throw new Error(error.message)
  revalidatePath('/dashboard/assets')
}

export async function deleteAsset(formData: FormData) {
  const { supabase, tenant } = await requireTenant()
  const id = clean(formData.get('id'))
  if (!id) return

  const { error } = await supabase
    .from('assets')
    .delete()
    .eq('tenant_id', tenant.id)
    .eq('id', id)

  if (error) throw new Error(error.message)
  revalidatePath('/dashboard/assets')
  revalidatePath('/dashboard')
}
