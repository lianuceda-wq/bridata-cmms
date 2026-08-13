import { requireTenant } from '@/lib/tenant'
import InviteForm from './InviteForm'
import { revokeInvitation, setMemberActive, setMemberRole, updateTenantSettings } from './actions'
import styles from './admin.module.css'

const roleLabels:Record<string,string>={owner:'Owner',admin:'Admin',planner:'Planner',supervisor:'Supervisor',technician:'Técnico',warehouse:'Almacén',viewer:'Consulta'}

export default async function AdminPage(){
  const {supabase,tenant,user,role}=await requireTenant()
  const canAdmin=['owner','admin'].includes(role)
  if(!canAdmin) return <main className="content"><div className="card"><h1>Administración</h1><p className="muted">Tu rol no puede administrar miembros o configuración de empresa.</p></div></main>

  const [{data:members},{data:settings},{data:invitations}] = await Promise.all([
    supabase.from('tenant_members').select('user_id,role,is_active,created_at').eq('tenant_id',tenant.id).order('created_at'),
    supabase.from('tenant_settings').select('*').eq('tenant_id',tenant.id).maybeSingle(),
    supabase.from('tenant_invitations').select('id,email,role,status,expires_at,created_at').eq('tenant_id',tenant.id).order('created_at',{ascending:false}).limit(50),
  ])
  const ids=(members??[]).map(m=>m.user_id)
  const {data:profiles}=ids.length?await supabase.from('profiles').select('id,full_name,email').in('id',ids):{data:[]}
  const profileMap=new Map((profiles??[]).map(p=>[p.id,p]))
  const active=(members??[]).filter(m=>m.is_active).length
  const owners=(members??[]).filter(m=>m.is_active&&m.role==='owner').length
  const pending=(invitations??[]).filter(i=>i.status==='pending'&&new Date(i.expires_at)>new Date())
  const warehouse=(members??[]).filter(m=>m.is_active&&m.role==='warehouse').length

  return <main className="content stack gap-24">
    <div className="header"><div><span className="badge">Administración</span><h1>Empresa y usuarios</h1><p className="muted">{tenant.name} · membresías, roles e identidad operacional.</p></div></div>
    <section className={styles.metrics}><div className={styles.metric}><span>Miembros activos</span><strong>{active}</strong></div><div className={styles.metric}><span>Owners</span><strong>{owners}</strong></div><div className={styles.metric}><span>Invitaciones pendientes</span><strong>{pending.length}</strong></div><div className={styles.metric}><span>Usuarios almacén</span><strong>{warehouse}</strong></div></section>

    <section className={styles.grid}><InviteForm/><form action={updateTenantSettings} className="card stack"><div><strong>Configuración empresa</strong><p className="muted small">Valores globales heredados por los módulos.</p></div><label className={styles.settings}>Zona horaria<input className="input" name="timezone" defaultValue={settings?.timezone??'America/Lima'} required/></label><div className="form-grid"><label className={styles.settings}>Moneda<input className="input" name="default_currency" maxLength={3} defaultValue={settings?.default_currency??'PEN'} required/></label><label className={styles.settings}>Locale<input className="input" name="locale" defaultValue={settings?.locale??'es-PE'} required/></label></div><div className="form-grid"><select className="input" name="measurement_system" defaultValue={settings?.measurement_system??'metric'}><option value="metric">Sistema métrico</option><option value="imperial">Imperial</option></select><select className="input" name="hydraulic_capture_mode" defaultValue={settings?.hydraulic_capture_mode??'manual'}><option value="manual">Hidráulica manual</option><option value="mixed">Mixta</option><option value="automatic">Automática</option></select></div><label className="muted small"><input type="checkbox" name="require_supervisor_validation" defaultChecked={settings?.require_supervisor_validation??true}/> Exigir validación de supervisor cuando aplique</label><button className="button" type="submit">Guardar configuración</button></form></section>

    <section className="card stack"><div className="section-heading"><div><strong>Miembros</strong><p className="muted small">El último owner no puede desactivarse ni degradarse.</p></div></div><div className={styles.members}>{(members??[]).map(member=>{const p=profileMap.get(member.user_id);const self=member.user_id===user.id;return <article className={styles.member} key={member.user_id}><div className={styles.memberName}><strong>{p?.full_name||p?.email||member.user_id}{self?' · tú':''}</strong><span className={styles.meta}>{p?.email||'Sin correo en perfil'}</span></div><span className={styles.role}>{roleLabels[member.role]??member.role}</span><span className={member.is_active?'':'muted'}>{member.is_active?'Activo':'Inactivo'}</span><div>{member.is_active&&<form action={setMemberRole} className="inline-form"><input type="hidden" name="user_id" value={member.user_id}/><select className="input input-compact" name="role" defaultValue={member.role}>{Object.entries(roleLabels).map(([value,label])=><option key={value} value={value}>{label}</option>)}</select><button className="button button-secondary button-compact" type="submit">Rol</button></form>}{!self&&<form action={setMemberActive} style={{marginTop:6}}><input type="hidden" name="user_id" value={member.user_id}/><input type="hidden" name="active" value={member.is_active?'false':'true'}/><button className="button button-secondary button-compact" type="submit">{member.is_active?'Desactivar':'Activar'}</button></form>}</div></article>})}</div></section>

    <section className="card stack"><div className="section-heading"><div><strong>Invitaciones</strong><p className="muted small">El código solo se muestra al crearlo; aquí queda su estado auditable.</p></div></div>{(invitations??[]).length===0?<div className="empty-state"><span className="muted">Sin invitaciones.</span></div>:<div className={styles.members}>{(invitations??[]).map(inv=><article className={styles.pending} key={inv.id}><div><strong>{inv.email}</strong><div className={styles.meta}>Creada {new Date(inv.created_at).toLocaleDateString('es-PE')}</div></div><span className={styles.role}>{roleLabels[inv.role]??inv.role}</span><span className={inv.status==='pending'&&new Date(inv.expires_at)<new Date()?styles.warn:''}>{inv.status==='pending'&&new Date(inv.expires_at)<new Date()?'expirada':inv.status}</span>{inv.status==='pending'&&new Date(inv.expires_at)>new Date()?<form action={revokeInvitation}><input type="hidden" name="invitation_id" value={inv.id}/><button className="button button-secondary button-compact" type="submit">Revocar</button></form>:<span/>}</article>)}</div>}</section>
  </main>
}