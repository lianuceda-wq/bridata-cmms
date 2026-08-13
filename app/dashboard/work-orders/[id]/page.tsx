import Link from 'next/link'
import { notFound } from 'next/navigation'
import { requireTenant } from '@/lib/tenant'
import {
  assignWorkOrder,
  transitionWorkOrder,
  updateWorkOrderTask,
  uploadWorkOrderEvidence,
} from '../actions'
import styles from '../work-orders.module.css'

const statusLabels: Record<string, string> = {
  requested: 'Solicitada', planned: 'Planificada', assigned: 'Asignada',
  in_progress: 'En ejecución', paused: 'Pausada', completed: 'Completada',
  validated: 'Validada', closed: 'Cerrada', cancelled: 'Cancelada',
}

const transitionLabels: Record<string, string> = {
  planned: 'Planificar', assigned: 'Asignar', in_progress: 'Iniciar / reanudar',
  paused: 'Pausar', completed: 'Completar', validated: 'Validar',
  closed: 'Cerrar OT', cancelled: 'Cancelar', requested: 'Reabrir',
}

const managerTransitions: Record<string, string[]> = {
  requested: ['planned', 'cancelled'],
  planned: ['in_progress', 'cancelled'],
  assigned: ['planned', 'in_progress', 'cancelled'],
  in_progress: ['paused', 'completed', 'cancelled'],
  paused: ['in_progress', 'completed', 'cancelled'],
  completed: ['validated', 'in_progress'],
  validated: ['closed', 'completed'],
  cancelled: ['requested'],
  closed: [],
}

const technicianTransitions: Record<string, string[]> = {
  assigned: ['in_progress'],
  planned: ['in_progress'],
  in_progress: ['paused', 'completed'],
  paused: ['in_progress', 'completed'],
  completed: ['in_progress'],
}

function formatDate(value: string | null) {
  if (!value) return '—'
  return new Intl.DateTimeFormat('es-PE', {
    timeZone: 'America/Lima', dateStyle: 'medium', timeStyle: 'short',
  }).format(new Date(value))
}

