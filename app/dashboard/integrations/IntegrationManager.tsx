'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'

const EVENTS=[
 'work_order.created','work_order.status_changed','failure.created','failure.status_changed',
 'hydraulic.validated','inventory.movement','inspection.completed','inspection.validated',
]

interface Connection {id:string;name:string;provider:string;direction:string;status:string;base_url:string|null;last_success_at:string|null;last_error:string|null}

export default function IntegrationManager({tenantId,connections}:{tenantId:string;connections:Connection[]}){
 const router=useRouter();const [message,setMessage]=useState('');const [busy,setBusy]=useState(false)
 const [name,setName]=useState('');const [provider,setProvider]=useState('generic_webhook');const [direction,setDirection]=useState('outbound');const [baseUrl,setBaseUrl]=useState('');const [secret,setSecret]=useState('')
 const [connectionId,setConnectionId]=useState(connections.find((item)=>item.provider==='generic_webhook')?.id??'');const [eventKey,setEventKey]=useState(EVENTS[0]);const [targetUrl,setTargetUrl]=useState('');const [signingSecret,setSigningSecret]=useState('')

 async function createConnection(){
  if(!name.trim())return setMessage('Ingresa un nombre de conexión.');setBusy(true);setMessage('')
  const supabase=createClient();const {error}=await supabase.rpc('create_integration_connection',{
   p_tenant_id:tenantId,p_provider:provider,p_name:name.trim(),p_direction:direction,p_base_url:baseUrl||null,p_config:{},p_secret:secret||null,
  });setBusy(false);if(error)return setMessage(error.message);setMessage('Conexión creada en borrador.');setName('');setSecret('');router.refresh()
 }
 async function changeStatus(id:string,status:string){setBusy(true);const supabase=createClient();const {error}=await supabase.rpc('set_integration_connection_status',{p_tenant_id:tenantId,p_connection_id:id,p_status:status});setBusy(false);setMessage(error?.message??`Conexión ${status}.`);router.refresh()}
 async function addSubscription(){
  if(!connectionId||!targetUrl.startsWith('https://'))return setMessage('Selecciona conexión y URL HTTPS.');setBusy(true);setMessage('')
  const supabase=createClient();const {error}=await supabase.rpc('create_webhook_subscription',{
   p_tenant_id:tenantId,p_connection_id:connectionId,p_event_key:eventKey,p_target_url:targetUrl,p_signing_secret:signingSecret||null,p_max_attempts:8,
  });setBusy(false);if(error)return setMessage(error.message);setMessage('Suscripción webhook creada.');setTargetUrl('');setSigningSecret('');router.refresh()
 }
 return <div className="stack">
  <section className="card stack"><div><span className="badge">Vault</span><h2>Nueva conexión</h2><p className="muted small">Credenciales sensibles se almacenan en Supabase Vault, no en tablas operativas.</p></div>
   <div style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(180px,1fr))',gap:10}}>
    <input className="input" placeholder="Nombre" value={name} onChange={(e)=>setName(e.target.value)}/>
    <select className="input" value={provider} onChange={(e)=>setProvider(e.target.value)}><option value="generic_webhook">Webhook genérico</option><option value="sap">SAP</option><option value="talgil_dream2">Talgil Dream 2</option><option value="gps">GPS</option><option value="iot">IoT</option><option value="power_bi">Power BI</option><option value="other">Otro</option></select>
    <select className="input" value={direction} onChange={(e)=>setDirection(e.target.value)}><option value="outbound">Salida</option><option value="inbound">Entrada</option><option value="bidirectional">Bidireccional</option></select>
    <input className="input" placeholder="Base URL (opcional)" value={baseUrl} onChange={(e)=>setBaseUrl(e.target.value)}/>
    <input className="input" type="password" placeholder="Credencial/API token (opcional)" value={secret} onChange={(e)=>setSecret(e.target.value)}/>
   </div><button className="button" disabled={busy} type="button" onClick={createConnection}>Crear conexión</button>
  </section>
  <section className="card stack"><h2>Conexiones</h2>{connections.length===0?<p className="muted">No hay conexiones.</p>:connections.map((item)=><div key={item.id} className="card" style={{padding:12}}><strong>{item.name}</strong> <span className="badge">{item.provider}</span><div className="muted small">{item.direction} · {item.status}{item.last_success_at?` · última entrega ${new Date(item.last_success_at).toLocaleString('es-PE')}`:''}</div>{item.last_error&&<div className="small">Último error: {item.last_error}</div>}<div style={{display:'flex',gap:6,marginTop:8}}>{item.status!=='active'&&<button className="button button-compact" onClick={()=>changeStatus(item.id,'active')} disabled={busy}>Activar</button>}{item.status==='active'&&<button className="button button-secondary button-compact" onClick={()=>changeStatus(item.id,'paused')} disabled={busy}>Pausar</button>}<button className="button button-secondary button-compact" onClick={()=>changeStatus(item.id,'disabled')} disabled={busy}>Deshabilitar</button></div></div>)}
  </section>
  <section className="card stack"><h2>Suscripción webhook</h2><select className="input" value={connectionId} onChange={(e)=>setConnectionId(e.target.value)}><option value="">Selecciona conexión webhook</option>{connections.filter((item)=>item.provider==='generic_webhook').map((item)=><option key={item.id} value={item.id}>{item.name}</option>)}</select><select className="input" value={eventKey} onChange={(e)=>setEventKey(e.target.value)}>{EVENTS.map((event)=><option key={event} value={event}>{event}</option>)}</select><input className="input" placeholder="https://sistema.destino/webhook" value={targetUrl} onChange={(e)=>setTargetUrl(e.target.value)}/><input className="input" type="password" placeholder="Secreto HMAC compartido (opcional)" value={signingSecret} onChange={(e)=>setSigningSecret(e.target.value)}/><button className="button" type="button" disabled={busy} onClick={addSubscription}>Crear suscripción</button></section>
  {message&&<div className="card small">{message}</div>}
 </div>
}
