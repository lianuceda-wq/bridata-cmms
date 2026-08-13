'use server'

import { revalidatePath } from 'next/cache'
import { requireTenant } from '@/lib/tenant'

const clean=(value:FormDataEntryValue|null)=>String(value??'').trim()

export async function cancelPurchaseOrder(formData:FormData){
  const {supabase,tenant}=await requireTenant()
  const purchaseOrderId=clean(formData.get('purchase_order_id'))
  const reason=clean(formData.get('reason'))
  if(!purchaseOrderId||!reason) throw new Error('Orden y motivo de cancelación son obligatorios.')

  const {error}=await supabase.rpc('cancel_purchase_order',{
    p_tenant_id:tenant.id,
    p_purchase_order_id:purchaseOrderId,
    p_reason:reason,
  })
  if(error) throw new Error(error.message)
  revalidatePath('/dashboard/inventory')
}
