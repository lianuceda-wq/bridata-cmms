import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'

export default async function DashboardPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  return (
    <main className="container">
      <div className="header">
        <div>
          <span className="badge">Operación</span>
          <h1>Centro de mantenimiento</h1>
          <p className="muted">Sesión: {user.email}</p>
        </div>
      </div>
      <div className="grid">
        <div className="card"><strong>Activos</strong><div className="kpi">0</div><span className="muted">Registrados</span></div>
        <div className="card"><strong>OT abiertas</strong><div className="kpi">0</div><span className="muted">Pendientes</span></div>
        <div className="card"><strong>OT vencidas</strong><div className="kpi">0</div><span className="muted">Requieren atención</span></div>
        <div className="card"><strong>Disponibilidad</strong><div className="kpi">—</div><span className="muted">Sin datos todavía</span></div>
      </div>
    </main>
  )
}
