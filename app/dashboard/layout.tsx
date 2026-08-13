import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

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
        <nav className="nav-stack">
          <Link href="/dashboard" className="nav-link">Dashboard</Link>
          <Link href="/dashboard/assets" className="nav-link">Activos</Link>
          <Link href="/dashboard/plans" className="nav-link">Planes de mantenimiento</Link>
          <Link href="/dashboard/work-orders" className="nav-link">Órdenes de trabajo</Link>
          <span className="nav-link nav-disabled">Inventario</span>
          <span className="nav-link nav-disabled">Reportes</span>
        </nav>
        <div className="sidebar-footer">
          <span className="muted small">Sesión activa</span>
          <span className="ellipsis">{user.email}</span>
        </div>
      </aside>
      <div className="app-main">{children}</div>
    </div>
  )
}
