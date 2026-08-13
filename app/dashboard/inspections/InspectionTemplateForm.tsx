'use client'

import { useState } from 'react'
import { createInspectionTemplate } from './actions'
import styles from './inspections.module.css'

type Unit={id:string;code:string;name:string;symbol:string}
type Item={key:number;title:string;instructions:string;response_type:string;mandatory:boolean;requires_evidence:boolean;expected_boolean:string;expected_text:string;options:string;unit_id:string;min_value:string;max_value:string;default_finding_severity:string}
const blank=(key:number):Item=>({key,title:'',instructions:'',response_type:'boolean',mandatory:true,requires_evidence:false,expected_boolean:'true',expected_text:'',options:'',unit_id:'',min_value:'',max_value:'',default_finding_severity:'medium'})

export default function InspectionTemplateForm({units}:{units:Unit[]}){
  const [items,setItems]=useState<Item[]>([blank(1)])
  const update=(key:number,field:keyof Item,value:string|boolean)=>setItems(rows=>rows.map(row=>row.key===key?{...row,[field]:value}:row))
  const add=()=>setItems(rows=>[...rows,blank(Math.max(0,...rows.map(r=>r.key))+1)])
  const remove=(key:number)=>setItems(rows=>rows.length===1?rows:rows.filter(r=>r.key!==key))
  const payload=items.map(({key:_key,...item})=>({
    ...item,
    expected_boolean:item.response_type==='boolean'?item.expected_boolean:'',
    expected_text:item.response_type==='choice'?item.expected_text:'',
    options:item.response_type==='choice'?item.options.split(',').map(v=>v.trim()).filter(Boolean):[],
    unit_id:item.response_type==='number'?item.unit_id:'',
    min_value:item.response_type==='number'?item.min_value:'',
    max_value:item.response_type==='number'?item.max_value:'',
  }))

  return <form action={createInspectionTemplate} className="card stack">
    <div><strong>Nueva plantilla</strong><p className="muted small">Cada versión activa queda congelada en las inspecciones ejecutadas.</p></div>
    <div className="form-grid"><input className="input" name="code" placeholder="Código: INSP-BOMBA" required/><input className="input" name="name" placeholder="Nombre de plantilla" required/></div>
    <textarea className="input" name="description" rows={2} placeholder="Objetivo / alcance"/>
    <div className={styles.templateItems}>{items.map((item,index)=><div className={styles.templateItem} key={item.key}>
      <div className={styles.itemIndex}>{index+1}</div>
      <div className={styles.itemFields}>
        <input className="input" value={item.title} onChange={e=>update(item.key,'title',e.target.value)} placeholder="Punto a inspeccionar" required/>
        <input className="input" value={item.instructions} onChange={e=>update(item.key,'instructions',e.target.value)} placeholder="Instrucción opcional"/>
        <div className="form-grid"><select className="input" value={item.response_type} onChange={e=>update(item.key,'response_type',e.target.value)}><option value="boolean">Sí / No</option><option value="number">Medición</option><option value="choice">Lista</option><option value="text">Texto</option><option value="photo">Foto / evidencia</option></select><select className="input" value={item.default_finding_severity} onChange={e=>update(item.key,'default_finding_severity',e.target.value)}><option value="low">Hallazgo leve</option><option value="medium">Hallazgo medio</option><option value="high">Hallazgo alto</option><option value="critical">Hallazgo crítico</option></select></div>
        {item.response_type==='boolean'&&<select className="input" value={item.expected_boolean} onChange={e=>update(item.key,'expected_boolean',e.target.value)}><option value="true">Esperado: Sí</option><option value="false">Esperado: No</option></select>}
        {item.response_type==='number'&&<div className={styles.measureGrid}><select className="input" value={item.unit_id} onChange={e=>update(item.key,'unit_id',e.target.value)}><option value="">Sin unidad</option>{units.map(u=><option key={u.id} value={u.id}>{u.symbol} · {u.name}</option>)}</select><input className="input" value={item.min_value} onChange={e=>update(item.key,'min_value',e.target.value)} type="number" step="any" placeholder="Mínimo"/><input className="input" value={item.max_value} onChange={e=>update(item.key,'max_value',e.target.value)} type="number" step="any" placeholder="Máximo"/></div>}
        {item.response_type==='choice'&&<div className="form-grid"><input className="input" value={item.options} onChange={e=>update(item.key,'options',e.target.value)} placeholder="Opciones separadas por coma"/><input className="input" value={item.expected_text} onChange={e=>update(item.key,'expected_text',e.target.value)} placeholder="Opción esperada"/></div>}
        <div className={styles.checks}><label><input type="checkbox" checked={item.mandatory} onChange={e=>update(item.key,'mandatory',e.target.checked)}/> Obligatorio</label><label><input type="checkbox" checked={item.requires_evidence} onChange={e=>update(item.key,'requires_evidence',e.target.checked)}/> Exige evidencia</label></div>
      </div>
      <button className={styles.remove} type="button" onClick={()=>remove(item.key)}>×</button>
    </div>)}</div>
    <input type="hidden" name="items_json" value={JSON.stringify(payload)} readOnly/>
    <div className={styles.formActions}><button className="button button-secondary" type="button" onClick={add}>+ Punto</button><button className="button" type="submit">Crear borrador</button></div>
  </form>
}
