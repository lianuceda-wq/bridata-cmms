-- Bridata CMMS - evidencia registrada solo si el archivo existe realmente

create or replace function public.register_inspection_evidence(
  p_tenant_id uuid,p_run_id uuid,p_item_id uuid,p_storage_path text,p_file_name text,p_mime_type text,p_file_size bigint,p_caption text
)
returns uuid
language plpgsql
security definer
set search_path=public,private,storage,pg_temp
as $$
declare v_run public.inspection_runs;v_id uuid;
begin
  select * into v_run from public.inspection_runs where tenant_id=p_tenant_id and id=p_run_id;
  if not found then raise exception 'Inspection run not found'; end if;
  if v_run.status not in('assigned','in_progress') then raise exception 'Inspection is immutable'; end if;
  if not public.can_manage_tenant(p_tenant_id) and v_run.assigned_to is distinct from auth.uid() then raise exception 'Inspection is not assigned to user'; end if;
  if p_item_id is not null and not exists(
    select 1 from public.inspection_run_items
    where tenant_id=p_tenant_id and inspection_run_id=p_run_id and id=p_item_id
  ) then raise exception 'Inspection item does not belong to run'; end if;
  if p_storage_path not like p_tenant_id::text||'/'||p_run_id::text||'/%' then raise exception 'Invalid evidence storage path'; end if;
  if not exists(
    select 1 from storage.objects
    where bucket_id='inspection-evidence' and name=p_storage_path
  ) then raise exception 'Evidence file does not exist in storage'; end if;

  insert into public.inspection_evidence(
    tenant_id,inspection_run_id,inspection_run_item_id,storage_path,file_name,mime_type,file_size,caption,uploaded_by
  ) values(
    p_tenant_id,p_run_id,p_item_id,p_storage_path,p_file_name,p_mime_type,p_file_size,nullif(trim(p_caption),''),auth.uid()
  ) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.register_inspection_evidence(uuid,uuid,uuid,text,text,text,bigint,text) from public,anon;
grant execute on function public.register_inspection_evidence(uuid,uuid,uuid,text,text,text,bigint,text) to authenticated;
