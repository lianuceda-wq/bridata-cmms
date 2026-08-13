import { requireTenant } from '@/lib/tenant'
import { createAsset, createLocation, createSite, deleteAsset, updateAssetStatus } from './actions'

const locationLabels: Record<string, string> = {
  area: 'Área',
  system: 'Sistema',
  sector: 'Sector',
  room: 'Sala/Caseta',
  line: 'Línea',
  warehouse: 'Almacén',
  other: 'Otro',
}

export default async function AssetsPage() {
  const { supabase, tenant, role } = await requireTenant()

  const [{ data: sites }, { data: locations }, { data: assets }] = await Promise.all([
    supabase.from('sites').select('id,name,code').eq('tenant_id', tenant.id).order('name'),
    supabase.from('locations').select('id,site_id,parent_location_id,code,name,location_type').eq('tenant_id', tenant.id).order('name'),
    supabase.from('assets').select('id,site_id,location_id,parent_asset_id,code,name,asset_type,status,criticality,manufacturer,model').eq('tenant_id', tenant.id).order('name'),
  ])

  const siteRows = sites ?? []
  const locationRows = locations ?? []
  const assetRows = assets ?? []
  const canWrite = ['owner', 'admin', 'planner', 'supervisor'].includes(role)
  const canDelete = ['owner', 'admin'].includes(role)

  const siteName = new Map(siteRows.map((site) => [site.id, site.name]))
  const locationName = new Map(locationRows.map((location) => [location.id, location.name]))

  return (
    <main className="content stack gap-24">
      <div className="header">
        <div>
          <span className="badge">Activos</span>
          <h1>Jerarquía de activos</h1>
          <p className="muted">{tenant.name} · rol {role}</p>
        </div>
        <div className="summary-chip">{assetRows.length} activos</div>
      </div>

      {canWrite && (
        <section className="grid grid-3">
          <form action={createSite} className="card stack">
            <div>
              <strong>1. Fundo / sede</strong>
              <p className="muted small">Nivel físico principal.</p>
            </div>
            <input className="input" name="name" placeholder="Ej. Yakuy Minka" required />
            <input className="input" name="code" placeholder="Código opcional" />
            <button className="button" type="submit">Agregar fundo/sede</button>
          </form>

          <form action={createLocation} className="card stack">
            <div>
              <strong>2. Ubicación</strong>
              <p className="muted small">Área, sistema, sector, caseta o línea.</p>
            </div>
            <select className="input" name="site_id" required defaultValue="">
              <option value="" disabled>Selecciona fundo/sede</option>
              {siteRows.map((site) => <option key={site.id} value={site.id}>{site.name}</option>)}
            </select>
            <select className="input" name="parent_location_id" defaultValue="">
              <option value="">Sin ubicación padre</option>
              {locationRows.map((location) => <option key={location.id} value={location.id}>{location.name}</option>)}
            </select>
            <div className="form-grid">
              <input className="input" name="name" placeholder="Nombre" required />
              <input className="input" name="code" placeholder="Código" />
            </div>
            <select className="input" name="location_type" defaultValue="area">
              {Object.entries(locationLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
            </select>
            <button className="button" type="submit">Agregar ubicación</button>
          </form>

          <form action={createAsset} className="card stack">
            <div>
              <strong>3. Activo</strong>
              <p className="muted small">Equipo o componente mantenible.</p>
            </div>
            <div className="form-grid">
              <input className="input" name="code" placeholder="Código activo" required />
              <input className="input" name="name" placeholder="Nombre" required />
            </div>
            <select className="input" name="site_id" required defaultValue="">
              <option value="" disabled>Selecciona fundo/sede</option>
              {siteRows.map((site) => <option key={site.id} value={site.id}>{site.name}</option>)}
            </select>
            <select className="input" name="location_id" defaultValue="">
              <option value="">Sin ubicación específica</option>
              {locationRows.map((location) => <option key={location.id} value={location.id}>{location.name}</option>)}
            </select>
            <select className="input" name="parent_asset_id" defaultValue="">
              <option value="">Activo raíz</option>
              {assetRows.map((asset) => <option key={asset.id} value={asset.id}>{asset.code} · {asset.name}</option>)}
            </select>
            <div className="form-grid">
              <input className="input" name="asset_type" placeholder="Tipo: bomba, motor..." />
              <select className="input" name="criticality" defaultValue="medium">
                <option value="low">Baja</option>
                <option value="medium">Media</option>
                <option value="high">Alta</option>
                <option value="critical">Crítica</option>
              </select>
            </div>
            <div className="form-grid">
              <input className="input" name="manufacturer" placeholder="Fabricante" />
              <input className="input" name="model" placeholder="Modelo" />
            </div>
            <button className="button" type="submit">Registrar activo</button>
          </form>
        </section>
      )}

      <section className="card table-card">
        <div className="section-heading">
          <div>
            <strong>Inventario técnico</strong>
            <p className="muted small">Vista operativa inicial de la jerarquía registrada.</p>
          </div>
        </div>

        {assetRows.length === 0 ? (
          <div className="empty-state">
            <strong>Aún no hay activos</strong>
            <span className="muted">Crea primero un fundo/sede y luego registra el primer equipo.</span>
          </div>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Código</th>
                  <th>Activo</th>
                  <th>Fundo/sede</th>
                  <th>Ubicación</th>
                  <th>Criticidad</th>
                  <th>Estado</th>
                  <th>Acciones</th>
                </tr>
              </thead>
              <tbody>
                {assetRows.map((asset) => (
                  <tr key={asset.id}>
                    <td><span className="mono">{asset.code}</span></td>
                    <td>
                      <strong>{asset.name}</strong>
                      <div className="muted small">{asset.asset_type || 'Sin tipo'}{asset.model ? ` · ${asset.model}` : ''}</div>
                    </td>
                    <td>{siteName.get(asset.site_id) ?? '—'}</td>
                    <td>{asset.location_id ? locationName.get(asset.location_id) ?? '—' : '—'}</td>
                    <td><span className={`status status-${asset.criticality}`}>{asset.criticality}</span></td>
                    <td>
                      {canWrite ? (
                        <form action={updateAssetStatus} className="inline-form">
                          <input type="hidden" name="id" value={asset.id} />
                          <select className="input input-compact" name="status" defaultValue={asset.status}>
                            <option value="operational">Operativo</option>
                            <option value="maintenance">Mantenimiento</option>
                            <option value="stopped">Detenido</option>
                            <option value="retired">Retirado</option>
                          </select>
                          <button className="button button-secondary button-compact" type="submit">Guardar</button>
                        </form>
                      ) : asset.status}
                    </td>
                    <td>
                      {canDelete ? (
                        <form action={deleteAsset}>
                          <input type="hidden" name="id" value={asset.id} />
                          <button className="button button-danger button-compact" type="submit">Eliminar</button>
                        </form>
                      ) : <span className="muted">—</span>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </main>
  )
}
