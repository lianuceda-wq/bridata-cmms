'use server'

import { randomUUID } from 'node:crypto'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

function slugify(value: string) {
  return value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 42)
}

export async function createWorkspace(formData: FormData) {
  const name = String(formData.get('name') ?? '').trim()
  if (name.length < 2) throw new Error('Ingresa un nombre de empresa válido.')

  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const base = slugify(name) || 'empresa'
  const slug = `${base}-${randomUUID().slice(0, 6)}`

  const { error } = await supabase.rpc('bootstrap_tenant', {
    p_name: name,
    p_slug: slug,
  })

  if (error) throw new Error(error.message)
  redirect('/dashboard')
}
