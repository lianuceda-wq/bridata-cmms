import Link from 'next/link'
import { requireTenant } from '@/lib/tenant'
import InspectionTemplateForm from './InspectionTemplateForm'
import {
  changeInspectionTemplateStatus,
  createManualInspectionRun,
  linkTemplateToRoutine,
} from './actions'
import styles from './inspections.module.css'

function date(value:string|null){
  return value?new Intl.DateTimeFormat('es-PE',{timeZone:'America/Lima',dateStyle:'medium',timeStyle:'short'}).format(new Date(value)):'—'
}

export default async function InspectionsPage(){
  const {supabase,tenant,user,role}=await requireTenant()
  const canManage=['owner','admin','planner','supervisor'].includes(role)
  const canPlan=['owner','admin','planner'].includes(role)

  const [
    {data:templates},{data:templateItems},{data:runs},{data:kpis},{data:findings},
    {data:assets},{data:locations},{data:units},{data:members},{data:routines},
  ]=await Promise.all([
    supabase.from('inspection_templates').select('id,code,name,description,revision,status,created_at').eq('tenant_id',tenant.id).order('created_at',{ascending:false}).limit(80),
    supabase.from('inspection_template_items').select('id,template_id').eq('tenant_id',tenant.id),
    supabase.from('inspection_runs').select('id,code,template_id,work_order_id,asset_id,location_id,status,assigned_to,scheduled_at,started_at,completed_at,created_at').eq('tenant_id',tenant.id).order('created_at',{ascending:false}).limit(120),
    supabase.from('inspection_run_kpis').select('*').eq('tenant_id',tenant.id),
    supabase.from('inspection_findings').select('id,inspection_run_id,severity,status,title,failure_event_id,work_order_id,created_at').eq('tenant_id',tenant.id).order('created_at',{ascending:false}).limit(100),
    supabase.from('assets').select('id,code,name,location_id,site_id').eq('tenant_id',tenant.id).eq('is_active',true).order('code'),
    supabase.from('locations').select('id,code,name,location_type,site_id').eq('tenant_id',tenant.id).order('name'),
    supabase.from('measurement_units').select('id,code,name,symbol').eq('is_active',true).order('name'),
    supabase.from('tenant_members').select('user_id,role,is_active').eq('tenant_id',tenant.id).eq('is_active',true),
    supabase.from('maintenance_routines').select('id,code,name,maintenance_type,inspection_template_id,active').eq('tenant_id',tenant.id).eq('maintenance_type','inspection').eq('active',true).order('code'),
  ])

  const memberIds=(members??[]).map(m=>m.user_id)
  const {data:profiles}=memberIds.length?await supabase.from('profiles').select('id,full_name,email').in('id',memberIds):{data:[]}
  const profileMap=new Map((profiles??[]).map(p=>[p.id,p]))
  const templateMap=new Map((templates??[]).map(t=>[t.id,t]))
  const assetMap=new Map((assets??[]).map(a=>[a.id,a]))
  const locationMap=new Map((locations??[]).map(l=>[l.id,l]))
  const kpiMap=new Map((kpis??[]).map(k=>[k.inspection_run_id,k]))
  const itemCount=new Map<string,number>()
  for(const item of templateItems??[]) itemCount.set(item.template_id,(itemCount.get(item.template_id)??0)+1)

  const activeRuns=(runs??[]).filter(r=>['assigned','in_progress'].includes(r.status)).length
  const completed=(runs??[]).filter(r=>['completed','validated'].includes(r.status)).length
  const openFindings=(findings??[]).filter(f=>f.status==='open').length
  const nonConforming=(kpis??[]).reduce((n,k)=>n+Number(k.nonconforming_items??0),0)
  const validatedKpis=(runs??[]).filter(r=>r.status==='validated').map(r=>kpiMap.get(r.id)).filter(Boolean)
  const compliance=validatedKpis.length?validatedKpis.reduce((s,k)=>s+Number(k?.compliance_percent??0),0)/validatedKpis.length:null
  const activeTemplates=(templates??[]).filter(t=>t.status==='active')
  const staff=(members??[]).filter(m=>['owner','admin','planner','supervisor','technician'].includes(m.role))

  return <main className="content stack gap-24">
    <section className={styles.hero}>
      <div><span className="badge">Inspecciones</span><h1>Inspección y hallazgos</h1><p className="muted">{tenant.name} · plantilla → ejecución → no conformidad → falla/OT.</p></div>
      <div className={styles.heroActions}><Link className="button button-secondary" href="/dashboard/failures">Fallas</Link><Link className="button button-secondary" href="/dashboard/plans">Planes</Link></div>
    </section>

    <section className={styles.metrics}>
      <div className={styles.metric}><span>En curso / asignadas</span><strong>{activeRuns}</strong></div>
      <div className={styles.metric}><span>Completadas / validadas</span><strong>{completed}</strong></div>
      <div className={styles.metric}><span>Hallazgos abiertos</span><strong className={openFindings?styles.warn:undefined}>{openFindings}</strong></div>
      <div className={styles.metric}><span>No conformidades</span><strong className={nonConforming?styles.danger:undefined}>{nonConforming}</strong></div>
      <div className={styles.metric}><span>Cumplimiento validado</span><strong>{compliance===null?'—':`${compliance.toFixed(1)}%`}</strong></div>
    </section>

    <section className="grid grid-2">
      {canManage&&<InspectionTemplateForm units={units??[]}/>} 
      <form action={createManualInspectionRun} className="card stack">
        <div><strong>Nueva inspección</strong><p className="muted small">Ejecución manual. Para recurrencia, vincula la plantilla a una rutina de inspección del plan.</p></div>
        <select className="input" name="template_id" required defaultValue=""><option value="" disabled>Plantilla activa</option>{activeTemplates.map(t=><option key={t.id} value={t.id}>{t.code} r{t.revision} · {t.name}</option>)}</select>
        <select className="input" name="asset_id" defaultValue=""><option value="">Activo (opcional si eliges ubicación)</option>{(assets??[]).map(a=><option key={a.id} value={a.id}>{a.code} · {a.name}</option>)}</select>
        <select className="input" name="location_id" defaultValue=""><option value="">Ubicación (opcional si eliges activo)</option>{(locations??[]).map(l=><option key={l.id} value={l.id}>{l.code?`${l.code} · `:''}{l.name} · {l.location_type}</option>)}</select>
        {role==='technician'?<input type="hidden" name="assigned_to" value={user.id}/>:<select className="input" name="assigned_to" defaultValue=""><option value="">Sin responsable todavía</option>{staff.map(member=>{const p=profileMap.get(member.user_id);return <option key={member.user_id} value={member.user_id}>{p?.full_name||p?.email||member.user_id} · {member.role}</option>})}</select>}
        <label className="muted small">Programada<input className="input" type="datetime-local" name="scheduled_at"/></label>
        <button className="button" type="submit">Crear inspección</button>
      </form>
    </section>

    {canPlan&&(routines??[]).length>0&&activeTemplates.length>0&&<section className="card stack">
      <div><strong>Recurrencia desde planes</strong><p className="muted small">No existe un scheduler paralelo: la rutina de mantenimiento genera la OT y la inspección snapshot automáticamente.</p></div>
      <form action={linkTemplateToRoutine} className={styles.linkForm}>
        <select className="input" name="routine_id" required defaultValue=""><option value="" disabled>Rutina tipo inspección</option>{(routines??[]).map(r=><option key={r.id} value={r.id}>{r.code} · {r.name}{r.inspection_template_id?' · ya vinculada':''}</option>)}</select>
        <select className="input" name="template_id" required defaultValue=""><option value="" disabled>Plantilla activa</option>{activeTemplates.map(t=><option key={t.id} value={t.id}>{t.code} r{t.revision} · {t.name}</option>)}</select>
        <button className="button button-secondary" type="submit">Vincular</button>
      </form>
    </section>}

    <section className="card stack">
      <div className="section-heading"><div><strong>Plantillas</strong><p className="muted small">Las revisiones antiguas se conservan; cada ejecución copia un snapshot.</p></div></div>
      {(templates??[]).length===0?<div className={styles.empty}>Aún no existen plantillas.</div>:<div className={styles.templateList}>{(templates??[]).map(t=><div className={styles.templateCard} key={t.id}><div><strong>{t.code} · {t.name}</strong><span className={styles.templateMeta}>Revisión {t.revision} · {itemCount.get(t.id)??0} puntos · creada {date(t.created_at)}</span><span className="muted small">{t.description||'Sin descripción'}</span></div><div className="stack"><span className={styles.status}>{t.status}</span>{canManage&&t.status==='draft'&&<form action={changeInspectionTemplateStatus}><input type="hidden" name="template_id" value={t.id}/><input type="hidden" name="status" value="active"/><button className="button button-secondary button-compact" type="submit">Activar</button></form>}{canManage&&t.status==='active'&&<form action={changeInspectionTemplateStatus}><input type="hidden" name="template_id" value={t.id}/><input type="hidden" name="status" value="retired"/><button className="button button-secondary button-compact" type="submit">Retirar</button></form>}</div></div>)}</div>}
    </section>

    <section className="card stack">
      <div className="section-heading"><div><strong>Ejecuciones</strong><p className="muted small">Últimas {(runs??[]).length} inspecciones visibles.</p></div></div>
      {(runs??[]).length===0?<div className={styles.empty}>Sin inspecciones.</div>:<div className={styles.runGrid}>{(runs??[]).map(run=>{const t=templateMap.get(run.template_id),a=run.asset_id?assetMap.get(run.asset_id):null,l=run.location_id?locationMap.get(run.location_id):null,k=kpiMap.get(run.id),p=run.assigned_to?profileMap.get(run.assigned_to):null;return <Link href={`/dashboard/inspections/${run.id}`} key={run.id} className={styles.runCard}><div className={styles.runTitle}><span className={styles.runCode}>{run.code}</span><strong>{t?.name??'Inspección'}</strong><span className={styles.runMeta}>{a?`${a.code} · ${a.name}`:l?.name??'Sin alcance'}{run.work_order_id?' · vinculada a OT':''}</span></div><div><span className={styles.runMeta}>Estado</span><br/><span className={styles.status}>{run.status}</span></div><div><span className={styles.runMeta}>Responsable</span><br/>{p?.full_name||p?.email||'Sin asignar'}</div><div><span className={styles.runMeta}>Programada</span><br/>{date(run.scheduled_at??run.created_at)}</div><div><span className={styles.runMeta}>Resultado</span><br/><strong className={Number(k?.nonconforming_items??0)>0?styles.danger:styles.good}>{k?.compliance_percent===null||k?.compliance_percent===undefined?'—':`${Number(k.compliance_percent).toFixed(1)}%`}</strong></div></Link>})}</div>}
    </section>

    <section className="card stack">
      <div className="section-heading"><div><strong>Hallazgos recientes</strong><p className="muted small">No conformidades generadas automáticamente al completar inspecciones.</p></div></div>
      {(findings??[]).length===0?<div className={styles.empty}>Sin hallazgos.</div>:<div className={styles.findingList}>{(findings??[]).slice(0,30).map(f=><div className={styles.finding} key={f.id}><div><strong>{f.title}</strong><div className="muted small">{f.status} · inspección {runs?.find(r=>r.id===f.inspection_run_id)?.code??''}</div></div><span className={`${styles.severity} ${['high','critical'].includes(f.severity)?styles.danger:styles.warn}`}>{f.severity}</span></div>)}</div>}
    </section>
  </main>
}