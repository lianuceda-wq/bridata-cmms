import { requireTenant } from '@/lib/tenant'
import { createHydraulicComponentModel, createTargetVersion, saveLocationHydraulicConfig } from './actions'
import styles from './measurements.module.css'

const scopeLabel: Record<string, string> = {
  farm: 'Fundo', area: 'Área', system: 'Sistema', sector: 'Sector', parcel: 'Parcela', lot: 'Lote',
  pumping_station: 'Estación de bombeo', hydraulic_zone: 'Zona hidráulica', line: 'Línea', warehouse: 'Almacén', other: 'Otro',
}

const componentLabels: Record<string, string> = {
  hose: 'Manguera', valve: 'Válvula', pilot: 'Piloto', filter: 'Filtro',
}

function fmt(value: number | null) {
  return value === null ? '—' : String(value)
}

export default async function MeasurementSettingsPage() {
  const { supabase, tenant, role } = await requireTenant()
  const canManage = ['owner', 'admin', 'planner', 'supervisor'].includes(role)

  const [
    { data: parameters }, { data: points }, { data: units }, { data: sites }, { data: locations },
    { data: assets }, { data: targets }, { data: models }, { data: configs },
  ] = await Promise.all([
    supabase.from('measurement_parameters').select('id,code,name,quantity,default_unit_id').eq('tenant_id', tenant.id).eq('is_active', true).order('name'),
    supabase.from('measurement_points').select('id,code,name,group_code,suggested_parameter_code,sequence').eq('tenant_id', tenant.id).eq('is_active', true).order('sequence'),
    supabase.from('measurement_units').select('id,code,name,symbol,quantity').eq('is_active', true).order('quantity'),
    supabase.from('sites').select('id,name,code').eq('tenant_id', tenant.id).order('name'),
    supabase.from('locations').select('id,site_id,parent_location_id,code,name,location_type').eq('tenant_id', tenant.id).order('name'),
    supabase.from('assets').select('id,site_id,location_id,code,name').eq('tenant_id', tenant.id).eq('is_active', true).order('name'),
    supabase.from('measurement_targets').select('id,parameter_id,point_id,site_id,location_id,asset_id,unit_id,target_value,min_value,max_value,tolerance_percent,valid_from,valid_to,is_active,notes,created_at').eq('tenant_id', tenant.id).order('valid_from', { ascending: false }).limit(200),
    supabase.from('hydraulic_component_models').select('id,component_type,code,name,manufacturer,is_active').eq('tenant_id', tenant.id).order('component_type').order('name'),
    supabase.from('hydraulic_location_configs').select('id,location_id,hose_model_id,valve_model_id,pilot_model_id,valid_from,valid_to,is_active,notes').eq('tenant_id', tenant.id).order('valid_from', { ascending: false }).limit(150),
  ])

  const parameterRows = parameters ?? []
  const pointRows = points ?? []
  const unitRows = units ?? []
  const siteRows = sites ?? []
  const locationRows = locations ?? []
  const assetRows = assets ?? []
  const targetRows = targets ?? []
  const modelRows = models ?? []
  const configRows = configs ?? []

  const parameterMap = new Map(parameterRows.map((x) => [x.id, x]))
  const pointMap = new Map(pointRows.map((x) => [x.id, x]))
  const unitMap = new Map(unitRows.map((x) => [x.id, x]))
  const siteMap = new Map(siteRows.map((x) => [x.id, x]))
  const locationMap = new Map(locationRows.map((x) => [x.id, x]))
  const assetMap = new Map(assetRows.map((x) => [x.id, x]))
  const modelMap = new Map(modelRows.map((x) => [x.id, x]))

  const activeTargets = targetRows.filter((t) => t.is_active && !t.valid_to).length
  const hydraulicTargets = targetRows.filter((t) => {
    const p = parameterMap.get(t.parameter_id)
    return p?.code === 'pressure' || p?.code === 'flow'
  }).length

  return (
    <main className="content stack gap-24">
      <div className="header">
        <div>
          <span className="badge">Configuración operacional</span>
          <h1>Nominales y parámetros</h1>
          <p className="muted">{tenant.name} · objetivos versionados, límites y catálogos hidráulicos.</p>
        </div>
        <div className={styles.heroStats}>
          <span><strong>{activeTargets}</strong> vigentes</span>
          <span><strong>{hydraulicTargets}</strong> hidráulicos</span>
        </div>
      </div>

      <section className={styles.explainer}>
        <strong>Jerarquía de resolución</strong>
        <span>Activo → Lote → Sector → Parcela → Fundo/sede → Empresa.</span>
        <p className="muted small">BRIDATA guarda una copia del nominal, mínimo y máximo que aplicaba al momento de cada lectura. Cambiar un nominal futuro no altera históricos.</p>
      </section>

      {canManage && (
        <section className="grid grid-3">
          <form action={createTargetVersion} className="card stack">
            <div>
              <strong>Nueva versión de nominal</strong>
              <p className="muted small">Si ya existe una versión anterior para el mismo alcance, se cierra automáticamente el día previo.</p>
            </div>

            <select className="input" name="parameter_id" required defaultValue="">
              <option value="" disabled>Parámetro</option>
              {parameterRows.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
            <select className="input" name="point_id" defaultValue="">
              <option value="">Todos los puntos</option>
              {pointRows.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
            <select className="input" name="site_id" defaultValue="">
              <option value="">Toda la empresa</option>
              {siteRows.map((site) => <option key={site.id} value={site.id}>{site.name}</option>)}
            </select>
            <select className="input" name="location_id" defaultValue="">
              <option value="">Sin ubicación específica</option>
              {locationRows.map((loc) => <option key={loc.id} value={loc.id}>{scopeLabel[loc.location_type] ?? loc.location_type} · {loc.code || loc.name}</option>)}
            </select>
            <select className="input" name="asset_id" defaultValue="">
              <option value="">Sin activo específico</option>
              {assetRows.map((asset) => <option key={asset.id} value={asset.id}>{asset.code} · {asset.name}</option>)}
            </select>
            <select className="input" name="unit_id" required defaultValue="">
              <option value="" disabled>Unidad</option>
              {unitRows.map((u) => <option key={u.id} value={u.id}>{u.symbol} · {u.name}</option>)}
            </select>
            <div className="form-grid">
              <input className="input" name="target_value" type="number" step="any" placeholder="Nominal" />
              <input className="input" name="tolerance_percent" type="number" step="any" min="0" placeholder="Tolerancia %" />
            </div>
            <div className="form-grid">
              <input className="input" name="min_value" type="number" step="any" placeholder="Mínimo" />
              <input className="input" name="max_value" type="number" step="any" placeholder="Máximo" />
            </div>
            <label className={styles.fieldLabel}>Vigente desde
              <input className="input" name="valid_from" type="date" required />
            </label>
            <textarea className="input" name="notes" rows={2} placeholder="Motivo / observación de la configuración" />
            <button className="button" type="submit">Crear versión</button>
          </form>

          <form action={createHydraulicComponentModel} className="card stack">
            <div>
              <strong>Catálogo hidráulico</strong>
              <p className="muted small">Mangueras, válvulas y pilotos que aparecen en los formatos de campo.</p>
            </div>
            <select className="input" name="component_type" required defaultValue="hose">
              {Object.entries(componentLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
            </select>
            <input className="input" name="name" placeholder="Ej. Aries / S100 / PC-SHARP" required />
            <div className="form-grid">
              <input className="input" name="code" placeholder="Código opcional" />
              <input className="input" name="manufacturer" placeholder="Fabricante" />
            </div>
            <button className="button" type="submit">Agregar al catálogo</button>

            <div className={styles.catalogPreview}>
              {modelRows.slice(0, 12).map((model) => (
                <span key={model.id}><b>{componentLabels[model.component_type] ?? model.component_type}:</b> {model.name}</span>
              ))}
              {modelRows.length === 0 && <span className="muted small">Aún no hay modelos registrados.</span>}
            </div>
          </form>

          <form action={saveLocationHydraulicConfig} className="card stack">
            <div>
              <strong>Configuración por lote</strong>
              <p className="muted small">Asocia la configuración física para precargarla durante la captura.</p>
            </div>
            <select className="input" name="location_id" required defaultValue="">
              <option value="" disabled>Selecciona lote / ubicación</option>
              {locationRows.map((loc) => <option key={loc.id} value={loc.id}>{loc.code || loc.name} · {loc.name}</option>)}
            </select>
            {(['hose','valve','pilot'] as const).map((type) => (
              <select key={type} className="input" name={`${type}_model_id`} defaultValue="">
                <option value="">Sin {componentLabels[type].toLowerCase()}</option>
                {modelRows.filter((m) => m.component_type === type).map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}
              </select>
            ))}
            <label className={styles.fieldLabel}>Vigente desde
              <input className="input" name="valid_from" type="date" required />
            </label>
            <textarea className="input" name="notes" rows={2} placeholder="Observación" />
            <button className="button" type="submit">Guardar configuración</button>
          </form>
        </section>
      )}

      <section className="card table-card">
        <div className="section-heading">
          <div><strong>Historial de nominales</strong><p className="muted small">Cada fila es una versión trazable; no se sobreescribe el histórico.</p></div>
        </div>
        {targetRows.length === 0 ? (
          <div className="empty-state"><strong>Sin nominales todavía</strong><span className="muted">Configura presión/caudal antes de registrar controles para obtener cumplimiento automático.</span></div>
        ) : (
          <div className="table-wrap"><table>
            <thead><tr><th>Parámetro / punto</th><th>Alcance</th><th>Nominal</th><th>Rango</th><th>Vigencia</th><th>Estado</th></tr></thead>
            <tbody>{targetRows.map((target) => {
              const p = parameterMap.get(target.parameter_id)
              const point = target.point_id ? pointMap.get(target.point_id) : null
              const unit = unitMap.get(target.unit_id)
              const scope = target.asset_id ? `Activo: ${assetMap.get(target.asset_id)?.code ?? '—'}`
                : target.location_id ? `${scopeLabel[locationMap.get(target.location_id)?.location_type ?? ''] ?? 'Ubicación'}: ${locationMap.get(target.location_id)?.code || locationMap.get(target.location_id)?.name || '—'}`
                : target.site_id ? `Fundo/sede: ${siteMap.get(target.site_id)?.name ?? '—'}` : 'Empresa completa'
              return <tr key={target.id}>
                <td><strong>{p?.name ?? 'Parámetro'}</strong><div className="muted small">{point?.name ?? 'Todos los puntos'}</div></td>
                <td>{scope}</td>
                <td><strong>{fmt(target.target_value)} {unit?.symbol ?? ''}</strong></td>
                <td>{fmt(target.min_value)} — {fmt(target.max_value)} {unit?.symbol ?? ''}</td>
                <td>{target.valid_from}<div className="muted small">hasta {target.valid_to ?? 'actualidad'}</div></td>
                <td><span className={`status ${target.is_active && !target.valid_to ? 'status-low' : ''}`}>{target.is_active && !target.valid_to ? 'Vigente' : 'Histórico'}</span></td>
              </tr>
            })}</tbody>
          </table></div>
        )}
      </section>

      <section className="card table-card">
        <div className="section-heading"><div><strong>Configuración física por ubicación</strong><p className="muted small">Últimas asociaciones de manguera, válvula y piloto.</p></div></div>
        {configRows.length === 0 ? <div className="empty-state"><span className="muted">Aún no hay configuraciones por lote.</span></div> : (
          <div className="table-wrap"><table>
            <thead><tr><th>Ubicación</th><th>Manguera</th><th>Válvula</th><th>Piloto</th><th>Vigencia</th></tr></thead>
            <tbody>{configRows.map((config) => <tr key={config.id}>
              <td>{locationMap.get(config.location_id)?.code || locationMap.get(config.location_id)?.name || '—'}</td>
              <td>{config.hose_model_id ? modelMap.get(config.hose_model_id)?.name ?? '—' : '—'}</td>
              <td>{config.valve_model_id ? modelMap.get(config.valve_model_id)?.name ?? '—' : '—'}</td>
              <td>{config.pilot_model_id ? modelMap.get(config.pilot_model_id)?.name ?? '—' : '—'}</td>
              <td>{config.valid_from}{config.valid_to ? ` → ${config.valid_to}` : ' → actualidad'}</td>
            </tr>)}</tbody>
          </table></div>
        )}
      </section>
    </main>
  )
}
