'use server'

import { revalidatePath } from 'next/cache'
import { requireTenant } from '@/lib/tenant'

const clean=(value:FormDataEntryValue|null)=>String(value??'').trim()
const nullable=(value:FormDataEntryValue|null)=>clean(value)||null
const numeric=(value:FormDataEntryValue|null)=>{
  const raw=clean(value)
  if(!raw) return null
  const result=Number(raw.replace(',','.'))
  if(!Number.isFinite(result)) throw new Error(`Número inválido: ${raw}`)
  return result
}

export async function createLaborRate(formData:FormData){
  const {supabase,tenant}=await requireTenant()
  const rate=numeric(formData.get('hourly_rate'))
  const validFrom=clean(formData.get('valid_from'))
  if(rate===null||!validFrom) throw new Error('Tarifa y vigencia son obligatorias.')
  const {error}=await supabase.rpc('create_labor_rate_version',{
    p_tenant_id:tenant.id,
    p_user_id:nullable(formData.get('user_id')),
    p_labor_role:nullable(formData.get('labor_role')),
    p_hourly_rate:rate,
    p_currency:(clean(formData.get('currency'))||'PEN').toUpperCase(),
    p_valid_from:validFrom,
    p_notes:nullable(formData.get('notes')),
  })
  if(error) throw new Error(error.message)
  revalidatePath('/dashboard/analytics')
}

export async function createBudget(formData:FormData){
  const {supabase,tenant}=await requireTenant()
  const amount=numeric(formData.get('amount'))
  const code=clean(formData.get('code'))
  const name=clean(formData.get('name'))
  const start=clean(formData.get('period_start'))
  const end=clean(formData.get('period_end'))
  if(amount===null||!code||!name||!start||!end) throw new Error('Completa código, nombre, periodo y monto.')

  const {error}=await supabase.rpc('create_maintenance_budget',{
    p_tenant_id:tenant.id,
    p_code:code,
    p_name:name,
    p_period_start:start,
    p_period_end:end,
    p_currency:(clean(formData.get('currency'))||'PEN').toUpperCase(),
    p_lines:[{
      site_id:nullable(formData.get('site_id'))??'',
      asset_id:nullable(formData.get('asset_id'))??'',
      maintenance_type:nullable(formData.get('maintenance_type'))??'',
      category:clean(formData.get('category'))||'other',
      amount,
    }],
  })
  if(error) throw new Error(error.message)
  revalidatePath('/dashboard/analytics')
}

export async function changeBudgetStatus(formData:FormData){
  const {supabase,tenant}=await requireTenant()
  const budgetId=clean(formData.get('budget_id'))
  const status=clean(formData.get('status'))
  if(!budgetId||!status) throw new Error('Presupuesto o estado inválido.')
  const {error}=await supabase.rpc('change_maintenance_budget_status',{
    p_tenant_id:tenant.id,
    p_budget_id:budgetId,
    p_status:status,
  })
  if(error) throw new Error(error.message)
  revalidatePath('/dashboard/analytics')
}
