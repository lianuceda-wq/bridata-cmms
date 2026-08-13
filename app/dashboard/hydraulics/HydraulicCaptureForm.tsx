'use client'

import { useEffect, useMemo, useState } from 'react'
import { createHydraulicControl } from './actions'
import styles from './hydraulics.module.css'

type Site = { id: string; name: string; code: string | null }
type Location = { id: string; site_id: string; parent_location_id: string | null; code: string | null; name: string; location_type: string }
type Model = { id: string; component_type: string; name: string }
type LocationConfig = { location_id: string; hose_model_id: string | null; valve_model_id: string | null; pilot_model_id: string | null; valid_from: string; valid_to: string | null }

type CaptureRow = {
  key: number
  shift_number: string
  location_id: string
  flow: string
  filter_before: string
  filter_after: string
  field_pressure: string
  field_valve: string
  field_relief: string
  valve_before: string
  valve_after: string
  fd_right: string
  fd_center: string
  fd_left: string
  fm_right: string
  fm_center: string
  fm_left: string
  hose_model_id: string
  valve_model_id: string
  pilot_model_id: string
  notes: string
}

const blankRow = (key: number, shift = '1'): CaptureRow => ({
  key,
  shift_number: shift,
  location_id: '',
  flow: '',
  filter_before: '',
  filter_after: '',
  field_pressure: '',
  field_valve: '',
  field_relief: '',
  valve_before: '',
  valve_after: '',
  fd_right: '',
  fd_center: '',
  fd_left: '',
  fm_right: '',
  fm_center: '',
  fm_left: '',
  hose_model_id: '',
  valve_model_id: '',
  pilot_model_id: '',
  notes: '',
})

