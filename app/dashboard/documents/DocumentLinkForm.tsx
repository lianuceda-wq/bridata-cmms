'use client'

import { useMemo, useState } from 'react'
import { linkDocument } from './actions'

type Entity={id:string;label:string}
type Groups=Record<string,Entity[]>

const labels:Record<string,string>={asset:'Activo',work_order:'OT',failure:'Falla',inspection:'Inspección',material:'Material',worker:'Trabajador',maintenance_plan:'Plan',supplier:'Proveedor',purchase_order:'OC'}

export default function DocumentLinkForm({documents,groups}:{documents:{id:string;code:string;title:string}[];groups:Groups}){
  const [type,setType]=useState('asset')
  const options=useMemo(()=>groups[type]??[],[groups,type])
  return <form action={linkDocument} className="inline-form">
    <select className="input" name="document_id" required defaultValue=""><option value="" disabled>Documento</option>{documents.map(doc=><option key={doc.id} value={doc.id}>{doc.code} · {doc.title}</option>)}</select>
    <select className="input" name="entity_type" value={type} onChange={e=>setType(e.target.value)}>{Object.keys(labels).map(key=><option key={key} value={key}>{labels[key]}</option>)}</select>
    <select className="input" name="entity_id" required defaultValue=""><option value="" disabled>Entidad</option>{options.map(option=><option key={option.id} value={option.id}>{option.label}</option>)}</select>
    <button className="button button-secondary" type="submit">Vincular</button>
  </form>
}
