import Link from 'next/link'
import { requireTenant } from '@/lib/tenant'
import { generateDueWorkOrders } from './actions'
import styles from './work-orders.module.css'

const statusLabels: Record<string, string> = {
  requested: 'Solicitada',
  planned: 'Planificada',
  assigned: 'Asignada',
  in_progress: 'En ejecución',
  paused: 'Pausada',
  completed: 'Completada',
  validated: 'Validada',
  closed: 'Cerrada',
  cancelled: 'Cancelada',
}

const priorityLabels: Record<string, string> = {
  low: 'Baja',
  medium: 'Media',
  high: 'Alta',
  critical: 'Crítica',
}

function formatDate(value: string | null) {
  if (!value) return '—'
  return new Intl.DateTimeFormat('es-PE', {
    timeZone: 'America/Lima',
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value))
}

function priorityClass(priority: string) {
  if (priority === 'critical') return styles.priorityCritical
  if (priority === 'high') return styles.priorityHigh
  if (priority === 'low') return styles.priorityLow
  return styles.priorityMedium
}

export default async function WorkOrdersPage() {
  const { supabase, tenant, role } = await requireTenant()
  const canManage = ['owner', 'admin', 'planner', 'supervisor'].includes(role)
  const now = new Date()

  const [{ data: orders }, { data: assets }, { data: members }, { data: automation }] = await Promise.all([
    supabase
      .from('work_orders')
      .select('id,asset_id,assigned_to,code,title,status,priority,maintenance_type,source,scheduled_at,due_at,due_meter,created_at')
      .eq('tenant_id', tenant.id)
      .order('created_at', { ascending: false })
      .limit(150),
    supabase
      .from('assets')
      .select('id,code,name')
      .eq('tenant_id', tenant.id),
    supabase
      .from('tenant_members')
      .select('user_id,role,is_active')
      .eq('tenant_id', tenant.id)
      .eq('is_active', true),
    supabase
      .from('maintenance_automation_runs')
      .select('started_at,completed_at,generated_count,status,error_message')
      .eq('tenant_id', tenant.id)
      .order('started_at', { ascending: false })
      .limit(1)
      .maybeSingle(),
  ])

  const memberIds = (members ?? []).map((member) => member.user_id)
  const { data: profiles } = memberIds.length
    ? await supabase.from('profiles').select('id,full_name,email').in('id', memberIds)
    : { data: [] }

  const assetMap = new Map((assets ?? []).map((asset) => [asset.id, asset]))
  const profileMap = new Map((profiles ?? []).map((profile) => [profile.id, profile]))
  const rows = orders ?? []
  const openStatuses = new Set(['requested', 'planned', 'assigned', 'in_progress', 'paused'])
  const open = rows.filter((order) => openStatuses.has(order.status)).length
  const inProgress = rows.filter((order) => order.status === 'in_progress').length
  const overdue = rows.filter((order) => {
    const due = order.due_at ?? order.scheduled_at
    return openStatuses.has(order.status) && due && new Date(due) < now
  }).length
  const closed = rows.filter((order) => order.status === 'closed').length

  return (
    <main className="content">
      <div className={styles.workspace}>
        <section className={styles.hero}>
          <div>
            <span className="badge">Órdenes de trabajo</span>
            <h1>Centro de ejecución</h1>
            <p className="muted">{tenant.name} · generación automática cada 5 minutos, asignación y ejecución.</p>
          </div>
          <div className={styles.heroActions}>
            <Link href="/dashboard/plans" className="button button-secondary">Ver planes</Link>
            {canManage && (
              <form action={generateDueWorkOrders}>
                <button className="button" type="submit">Ejecutar generador ahora</button>
              </form>
            )}
          </div>
        </section>

        <section className={styles.metrics}>
          <div className={styles.metric}><span>OT abiertas</span><strong>{open}</strong></div>
          <div className={styles.metric}><span>En ejecución</span><strong>{inProgress}</strong></div>
          <div className={styles.metric}><span>Vencidas</span><strong className={overdue ? styles.overdue : undefined}>{overdue}</strong></div>
          <div className={styles.metric}><span>Cerradas</span><strong>{closed}</strong></div>
        </section>

        <section className="card">
          <div className="section-heading">
            <div>
              <strong>Automatización de mantenimiento</strong>
              <p className="muted small">
                Supabase Cron revisa todos los planes activos cada 5 minutos y genera únicamente las ocurrencias que correspondan.
              </p>
            </div>
            <div className="stack gap-6">
              <span className={styles.pill}>
                {automation ? (automation.status === 'success' ? 'Activa · última ejecución OK' : automation.status === 'failed' ? 'Revisar última ejecución' : 'Ejecutando') : 'Activa · esperando primera ejecución'}
              </span>
              {automation && (
                <span className={styles.meta}>
                  {formatDate(automation.completed_at ?? automation.started_at)} · {automation.generated_count} OT generadas
                </span>
              )}
              {automation?.error_message && <span className={styles.overdue}>{automation.error_message}</span>}
            </div>
          </div>
        </section>

        <section className="card stack">
          <div className="section-heading">
            <div>
              <strong>Bandeja operacional</strong>
              <p className="muted small">Últimas {rows.length} órdenes visibles para tu empresa.</p>
            </div>
          </div>

          {rows.length === 0 ? (
            <div className={styles.empty}>
              Aún no existen órdenes. La automatización creará las OT cuando una rutina alcance su fecha o umbral de medidor.
            </div>
          ) : (
            <div className={styles.list}>
              {rows.map((order) => {
                const asset = order.asset_id ? assetMap.get(order.asset_id) : null
                const assignee = order.assigned_to ? profileMap.get(order.assigned_to) : null
                const due = order.due_at ?? order.scheduled_at
                const isOverdue = Boolean(due && openStatuses.has(order.status) && new Date(due) < now)

                return (
                  <Link key={order.id} href={`/dashboard/work-orders/${order.id}`} className={styles.order}>
                    <div className={styles.orderTitle}>
                      <span className={styles.code}>{order.code}</span>
                      <strong>{order.title}</strong>
                      <span className={styles.meta}>
                        {asset ? `${asset.code} · ${asset.name}` : 'Sin activo'} · {order.source === 'maintenance_plan' ? 'Plan automático' : 'Manual'}
                      </span>
                    </div>
                    <div>
                      <span className={styles.meta}>Estado</span><br />
                      <span className={styles.pill}>{statusLabels[order.status] ?? order.status}</span>
                    </div>
                    <div>
                      <span className={styles.meta}>Responsable</span><br />
                      <span>{assignee?.full_name || assignee?.email || 'Sin asignar'}</span>
                    </div>
                    <div>
                      <span className={styles.meta}>Prioridad</span><br />
                      <span className={`${styles.pill} ${priorityClass(order.priority)}`}>{priorityLabels[order.priority] ?? order.priority}</span>
                    </div>
                    <div>
                      <span className={isOverdue ? styles.overdue : styles.meta}>{isOverdue ? 'Vencida' : 'Programada'}</span><br />
                      <span className={styles.meta}>{formatDate(due)}</span>
                    </div>
                  </Link>
                )
              })}
            </div>
          )}
        </section>
      </div>
    </main>
  )
}
