import { requireTenant } from '@/lib/tenant'
import InboundKeyManager from '../InboundKeyManager'

export default async function InboundIntegrationsPage(){
 const {supabase,tenant,role}=await requireTenant()
 const canManage=['owner','admin'].includes(role)
 const {data:connections}=await supabase.from('integration_connections').select('id,name,direction').eq('tenant_id',tenant.id).in('direction',['inbound','bidirectional']).order('name')
 let keys:unknown[]=[]
 if(canManage){const {data}=await supabase.rpc('list_integration_inbound_keys',{p_tenant_id:tenant.id});keys=data??[]}
 return <main className="content stack"><section className="card"><span className="badge">Inbound Ledger</span><h1>API de entrada</h1><p className="muted">Recepción idempotente para GPS, Talgil y proveedores externos. Los eventos se validan y almacenan antes de tocar dominios operativos.</p><p className="small">Endpoint: <code>/api/integrations/inbound/CONNECTION_ID</code> · headers <code>Authorization</code>, <code>X-Bridata-Event-Id</code> y <code>X-Bridata-Event</code>.</p></section>{canManage?<InboundKeyManager tenantId={tenant.id} connections={(connections??[]) as never[]} initialKeys={keys as never[]}/>:<section className="card"><p className="muted">Solo owner/admin puede gestionar claves inbound.</p></section>}</main>
}
