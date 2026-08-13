import Link from 'next/link'
import { requireTenant } from '@/lib/tenant'

export default async function DashboardPage() {
  const { supabase, tenant, role } = await requireTenant()
  const now = new Date().toISOString()

  const [
    { count: assetsCount },
    { count: plansCount },
    { count: openOrders },
    { count: overdueOrders },
    { count: activeAlerts },
    { count: urgentAlerts },
  ] = await Promise.all([
    supabase.from('assets').select('*', { count: 'exact', head: true }).eq('tenant_id', tenant.id).eq('is_active', true),
    supabase.from('maintenance_plans').select('*', { count: 'exact', head: true }).eq('tenant_id', tenant.id).eq('status', 'active'),
    supabase.from('work_orders').select('*', { count: 'exact', head: true }).eq('tenant_id', tenant.id).in('status', ['requested', 'planned', 'assigned', 'in_progress', 'paused']),
    supabase.from('work_orders').select('*', { count: 'exact', head: true }).eq('tenant_id', tenant.id).lt('due_at', now).in('status', ['requested', 'planned', 'assigned', 'in_progress', 'paused']),
    supabase.from('operational_alerts').select('*', { count: 'exact', head: true }).eq('tenant_id', tenant.id).neq('state', 'resolved'),
    supabase.from('operational_alerts').select('*', { count: 'exact', head: true }).eq('tenant_id', tenant.id).neq('state', 'resolved').in('severity', ['high', 'critical']),
  ])

  return (
    <main className="content stack gap-24">
      <div className="header">
        <div>
          <span className="badge">Operación</span>
          <h1>Centro de mantenimiento</h1>
          <p className="muted">{tenant.name} · rol {role}</p>
        </div>
        <div className="inline-form">
          <Link href="/dashboard/alerts" className="button button-secondary">Alertas</Link>
          <Link href="/dashboard/notifications" className="button button-secondary">Notificaciones</Link>
          <Link href="/dashboard/work-orders" className="button">Órdenes de trabajo</Link>
        </div>
      </div>

      <div className="grid">
        <div className="card"><strong>Activos</strong><div className="kpi">{assetsCount ?? 0}</div><span className="muted">Registrados</span></div>
        <div className="card"><strong>Planes activos</strong><div className="kpi">{plansCount ?? 0}</div><span className="muted">Preventivos / predictivos</span></div>
        <div className="card"><strong>OT abiertas</strong><div className="kpi">{openOrders ?? 0}</div><span className="muted">Pendientes</span></div>
        <div className="card"><strong>OT vencidas</strong><div className="kpi">{overdueOrders ?? 0}</div><span className="muted">Fuera de fecha límite</span></div>
        <div className="card"><strong>Alertas activas</strong><div className="kpi">{activeAlerts ?? 0}</div><span className="muted">{urgentAlerts ?? 0} alta / crítica</span></div>
      </div>

      <section className="grid">
        <div className="card">
          <div className="section-heading">
            <div>
              <strong>Jerarquía técnica</strong>
              <p className="muted small">Estructura fundos, ubicaciones, equipos y componentes.</p>
            </div>
            <Link href="/dashboard/assets" className="button button-secondary">Abrir activos</Link>
          </div>
        </div>
        <div className="card">
          <div className="section-heading">
            <div>
              <strong>Planificación preventiva</strong>
              <p className="muted small">Configura rutinas por calendario, horómetro, ciclos, km o m³.</p>
            </div>
            <Link href="/dashboard/plans" className="button button-secondary">Abrir planes</Link>
          </div>
        </div>
        <div className="card">
          <div className="section-heading">
            <div>
              <strong>Ejecución operacional</strong>
              <p className="muted small">Genera, asigna, ejecuta, valida y cierra órdenes con trazabilidad.</p>
            </div>
            <Link href="/dashboard/work-orders" className="button button-secondary">Abrir OT</Link>
          </div>
        </div>
        <div className="card">
          <div className="section-heading">
            <div>
              <strong>Monitoreo automático</strong>
              <p className="muted small">OT vencidas, stock, EPP, competencias, compras, documentos y presupuesto.</p>
            </div>
            <Link href="/dashboard/alerts" className="button button-secondary">Abrir alertas</Link>
          </div>
        </div>
      </section>
    </main>
  )
}
