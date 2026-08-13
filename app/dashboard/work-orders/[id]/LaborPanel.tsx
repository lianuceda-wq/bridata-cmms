import { requireTenant } from '@/lib/tenant'
import { closeLaborSession } from '../labor-actions'
import LaborEntryForm from './LaborEntryForm'
import styles from './labor.module.css'

function durationHours(startedAt:string, endedAt:string|null) {
  const end = endedAt ? new Date(endedAt).getTime() : Date.now()
  const start = new Date(startedAt).getTime()
  return Math.max(0,(end-start)/3_600_000)
}

function formatDate(value:string|null) {
  if (!value) return 'En curso'
  return new Intl.DateTimeFormat('es-PE',{timeZone:'America/Lima',dateStyle:'short',timeStyle:'short'}).format(new Date(value))
}

export default async function LaborPanel({ workOrderId }:{workOrderId:string}) {
  const { supabase,tenant,user,role } = await requireTenant()
  const managers = ['owner','admin','planner','supervisor']

  const [{data:order},{data:sessions},{data:metric},{data:members}] = await Promise.all([
    supabase.from('work_orders').select('id,status,assigned_to').eq('tenant_id',tenant.id).eq('id',workOrderId).maybeSingle(),
    supabase.from('work_order_labor_sessions').select('id,worker_user_id,worker_name,worker_type,started_at,ended_at,labor_role,notes,created_by').eq('tenant_id',tenant.id).eq('work_order_id',workOrderId).order('started_at'),
    supabase.from('work_order_labor_metrics').select('labor_records,open_labor_sessions,labor_hours').eq('tenant_id',tenant.id).eq('work_order_id',workOrderId).maybeSingle(),
    supabase.from('tenant_members').select('user_id,role,is_active').eq('tenant_id',tenant.id).eq('is_active',true),
  ])
  if (!order) return null

  const memberIds = (members??[]).map((member)=>member.user_id)
  const {data:profiles} = memberIds.length ? await supabase.from('profiles').select('id,full_name,email').in('id',memberIds) : {data:[]}
  const profileMap = new Map((profiles??[]).map((profile)=>[profile.id,profile]))
  const staff = (members??[]).map((member)=>({user_id:member.user_id,role:member.role,label:profileMap.get(member.user_id)?.full_name || profileMap.get(member.user_id)?.email || member.user_id}))
  const canAdd = !['closed','cancelled'].includes(order.status) && (managers.includes(role) || (role==='technician' && order.assigned_to===user.id))

  return <section className={styles.panel}>
    <div className={styles.header}>
      <div><strong>Mano de obra</strong><span>HH independientes del MTTR</span></div>
      <div className={styles.kpis}><b>{Number(metric?.labor_hours??0).toFixed(2)} HH</b><small>{Number(metric?.open_labor_sessions??0)} activas</small></div>
    </div>
    <div className={styles.body}>
      {(sessions??[]).length===0 ? <div className="muted small">Aún no hay mano de obra registrada.</div> : <div className={styles.list}>
        {(sessions??[]).map((session)=>{
          const profile = session.worker_user_id ? profileMap.get(session.worker_user_id) : null
          const label = profile?.full_name || profile?.email || session.worker_name || 'Trabajador'
          const canClose = !session.ended_at && (managers.includes(role) || session.worker_user_id===user.id || session.created_by===user.id)
          return <div key={session.id} className={styles.row}>
            <div><strong>{label}</strong><span>{session.labor_role || session.worker_type}</span></div>
            <div><b>{durationHours(session.started_at,session.ended_at).toFixed(2)} h</b><span>{formatDate(session.started_at)} → {formatDate(session.ended_at)}</span></div>
            {canClose && <form action={closeLaborSession}><input type="hidden" name="id" value={session.id}/><input type="hidden" name="work_order_id" value={workOrderId}/><button className="button button-secondary button-compact" type="submit">Finalizar ahora</button></form>}
          </div>
        })}
      </div>}
      {canAdd && <LaborEntryForm workOrderId={workOrderId} role={role} userId={user.id} staff={staff}/>} 
      {Number(metric?.open_labor_sessions??0)>0 && <div className={styles.warning}>Debes finalizar las sesiones activas antes de completar la OT.</div>}
    </div>
  </section>
}
