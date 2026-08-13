'use client'

import Link from 'next/link'
import { useActionState } from 'react'
import { acceptInvite, type JoinState } from './actions'

const initial:JoinState={}

export default function JoinForm(){
  const [state,action,pending]=useActionState(acceptInvite,initial)
  return <form action={action} className="card stack" style={{maxWidth:560,width:'100%'}}>
    <div><span className="badge">Invitación</span><h1>Unirme a una empresa</h1><p className="muted">Inicia sesión con el mismo correo al que se emitió la invitación y pega el código.</p></div>
    <input className="input" name="token" placeholder="Código de invitación" autoComplete="off" required/>
    <button className="button" type="submit" disabled={pending}>{pending?'Validando…':'Aceptar invitación'}</button>
    {state.error&&<div className="error-banner">{state.error}</div>}
    {state.success&&<div className="success-banner">{state.success} <Link href="/dashboard">Abrir dashboard</Link></div>}
    <div className="muted small"><Link href="/login">Iniciar sesión</Link> · <Link href="/signup">Crear cuenta</Link></div>
  </form>
}
