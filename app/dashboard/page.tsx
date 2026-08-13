import Link from 'next/link'
import { requireTenant } from '@/lib/tenant'

export default async function DashboardPage() {
  const { supabase, tenant, role } = await requireTenant()

  const [{ count: assetsCount }, { count: openOrders }, { count: overdueOrders }] = await Promise.all([
    supabase.from('assets').select('*', { count: 'exact', head: true }).eq('tenant_id', tenant.id).eq('is_active', true),
    supabase.from('work_orders').select('*', { count: 'exact', head: true }).eq('tenant_id', tenant.id).in('status', ['requested', 'planned', 'assigned', 'in_progress', 'paused']),
    supabase.from('work_orders').select('*', { count: 'exact', head: true }).eq('tenant_id', tenant.id).lt('scheduled_at', new Date().toISOString()).in('status', ['requested', 'planned', 'assigned', 'in_progress', 'paused']),
  ])

  return (
    <main className="content stack gap-24">
      <div className="header">
        <div>
          <span className="badge">Operación</span>
          <h1>Centro de mantenimiento</h1>
          <p className="muted">{tenant.name} · rol {role}</p>
        </div>
        <Link href="/dashboard/assets" className="button">Gestionar activos</Link>
      </div>

      <div className="grid">
        <div className="card"><strong>Activos</strong><div className="kpi">{assetsCount ?? 0}</div><span className="muted">Registrados</span></div>
        <div className="card"><strong>OT abiertas</strong><div className="kpi">{openOrders ?? 0}</div><span className="muted">Pendientes</span></div>
        <div className="card"><strong>OT vencidas</strong><div className="kpi">{overdueOrders ?? 0}</div><span className="muted">Requieren atención</span></div>
        <div className="card"><strong>Disponibilidad</strong><div className="kpi">—</div><span className="muted">Se calculará con tiempos de parada</span></div>
      </div>

      <section className="card">
        <div className="section-heading">
          <div>
            <strong>Base operacional</strong>
            <p className="muted small">Comienza estructurando fundos, ubicaciones y activos antes de crear los planes de mantenimiento.</p>
          </div>
          <Link href="/dashboard/assets" className="button button-secondary">Abrir jerarquía</Link>
        </div>
      </section>
    </main>
  )
}
