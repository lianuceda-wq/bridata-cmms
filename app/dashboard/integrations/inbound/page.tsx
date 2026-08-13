import { requireTenant } from '@/lib/tenant'

export default async function InboundIntegrationsPage(){
  const {supabase,tenant,role}=await requireTenant()
  const canManage=['owner','admin'].includes(role)
  const {data:connections,error}=await supabase
    .from('integration_connections')
    .select('id,name,provider,direction,status,last_success_at,last_error')
    .eq('tenant_id',tenant.id)
    .in('direction',['inbound','bidirectional'])
    .order('name')
  if(error)throw new Error(error.message)

  return <main className="content stack">
    <section className="card">
      <span className="badge">Inbound Ledger</span>
      <h1>API de entrada</h1>
      <p className="muted">Recepción idempotente para GPS, Talgil y proveedores externos. Los eventos se validan y almacenan antes de tocar dominios operativos.</p>
      <p className="small">Endpoint: <code>/api/integrations/inbound/CONNECTION_ID</code> · headers <code>Authorization</code>, <code>X-Bridata-Event-Id</code> y <code>X-Bridata-Event</code>.</p>
    </section>
    <section className="card stack">
      <h2>Conexiones inbound</h2>
      {!canManage&&<p className="muted">Tu rol tiene acceso de consulta.</p>}
      {(connections??[]).length===0?<p className="muted">No hay conexiones inbound configuradas.</p>:(connections??[]).map((item)=><div className="card" style={{padding:12}} key={item.id}><strong>{item.name}</strong> <span className="badge">{item.provider}</span><div className="muted small">{item.direction} · {item.status}</div>{item.last_error&&<div className="small">Último error: {item.last_error}</div>}</div>)}
    </section>
  </main>
}
