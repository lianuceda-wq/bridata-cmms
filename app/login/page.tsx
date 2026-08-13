'use client'

import { FormEvent, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { useRouter } from 'next/navigation'

export default function LoginPage() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const router = useRouter()

  async function handleSubmit(e: FormEvent) {
    e.preventDefault()
    setError('')
    const supabase = createClient()
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) return setError(error.message)
    router.push('/dashboard')
    router.refresh()
  }

  return (
    <main className="container" style={{ maxWidth: 520 }}>
      <div className="card">
        <span className="badge">Acceso seguro</span>
        <h1>Ingresar a Bridata</h1>
        <form className="stack" onSubmit={handleSubmit}>
          <input className="input" type="email" placeholder="correo@empresa.com" value={email} onChange={(e) => setEmail(e.target.value)} required />
          <input className="input" type="password" placeholder="Contraseña" value={password} onChange={(e) => setPassword(e.target.value)} required />
          {error && <p>{error}</p>}
          <button className="button" type="submit">Ingresar</button>
        </form>
      </div>
    </main>
  )
}