export default async function WorkOrderDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const { supabase, tenant, user, role } = await requireTenant()
  const canManage = ['owner', 'admin', 'planner', 'supervisor'].includes(role)

  const { data: order, error: orderError } = await supabase
    .from('work_orders')
    .select('id,asset_id,plan_id,routine_id,assigned_to,code,title,description,status,priority,maintenance_type,source,scheduled_at,due_at,due_meter,started_at,completed_at,validated_at,closed_at,cancellation_reason,created_at')
    .eq('tenant_id', tenant.id)
    .eq('id', id)
    .maybeSingle()

  if (orderError) throw new Error(orderError.message)
  if (!order) notFound()

  const [{ data: tasks }, { data: evidence }, { data: history }, { data: members }, { data: asset }] = await Promise.all([
    supabase.from('work_order_tasks').select('id,sequence,title,instructions,estimated_minutes,mandatory,task_type,requires_evidence,measurement_unit,min_value,max_value,status,measurement_value,result_status,notes,completed_at').eq('tenant_id', tenant.id).eq('work_order_id', id).order('sequence'),
    supabase.from('work_order_evidence').select('id,task_id,storage_path,file_name,mime_type,caption,created_at').eq('tenant_id', tenant.id).eq('work_order_id', id).order('created_at'),
    supabase.from('work_order_status_history').select('id,from_status,to_status,changed_by,changed_at').eq('tenant_id', tenant.id).eq('work_order_id', id).order('changed_at', { ascending: false }),
    supabase.from('tenant_members').select('user_id,role,is_active').eq('tenant_id', tenant.id).eq('is_active', true),
    order.asset_id ? supabase.from('assets').select('id,code,name').eq('tenant_id', tenant.id).eq('id', order.asset_id).maybeSingle() : Promise.resolve({ data: null }),
  ])

  const memberIds = (members ?? []).map((member) => member.user_id)
  const { data: profiles } = memberIds.length
    ? await supabase.from('profiles').select('id,full_name,email').in('id', memberIds)
    : { data: [] }

  const profileMap = new Map((profiles ?? []).map((profile) => [profile.id, profile]))
  const staff = (members ?? []).map((member) => ({ ...member, profile: profileMap.get(member.user_id) }))
  const assignedProfile = order.assigned_to ? profileMap.get(order.assigned_to) : null
  const isAssignedTechnician = role === 'technician' && order.assigned_to === user.id
  const isLocked = ['completed', 'validated', 'closed', 'cancelled'].includes(order.status)
  const canExecuteTasks = (canManage || isAssignedTechnician) && !isLocked
  const transitions = canManage
    ? (managerTransitions[order.status] ?? [])
    : (isAssignedTechnician ? technicianTransitions[order.status] ?? [] : [])

  const evidenceWithUrls = await Promise.all((evidence ?? []).map(async (item) => {
    const { data } = await supabase.storage.from('work-order-evidence').createSignedUrl(item.storage_path, 600)
    return { ...item, signedUrl: data?.signedUrl ?? null }
  }))
  const evidenceByTask = new Map<string, typeof evidenceWithUrls>()
  for (const item of evidenceWithUrls) {
    if (!item.task_id) continue
    evidenceByTask.set(item.task_id, [...(evidenceByTask.get(item.task_id) ?? []), item])
  }

  return (
    <main className="content">
      <div className={styles.workspace}>
        <section className={styles.hero}>
          <div>
            <Link href="/dashboard/work-orders" className="muted small">← Órdenes de trabajo</Link>
            <div className={styles.code}>{order.code}</div>
            <h1>{order.title}</h1>
            <p className="muted">
              {asset ? `${asset.code} · ${asset.name}` : 'Sin activo'} · {statusLabels[order.status] ?? order.status}
            </p>
          </div>
          <div className={styles.heroActions}>
            <span className={styles.pill}>{order.priority}</span>
            <span className={styles.pill}>{order.maintenance_type}</span>
            <span className={styles.pill}>{order.source === 'maintenance_plan' ? 'Automática' : 'Manual'}</span>
          </div>
        </section>

        <div className={styles.detailGrid}>
          <div className={styles.sideStack}>
            <section className={styles.panel}>
              <div className={styles.panelHeader}>
                <div>
                  <strong>Checklist de ejecución</strong>
                  <div className={styles.meta}>{(tasks ?? []).length} actividades emitidas como snapshot</div>
                </div>
              </div>
              <div className={styles.panelBody}>
                {(tasks ?? []).length === 0 ? (
                  <div className={styles.empty}>Esta OT no tiene actividades configuradas.</div>
                ) : (tasks ?? []).map((task) => {
                  const taskEvidence = evidenceByTask.get(task.id) ?? []
                  return (
                    <article key={task.id} className={styles.task}>
                      <div className={styles.taskHead}>
                        <div className={styles.taskTitle}>
                          <span className={styles.taskIndex}>{task.sequence}</span>
                          <div>
                            <strong>{task.title}</strong>
                            <div className={styles.meta}>
                              {task.task_type} · {task.mandatory ? 'Obligatoria' : 'Opcional'}
                              {task.requires_evidence ? ' · Evidencia requerida' : ''}
                            </div>
                          </div>
                        </div>
                        <span className={styles.pill}>{task.status}</span>
                      </div>

                      {task.instructions && <p className="muted small">{task.instructions}</p>}

                      {canExecuteTasks && (
                        <form action={updateWorkOrderTask} className={styles.formGrid}>
                          <input type="hidden" name="task_id" value={task.id} />
                          <input type="hidden" name="work_order_id" value={order.id} />
                          <select className="input" name="status" defaultValue={task.status}>
                            <option value="pending">Pendiente</option>
                            <option value="completed">Completada</option>
                            {!task.mandatory && <option value="skipped">Omitida</option>}
                          </select>
                          {task.task_type === 'measurement' ? (
                            <input className="input" name="measurement_value" type="number" step="any" defaultValue={task.measurement_value ?? ''} placeholder={`Medición${task.measurement_unit ? ` (${task.measurement_unit})` : ''}`} />
                          ) : (
                            <select className="input" name="result_status" defaultValue={task.result_status ?? ''}>
                              <option value="">Resultado automático</option>
                              <option value="passed">Conforme</option>
                              <option value="failed">No conforme</option>
                              {!task.mandatory && <option value="not_applicable">No aplica</option>}
                            </select>
                          )}
                          <input className={`input ${styles.full}`} name="notes" defaultValue={task.notes ?? ''} placeholder="Observación / resultado" />
                          <button className="button button-secondary" type="submit">Guardar actividad</button>
                        </form>
                      )}

                      {task.task_type === 'measurement' && (task.min_value !== null || task.max_value !== null) && (
                        <div className={styles.meta}>
                          Rango esperado: {task.min_value ?? '−∞'} – {task.max_value ?? '+∞'} {task.measurement_unit ?? ''}
                          {task.result_status === 'out_of_range' ? ' · FUERA DE RANGO' : ''}
                        </div>
                      )}

                      {taskEvidence.length > 0 && (
                        <div className={styles.evidenceList}>
                          {taskEvidence.map((item) => item.signedUrl ? (
                            <a key={item.id} className={styles.evidence} href={item.signedUrl} target="_blank" rel="noreferrer">
                              {item.file_name || 'Evidencia'}
                            </a>
                          ) : <span key={item.id} className={styles.evidence}>{item.file_name || 'Evidencia'}</span>)}
                        </div>
                      )}

                      {canExecuteTasks && (
                        <form action={uploadWorkOrderEvidence} className={styles.formGrid}>
                          <input type="hidden" name="work_order_id" value={order.id} />
                          <input type="hidden" name="task_id" value={task.id} />
                          <input className="input" name="file" type="file" accept="image/*,application/pdf" required />
                          <input className="input" name="caption" placeholder="Descripción de evidencia" />
                          <button className="button button-secondary" type="submit">Subir evidencia</button>
                        </form>
                      )}
                    </article>
                  )
                })}
              </div>
            </section>
          </div>

          <aside className={styles.sideStack}>
            <section className={styles.panel}>
              <div className={styles.panelHeader}><strong>Control de la OT</strong></div>
              <div className={styles.panelBody}>
                <div><div className={styles.meta}>Estado actual</div><strong>{statusLabels[order.status] ?? order.status}</strong></div>
                <div><div className={styles.meta}>Programada / vencimiento</div><strong>{formatDate(order.due_at ?? order.scheduled_at)}</strong></div>
                {order.due_meter !== null && <div><div className={styles.meta}>Umbral de medidor</div><strong>{order.due_meter}</strong></div>}
                <div><div className={styles.meta}>Responsable</div><strong>{assignedProfile?.full_name || assignedProfile?.email || 'Sin asignar'}</strong></div>

                {canManage && !['closed', 'cancelled'].includes(order.status) && (
                  <form action={assignWorkOrder} className="stack">
                    <input type="hidden" name="id" value={order.id} />
                    <select className="input" name="assigned_to" defaultValue={order.assigned_to ?? ''}>
                      <option value="">Sin asignar</option>
                      {staff.map((member) => (
                        <option key={member.user_id} value={member.user_id}>
                          {member.profile?.full_name || member.profile?.email || member.user_id} · {member.role}
                        </option>
                      ))}
                    </select>
                    <button className="button button-secondary" type="submit">Guardar responsable</button>
                  </form>
                )}

                {transitions.length > 0 && (
                  <div className={styles.transitionGrid}>
                    {transitions.filter((status) => status !== 'cancelled').map((status) => (
                      <form action={transitionWorkOrder} key={status}>
                        <input type="hidden" name="id" value={order.id} />
                        <input type="hidden" name="status" value={status} />
                        <button className="button button-secondary button-compact" type="submit">{transitionLabels[status] ?? status}</button>
                      </form>
                    ))}
                  </div>
                )}

                {canManage && transitions.includes('cancelled') && (
                  <form action={transitionWorkOrder} className="stack">
                    <input type="hidden" name="id" value={order.id} />
                    <input type="hidden" name="status" value="cancelled" />
                    <input className="input" name="cancellation_reason" placeholder="Motivo de cancelación" required />
                    <button className="button button-danger" type="submit">Cancelar OT</button>
                  </form>
                )}
              </div>
            </section>

            <section className={styles.panel}>
              <div className={styles.panelHeader}><strong>Trazabilidad</strong></div>
              <div className={styles.panelBody}>
                <div className={styles.timeline}>
                  {(history ?? []).map((event) => {
                    const actor = event.changed_by ? profileMap.get(event.changed_by) : null
                    return (
                      <div key={event.id} className={styles.event}>
                        <span className={styles.dot} />
                        <div className={styles.eventText}>
                          <strong>{statusLabels[event.to_status] ?? event.to_status}</strong>
                          <span className={styles.meta}>{formatDate(event.changed_at)}</span>
                          <span className={styles.meta}>{actor?.full_name || actor?.email || 'Sistema'}</span>
                        </div>
                      </div>
                    )
                  })}
                  {(history ?? []).length === 0 && <span className="muted small">Sin eventos registrados.</span>}
                </div>
              </div>
            </section>

            <section className={styles.panel}>
              <div className={styles.panelHeader}><strong>Tiempos</strong></div>
              <div className={styles.panelBody}>
                <div><div className={styles.meta}>Creada</div><span>{formatDate(order.created_at)}</span></div>
                <div><div className={styles.meta}>Inicio</div><span>{formatDate(order.started_at)}</span></div>
                <div><div className={styles.meta}>Completada</div><span>{formatDate(order.completed_at)}</span></div>
                <div><div className={styles.meta}>Validada</div><span>{formatDate(order.validated_at)}</span></div>
                <div><div className={styles.meta}>Cerrada</div><span>{formatDate(order.closed_at)}</span></div>
              </div>
            </section>
          </aside>
        </div>
      </div>
    </main>
  )
}
