import Link from 'next/link'
import { requireTenant } from '@/lib/tenant'
import HydraulicCaptureForm from './HydraulicCaptureForm'
import { changeHydraulicSessionStatus } from './actions'
import styles from './hydraulics.module.css'

const statusLabels: Record<string, string> = {
  draft: 'Borrador', submitted: 'En validación', validated: 'Validado', cancelled: 'Cancelado',
}

function formatDate(value: string | null) {
  if (!value) return '—'
  return new Intl.DateTimeFormat('es-PE', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
}

export default async function HydraulicsPage({ searchParams }: { searchParams?: Promise<{ created?: string }> }) {
  const { supabase, tenant, role } = await requireTenant()
  const params = searchParams ? await searchParams : {}
  const canManage = ['owner', 'admin', 'planner', 'supervisor'].includes(role)

  const [
    { data: sites }, { data: locations }, { data: models }, { data: configs }, { data: sessions }, { data: kpis },
  ] = await Promise.all([
    supabase.from('sites').select('id,name,code').eq('tenant_id', tenant.id).order('name'),
    supabase.from('locations').select('id,site_id,parent_location_id,code,name,location_type').eq('tenant_id', tenant.id).order('name'),
    supabase.from('hydraulic_component_models').select('id,component_type,name').eq('tenant_id', tenant.id).eq('is_active', true).order('name'),
    supabase.from('hydraulic_location_configs').select('location_id,hose_model_id,valve_model_id,pilot_model_id,valid_from,valid_to').eq('tenant_id', tenant.id).eq('is_active', true).order('valid_from', { ascending: false }),
    supabase.from('measurement_sessions').select('id,code,status,site_id,location_id,occurred_at,responsible_name,source_type,created_at').eq('tenant_id', tenant.id).eq('session_type', 'hydraulic_control').order('occurred_at', { ascending: false }).limit(60),
    supabase.from('hydraulic_session_kpis').select('session_id,total_readings,evaluated_readings,compliant_readings,out_of_range_readings,compliance_percent,avg_pressure,avg_flow').eq('tenant_id', tenant.id).order('occurred_at', { ascending: false }).limit(60),
  ])

  const siteRows = sites ?? []
  const locationRows = locations ?? []
  const sessionRows = sessions ?? []
  const kpiMap = new Map((kpis ?? []).map((kpi) => [kpi.session_id, kpi]))
  const siteMap = new Map(siteRows.map((site) => [site.id, site]))
  const locationMap = new Map(locationRows.map((location) => [location.id, location]))

  const validated = sessionRows.filter((session) => session.status === 'validated').length
  const pending = sessionRows.filter((session) => session.status === 'submitted').length
  const aggregateEvaluated = (kpis ?? []).reduce((sum, kpi) => sum + Number(kpi.evaluated_readings ?? 0), 0)
  const aggregateCompliant = (kpis ?? []).reduce((sum, kpi) => sum + Number(kpi.compliant_readings ?? 0), 0)
  const aggregateCompliance = aggregateEvaluated ? Math.round((aggregateCompliant / aggregateEvaluated) * 1000) / 10 : null

  return (
    <main className="content stack gap-24">
      <div className="header">
        <div>
          <span className="badge">Operación de riego</span>
          <h1>Control hidráulico</h1>
          <p className="muted">{tenant.name} · presión, caudal y cumplimiento por turno/lote.</p>
        </div>
        <div className={styles.pageActions}>
          <Link className="button button-secondary" href="/dashboard/settings/measurements">Configurar nominales</Link>
        </div>
      </div>

      {params.created && (
        <div className={styles.successBanner}>
          <strong>{params.created}</strong> se guardó correctamente. El cumplimiento usa el nominal vigente de cada punto y ubicación.
        </div>
      )}

      <section className={styles.metrics}>
        <div><span>Controles recientes</span><strong>{sessionRows.length}</strong></div>
        <div><span>Pendientes de validar</span><strong>{pending}</strong></div>
        <div><span>Validados</span><strong>{validated}</strong></div>
        <div><span>Cumplimiento</span><strong>{aggregateCompliance === null ? '—' : `${aggregateCompliance}%`}</strong></div>
      </section>

      {siteRows.length === 0 ? (
        <section className="card empty-state">
          <strong>Primero registra un fundo/sede</strong>
          <span className="muted">El control hidráulico necesita una estructura operativa de ubicaciones.</span>
          <Link href="/dashboard/assets" className="button">Ir a Activos y ubicaciones</Link>
        </section>
      ) : (
        <HydraulicCaptureForm sites={siteRows} locations={locationRows} models={models ?? []} configs={configs ?? []} />
      )}

      <section className="card table-card">
        <div className="section-heading">
          <div><strong>Historial de controles</strong><p className="muted small">Cada control conserva las lecturas y nominales aplicados en la fecha de medición.</p></div>
        </div>
        {sessionRows.length === 0 ? (
          <div className="empty-state"><strong>Sin controles registrados</strong><span className="muted">La primera jornada aparecerá aquí.</span></div>
        ) : (
          <div className="table-wrap"><table>
            <thead><tr><th>Control</th><th>Fecha</th><th>Fundo / parcela</th><th>Responsable</th><th>Lecturas</th><th>Cumplimiento</th><th>Fuera rango</th><th>Estado</th><th>Acción</th></tr></thead>
            <tbody>{sessionRows.map((session) => {
              const kpi = kpiMap.get(session.id)
              const site = session.site_id ? siteMap.get(session.site_id) : null
              const location = session.location_id ? locationMap.get(session.location_id) : null
              return <tr key={session.id}>
                <td><span className="mono">{session.code ?? '—'}</span><div className="muted small">Origen: {session.source_type}</div></td>
                <td>{formatDate(session.occurred_at)}</td>
                <td><strong>{site?.name ?? '—'}</strong><div className="muted small">{location ? `${location.code || ''} ${location.name}`.trim() : 'Sin parcela cabecera'}</div></td>
                <td>{session.responsible_name || '—'}</td>
                <td>{Number(kpi?.total_readings ?? 0)}</td>
                <td><strong>{kpi?.compliance_percent === null || kpi?.compliance_percent === undefined ? '—' : `${kpi.compliance_percent}%`}</strong></td>
                <td><span className={Number(kpi?.out_of_range_readings ?? 0) > 0 ? styles.outOfRange : ''}>{Number(kpi?.out_of_range_readings ?? 0)}</span></td>
                <td><span className={styles.statusPill}>{statusLabels[session.status] ?? session.status}</span></td>
                <td>
                  {canManage && session.status === 'submitted' ? (
                    <form action={changeHydraulicSessionStatus} className="inline-form">
                      <input type="hidden" name="id" value={session.id} /><input type="hidden" name="status" value="validated" />
                      <button className="button button-compact" type="submit">Validar</button>
                    </form>
                  ) : <span className="muted">—</span>}
                </td>
              </tr>
            })}</tbody>
          </table></div>
        )}
      </section>
    </main>
  )
}
