import { requireTenant } from '@/lib/tenant'

type Recipient={notification_id:string;read_at:string|null;dismissed_at:string|null}
type Notice={id:string;severity:string;title:string;body:string;entity_type:string|null;entity_id:string|null;created_at:string}

export default async function NotificationsPage(){
  const {supabase,tenant,user}=await requireTenant()
  const {data:recipientRows,error:recipientError}=await supabase
    .from('notification_recipients')
    .select('notification_id,read_at,dismissed_at')
    .eq('tenant_id',tenant.id)
    .eq('user_id',user.id)
    .is('dismissed_at',null)
    .order('created_at',{ascending:false})
    .limit(100)
  if(recipientError)throw new Error(recipientError.message)

  const recipients=(recipientRows??[]) as Recipient[]
  const ids=recipients.map((item)=>item.notification_id)
  let notices:Notice[]=[]
  if(ids.length){
    const {data,error}=await supabase.from('notifications').select('id,severity,title,body,entity_type,entity_id,created_at').eq('tenant_id',tenant.id).in('id',ids).order('created_at',{ascending:false})
    if(error)throw new Error(error.message)
    notices=(data??[]) as Notice[]
  }
  const state=new Map(recipients.map((item)=>[item.notification_id,item]))
  const unread=notices.filter((item)=>!state.get(item.id)?.read_at).length

  return <main className="content stack">
    <section className="card">
      <span className="badge">Centro de notificaciones</span>
      <h1>Notificaciones</h1>
      <p className="muted">{unread} sin leer · {notices.length} activas</p>
    </section>
    {notices.length===0?<section className="card"><p className="muted">No tienes notificaciones pendientes.</p></section>:notices.map((item)=><article className="card" key={item.id} style={{opacity:state.get(item.id)?.read_at?0.76:1}}>
      <div style={{display:'flex',justifyContent:'space-between',gap:10,alignItems:'flex-start',flexWrap:'wrap'}}>
        <div><span className="badge">{item.severity}</span><h3>{item.title}</h3></div>
        <span className="muted small">{new Date(item.created_at).toLocaleString('es-PE')}</span>
      </div>
      <p>{item.body}</p>
      {item.entity_type&&<div className="muted small">{item.entity_type}{item.entity_id?` · ${item.entity_id}`:''}</div>}
    </article>)}
  </main>
}
