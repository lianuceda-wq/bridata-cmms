import type { SupabaseClient } from '@supabase/supabase-js'
import { REPORTS, type ReportKey } from './catalog'

export interface ReportQueryOptions {
  from?: string | null
  to?: string | null
  limit?: number
}

function monthStart(value: string) {
  const date = new Date(`${value}T00:00:00Z`)
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1)).toISOString()
}

export async function queryTenantReport(
  client: SupabaseClient,
  tenantId: string,
  reportKey: ReportKey,
  options: ReportQueryOptions = {},
) {
  const report = REPORTS[reportKey]
  const limit = Math.min(Math.max(options.limit ?? 2000, 1), 5000)
  const from = options.from ?? null
  const to = options.to ?? null

  let query = client
    .from(report.view)
    .select('*')
    .eq('tenant_id', tenantId)
    .limit(limit)

  if (report.rangeMode === 'month' && report.dateColumn) {
    if (from) query = query.gte(report.dateColumn, monthStart(from))
    if (to) query = query.lte(report.dateColumn, monthStart(to))
  } else if (report.rangeMode === 'timestamp' && report.dateColumn) {
    if (from) query = query.gte(report.dateColumn, `${from}T00:00:00.000Z`)
    if (to) query = query.lte(report.dateColumn, `${to}T23:59:59.999Z`)
  } else if (report.rangeMode === 'period_intersection' && report.dateColumn && report.endDateColumn) {
    if (from) query = query.gte(report.endDateColumn, from)
    if (to) query = query.lte(report.dateColumn, to)
  }

  query = query.order(report.orderColumn, { ascending: true, nullsFirst: false })
  const { data, error } = await query
  if (error) throw new Error(error.message)
  return data ?? []
}
