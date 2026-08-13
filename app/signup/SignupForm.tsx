'use client'

import Link from 'next/link'
import { useActionState } from 'react'
import { signup, type SignupState } from './actions'

const initial:SignupState={}

export default function SignupForm(){
  const [state,action,pending]=useActionState(signup,initial)
  return <form action={action} className="card stack" style={{maxWidth:520,width:'100%'}}>
    <div><span className="badge">BRIDATA</span><h1>Crear cuenta</h1><p className="muted">La cuenta es personal. La empresa se incorpora mediante un código de invitación o creando tu propio tenant.</p></div>
    <input className="input" name="full_name" placeholder="Nombre completo" required/>
    <input className="input" name="email" type="email" placeholder="correo@empresa.com" autoComplete="email" required/>
    <input className="input" name="password" type="password" minLength={8} placeholder="Contraseña (mínimo 8 caracteres)" autoComplete="new-password" required/>
    <button className="button" type="submit" disabled={pending}>{pending?'Creando…':'Crear cuenta'}</button>
    {state.error&&<div className="error-banner">{state.error}</div>}
    {state.success&&<div className="success-banner">{state.success}</div>}
    <div className="muted small">¿Ya tienes cuenta? <Link href="/login">Iniciar sesión</Link> · ¿Tienes código? <Link href="/join">Aceptar invitación</Link></div>
  </form>
}
