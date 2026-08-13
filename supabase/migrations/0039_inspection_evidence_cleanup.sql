-- Bridata CMMS - permitir compensación de upload fallido al usuario asignado

drop policy if exists "inspection evidence manager delete" on storage.objects;
create policy "inspection evidence controlled delete"
on storage.objects for delete to authenticated
using(
  bucket_id='inspection-evidence'
  and exists(
    select 1 from public.inspection_runs r
    where r.tenant_id=((storage.foldername(name))[1])::uuid
      and r.id=((storage.foldername(name))[2])::uuid
      and (
        public.can_manage_tenant(r.tenant_id)
        or (r.assigned_to=auth.uid() and r.status in('assigned','in_progress'))
      )
  )
);
