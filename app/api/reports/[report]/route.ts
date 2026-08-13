import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { isReportKey } from '@/lib/reports/catalog'
import { queryTenantReport } from '@/lib/reports/query'

export async function GET(request: NextRequest,{params}:{params:Promise<{report:string}>}) {
  const {report}=await params
  if(!isReportKey(report)) return NextResponse.json({error:'Reporte no válido'},{status:404})

  const supabase=await createClient()
  const {data:{user}}=await supabase.auth.getUser()
  if(!user) return NextResponse.json({error:'No autenticado'},{status:401})

  const {data:membership}=await supabase.from('tenant_members').select('tenant_id').eq('user_id',user.id).eq('is_active',true).limit(1).maybeSingle()
  if(!membership) return NextResponse.json({error:'Empresa no disponible'},{status:403})

  const search=request.nextUrl.searchParams
  const parsedLimit=Number(search.get('limit')??2000)
  try {
    const rows=await queryTenantReport(supabase,membership.tenant_id as string,report,{
      from:search.get('from'),to:search.get('to'),limit:Number.isFinite(parsedLimit)?parsedLimit:2000,
    })
    return NextResponse.json({report,row_count:rows.length,rows},{headers:{'Cache-Control':'private, no-store'}})
  } catch(error) {
    return NextResponse.json({error:error instanceof Error?error.message:'No se pudo generar el reporte'},{status:500})
  }
}
