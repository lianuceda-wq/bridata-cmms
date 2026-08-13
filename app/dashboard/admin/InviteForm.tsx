'use client'

import { useActionState } from 'react'
import { createInvitation, type InviteState } from './actions'

const initialState:InviteState={}

export default function InviteForm(){
  const [state,action,pending]=useActionState(createInvitation,initialState)
  return <form action={action} className="card stack">
    <div><strong>Invitar usuario</strong><p className="muted small">El usuario crea/inicia su cuenta de Supabase y acepta este código en `/join`. No usamos service_role en el navegador.</p></div>
    <input className="input" type="email" name="email" placeholder="correo@empresa.com" required/>
    <div className="form-grid"><select className="input" name="role" defaultValue="technician"><option value="owner">Owner</option><option value="admin">Admin</option><option value="planner">Planner</option><option value="supervisor">Supervisor</option><option value="technician">Técnico</option><option value="warehouse">Almacén</option><option value="viewer">Consulta</option></select><select className="input" name="expires_days" defaultValue="7"><option value="1">1 día</option><option value="3">3 días</option><option value="7">7 días</option><option value="14">14 días</option><option value="30">30 días</option></select></div>
    <button className="button" type="submit" disabled={pending}>{pending?'Creando…':'Crear invitación'}</button>
    {state.error&&<div className="error-banner">{state.error}</div>}
    {state.token&&<div className="success-banner"><strong>Código para {state.email}</strong><br/><code style={{wordBreak:'break-all'}}>{state.token}</code><br/><span className="muted small">Compártelo por un canal seguro. Por seguridad el código no vuelve a mostrarse.</span></div>}
  </form>
}
