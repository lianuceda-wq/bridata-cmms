import { requireTenant } from '@/lib/tenant'
import DocumentLinkForm from './DocumentLinkForm'
import { archiveDocument, createDocumentType, createDocumentWithFile, uploadDocumentVersion } from './actions'
import styles from './documents.module.css'

function date(value:string|null){return value?new Intl.DateTimeFormat('es-PE',{timeZone:'America/Lima',dateStyle:'medium'}).format(new Date(value)):'—'}
function size(value:number|null){if(value===null)return '—';if(value<1024)return `${value} B`;if(value<1024*1024)return `${(value/1024).toFixed(1)} KB`;return `${(value/1024/1024).toFixed(1)} MB`}

export default async function DocumentsPage(){
  const {supabase,tenant,role}=await requireTenant()
  const canManage=['owner','admin','planner','supervisor'].includes(role)
  const [{data:types},{data:docs},{data:versions},{data:links},{data:workers},{data:assets},{data:orders},{data:failures},{data:inspections},{data:materials},{data:plans},{data:suppliers},{data:purchaseOrders}] = await Promise.all([
    supabase.from('document_types').select('*').eq('tenant_id',tenant.id).eq('is_active',true).order('name'),
    supabase.from('document_registry').select('*').eq('tenant_id',tenant.id).order('updated_at',{ascending:false}).limit(150),
    supabase.from('document_versions').select('*').eq('tenant_id',tenant.id).order('created_at',{ascending:false}).limit(300),
    supabase.from('document_links').select('*').eq('tenant_id',tenant.id).order('created_at',{ascending:false}).limit(500),
    supabase.from('workers').select('id,employee_code,full_name').eq('tenant_id',tenant.id).eq('status','active').order('employee_code'),
    supabase.from('assets').select('id,code,name').eq('tenant_id',tenant.id).eq('is_active',true).order('code'),
    supabase.from('work_orders').select('id,code,title').eq('tenant_id',tenant.id).order('created_at',{ascending:false}).limit(100),
    supabase.from('failure_events').select('id,code,title').eq('tenant_id',tenant.id).order('occurred_at',{ascending:false}).limit(100),
    supabase.from('inspection_runs').select('id,code').eq('tenant_id',tenant.id).order('created_at',{ascending:false}).limit(100),
    supabase.from('materials').select('id,code,name').eq('tenant_id',tenant.id).eq('is_active',true).order('code'),
    supabase.from('maintenance_plans').select('id,code,name').eq('tenant_id',tenant.id).order('code'),
    supabase.from('suppliers').select('id,code,name').eq('tenant_id',tenant.id).eq('is_active',true).order('code'),
    supabase.from('purchase_orders').select('id,code,status').eq('tenant_id',tenant.id).order('created_at',{ascending:false}).limit(100),
  ])
  const documentRows=docs??[],versionRows=versions??[],linkRows=links??[]
  const active=documentRows.filter(d=>d.status==='active').length
  const archived=documentRows.filter(d=>d.status==='archived').length
  const withFile=documentRows.filter(d=>Number(d.current_version)>0).length
  const totalVersions=versionRows.length
  const workerMap=new Map((workers??[]).map(w=>[w.id,w]))
  const currentSigned=new Map<string,string>()
  for(const doc of documentRows){if(!doc.storage_path)continue;const {data}=await supabase.storage.from('documents').createSignedUrl(doc.storage_path,60*20);if(data?.signedUrl)currentSigned.set(doc.id,data.signedUrl)}
  const groups={
    asset:(assets??[]).map(x=>({id:x.id,label:`${x.code} · ${x.name}`})),
    work_order:(orders??[]).map(x=>({id:x.id,label:`${x.code} · ${x.title}`})),
    failure:(failures??[]).map(x=>({id:x.id,label:`${x.code} · ${x.title}`})),
    inspection:(inspections??[]).map(x=>({id:x.id,label:x.code})),
    material:(materials??[]).map(x=>({id:x.id,label:`${x.code} · ${x.name}`})),
    worker:(workers??[]).map(x=>({id:x.id,label:`${x.employee_code} · ${x.full_name}`})),
    maintenance_plan:(plans??[]).map(x=>({id:x.id,label:`${x.code} · ${x.name}`})),
    supplier:(suppliers??[]).map(x=>({id:x.id,label:`${x.code} · ${x.name}`})),
    purchase_order:(purchaseOrders??[]).map(x=>({id:x.id,label:`${x.code} · ${x.status}`})),
  }

  return <main className="content stack gap-24">
    <div className="header"><div><span className="badge">Documentos</span><h1>Registro documental</h1><p className="muted">{tenant.name} · versiones inmutables y vínculos con la operación.</p></div></div>
    <section className={styles.metrics}><div className={styles.metric}><span>Activos</span><strong>{active}</strong></div><div className={styles.metric}><span>Versiones</span><strong>{totalVersions}</strong></div><div className={styles.metric}><span>Con archivo vigente</span><strong>{withFile}</strong></div><div className={styles.metric}><span>Archivados</span><strong>{archived}</strong></div></section>

    {canManage&&<section className={styles.grid}>
      <form action={createDocumentWithFile} className="card stack" encType="multipart/form-data"><div><strong>Nuevo documento</strong><p className="muted small">El archivo inicial será versión 1. Las versiones anteriores nunca se sobrescriben.</p></div><div className="form-grid"><input className="input" name="code" placeholder="Código" required/><input className="input" name="title" placeholder="Título" required/></div><select className="input" name="document_type_id" defaultValue=""><option value="">Sin tipo</option>{(types??[]).map(t=><option key={t.id} value={t.id}>{t.code} · {t.name}</option>)}</select><select className="input" name="owner_worker_id" defaultValue=""><option value="">Sin responsable</option>{(workers??[]).map(w=><option key={w.id} value={w.id}>{w.employee_code} · {w.full_name}</option>)}</select><textarea className="input" name="description" rows={2} placeholder="Descripción"/><div className="form-grid"><input className="input" name="effective_from" type="date"/><input className="input" name="effective_to" type="date"/></div><input className="input" name="file" type="file" required/><input className="input" name="change_notes" defaultValue="Versión inicial" placeholder="Nota de versión"/><button className="button" type="submit">Crear documento</button></form>
      <form action={createDocumentType} className="card stack"><div><strong>Tipo documental</strong><p className="muted small">Manuales, planos, procedimientos, certificados, fichas técnicas, etc.</p></div><div className="form-grid"><input className="input" name="code" placeholder="Código" required/><input className="input" name="name" placeholder="Nombre" required/></div><textarea className="input" name="description" rows={2} placeholder="Descripción"/><button className="button button-secondary" type="submit">Crear tipo</button><div className={styles.links}>{(types??[]).map(t=><span className={styles.linkPill} key={t.id}>{t.code} · {t.name}</span>)}</div></form>
    </section>}

    {canManage&&documentRows.filter(d=>d.status==='active').length>0&&<section className="card stack"><div><strong>Vincular documento</strong><p className="muted small">Un mismo documento puede relacionarse con varias entidades sin duplicar el archivo.</p></div><DocumentLinkForm documents={documentRows.filter(d=>d.status==='active').map(d=>({id:d.id,code:d.code,title:d.title}))} groups={groups}/></section>}

    <section className="card stack"><div className="section-heading"><div><strong>Documentos</strong><p className="muted small">Últimos {documentRows.length} registros.</p></div></div>{documentRows.length===0?<div className="empty-state"><span className="muted">Sin documentos.</span></div>:<div className={styles.registry}>{documentRows.map(doc=>{const docVersions=versionRows.filter(v=>v.document_id===doc.id);const docLinks=linkRows.filter(l=>l.document_id===doc.id);const owner=doc.owner_worker_id?workerMap.get(doc.owner_worker_id):null;return <article className={`${styles.document} ${doc.status==='archived'?styles.archived:''}`} key={doc.id}><div className={styles.title}><span className={styles.code}>{doc.code}</span><strong>{doc.title}</strong><span className={styles.meta}>{doc.document_type_name||'Sin tipo'} · responsable {owner?.full_name||'—'} · actualizado {date(doc.updated_at)}</span><div className={styles.links}>{docLinks.slice(0,6).map(link=><span className={styles.linkPill} key={link.id}>{link.entity_type}</span>)}</div></div><div><span className={styles.meta}>Versión vigente</span><br/><strong>v{doc.current_version}</strong><div className={styles.meta}>{size(doc.file_size)}</div></div><div><span className={styles.meta}>Vigencia</span><br/>{doc.effective_from||'—'}<div className={styles.meta}>{doc.effective_to?`hasta ${doc.effective_to}`:'sin fin'}</div></div><div><span className={styles.meta}>Estado</span><br/><span className={styles.pill}>{doc.status}</span></div><div className={styles.actions}>{currentSigned.get(doc.id)&&<a className="button button-secondary button-compact" href={currentSigned.get(doc.id)} target="_blank" rel="noreferrer">Abrir</a>}{canManage&&doc.status==='active'&&<details><summary className="button button-secondary button-compact">Nueva versión</summary><form action={uploadDocumentVersion} className="stack" encType="multipart/form-data"><input type="hidden" name="document_id" value={doc.id}/><input className="input input-compact" type="file" name="file" required/><input className="input input-compact" name="change_notes" placeholder="Qué cambió"/><button className="button button-compact" type="submit">Subir</button></form></details>}{canManage&&doc.status==='active'&&<form action={archiveDocument}><input type="hidden" name="document_id" value={doc.id}/><button className="button button-secondary button-compact" type="submit">Archivar</button></form>}</div>{docVersions.length>1&&<details style={{gridColumn:'1/-1'}}><summary className={styles.meta}>Historial de {docVersions.length} versiones</summary><div className={styles.versions}>{docVersions.map(v=><div className={styles.version} key={v.id}><div><strong>v{v.version_number} · {v.file_name}</strong><span className={styles.meta}>{v.change_notes||'Sin nota'} · {date(v.created_at)}</span></div><span>{size(v.file_size)}</span></div>)}</div></details>}</article>})}</div>}</section>
  </main>
}