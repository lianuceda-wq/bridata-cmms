'use server'

import { revalidatePath } from 'next/cache'
import { requireTenant } from '@/lib/tenant'

const clean=(value:FormDataEntryValue|null)=>String(value??'').trim()

export async function createBudgetAdvanced(formData:FormData){
  const {supabase,tenant}=await requireTenant()
  const code=clean(formData.get('code'))
  const name=clean(formData.get('name'))
  const periodStart=clean(formData.get('period_start'))
  const periodEnd=clean(formData.get('period_end'))
  const currency=(clean(formData.get('currency'))||'PEN').toUpperCase()
  const linesRaw=clean(formData.get('lines_json'))
  if(!code||!name||!periodStart||!periodEnd||!linesRaw) throw new Error('Datos de presupuesto incompletos.')

  let lines:unknown
  try{ lines=JSON.parse(linesRaw) }catch{ throw new Error('No se pudieron interpretar las líneas del presupuesto.') }
  if(!Array.isArray(lines)||lines.length===0) throw new Error('Agrega al menos una línea presupuestal.')

  const {error}=await supabase.rpc('create_maintenance_budget',{
    p_tenant_id:tenant.id,
    p_code:code,
    p_name:name,
    p_period_start:periodStart,
    p_period_end:periodEnd,
    p_currency:currency,
    p_lines:lines,
  })
  if(error) throw new Error(error.message)
  revalidatePath('/dashboard/analytics')
}
