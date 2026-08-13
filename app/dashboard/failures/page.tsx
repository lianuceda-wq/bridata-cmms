import Link from 'next/link'
import { requireTenant } from '@/lib/tenant'
import FailureReportForm from './FailureReportForm'
import { changeFailureStatus, createFailureCause, createFailureMode, updateFailureDiagnosis } from './actions'
import styles from './failures.module.css'

const severityLabels: Record<string,string> = { low:'Baja', medium:'Media', high:'Alta', critical:'Crítica' }
const statusLabels: Record<string,string> = { open:'Abierta', in_repair:'En reparación', restored:'Restaurada', closed:'Cerrada', cancelled:'Cancelada' }

function formatDate(value: string | null) {
  if (!value) return '—'
  return new Intl.DateTimeFormat('es-PE', { timeZone:'America/Lima', dateStyle:'medium', timeStyle:'short' }).format(new Date(value))
}
function hours(minutes: number | null | undefined) {
  return minutes === null || minutes === undefined ? '—' : `${(Number(minutes)/60).toFixed(2)} h`
}
function average(values: Array<number | null | undefined>) {
  const valid = values.map(Number).filter((value) => Number.isFinite(value))
  return valid.length ? valid.reduce((a,b) => a+b,0) / valid.length : null
}

export default async function FailuresPage({ searchParams }: { searchParams?: Promise<{ created?: string }> }) {
  const { supabase, tenant, role } = await requireTenant()
  const params = searchParams ? await searchParams : {}
  const canManage = ['owner','admin','planner','supervisor'].includes(role)

  const [
    { data: assets }, { data: modes }, { data: causes }, { data: failures }, { data: metrics }, { data: reliability },
  ] = await Promise.all([
    supabase.from('assets').select('id,code,name,site_id,location_id').eq('tenant_id',tenant.id).eq('is_active',true).order('code'),
    supabase.from('failure_modes').select('id,code,name,category').eq('tenant_id',tenant.id).eq('is_active',true).order('name'),
    supabase.from('failure_causes').select('id,failure_mode_id,code,name,category').eq('tenant_id',tenant.id).eq('is_active',true).order('name'),
    supabase.from('failure_events').select('id,code,asset_id,failure_mode_id,failure_cause_id,severity,status,symptom,description,occurred_at,reported_at,repair_started_at,restored_at,closed_at,root_cause_notes').eq('tenant_id',tenant.id).order('occurred_at',{ascending:false}).limit(200),
    supabase.from('failure_event_metrics').select('id,repair_minutes,downtime_minutes,response_minutes,detection_minutes,work_order_id,work_order_code,work_order_status').eq('tenant_id',tenant.id).order('occurred_at',{ascending:false}).limit(200),
    supabase.from('asset_reliability_metrics').select('asset_id,failure_count,failures_12m,mttr_hours,avg_downtime_hours,mtbf_hours').eq('tenant_id',tenant.id),
  ])

  const assetRows = assets ?? []
  const modeRows = modes ?? []
  const causeRows = causes ?? []
  const failureRows = failures ?? []
  const metricRows = metrics ?? []
  const reliabilityRows = reliability ?? []
  const assetMap = new Map(assetRows.map((row) => [row.id,row]))
  const modeMap = new Map(modeRows.map((row) => [row.id,row]))
  const causeMap = new Map(causeRows.map((row) => [row.id,row]))
  const metricMap = new Map(metricRows.map((row) => [row.id,row]))

  const activeStatuses = new Set(['open','in_repair','restored'])
  const activeFailures = failureRows.filter((row) => activeStatuses.has(row.status)).length
  const failures12m = reliabilityRows.reduce((sum,row) => sum + Number(row.failures_12m ?? 0),0)
  const mttrMinutes = average(metricRows.filter((row) => row.repair_minutes !== null).map((row) => Number(row.repair_minutes)))
  const downtimeMinutes = average(metricRows.filter((row) => row.downtime_minutes !== null).map((row) => Number(row.downtime_minutes)))
  const mtbfHours = average(reliabilityRows.filter((row) => row.mtbf_hours !== null).map((row) => Number(row.mtbf_hours)))

  return (
    <main className="content stack gap-24">
      <div className="header">
        <div>
          <span className="badge">Confiabilidad</span>
          <h1>Fallas y MTTR</h1>
          <p className="muted">{tenant.name} · hechos de falla, tiempos reales y trazabilidad hasta la OT.</p>
        </div>
        <Link href="/dashboard/work-orders" className="button button-secondary">Órdenes de trabajo</Link>
      </div>

      {params.created && <div className={styles.successBanner}><strong>{params.created}</strong> registrada. Si se generó una OT, sus cambios de estado actualizarán automáticamente la falla.</div>}

      <section className={styles.metrics}>
        <div><span>Fallas activas</span><strong>{activeFailures}</strong></div>
        <div><span>Fallas 12 meses</span><strong>{failures12m}</strong></div>
        <div><span>MTTR</span><strong>{mttrMinutes === null ? '—' : `${(mttrMinutes/60).toFixed(2)} h`}</strong><small>reparación efectiva</small></div>
        <div><span>Downtime medio</span><strong>{downtimeMinutes === null ? '—' : `${(downtimeMinutes/60).toFixed(2)} h`}</strong><small>falla → restauración</small></div>
        <div><span>MTBF</span><strong>{mtbfHours === null ? '—' : `${mtbfHours.toFixed(2)} h`}</strong><small>entre restauración y siguiente falla</small></div>
      </section>

      <FailureReportForm assets={assetRows} modes={modeRows} causes={causeRows} />

      {canManage && (
        <section className="grid grid-2">
          <form action={createFailureMode} className="card stack">
            <div><strong>Catálogo · modos de falla</strong><p className="muted small">Qué forma tomó la falla: rotura, fuga, obstrucción, desgaste, etc.</p></div>
            <div className="form-grid"><input className="input" name="code" placeholder="Código" required/><input className="input" name="name" placeholder="Nombre" required/></div>
            <input className="input" name="category" placeholder="Categoría opcional"/>
            <textarea className="input" name="description" rows={2} placeholder="Descripción"/>
            <button className="button" type="submit">Crear modo</button>
          </form>
          <form action={createFailureCause} className="card stack">
            <div><strong>Catálogo · causas</strong><p className="muted small">La causa puede asociarse a un modo para mantener consistencia del diagnóstico.</p></div>
            <select className="input" name="failure_mode_id" defaultValue=""><option value="">Causa transversal</option>{modeRows.map((m) => <option key={m.id} value={m.id}>{m.code} · {m.name}</option>)}</select>
            <div className="form-grid"><input className="input" name="code" placeholder="Código" required/><input className="input" name="name" placeholder="Nombre" required/></div>
            <input className="input" name="category" placeholder="Categoría opcional"/>
            <textarea className="input" name="description" rows={2} placeholder="Descripción"/>
            <button className="button" type="submit">Crear causa</button>
          </form>
        </section>
      )}

      <section className="card table-card">
        <div className="section-heading"><div><strong>Registro de fallas</strong><p className="muted small">El MTTR se calcula desde repair_started_at hasta restored_at; no desde horas-hombre.</p></div></div>
        {failureRows.length === 0 ? <div className="empty-state"><strong>Sin fallas registradas</strong><span className="muted">Los eventos correctivos aparecerán aquí.</span></div> : (
          <div className="table-wrap"><table>
            <thead><tr><th>Falla</th><th>Activo</th><th>Ocurrencia</th><th>Severidad</th><th>Estado</th><th>MTTR</th><th>Downtime</th><th>OT</th><th>Diagnóstico / acción</th></tr></thead>
            <tbody>{failureRows.map((failure) => {
              const asset = assetMap.get(failure.asset_id)
              const metric = metricMap.get(failure.id)
              const availableCauses = causeRows.filter((cause) => !cause.failure_mode_id || cause.failure_mode_id === failure.failure_mode_id)
              return <tr key={failure.id}>
                <td><span className="mono">{failure.code}</span><div className="muted small">{failure.symptom || failure.description}</div></td>
                <td><strong>{asset?.code ?? '—'}</strong><div className="muted small">{asset?.name ?? 'Activo'}</div></td>
                <td>{formatDate(failure.occurred_at)}<div className="muted small">Reporte {formatDate(failure.reported_at)}</div></td>
                <td><span className={`${styles.pill} ${styles[`severity_${failure.severity}`] ?? ''}`}>{severityLabels[failure.severity] ?? failure.severity}</span></td>
                <td><span className={styles.pill}>{statusLabels[failure.status] ?? failure.status}</span></td>
                <td><strong>{hours(metric?.repair_minutes)}</strong><div className="muted small">Resp. {hours(metric?.response_minutes)}</div></td>
                <td>{hours(metric?.downtime_minutes)}</td>
                <td>{metric?.work_order_id ? <Link className={styles.woLink} href={`/dashboard/work-orders/${metric.work_order_id}`}>{metric.work_order_code || 'Ver OT'} →</Link> : <span className="muted">Sin OT</span>}</td>
                <td>
                  {canManage ? <div className={styles.rowActions}>
                    <form action={updateFailureDiagnosis} className={styles.diagnosisForm}>
                      <input type="hidden" name="id" value={failure.id}/>
                      <select className="input input-compact" name="failure_mode_id" defaultValue={failure.failure_mode_id ?? ''}><option value="">Modo</option>{modeRows.map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}</select>
                      <select className="input input-compact" name="failure_cause_id" defaultValue={failure.failure_cause_id ?? ''}><option value="">Causa</option>{availableCauses.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</select>
                      <input className="input input-compact" name="root_cause_notes" defaultValue={failure.root_cause_notes ?? ''} placeholder="Nota causa raíz"/>
                      <button className="button button-secondary button-compact" type="submit">Guardar</button>
                    </form>
                    {!metric?.work_order_id && failure.status === 'open' && <form action={changeFailureStatus}><input type="hidden" name="id" value={failure.id}/><input type="hidden" name="status" value="in_repair"/><button className="button button-secondary button-compact" type="submit">Iniciar reparación</button></form>}
                    {!metric?.work_order_id && failure.status === 'in_repair' && <form action={changeFailureStatus}><input type="hidden" name="id" value={failure.id}/><input type="hidden" name="status" value="restored"/><button className="button button-secondary button-compact" type="submit">Restaurar</button></form>}
                    {!metric?.work_order_id && failure.status === 'restored' && <form action={changeFailureStatus}><input type="hidden" name="id" value={failure.id}/><input type="hidden" name="status" value="closed"/><button className="button button-compact" type="submit">Cerrar</button></form>}
                  </div> : <span className="muted small">{modeMap.get(failure.failure_mode_id ?? '')?.name ?? 'Sin modo'} · {causeMap.get(failure.failure_cause_id ?? '')?.name ?? 'Sin causa'}</span>}
                </td>
              </tr>
            })}</tbody>
          </table></div>
        )}
      </section>

      <section className="card table-card">
        <div className="section-heading"><div><strong>Confiabilidad por activo</strong><p className="muted small">MTBF solo aparece cuando existe al menos un intervalo operativo entre dos fallas restauradas.</p></div></div>
        {reliabilityRows.length === 0 ? <div className="empty-state"><span className="muted">Aún no existen suficientes fallas para calcular confiabilidad.</span></div> : (
          <div className="table-wrap"><table><thead><tr><th>Activo</th><th>Fallas</th><th>12 meses</th><th>MTTR</th><th>Downtime</th><th>MTBF</th></tr></thead><tbody>
            {reliabilityRows.map((row) => { const asset=assetMap.get(row.asset_id); return <tr key={row.asset_id}><td><strong>{asset?.code ?? '—'}</strong><div className="muted small">{asset?.name}</div></td><td>{row.failure_count}</td><td>{row.failures_12m}</td><td>{row.mttr_hours === null ? '—' : `${row.mttr_hours} h`}</td><td>{row.avg_downtime_hours === null ? '—' : `${row.avg_downtime_hours} h`}</td><td>{row.mtbf_hours === null ? '—' : `${row.mtbf_hours} h`}</td></tr> })}
          </tbody></table></div>
        )}
      </section>
    </main>
  )
}
