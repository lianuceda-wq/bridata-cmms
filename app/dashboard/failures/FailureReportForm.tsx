'use client'

import { useEffect, useMemo, useState } from 'react'
import { reportFailure } from './actions'
import styles from './failures.module.css'

type Asset = { id: string; code: string; name: string; site_id: string | null; location_id: string | null }
type FailureMode = { id: string; code: string; name: string }
type FailureCause = { id: string; failure_mode_id: string | null; code: string; name: string }

function localDateTimeValue() {
  const now = new Date()
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${now.getFullYear()}-${pad(now.getMonth()+1)}-${pad(now.getDate())}T${pad(now.getHours())}:${pad(now.getMinutes())}`
}

export default function FailureReportForm({ assets, modes, causes }: { assets: Asset[]; modes: FailureMode[]; causes: FailureCause[] }) {
  const [modeId, setModeId] = useState('')
  const [offset, setOffset] = useState(0)
  useEffect(() => setOffset(new Date().getTimezoneOffset()), [])

  const visibleCauses = useMemo(
    () => causes.filter((cause) => !cause.failure_mode_id || !modeId || cause.failure_mode_id === modeId),
    [causes, modeId],
  )

  return (
    <form action={reportFailure} className={styles.reportCard}>
      <div className={styles.reportIntro}>
        <div>
          <span className="badge">Nueva falla</span>
          <h2>Reportar evento</h2>
          <p className="muted small">Registra el hecho real. Si creas la OT correctiva, sus tiempos alimentarán MTTR y downtime automáticamente.</p>
        </div>
        <label className={styles.switchRow}>
          <input type="checkbox" defaultChecked onChange={(e) => {
            const hidden = document.querySelector<HTMLInputElement>('#create_work_order_value')
            if (hidden) hidden.value = e.target.checked ? 'true' : 'false'
          }} />
          Generar OT correctiva
        </label>
        <input id="create_work_order_value" type="hidden" name="create_work_order" defaultValue="true" />
      </div>

      <div className={styles.reportGrid}>
        <label>Activo
          <select className="input" name="asset_id" required defaultValue="">
            <option value="" disabled>Selecciona activo</option>
            {assets.map((asset) => <option key={asset.id} value={asset.id}>{asset.code} · {asset.name}</option>)}
          </select>
        </label>
        <label>Fecha y hora de ocurrencia
          <input className="input" name="occurred_at" type="datetime-local" defaultValue={localDateTimeValue()} required />
        </label>
        <label>Severidad
          <select className="input" name="severity" defaultValue="medium">
            <option value="low">Baja</option><option value="medium">Media</option><option value="high">Alta</option><option value="critical">Crítica</option>
          </select>
        </label>
        <label>Modo de falla
          <select className="input" name="failure_mode_id" value={modeId} onChange={(e) => setModeId(e.target.value)}>
            <option value="">Sin clasificar</option>
            {modes.map((mode) => <option key={mode.id} value={mode.id}>{mode.code} · {mode.name}</option>)}
          </select>
        </label>
        <label>Causa preliminar
          <select className="input" name="failure_cause_id" defaultValue="">
            <option value="">Por determinar</option>
            {visibleCauses.map((cause) => <option key={cause.id} value={cause.id}>{cause.code} · {cause.name}</option>)}
          </select>
        </label>
        <label>Síntoma
          <input className="input" name="symptom" placeholder="Ej. caída de presión / fuga visible" />
        </label>
      </div>
      <label className={styles.fullField}>Descripción
        <textarea className="input" name="description" rows={3} placeholder="Qué ocurrió, dónde se observó y condición encontrada" required />
      </label>
      <input type="hidden" name="timezone_offset_minutes" value={offset} readOnly />
      <div className={styles.reportActions}>
        <span className="muted small">La hora de reporte se registra automáticamente al guardar.</span>
        <button className="button" type="submit">Registrar falla</button>
      </div>
    </form>
  )
}
