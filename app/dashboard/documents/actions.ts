'use server'

import { revalidatePath } from 'next/cache'
import { requireTenant } from '@/lib/tenant'

const clean=(value:FormDataEntryValue|null)=>String(value??'').trim()
const nullable=(value:FormDataEntryValue|null)=>clean(value)||null
const refresh=()=>revalidatePath('/dashboard/documents')

async function sha256(file:File){
  const hash=await crypto.subtle.digest('SHA-256',await file.arrayBuffer())
  return Array.from(new Uint8Array(hash)).map(value=>value.toString(16).padStart(2,'0')).join('')
}

function validateFile(file:File){
  if(file.size<=0) throw new Error('El archivo está vacío.')
  if(file.size>50*1024*1024) throw new Error('El archivo no puede superar 50 MB.')
}

export async function createDocumentType(formData:FormData){
  const {supabase,tenant}=await requireTenant()
  const code=clean(formData.get('code')),name=clean(formData.get('name'))
  if(!code||!name) throw new Error('Código y nombre son obligatorios.')
  const {error}=await supabase.from('document_types').insert({tenant_id:tenant.id,code:code.toUpperCase(),name,description:nullable(formData.get('description'))})
  if(error) throw new Error(error.message)
  refresh()
}

export async function createDocumentWithFile(formData:FormData){
  const {supabase,tenant}=await requireTenant()
  const file=formData.get('file')
  if(!(file instanceof File)) throw new Error('Selecciona un archivo.')
  validateFile(file)
  const {data:documentId,error:createError}=await supabase.rpc('create_document',{
    p_tenant_id:tenant.id,
    p_code:clean(formData.get('code')),
    p_title:clean(formData.get('title')),
    p_document_type_id:nullable(formData.get('document_type_id')),
    p_description:nullable(formData.get('description')),
    p_effective_from:nullable(formData.get('effective_from')),
    p_effective_to:nullable(formData.get('effective_to')),
    p_owner_worker_id:nullable(formData.get('owner_worker_id')),
  })
  if(createError) throw new Error(createError.message)
  const id=String(documentId)
  const safeName=(file.name||'documento').replace(/[^a-zA-Z0-9._-]+/g,'-').slice(-140)
  const path=`${tenant.id}/${id}/${crypto.randomUUID()}-${safeName}`
  const {error:uploadError}=await supabase.storage.from('documents').upload(path,file,{upsert:false,contentType:file.type||undefined})
  if(uploadError){await supabase.rpc('archive_document',{p_tenant_id:tenant.id,p_document_id:id});throw new Error(uploadError.message)}
  const checksum=await sha256(file)
  const {error:versionError}=await supabase.rpc('register_document_version',{
    p_tenant_id:tenant.id,p_document_id:id,p_storage_path:path,p_file_name:file.name,p_mime_type:file.type||null,p_file_size:file.size,p_checksum_sha256:checksum,p_change_notes:nullable(formData.get('change_notes')),
  })
  if(versionError){await supabase.storage.from('documents').remove([path]);await supabase.rpc('archive_document',{p_tenant_id:tenant.id,p_document_id:id});throw new Error(versionError.message)}
  refresh()
}

export async function uploadDocumentVersion(formData:FormData){
  const {supabase,tenant}=await requireTenant()
  const documentId=clean(formData.get('document_id'))
  const file=formData.get('file')
  if(!documentId||!(file instanceof File)) throw new Error('Documento y archivo son obligatorios.')
  validateFile(file)
  const safeName=(file.name||'documento').replace(/[^a-zA-Z0-9._-]+/g,'-').slice(-140)
  const path=`${tenant.id}/${documentId}/${crypto.randomUUID()}-${safeName}`
  const {error:uploadError}=await supabase.storage.from('documents').upload(path,file,{upsert:false,contentType:file.type||undefined})
  if(uploadError) throw new Error(uploadError.message)
  const checksum=await sha256(file)
  const {error}=await supabase.rpc('register_document_version',{
    p_tenant_id:tenant.id,p_document_id:documentId,p_storage_path:path,p_file_name:file.name,p_mime_type:file.type||null,p_file_size:file.size,p_checksum_sha256:checksum,p_change_notes:nullable(formData.get('change_notes')),
  })
  if(error){await supabase.storage.from('documents').remove([path]);throw new Error(error.message)}
  refresh()
}

export async function linkDocument(formData:FormData){
  const {supabase,tenant}=await requireTenant()
  const documentId=clean(formData.get('document_id')),entityType=clean(formData.get('entity_type')),entityId=clean(formData.get('entity_id'))
  if(!documentId||!entityType||!entityId) throw new Error('Documento y destino son obligatorios.')
  const {error}=await supabase.rpc('link_document',{p_tenant_id:tenant.id,p_document_id:documentId,p_entity_type:entityType,p_entity_id:entityId})
  if(error) throw new Error(error.message)
  refresh()
}

export async function archiveDocument(formData:FormData){
  const {supabase,tenant}=await requireTenant()
  const id=clean(formData.get('document_id'))
  if(!id) throw new Error('Documento inválido.')
  const {error}=await supabase.rpc('archive_document',{p_tenant_id:tenant.id,p_document_id:id})
  if(error) throw new Error(error.message)
  refresh()
}
