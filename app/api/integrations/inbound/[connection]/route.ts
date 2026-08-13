import { createHash } from 'node:crypto'
import { NextRequest,NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

export async function POST(request:NextRequest,{params}:{params:Promise<{connection:string}>}){
 const {connection}=await params
 if(!UUID.test(connection))return NextResponse.json({error:'Conexión inválida'},{status:404})
 const auth=request.headers.get('authorization')||''
 const raw=auth.startsWith('Bearer ')?auth.slice(7).trim():''
 if(raw.length<24)return NextResponse.json({error:'API key requerida'},{status:401})
 const externalId=(request.headers.get('x-bridata-event-id')||'').trim()
 const eventKey=(request.headers.get('x-bridata-event')||'').trim()
 if(!externalId||!eventKey)return NextResponse.json({error:'X-Bridata-Event-Id y X-Bridata-Event son obligatorios'},{status:400})
 const length=Number(request.headers.get('content-length')||0)
 if(length>1_048_576)return NextResponse.json({error:'Payload demasiado grande'},{status:413})
 let payload:unknown
 try{payload=await request.json()}catch{return NextResponse.json({error:'JSON inválido'},{status:400})}
 const hash=createHash('sha256').update(raw).digest('hex')
 const supabase=await createClient()
 const {data,error}=await supabase.rpc('accept_integration_event',{p_connection_id:connection,p_key_hash:hash,p_external_event_id:externalId,p_event_key:eventKey,p_payload:payload})
 if(error){const status=error.message.includes('rate limit')?429:error.message.includes('scope')?403:401;return NextResponse.json({error:error.message},{status})}
 const result=data as {duplicate?:boolean}
 return NextResponse.json(data,{status:result?.duplicate?200:202,headers:{'Cache-Control':'no-store'}})
}
