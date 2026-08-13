import Link from 'next/link'

export default function HomePage() {
  return (
    <main className="container">
      <div className="header">
        <div>
          <span className="badge">Bridata CMMS</span>
          <h1>Maintenance Intelligence Platform</h1>
          <p className="muted">Activos, planes, órdenes de trabajo, inventario, costos y KPIs en una plataforma multiempresa.</p>
        </div>
      </div>
      <div className="grid">
        <div className="card"><strong>Activos</strong><div className="kpi">0</div><span className="muted">Jerarquía técnica</span></div>
        <div className="card"><strong>OT abiertas</strong><div className="kpi">0</div><span className="muted">Operación</span></div>
        <div className="card"><strong>Planes</strong><div className="kpi">0</div><span className="muted">Preventivo</span></div>
        <div className="card"><strong>Cumplimiento PM</strong><div className="kpi">—</div><span className="muted">KPI</span></div>
      </div>
      <p style={{ marginTop: 24 }}><Link className="button" href="/login">Ingresar</Link></p>
    </main>
  )
}
