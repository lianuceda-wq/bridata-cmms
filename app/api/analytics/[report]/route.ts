import { createHash } from 'node:crypto'
import { NextRequest,NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { isReportKey } from '@/lib/reports/catalog'

export async function GET(request:NextRequest,{params}:{params:Promise<{report:string}>}) {
  const {report}=await params
  if(!isReportKey(report)) return NextResponse.json({error:'Reporte no válido'},{status:404})

  const header=request.headers.get('authorization')||''
  const rawKey=header.startsWith('Bearer ')?header.slice(7).trim():''
  if(rawKey.length<24) return NextResponse.json({error:'API key requerida'},{status:401})

  const hash=createHash('sha256').update(rawKey).digest('hex')
  const search=request.nextUrl.searchParams
  const limit=Number(search.get('limit')||2000)
  const supabase=await createClient()
  const {data,error}=await supabase.rpc('fetch_analytics_report',{
    p_key_hash:hash,p_report_key:report,p_from:search.get('from')||null,p_to:search.get('to')||null,
    p_limit:Number.isFinite(limit)?limit:2000,
  })

  if(error) return NextResponse.json({error:error.message},{status:error.message.includes('rate limit')?429:401})
  return NextResponse.json(data,{headers:{'Cache-Control':'no-store'}})
}
