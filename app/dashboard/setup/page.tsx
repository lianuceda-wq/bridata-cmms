import { redirect } from 'next/navigation'
import { getTenantContext } from '@/lib/tenant'
import { createWorkspace } from './actions'

export default async function SetupPage() {
  const { tenant, user } = await getTenantContext()
  if (tenant) redirect('/dashboard')

  return (
    <main className="container narrow">
      <div className="card stack">
        <span className="badge">Configuración inicial</span>
        <div>
          <h1>Crea tu empresa</h1>
          <p className="muted">
            Este será el tenant principal de Bridata. Tus activos, órdenes y usuarios quedarán aislados de otras empresas.
          </p>
        </div>
        <form action={createWorkspace} className="stack">
          <label className="stack gap-6">
            <span>Nombre de empresa</span>
            <input className="input" name="name" placeholder="Ej. Empresa Agrícola Demo" required minLength={2} />
          </label>
          <button className="button" type="submit">Crear empresa</button>
        </form>
        <p className="muted small">Usuario administrador inicial: {user.email}</p>
      </div>
    </main>
  )
}
