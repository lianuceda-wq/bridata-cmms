import Link from 'next/link'
import { notFound } from 'next/navigation'
import { requireTenant } from '@/lib/tenant'
import {
  convertFindingToFailure,
  transitionInspectionRun,
  updateInspectionItem,
  uploadInspectionEvidence,
} from '../actions'
import styles from './detail.module.css'

function date(value:string|null){return value?new Intl.DateTimeFormat('es-PE',{timeZone:'America/Lima',dateStyle:'medium',timeStyle:'short'}).format(new Date(value)):'—'}
function resultClass(result:string){return result==='compliant'?styles.compliant:result==='nonconforming'?styles.nonconforming:styles.pending}

export default async function InspectionDetailPage({params}:{params:Promise<{id:string}>}){
  const {id}=await params
  const {supabase,tenant,user,role}=await requireTenant()
  const {data:run}=await supabase.from('inspection_runs').select('*').eq('tenant_id',tenant.id).eq('id',id).maybeSingle()
  if(!run) notFound()

  const [{data:template},{data:items},{data:evidence},{data:findings},{data:asset},{data:location},{data:workOrder},{data:units}] = await Promise.all([
    supabase.from('inspection_templates').select('id,code,name,description,revision').eq('tenant_id',tenant.id).eq('id',run.template_id).maybeSingle(),
    supabase.from('inspection_run_items').select('*').eq('tenant_id',tenant.id).eq('inspection_run_id',id).order('sequence'),
    supabase.from('inspection_evidence').select('*').eq('tenant_id',tenant.id).eq('inspection_run_id',id).order('created_at'),
    supabase.from('inspection_findings').select('*').eq('tenant_id',tenant.id).eq('inspection_run_id',id).order('created_at',{ascending:false}),
    run.asset_id?supabase.from('assets').select('id,code,name').eq('tenant_id',tenant.id).eq('id',run.asset_id).maybeSingle():Promise.resolve({data:null}),
    run.location_id?supabase.from('locations').select('id,code,name,location_type').eq('tenant_id',tenant.id).eq('id',run.location_id).maybeSingle():Promise.resolve({data:null}),
    run.work_order_id?supabase.from('work_orders').select('id,code,title,status').eq('tenant_id',tenant.id).eq('id',run.work_order_id).maybeSingle():Promise.resolve({data:null}),
    supabase.from('measurement_units').select('id,symbol').eq('is_active',true),
  ])

  const unitMap=new Map((units??[]).map(u=>[u.id,u.symbol]))
  const manager=['owner','admin','planner','supervisor'].includes(role)
  const canExecute=manager||run.assigned_to===user.id
  const mutable=canExecute&&['assigned','in_progress'].includes(run.status)
  const evidenceByItem=new Map<string,typeof evidence>()
  for(const item of evidence??[]){if(!item.inspection_run_item_id)continue;const rows=evidenceByItem.get(item.inspection_run_item_id)??[];rows.push(item);evidenceByItem.set(item.inspection_run_item_id,rows)}
  const signed=new Map<string,string>()
  for(const item of evidence??[]){const {data}=await supabase.storage.from('inspection-evidence').createSignedUrl(item.storage_path,60*20);if(data?.signedUrl)signed.set(item.id,data.signedUrl)}
  const total=(items??[]).length
  const compliant=(items??[]).filter(i=>i.result_status==='compliant').length
  const nonconforming=(items??[]).filter(i=>i.result_status==='nonconforming').length
  const evaluated=(items??[]).filter(i=>['compliant','nonconforming'].includes(i.result_status)).length
  const compliance=evaluated?100*compliant/evaluated:null

  return <main className="content">
    <div className={styles.workspace}>
      <section className={styles.hero}>
        <div><Link href="/dashboard/inspections" className="muted small">← Inspecciones</Link><h1>{run.code}</h1><p className="muted">{template?.code} r{run.template_revision} · {template?.name}</p><div className={styles.badges}><span className={styles.badge}>{run.status}</span>{asset&&<span className={styles.badge}>{asset.code} · {asset.name}</span>}{location&&<span className={styles.badge}>{location.name}</span>}{workOrder&&<Link className={styles.badge} href={`/dashboard/work-orders/${workOrder.id}`}>{workOrder.code} · {workOrder.status}</Link>}</div></div>
        <div className={styles.actions}>
          {mutable&&run.status==='assigned'&&<form action={transitionInspectionRun}><input type="hidden" name="run_id" value={id}/><input type="hidden" name="status" value="in_progress"/><button className="button" type="submit">Iniciar</button></form>}
          {mutable&&<form action={transitionInspectionRun}><input type="hidden" name="run_id" value={id}/><input type="hidden" name="status" value="completed"/><button className="button" type="submit">Completar</button></form>}
          {manager&&run.status==='completed'&&<form action={transitionInspectionRun}><input type="hidden" name="run_id" value={id}/><input type="hidden" name="status" value="validated"/><button className="button" type="submit">Validar</button></form>}
        </div>
      </section>

      <section className={styles.layout}>
        <div className={styles.panel}>
          <div className={styles.panelHeader}><div><strong>Checklist de inspección</strong><div className={styles.meta}>{compliant}/{total} conformes · {nonconforming} no conformes · {compliance===null?'—':`${compliance.toFixed(1)}%`}</div></div></div>
          <div className={styles.panelBody}>
            {(items??[]).map(item=>{
              const itemEvidence=evidenceByItem.get(item.id)??[]
              const options:string[]=Array.isArray(item.options)?item.options.map((option:unknown)=>String(option)):[]
              return <article className={styles.item} key={item.id}>
                <div className={styles.itemHead}><div className={styles.itemTitle}><span className={styles.index}>{item.sequence}</span><div><strong>{item.title}</strong><div className={styles.meta}>{item.instructions||'Sin instrucción'}{item.mandatory?' · obligatorio':''}{item.requires_evidence?' · exige evidencia':''}</div></div></div><span className={`${styles.result} ${resultClass(item.result_status)}`}>{item.result_status}</span></div>
                {mutable&&<form action={updateInspectionItem} className={styles.response}>
                  <input type="hidden" name="run_id" value={id}/><input type="hidden" name="item_id" value={item.id}/><input type="hidden" name="response_type" value={item.response_type}/>
                  {item.response_type==='boolean'&&<select className="input" name="response_boolean" defaultValue={item.response_boolean===true?'true':item.response_boolean===false?'false':''} required={item.mandatory}><option value="">Seleccionar</option><option value="true">Sí</option><option value="false">No</option></select>}
                  {item.response_type==='number'&&<><input className="input" name="response_number" type="number" step="any" defaultValue={item.response_number??''} placeholder={`Valor${item.unit_id?` (${unitMap.get(item.unit_id)??''})`:''}`} required={item.mandatory}/><div className={styles.meta}>Rango: {item.min_value??'—'} a {item.max_value??'—'} {item.unit_id?unitMap.get(item.unit_id):''}</div></>}
                  {item.response_type==='choice'&&<select className="input" name="response_text" defaultValue={item.response_text??''} required={item.mandatory}><option value="">Seleccionar</option>{options.map((option:string)=><option key={option} value={option}>{option}</option>)}</select>}
                  {['text','photo'].includes(item.response_type)&&<><input className="input" name="response_text" defaultValue={item.response_text??''} placeholder="Respuesta / comentario"/><select className="input" name="result_status" defaultValue={item.result_status==='pending'?'compliant':item.result_status}><option value="compliant">Conforme</option><option value="nonconforming">No conforme</option><option value="not_applicable">No aplica</option></select>}
                  <textarea className={`input ${styles.full}`} name="notes" defaultValue={item.notes??''} rows={2} placeholder="Observación técnica"/>
                  <button className="button button-secondary" type="submit">Guardar respuesta</button>
                </form>}
                {itemEvidence.length>0&&<div className={styles.evidence}>{itemEvidence.map(ev=>signed.get(ev.id)?<a key={ev.id} href={signed.get(ev.id)} target="_blank" rel="noreferrer">{ev.file_name||'Evidencia'}</a>:null)}</div>}
                {mutable&&<form action={uploadInspectionEvidence} className={styles.upload} encType="multipart/form-data"><input type="hidden" name="run_id" value={id}/><input type="hidden" name="item_id" value={item.id}/><input className="input" name="file" type="file" accept="image/jpeg,image/png,image/webp,application/pdf" required/><input className="input" name="caption" placeholder="Descripción evidencia"/><button className="button button-secondary button-compact" type="submit">Adjuntar</button></form>}
              </article>
            })}
          </div>
        </div>

        <aside className={styles.side}>
          <section className={styles.panel}><div className={styles.panelHeader}><strong>Resumen</strong></div><div className={styles.panelBody}><div className={styles.timeline}><span className={styles.meta}>Programada</span><strong>{date(run.scheduled_at??run.created_at)}</strong><span className={styles.meta}>Iniciada</span><strong>{date(run.started_at)}</strong><span className={styles.meta}>Completada</span><strong>{date(run.completed_at)}</strong><span className={styles.meta}>Validada</span><strong>{date(run.validated_at)}</strong></div></div></section>

          <section className={styles.panel}><div className={styles.panelHeader}><strong>Hallazgos</strong><span className={nonconforming?styles.danger:styles.good}>{(findings??[]).length}</span></div><div className={styles.panelBody}>{(findings??[]).length===0?<span className="muted small">Se generan al completar una inspección con no conformidades.</span>:(findings??[]).map(f=><div className={styles.finding} key={f.id}><div className={styles.findingHead}><strong>{f.title}</strong><span className={['high','critical'].includes(f.severity)?styles.danger:styles.warn}>{f.severity}</span></div><span className={styles.meta}>{f.status} · {f.description||'Sin detalle adicional'}</span>{f.failure_event_id&&<Link href="/dashboard/failures">Ver falla vinculada →</Link>}{f.work_order_id&&<Link href={`/dashboard/work-orders/${f.work_order_id}`}>Ver OT correctiva →</Link>}{manager&&f.status==='open'&&asset&&<form action={convertFindingToFailure}><input type="hidden" name="run_id" value={id}/><input type="hidden" name="finding_id" value={f.id}/><input type="hidden" name="create_work_order" value="true"/><button className="button button-secondary button-compact" type="submit">Crear falla + OT</button></form>}</div>)}</div></section>

          {manager&&['assigned','in_progress'].includes(run.status)&&<section className={styles.panel}><div className={styles.panelHeader}><strong>Cancelar inspección</strong></div><div className={styles.panelBody}><form action={transitionInspectionRun} className="stack"><input type="hidden" name="run_id" value={id}/><input type="hidden" name="status" value="cancelled"/><input className="input" name="cancellation_reason" placeholder="Motivo obligatorio" required/><button className="button button-danger" type="submit">Cancelar</button></form></div></section>}
        </aside>
      </section>
    </div>
  </main>
}