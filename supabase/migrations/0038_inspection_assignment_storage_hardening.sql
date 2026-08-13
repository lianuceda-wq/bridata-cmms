-- Bridata CMMS - asignación, recurrencia y Storage de inspecciones

create or replace function public.link_inspection_template_to_routine(
  p_tenant_id uuid,p_routine_id uuid,p_template_id uuid
)
returns void
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  if public.tenant_role(p_tenant_id) not in('owner','admin','planner') then
    raise exception 'Insufficient inspection planning permissions';
  end if;
  if not exists(select 1 from public.maintenance_routines where tenant_id=p_tenant_id and id=p_routine_id and maintenance_type='inspection') then
    raise exception 'Routine is not an inspection routine';
  end if;
  if not exists(select 1 from public.inspection_templates where tenant_id=p_tenant_id and id=p_template_id and status='active') then
    raise exception 'Inspection template is not active';
  end if;
  update public.maintenance_routines
  set inspection_template_id=p_template_id,updated_at=now()
  where tenant_id=p_tenant_id and id=p_routine_id;
end;
$$;
revoke all on function public.link_inspection_template_to_routine(uuid,uuid,uuid) from public,anon;
grant execute on function public.link_inspection_template_to_routine(uuid,uuid,uuid) to authenticated;

create or replace function private.sync_inspection_assignment_from_work_order()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  if old.assigned_to is distinct from new.assigned_to then
    update public.inspection_runs
    set assigned_to=new.assigned_to,updated_at=now()
    where tenant_id=new.tenant_id and work_order_id=new.id
      and status in('assigned','in_progress');
  end if;
  return new;
end;
$$;
revoke all on function private.sync_inspection_assignment_from_work_order() from public,anon,authenticated;
create trigger sync_inspection_assignment_from_work_order
after update of assigned_to on public.work_orders
for each row execute function private.sync_inspection_assignment_from_work_order();

drop policy if exists "inspection evidence upload" on storage.objects;
create policy "inspection evidence upload"
on storage.objects for insert to authenticated
with check(
  bucket_id='inspection-evidence'
  and exists(
    select 1
    from public.inspection_runs r
    where r.tenant_id=((storage.foldername(name))[1])::uuid
      and r.id=((storage.foldername(name))[2])::uuid
      and r.status in('assigned','in_progress')
      and (
        public.can_manage_tenant(r.tenant_id)
        or r.assigned_to=auth.uid()
      )
  )
);
