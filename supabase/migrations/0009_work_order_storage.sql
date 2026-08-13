-- Bridata CMMS - bucket privado de evidencias de OT.

create or replace function private.safe_uuid(p_value text)
returns uuid
language plpgsql
immutable
security invoker
set search_path = pg_catalog, pg_temp
as $$
begin
  return p_value::uuid;
exception when invalid_text_representation then
  return null;
end;
$$;

revoke all on function private.safe_uuid(text) from public, anon;
grant execute on function private.safe_uuid(text) to authenticated, service_role;

insert into storage.buckets (id, name, public, file_size_limit)
values ('work-order-evidence', 'work-order-evidence', false, 10485760)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit;

-- Ruta canónica: tenant_id/work_order_id/task_id/<uuid>-archivo.ext
create policy work_order_evidence_storage_select
on storage.objects
for select to authenticated
using (
  bucket_id = 'work-order-evidence'
  and public.is_tenant_member(
    private.safe_uuid((storage.foldername(name))[1])
  )
);

create policy work_order_evidence_storage_insert
on storage.objects
for insert to authenticated
with check (
  bucket_id = 'work-order-evidence'
  and (
    public.can_manage_tenant(
      private.safe_uuid((storage.foldername(name))[1])
    )
    or exists (
      select 1
      from public.work_orders wo
      where wo.tenant_id = private.safe_uuid((storage.foldername(name))[1])
        and wo.id = private.safe_uuid((storage.foldername(name))[2])
        and wo.assigned_to = (select auth.uid())
        and public.tenant_role(wo.tenant_id) = 'technician'
    )
  )
);

create policy work_order_evidence_storage_delete
on storage.objects
for delete to authenticated
using (
  bucket_id = 'work-order-evidence'
  and public.can_manage_tenant(
    private.safe_uuid((storage.foldername(name))[1])
  )
);
