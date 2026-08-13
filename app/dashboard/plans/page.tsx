import {
  assignAssetToPlan,
  createMeter,
  createPlan,
  createRoutine,
  createRoutineTask,
  recordMeterReading,
  updatePlanStatus,
} from './actions'
import { requireTenant } from '@/lib/tenant'

const managerRoles = new Set(['owner', 'admin', 'planner', 'supervisor'])
const readingRoles = new Set(['owner', 'admin', 'planner', 'supervisor', 'technician'])

const triggerLabel: Record<string, string> = {
  calendar: 'Calendario',
  meter: 'Medidor',
}

const unitLabel: Record<string, string> = {
  day: 'día(s)',
  week: 'semana(s)',
  month: 'mes(es)',
  year: 'año(s)',
  hour: 'hora(s)',
  cycle: 'ciclo(s)',
  km: 'km',
  m3: 'm³',
  unit: 'unidad(es)',
}

const planStatusLabel: Record<string, string> = {
  draft: 'Borrador',
  active: 'Activo',
  paused: 'Pausado',
  archived: 'Archivado',
}

function formatNumber(value: number | string | null | undefined) {
  if (value === null || value === undefined) return '—'
  return new Intl.NumberFormat('es-PE', { maximumFractionDigits: 2 }).format(Number(value))
}

function formatDate(value: string | null | undefined) {
  if (!value) return '—'
  return new Intl.DateTimeFormat('es-PE', { dateStyle: 'medium' }).format(new Date(value))
}

