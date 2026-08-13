import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

export async function getTenantContext() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  const { data: membership, error } = await supabase
    .from('tenant_members')
    .select('tenant_id, role, tenants(name, slug)')
    .eq('user_id', user.id)
    .eq('is_active', true)
    .limit(1)
    .maybeSingle()

  if (error) throw new Error(error.message)

  if (!membership) {
    return { supabase, user, tenant: null, role: null as string | null }
  }

  const tenantRelation = membership.tenants as unknown
  const tenant = Array.isArray(tenantRelation)
    ? tenantRelation[0]
    : tenantRelation

  return {
    supabase,
    user,
    tenant: {
      id: membership.tenant_id as string,
      name: (tenant as { name?: string } | null)?.name ?? 'Empresa',
      slug: (tenant as { slug?: string } | null)?.slug ?? '',
    },
    role: membership.role as string,
  }
}

export async function requireTenant() {
  const context = await getTenantContext()
  if (!context.tenant) redirect('/dashboard/setup')
  return context as typeof context & { tenant: NonNullable<typeof context.tenant>; role: string }
}