function localDateTimeValue() {
  const now = new Date()
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}T${pad(now.getHours())}:${pad(now.getMinutes())}`
}

export default function HydraulicCaptureForm({
  sites,
  locations,
  models,
  configs,
}: {
  sites: Site[]
  locations: Location[]
  models: Model[]
  configs: LocationConfig[]
}) {
  const [siteId, setSiteId] = useState(sites[0]?.id ?? '')
  const [headerLocationId, setHeaderLocationId] = useState('')
  const [rows, setRows] = useState<CaptureRow[]>([blankRow(1), blankRow(2), blankRow(3)])
  const [timezoneOffset, setTimezoneOffset] = useState(0)

  useEffect(() => {
    setTimezoneOffset(new Date().getTimezoneOffset())
  }, [])

  const headerLocations = useMemo(
    () => locations.filter((location) => location.site_id === siteId && ['parcel','sector','hydraulic_zone','area','system'].includes(location.location_type)),
    [locations, siteId],
  )

  const rowLocations = useMemo(() => {
    const inSite = locations.filter((location) => location.site_id === siteId && ['lot','sector','parcel','hydraulic_zone'].includes(location.location_type))
    if (!headerLocationId) return inSite
    const directChildren = inSite.filter((location) => location.parent_location_id === headerLocationId)
    return directChildren.length ? directChildren : inSite
  }, [locations, siteId, headerLocationId])

  const configMap = useMemo(() => {
    const map = new Map<string, LocationConfig>()
    const today = new Date().toISOString().slice(0, 10)
    const sorted = [...configs]
      .filter((config) => config.valid_from <= today && (!config.valid_to || config.valid_to >= today))
      .sort((a, b) => b.valid_from.localeCompare(a.valid_from))
    for (const config of sorted) if (!map.has(config.location_id)) map.set(config.location_id, config)
    return map
  }, [configs])

  const modelGroups = useMemo(() => ({
    hose: models.filter((m) => m.component_type === 'hose'),
    valve: models.filter((m) => m.component_type === 'valve'),
    pilot: models.filter((m) => m.component_type === 'pilot'),
  }), [models])

  function updateRow(key: number, field: keyof CaptureRow, value: string) {
    setRows((current) => current.map((row) => {
      if (row.key !== key) return row
      const next = { ...row, [field]: value }
      if (field === 'location_id') {
        const config = configMap.get(value)
        next.hose_model_id = config?.hose_model_id ?? ''
        next.valve_model_id = config?.valve_model_id ?? ''
        next.pilot_model_id = config?.pilot_model_id ?? ''
      }
      return next
    }))
  }

  function addRow() {
    setRows((current) => {
      const nextKey = Math.max(0, ...current.map((row) => row.key)) + 1
      const lastShift = current.length ? current[current.length - 1].shift_number : '1'
      return [...current, blankRow(nextKey, lastShift)]
    })
  }

  function addShift() {
    setRows((current) => {
      const maxShift = Math.max(0, ...current.map((row) => Number(row.shift_number) || 0))
      const nextKey = Math.max(0, ...current.map((row) => row.key)) + 1
      return [...current, blankRow(nextKey, String(maxShift + 1))]
    })
  }

  function removeRow(key: number) {
    setRows((current) => current.length === 1 ? current : current.filter((row) => row.key !== key))
  }

  function clearSite() {
    setHeaderLocationId('')
    setRows([blankRow(1), blankRow(2), blankRow(3)])
  }

  const payload = rows.map(({ key: _key, ...row }) => row)

  return (
    <form action={createHydraulicControl} className={styles.captureForm}>
      <section className={styles.captureHeader}>
        <div>
          <span className="badge">Nueva lectura</span>
          <h2>Control hidráulico</h2>
          <p className="muted small">Captura rápida basada en los formatos de campo. Los nominales y el cumplimiento se aplican automáticamente.</p>
        </div>
        <div className={styles.headerFields}>
          <label>Fecha y hora
            <input className="input" type="datetime-local" name="occurred_at" defaultValue={localDateTimeValue()} required />
          </label>
          <label>Responsable
            <input className="input" name="responsible_name" placeholder="Nombre del responsable" />
          </label>
          <label>Fundo / sede
            <select className="input" name="site_id" value={siteId} required onChange={(event) => { setSiteId(event.target.value); clearSite() }}>
              <option value="">Selecciona</option>
              {sites.map((site) => <option key={site.id} value={site.id}>{site.code ? `${site.code} · ` : ''}{site.name}</option>)}
            </select>
          </label>
          <label>Parcela / sector
            <select className="input" name="location_id" value={headerLocationId} onChange={(event) => setHeaderLocationId(event.target.value)}>
              <option value="">Sin filtro</option>
              {headerLocations.map((location) => <option key={location.id} value={location.id}>{location.code || location.name} · {location.name}</option>)}
            </select>
          </label>
        </div>
      </section>

      <section className={styles.gridCard}>
        <div className={styles.gridToolbar}>
          <div><strong>Lecturas por turno y lote</strong><span className="muted small">Las columnas de filtrado/caudal pueden llenarse solo en la primera fila de cada turno.</span></div>
          <div className={styles.toolbarActions}>
            <button type="button" className="button button-secondary button-compact" onClick={addRow}>+ Lote</button>
            <button type="button" className="button button-secondary button-compact" onClick={addShift}>+ Turno</button>
          </div>
        </div>

        <div className={styles.captureTableWrap}>
          <table className={styles.captureTable}>
            <thead>
              <tr>
                <th rowSpan={2}>Turno</th><th rowSpan={2}>Lote</th><th rowSpan={2}>Caudal<br/><small>m³/h</small></th>
                <th colSpan={3}>Batería filtrado · m.c.a</th><th colSpan={2}>Campo · m.c.a</th><th colSpan={2}>Válvula · m.c.a</th>
                <th colSpan={3}>Final divisora · m.c.a</th><th colSpan={3}>Final manguera · m.c.a</th>
                <th rowSpan={2}>Manguera</th><th rowSpan={2}>Válvula</th><th rowSpan={2}>Piloto</th><th rowSpan={2}>Obs.</th><th rowSpan={2}></th>
              </tr>
              <tr>
                <th>Antes</th><th>Después</th><th>A campo</th><th>Válvula</th><th>Alivio</th><th>Antes</th><th>Después</th>
                <th>D</th><th>C</th><th>I</th><th>D</th><th>C</th><th>I</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr key={row.key}>
                  <td><input className={styles.cellInput} type="number" min="1" value={row.shift_number} onChange={(e) => updateRow(row.key, 'shift_number', e.target.value)} required /></td>
                  <td><select className={styles.cellSelect} value={row.location_id} onChange={(e) => updateRow(row.key, 'location_id', e.target.value)}>
                    <option value="">—</option>{rowLocations.map((location) => <option key={location.id} value={location.id}>{location.code || location.name}</option>)}
                  </select></td>
                  {(['flow','filter_before','filter_after','field_pressure','field_valve','field_relief','valve_before','valve_after','fd_right','fd_center','fd_left','fm_right','fm_center','fm_left'] as const).map((field) => (
                    <td key={field}><input className={styles.cellInput} type="number" step="any" min="0" value={row[field]} onChange={(e) => updateRow(row.key, field, e.target.value)} /></td>
                  ))}
                  <td><select className={styles.modelSelect} value={row.hose_model_id} onChange={(e) => updateRow(row.key, 'hose_model_id', e.target.value)}><option value="">—</option>{modelGroups.hose.map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}</select></td>
                  <td><select className={styles.modelSelect} value={row.valve_model_id} onChange={(e) => updateRow(row.key, 'valve_model_id', e.target.value)}><option value="">—</option>{modelGroups.valve.map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}</select></td>
                  <td><select className={styles.modelSelect} value={row.pilot_model_id} onChange={(e) => updateRow(row.key, 'pilot_model_id', e.target.value)}><option value="">—</option>{modelGroups.pilot.map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}</select></td>
                  <td><input className={styles.noteInput} value={row.notes} onChange={(e) => updateRow(row.key, 'notes', e.target.value)} placeholder="..." /></td>
                  <td><button type="button" className={styles.removeButton} onClick={() => removeRow(row.key)} aria-label="Eliminar fila">×</button></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <div className={styles.captureFooter}>
        <textarea className="input" name="notes" rows={2} placeholder="Observación general de la jornada" />
        <input type="hidden" name="rows_json" value={JSON.stringify(payload)} readOnly />
        <input type="hidden" name="timezone_offset_minutes" value={timezoneOffset} readOnly />
        <div className={styles.submitActions}>
          <button className="button button-secondary" type="submit" name="submit_mode" value="draft">Guardar borrador</button>
          <button className="button" type="submit" name="submit_mode" value="submit">Guardar y enviar a validación</button>
        </div>
      </div>
    </form>
  )
}
