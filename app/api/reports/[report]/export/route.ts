import { NextRequest,NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { isReportKey } from '@/lib/reports/catalog'
import { queryTenantReport } from '@/lib/reports/query'
import { rowsToCsv } from '@/lib/reports/csv'

export async function GET(request:NextRequest,{params}:{params:Promise<{report:string}>}) {
  const {report}=await params
  if(!isReportKey(report)) return NextResponse.json({error:'Reporte no válido'},{status:404})
  const supabase=await createClient()
  const {data:{user}}=await supabase.auth.getUser()
  if(!user) return NextResponse.json({error:'No autenticado'},{status:401})
  const {data:membership}=await supabase.from('tenant_members').select('tenant_id').eq('user_id',user.id).eq('is_active',true).limit(1).maybeSingle()
  if(!membership) return NextResponse.json({error:'Empresa no disponible'},{status:403})

  const search=request.nextUrl.searchParams
  const limit=Number(search.get('limit')||5000)
  const rows=await queryTenantReport(supabase,membership.tenant_id as string,report,{
    from:search.get('from'),to:search.get('to'),limit:Number.isFinite(limit)?limit:5000,
  }) as Record<string,unknown>[]

  return new NextResponse(rowsToCsv(rows),{
    headers:{'Content-Type':'text/csv; charset=utf-8','Content-Disposition':`attachment; filename=bridata-${report}.csv`,'Cache-Control':'private, no-store'},
  })
}
