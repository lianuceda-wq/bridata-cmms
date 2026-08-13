import { requireTenant } from '@/lib/tenant'
import { cancelPurchaseOrder } from './purchase-actions'
import styles from './inventory.module.css'

export default async function PurchaseCancellationPanel(){
  const {supabase,tenant,role}=await requireTenant()
  if(!['owner','admin','planner','supervisor','warehouse'].includes(role)) return null

  const {data:orders}=await supabase.from('purchase_orders')
    .select('id,code,status,currency,expected_at')
    .eq('tenant_id',tenant.id)
    .in('status',['ordered','partial','approved','draft'])
    .order('created_at',{ascending:false})
    .limit(30)

  if(!(orders??[]).length) return null

  return <section className="card stack">
    <div><strong>Cancelar orden de compra</strong><p className="muted small">La cancelación conserva el histórico y exige un motivo. Una OC totalmente recibida no puede cancelarse.</p></div>
    <form action={cancelPurchaseOrder} className="inline-form">
      <select className="input" name="purchase_order_id" required defaultValue="">
        <option value="" disabled>Selecciona OC</option>
        {(orders??[]).map(order=><option key={order.id} value={order.id}>{order.code} · {order.status}</option>)}
      </select>
      <input className="input" name="reason" placeholder="Motivo de cancelación" required/>
      <button className="button button-danger" type="submit">Cancelar OC</button>
    </form>
  </section>
}
