'use client'

import { useState } from 'react'
import { createBudgetAdvanced } from './budget-actions'
import styles from './analytics.module.css'

type Site={id:string;code:string|null;name:string}
type Asset={id:string;code:string;name:string;site_id:string|null}
type Row={key:number;site_id:string;asset_id:string;maintenance_type:string;category:string;amount:string}

const blank=(key:number):Row=>({key,site_id:'',asset_id:'',maintenance_type:'',category:'material',amount:''})

export default function BudgetForm({sites,assets}:{sites:Site[];assets:Asset[]}){
  const [rows,setRows]=useState<Row[]>([blank(1)])
  const update=(key:number,field:keyof Row,value:string)=>setRows(current=>current.map(row=>row.key===key?{...row,[field]:value}:row))
  const add=()=>setRows(current=>[...current,blank(Math.max(0,...current.map(r=>r.key))+1)])
  const remove=(key:number)=>setRows(current=>current.length===1?current:current.filter(row=>row.key!==key))
  const payload=rows.map(({key:_key,...row})=>({...row,amount:Number(row.amount||0)}))
  const year=new Date().getFullYear()

  return <form action={createBudgetAdvanced} className="card stack">
    <div><strong>Nuevo presupuesto de mantenimiento</strong><p className="muted small">Versiona la meta financiera por periodo y alcance. La ejecución se compara con costos reales trazables.</p></div>
    <div className="form-grid"><input className="input" name="code" defaultValue={`PRES-${year}`} placeholder="Código" required/><input className="input" name="name" defaultValue={`Presupuesto ${year}`} placeholder="Nombre" required/></div>
    <div className="form-grid"><label className={styles.label}>Desde<input className="input" type="date" name="period_start" defaultValue={`${year}-01-01`} required/></label><label className={styles.label}>Hasta<input className="input" type="date" name="period_end" defaultValue={`${year}-12-31`} required/></label></div>
    <input className="input" name="currency" defaultValue="PEN" maxLength={3}/>
    <div className={styles.budgetRows}>
      {rows.map(row=><div key={row.key} className={styles.budgetRow}>
        <select className="input" value={row.site_id} onChange={e=>update(row.key,'site_id',e.target.value)}><option value="">Toda la empresa</option>{sites.map(site=><option key={site.id} value={site.id}>{site.code?`${site.code} · `:''}{site.name}</option>)}</select>
        <select className="input" value={row.asset_id} onChange={e=>update(row.key,'asset_id',e.target.value)}><option value="">Todos los activos</option>{assets.filter(asset=>!row.site_id||asset.site_id===row.site_id).map(asset=><option key={asset.id} value={asset.id}>{asset.code} · {asset.name}</option>)}</select>
        <select className="input" value={row.maintenance_type} onChange={e=>update(row.key,'maintenance_type',e.target.value)}><option value="">Todo mantenimiento</option><option value="preventive">Preventivo</option><option value="corrective">Correctivo</option><option value="predictive">Predictivo</option><option value="inspection">Inspección</option><option value="improvement">Mejora</option></select>
        <select className="input" value={row.category} onChange={e=>update(row.key,'category',e.target.value)}><option value="material">Material</option><option value="labor">Mano de obra</option><option value="service">Servicio</option><option value="contractor">Contratista</option><option value="other">Otro</option></select>
        <input className="input" type="number" min="0" step="any" placeholder="Monto" value={row.amount} onChange={e=>update(row.key,'amount',e.target.value)} required/>
        <button className={styles.remove} type="button" onClick={()=>remove(row.key)}>×</button>
      </div>)}
    </div>
    <input type="hidden" name="lines_json" value={JSON.stringify(payload)} readOnly/>
    <div className={styles.formActions}><button className="button button-secondary" type="button" onClick={add}>+ Línea</button><button className="button" type="submit">Crear presupuesto</button></div>
  </form>
}
