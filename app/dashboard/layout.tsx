import Link from 'next/link'
import { redirect } from 'next/navigation'
import { getTenantContext } from '@/lib/tenant'

const roleLabel: Record<string, string> = {
  owner: 'Owner',
  admin: 'Administrador',
  planner: 'Planner',
  supervisor: 'Supervisor',
  technician: 'Técnico',
  warehouse: 'Almacén',
  viewer: 'Consulta',
}

export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  const context = await getTenantContext()
  if (!context.user) redirect('/login')

  const role = context.role ?? 'viewer'
  const canPlan = ['owner', 'admin', 'planner', 'supervisor'].includes(role)
  const canManagePeople = ['owner', 'admin', 'planner', 'supervisor'].includes(role)
  const canInventory = ['owner', 'admin', 'planner', 'supervisor', 'warehouse'].includes(role)
  const canAnalytics = ['owner', 'admin', 'planner', 'supervisor', 'viewer'].includes(role)
  const canConfigure = ['owner', 'admin', 'planner', 'supervisor'].includes(role)
  const canAdmin = ['owner', 'admin'].includes(role)

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <Link href="/dashboard" className="brand">
          <span className="brand-mark">B</span>
          <span>
            <strong>Bridata</strong>
            <small>CMMS</small>
          </span>
        </Link>

        <nav className="nav-stack" aria-label="Navegación principal">
          <Link href="/dashboard" className="nav-link">Dashboard</Link>
          <Link href="/dashboard/assets" className="nav-link">Activos</Link>
          {canPlan && <Link href="/dashboard/plans" className="nav-link">Planes de mantenimiento</Link>}
          <Link href="/dashboard/work-orders" className="nav-link">Órdenes de trabajo</Link>
          <Link href="/dashboard/inspections" className="nav-link">Inspecciones</Link>
          <Link href="/dashboard/failures" className="nav-link">Fallas y confiabilidad</Link>
          <Link href="/dashboard/hydraulics" className="nav-link">Control hidráulico</Link>
          {canInventory && <Link href="/dashboard/inventory" className="nav-link">Inventario y compras</Link>}
          {canManagePeople && <Link href="/dashboard/people" className="nav-link">Personal y cuadrillas</Link>}
          <Link href="/dashboard/resources" className="nav-link">Herramientas y EPP</Link>
          <Link href="/dashboard/documents" className="nav-link">Documentos</Link>
          {canAnalytics && <Link href="/dashboard/analytics" className="nav-link">Analítica y presupuesto</Link>}
          {canConfigure && <Link href="/dashboard/settings/measurements" className="nav-link">Nominales y parámetros</Link>}
          {canAdmin && <Link href="/dashboard/admin" className="nav-link">Administración</Link>}
        </nav>

        <div className="sidebar-footer">
          <span className="muted small">{context.tenant?.name ?? 'Sin empresa asignada'}</span>
          <strong className="small">{roleLabel[role] ?? role}</strong>
          <span className="ellipsis">{context.user.email}</span>
        </div>
      </aside>
      <div className="app-main">{children}</div>
    </div>
  )
}
