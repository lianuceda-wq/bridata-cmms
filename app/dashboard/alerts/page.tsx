import { requireTenant } from '@/lib/tenant'

export default async function AlertsPage(){
  const {supabase,tenant}=await requireTenant()
  const {data,error}=await supabase
    .from('operational_alerts')
    .select('id,alert_key,severity,title,body,state,entity_type,entity_id,first_seen_at,last_seen_at')
    .eq('tenant_id',tenant.id)
    .neq('state','resolved')
    .order('last_seen_at',{ascending:false})
    .limit(100)
  if(error)throw new Error(error.message)

  const alerts=data??[]
  const urgent=alerts.filter((item)=>item.severity==='critical'||item.severity==='high').length
  return <main className="content stack">
    <section className="card">
      <span className="badge">Monitoreo automático</span>
      <h1>Alertas operativas</h1>
      <p className="muted">{alerts.length} abiertas · {urgent} de severidad alta o crítica. Las condiciones resueltas desaparecen automáticamente del listado.</p>
    </section>
    {alerts.length===0?<section className="card"><p className="muted">No hay alertas operativas activas.</p></section>:alerts.map((item)=><article className="card" key={item.id}>
      <div style={{display:'flex',justifyContent:'space-between',gap:10,flexWrap:'wrap'}}><div><span className="badge">{item.severity}</span><h3>{item.title}</h3></div><span className="muted small">{new Date(item.last_seen_at).toLocaleString('es-PE')}</span></div>
      <p>{item.body}</p>
      <div className="muted small">{item.alert_key} · {item.state} · {item.entity_type}</div>
    </article>)}
  </main>
}
