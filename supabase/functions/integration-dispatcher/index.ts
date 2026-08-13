import { createClient } from 'npm:@supabase/supabase-js@2'

interface Delivery {
  delivery_id:number
  attempt_id:number
  tenant_id:string
  outbox_id:number
  event_id:string
  event_key:string
  target_url:string
  payload:Record<string,unknown>
  signing_secret:string|null
}

const encoder=new TextEncoder()

async function hmac(secret:string,body:string) {
  const key=await crypto.subtle.importKey('raw',encoder.encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign'])
  const signed=await crypto.subtle.sign('HMAC',key,encoder.encode(body))
  return Array.from(new Uint8Array(signed),(value)=>value.toString(16).padStart(2,'0')).join('')
}

Deno.serve(async (request)=>{
  const expected=Deno.env.get('INTEGRATION_DISPATCH_SECRET')
  const provided=request.headers.get('x-bridata-dispatch-secret')
  if(!expected||!provided||provided!==expected) return new Response('Unauthorized',{status:401})

  const url=Deno.env.get('SUPABASE_URL')
  const serviceKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if(!url||!serviceKey) return new Response('Missing Supabase server configuration',{status:500})
  const supabase=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}})
  const {data,error}=await supabase.rpc('claim_integration_deliveries',{p_limit:20})
  if(error) return Response.json({error:error.message},{status:500})

  const deliveries=(data??[]) as Delivery[]
  const results=await Promise.all(deliveries.map(async(delivery)=>{
    const started=Date.now()
    const body=JSON.stringify({
      id:delivery.event_id,event:delivery.event_key,delivery_id:delivery.delivery_id,data:delivery.payload,
    })
    const controller=new AbortController()
    const timeout=setTimeout(()=>controller.abort(),10_000)
    let status=0
    let success=false
    let message=''
    try {
      const headers:Record<string,string>={
        'content-type':'application/json','user-agent':'Bridata-CMMS/1.0','x-bridata-event':delivery.event_key,
        'x-bridata-delivery':String(delivery.delivery_id),
      }
      if(delivery.signing_secret) headers['x-bridata-signature']='sha256='+await hmac(delivery.signing_secret,body)
      const response=await fetch(delivery.target_url,{method:'POST',headers,body,signal:controller.signal,redirect:'error'})
      status=response.status
      success=response.ok
      if(!success) message=(await response.text()).slice(0,1000)||`HTTP ${response.status}`
    } catch(error) {
      message=error instanceof Error?error.message:'Webhook delivery failed'
    } finally { clearTimeout(timeout) }

    const {error:completeError}=await supabase.rpc('complete_integration_delivery',{
      p_delivery_id:delivery.delivery_id,p_attempt_id:delivery.attempt_id,p_success:success,p_http_status:status||null,
      p_duration_ms:Date.now()-started,p_error:message||null,
    })
    return {delivery_id:delivery.delivery_id,success,status,error:completeError?.message??message||null}
  }))

  return Response.json({claimed:deliveries.length,delivered:results.filter((item)=>item.success).length,results})
})