export default async function PlansPage() {
  const { supabase, tenant, role } = await requireTenant()
  const canManage = managerRoles.has(role)
  const canRecord = readingRoles.has(role)

  const [
    { data: plans },
    { data: assets },
    { data: meters },
    { data: assignments },
    { data: routines },
    { data: tasks },
    { data: schedules },
  ] = await Promise.all([
    supabase.from('maintenance_plans').select('id,code,name,description,status,version').eq('tenant_id', tenant.id).order('name'),
    supabase.from('assets').select('id,code,name,asset_type,status').eq('tenant_id', tenant.id).eq('is_active', true).order('name'),
    supabase.from('asset_meters').select('id,asset_id,code,name,meter_type,unit,current_value,last_reading_at').eq('tenant_id', tenant.id).order('name'),
    supabase.from('maintenance_plan_assets').select('id,plan_id,asset_id,start_at,active').eq('tenant_id', tenant.id).order('created_at'),
    supabase.from('maintenance_routines').select('id,plan_id,code,name,maintenance_type,priority,trigger_type,interval_value,interval_unit,meter_code,estimated_minutes,active').eq('tenant_id', tenant.id).order('created_at'),
    supabase.from('maintenance_routine_tasks').select('id,routine_id,sequence,title,instructions,estimated_minutes,mandatory,task_type,requires_evidence,measurement_unit,min_value,max_value').eq('tenant_id', tenant.id).order('sequence'),
    supabase.from('maintenance_schedule_states').select('id,plan_id,plan_asset_id,routine_id,meter_id,status,blocked_reason,next_due_at,next_due_meter').eq('tenant_id', tenant.id).order('created_at'),
  ])

  const planRows = plans ?? []
  const assetRows = assets ?? []
  const meterRows = meters ?? []
  const assignmentRows = assignments ?? []
  const routineRows = routines ?? []
  const taskRows = tasks ?? []
  const scheduleRows = schedules ?? []

  const assetById = new Map(assetRows.map((asset) => [asset.id, asset]))
  const meterById = new Map(meterRows.map((meter) => [meter.id, meter]))
  const assignmentById = new Map(assignmentRows.map((assignment) => [assignment.id, assignment]))
  const routineById = new Map(routineRows.map((routine) => [routine.id, routine]))

  const activePlans = planRows.filter((plan) => plan.status === 'active').length
  const plannedAssets = new Set(assignmentRows.filter((row) => row.active).map((row) => row.asset_id)).size
  const blockedSchedules = scheduleRows.filter((state) => state.status === 'blocked').length

  return (
    <main className="content stack gap-24">
      <div className="header">
        <div>
          <span className="badge">Planes</span>
          <h1>Planes de mantenimiento</h1>
          <p className="muted">{tenant.name} · planifica por calendario y medidores acumulativos.</p>
        </div>
        <div className="summary-chip">{planRows.length} planes</div>
      </div>

      <section className="grid">
        <div className="card"><strong>Planes activos</strong><div className="kpi">{activePlans}</div><span className="muted">En operación</span></div>
        <div className="card"><strong>Activos planificados</strong><div className="kpi">{plannedAssets}</div><span className="muted">Con plan asignado</span></div>
        <div className="card"><strong>Rutinas</strong><div className="kpi">{routineRows.length}</div><span className="muted">Frecuencias configuradas</span></div>
        <div className="card"><strong>Bloqueos</strong><div className="kpi">{blockedSchedules}</div><span className="muted">Programaciones sin medidor</span></div>
      </section>

      {canManage && (
        <section className="stack gap-24">
          <div className="section-heading">
            <div>
              <strong>Construcción del plan</strong>
              <p className="muted small">Primero crea el plan, luego asigna activos y configura sus medidores.</p>
            </div>
          </div>

          <div className="grid grid-3">
            <form action={createPlan} className="card stack">
              <div>
                <strong>1. Nuevo plan</strong>
                <p className="muted small">Plantilla reutilizable de mantenimiento.</p>
              </div>
              <div className="form-grid">
                <input className="input" name="code" placeholder="PM-BOMBAS" required />
                <select className="input" name="status" defaultValue="active">
                  <option value="draft">Borrador</option>
                  <option value="active">Activo</option>
                  <option value="paused">Pausado</option>
                </select>
              </div>
              <input className="input" name="name" placeholder="Mantenimiento de bombas" required />
              <input className="input" name="description" placeholder="Descripción opcional" />
              <button className="button" type="submit">Crear plan</button>
            </form>

            <form action={assignAssetToPlan} className="card stack">
              <div>
                <strong>2. Asignar activo</strong>
                <p className="muted small">Un plan puede atender varios equipos equivalentes.</p>
              </div>
              <select className="input" name="plan_id" required defaultValue="">
                <option value="" disabled>Selecciona plan</option>
                {planRows.map((plan) => <option key={plan.id} value={plan.id}>{plan.code} · {plan.name}</option>)}
              </select>
              <select className="input" name="asset_id" required defaultValue="">
                <option value="" disabled>Selecciona activo</option>
                {assetRows.map((asset) => <option key={asset.id} value={asset.id}>{asset.code} · {asset.name}</option>)}
              </select>
              <button className="button" type="submit">Asignar activo</button>
            </form>

            <form action={createMeter} className="card stack">
              <div>
                <strong>3. Medidor del activo</strong>
                <p className="muted small">Horómetro, ciclos, km, m³ u otro acumulador.</p>
              </div>
              <select className="input" name="asset_id" required defaultValue="">
                <option value="" disabled>Selecciona activo</option>
                {assetRows.map((asset) => <option key={asset.id} value={asset.id}>{asset.code} · {asset.name}</option>)}
              </select>
              <div className="form-grid">
                <input className="input" name="code" placeholder="HORAS" required />
                <input className="input" name="name" placeholder="Horómetro principal" required />
              </div>
              <div className="form-grid">
                <select className="input" name="meter_type" defaultValue="hours">
                  <option value="hours">Horas</option>
                  <option value="cycles">Ciclos</option>
                  <option value="distance">Distancia</option>
                  <option value="volume">Volumen</option>
                  <option value="energy">Energía</option>
                  <option value="custom">Personalizado</option>
                </select>
                <input className="input" name="unit" placeholder="h, ciclos, km, m³" required />
              </div>
              <input className="input" name="current_value" type="number" step="0.01" min="0" placeholder="Lectura inicial (opcional)" />
              <button className="button" type="submit">Crear medidor</button>
            </form>
          </div>

          <div className="grid">
            <form action={createRoutine} className="card stack">
              <div>
                <strong>4. Rutina / frecuencia</strong>
                <p className="muted small">Ejemplo: cada 30 días o cada 250 horas.</p>
              </div>
              <select className="input" name="plan_id" required defaultValue="">
                <option value="" disabled>Selecciona plan</option>
                {planRows.map((plan) => <option key={plan.id} value={plan.id}>{plan.code} · {plan.name}</option>)}
              </select>
              <div className="form-grid">
                <input className="input" name="code" placeholder="250H" required />
                <input className="input" name="name" placeholder="Servicio 250 horas" required />
              </div>
              <input className="input" name="description" placeholder="Alcance de la rutina" />
              <div className="form-grid">
                <select className="input" name="trigger_type" defaultValue="calendar">
                  <option value="calendar">Calendario</option>
                  <option value="meter">Medidor</option>
                </select>
                <select className="input" name="priority" defaultValue="medium">
                  <option value="low">Prioridad baja</option>
                  <option value="medium">Prioridad media</option>
                  <option value="high">Prioridad alta</option>
                  <option value="critical">Prioridad crítica</option>
                </select>
              </div>
              <div className="form-grid">
                <input className="input" name="interval_value" type="number" step="0.01" min="0.01" placeholder="Frecuencia" required />
                <select className="input" name="interval_unit" defaultValue="day">
                  <optgroup label="Calendario">
                    <option value="day">Días</option>
                    <option value="week">Semanas</option>
                    <option value="month">Meses</option>
                    <option value="year">Años</option>
                  </optgroup>
                  <optgroup label="Medidor">
                    <option value="hour">Horas</option>
                    <option value="cycle">Ciclos</option>
                    <option value="km">Kilómetros</option>
                    <option value="m3">m³</option>
                    <option value="unit">Unidades</option>
                  </optgroup>
                </select>
              </div>
              <input className="input" name="meter_code" placeholder="Código de medidor si aplica, ej. HORAS" />
              <div className="form-grid">
                <input className="input" name="estimated_minutes" type="number" min="0" placeholder="Duración estimada (min)" />
                <input className="input" name="lead_time_days" type="number" min="0" placeholder="Anticipación (días)" />
              </div>
              <select className="input" name="maintenance_type" defaultValue="preventive">
                <option value="preventive">Preventivo</option>
                <option value="predictive">Predictivo</option>
                <option value="inspection">Inspección</option>
                <option value="improvement">Mejora</option>
              </select>
              <button className="button" type="submit">Agregar rutina</button>
            </form>

            <form action={createRoutineTask} className="card stack">
              <div>
                <strong>5. Actividad / checklist</strong>
                <p className="muted small">Actividades ordenadas que ejecutará el técnico.</p>
              </div>
              <select className="input" name="routine_id" required defaultValue="">
                <option value="" disabled>Selecciona rutina</option>
                {routineRows.map((routine) => {
                  const plan = planRows.find((item) => item.id === routine.plan_id)
                  return <option key={routine.id} value={routine.id}>{plan?.code ?? 'PLAN'} · {routine.code} · {routine.name}</option>
                })}
              </select>
              <div className="form-grid">
                <input className="input" name="sequence" type="number" min="1" defaultValue="1" required />
                <select className="input" name="task_type" defaultValue="task">
                  <option value="task">Tarea</option>
                  <option value="inspection">Inspección</option>
                  <option value="measurement">Medición</option>
                  <option value="safety">Seguridad</option>
                </select>
              </div>
              <input className="input" name="title" placeholder="Revisar fugas en sello mecánico" required />
              <input className="input" name="instructions" placeholder="Instrucciones opcionales" />
              <div className="form-grid">
                <input className="input" name="estimated_minutes" type="number" min="0" placeholder="Minutos" />
                <input className="input" name="measurement_unit" placeholder="Unidad de medición" />
              </div>
              <div className="form-grid">
                <input className="input" name="min_value" type="number" step="0.01" placeholder="Mínimo" />
                <input className="input" name="max_value" type="number" step="0.01" placeholder="Máximo" />
              </div>
              <label className="check-row"><input type="checkbox" name="mandatory" defaultChecked /> Actividad obligatoria</label>
              <label className="check-row"><input type="checkbox" name="requires_evidence" /> Requiere evidencia/foto</label>
              <button className="button" type="submit">Agregar actividad</button>
            </form>
          </div>
        </section>
      )}

      {canRecord && meterRows.length > 0 && (
        <section className="card stack">
          <div className="section-heading">
            <div>
              <strong>Registrar lectura</strong>
              <p className="muted small">Las lecturas acumulativas alimentarán las rutinas por horómetro o medidor.</p>
            </div>
          </div>
          <form action={recordMeterReading} className="reading-form">
            <select className="input" name="meter_id" required defaultValue="">
              <option value="" disabled>Selecciona medidor</option>
              {meterRows.map((meter) => {
                const asset = assetById.get(meter.asset_id)
                return <option key={meter.id} value={meter.id}>{asset?.code ?? 'ACT'} · {meter.code} · {formatNumber(meter.current_value)} {meter.unit}</option>
              })}
            </select>
            <input className="input" name="value" type="number" min="0" step="0.01" placeholder="Nueva lectura" required />
            <input className="input" name="notes" placeholder="Observación opcional" />
            <button className="button" type="submit">Guardar lectura</button>
          </form>
        </section>
      )}

      <section className="stack gap-24">
        <div className="section-heading">
          <div>
            <strong>Planes configurados</strong>
            <p className="muted small">Vista consolidada de activos, rutinas, actividades y próxima ejecución.</p>
          </div>
        </div>

        {planRows.length === 0 ? (
          <div className="card empty-state">
            <strong>Aún no hay planes de mantenimiento</strong>
            <span className="muted">Crea el primer plan y asígnalo a uno o más activos.</span>
          </div>
        ) : (
          <div className="plan-list">
            {planRows.map((plan) => {
              const planAssignments = assignmentRows.filter((row) => row.plan_id === plan.id)
              const planRoutines = routineRows.filter((row) => row.plan_id === plan.id)
              const planSchedules = scheduleRows.filter((row) => row.plan_id === plan.id)

              return (
                <article className="card plan-card" key={plan.id}>
                  <div className="plan-header">
                    <div>
                      <div className="plan-title-row">
                        <span className="mono">{plan.code}</span>
                        <span className={`status plan-status-${plan.status}`}>{planStatusLabel[plan.status] ?? plan.status}</span>
                      </div>
                      <h2>{plan.name}</h2>
                      <p className="muted small">{plan.description || 'Sin descripción'} · versión {plan.version}</p>
                    </div>
                    {canManage && (
                      <form action={updatePlanStatus} className="inline-form">
                        <input type="hidden" name="id" value={plan.id} />
                        <select className="input input-compact" name="status" defaultValue={plan.status}>
                          <option value="draft">Borrador</option>
                          <option value="active">Activo</option>
                          <option value="paused">Pausado</option>
                          <option value="archived">Archivado</option>
                        </select>
                        <button className="button button-secondary button-compact" type="submit">Guardar</button>
                      </form>
                    )}
                  </div>

                  <div className="plan-columns">
                    <div className="stack gap-6">
                      <strong className="small">Activos asignados · {planAssignments.length}</strong>
                      {planAssignments.length === 0 ? <span className="muted small">Sin activos asignados</span> : planAssignments.map((assignment) => {
                        const asset = assetById.get(assignment.asset_id)
                        return <div className="list-row" key={assignment.id}><span><span className="mono">{asset?.code ?? '—'}</span> · {asset?.name ?? 'Activo'}</span><span className="muted small">desde {formatDate(assignment.start_at)}</span></div>
                      })}
                    </div>

                    <div className="stack gap-6">
                      <strong className="small">Rutinas · {planRoutines.length}</strong>
                      {planRoutines.length === 0 ? <span className="muted small">Sin rutinas</span> : planRoutines.map((routine) => {
                        const routineTasks = taskRows.filter((task) => task.routine_id === routine.id)
                        return (
                          <div className="routine-box" key={routine.id}>
                            <div className="list-row">
                              <div>
                                <span className="mono">{routine.code}</span> · <strong>{routine.name}</strong>
                                <div className="muted small">{triggerLabel[routine.trigger_type] ?? routine.trigger_type} · cada {formatNumber(routine.interval_value)} {unitLabel[routine.interval_unit] ?? routine.interval_unit}{routine.meter_code ? ` · ${routine.meter_code}` : ''}</div>
                              </div>
                              <span className={`status status-${routine.priority}`}>{routine.priority}</span>
                            </div>
                            {routineTasks.length > 0 && (
                              <ol className="task-list">
                                {routineTasks.map((task) => (
                                  <li key={task.id}>
                                    <span>{task.title}</span>
                                    <span className="muted small">{task.mandatory ? 'obligatoria' : 'opcional'}{task.requires_evidence ? ' · evidencia' : ''}</span>
                                  </li>
                                ))}
                              </ol>
                            )}
                          </div>
                        )
                      })}
                    </div>
                  </div>

                  <div className="schedule-strip">
                    <strong className="small">Programación</strong>
                    {planSchedules.length === 0 ? (
                      <span className="muted small">Se generará al combinar activos y rutinas.</span>
                    ) : (
                      <div className="schedule-grid">
                        {planSchedules.map((state) => {
                          const assignment = assignmentById.get(state.plan_asset_id)
                          const asset = assignment ? assetById.get(assignment.asset_id) : null
                          const routine = routineById.get(state.routine_id)
                          const meter = state.meter_id ? meterById.get(state.meter_id) : null
                          const due = state.next_due_at
                            ? formatDate(state.next_due_at)
                            : state.next_due_meter !== null
                              ? `${formatNumber(state.next_due_meter)} ${meter?.unit ?? ''}`
                              : 'Pendiente'
                          return (
                            <div className="schedule-item" key={state.id}>
                              <span><strong>{asset?.code ?? 'ACT'}</strong> · {routine?.code ?? 'Rutina'}</span>
                              <span>{due}</span>
                              <span className={`status schedule-${state.status}`}>{state.status}</span>
                              {state.blocked_reason && <span className="muted small">{state.blocked_reason}</span>}
                            </div>
                          )
                        })}
                      </div>
                    )}
                  </div>
                </article>
              )
            })}
          </div>
        )}
      </section>
    </main>
  )
}
