'use client'

import { useEffect, useState } from 'react'
import { addLaborSession } from '../labor-actions'
import styles from './labor.module.css'

type Staff = { user_id: string; label: string; role: string }

function nowLocal() {
  const now = new Date()
  const pad = (n:number) => String(n).padStart(2,'0')
  return `${now.getFullYear()}-${pad(now.getMonth()+1)}-${pad(now.getDate())}T${pad(now.getHours())}:${pad(now.getMinutes())}`
}

export default function LaborEntryForm({ workOrderId, role, userId, staff }: { workOrderId:string; role:string; userId:string; staff:Staff[] }) {
  const [offset,setOffset] = useState(0)
  const [external,setExternal] = useState(false)
  useEffect(() => setOffset(new Date().getTimezoneOffset()),[])
  const isTechnician = role === 'technician'

  return <form action={addLaborSession} className={styles.form}>
    <input type="hidden" name="work_order_id" value={workOrderId}/>
    <input type="hidden" name="timezone_offset_minutes" value={offset}/>

    {!isTechnician && <label className={styles.toggle}><input type="checkbox" checked={external} onChange={(e)=>setExternal(e.target.checked)}/> Trabajador externo / contratista</label>}

    {isTechnician ? <input type="hidden" name="worker_user_id" value={userId}/> : external ? (
      <input className="input" name="worker_name" placeholder="Nombre del trabajador externo" required/>
    ) : (
      <select className="input" name="worker_user_id" defaultValue={userId} required>
        {staff.map((member)=><option key={member.user_id} value={member.user_id}>{member.label} · {member.role}</option>)}
      </select>
    )}

    <input type="hidden" name="worker_type" value={external ? 'contractor' : 'employee'}/>
    <div className={styles.twoCol}>
      <label>Inicio<input className="input" type="datetime-local" name="started_at" defaultValue={nowLocal()} required/></label>
      <label>Fin opcional<input className="input" type="datetime-local" name="ended_at"/></label>
    </div>
    <div className={styles.twoCol}>
      <input className="input" name="labor_role" placeholder="Función: técnico, soldador..."/>
      <input className="input" name="notes" placeholder="Observación"/>
    </div>
    <button className="button button-secondary" type="submit">Registrar mano de obra</button>
  </form>
}
