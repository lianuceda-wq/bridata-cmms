-- Bridata CMMS - evidencia privada de inspecciones

create table public.inspection_evidence (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  inspection_run_id uuid not null,
  inspection_run_item_id uuid,
  storage_path text not null,
  file_name text,
  mime_type text,
  file_size bigint check(file_size is null or file_size>=0),
  caption text,
  uploaded_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  unique(tenant_id,storage_path),
  foreign key(tenant_id,inspection_run_id) references public.inspection_runs(tenant_id,id) on delete cascade,
  foreign key(tenant_id,inspection_run_item_id) references public.inspection_run_items(tenant_id,id) on delete cascade
);
create unique index uq_inspection_evidence_tenant_id on public.inspection_evidence(tenant_id,id);
create index idx_inspection_evidence_run on public.inspection_evidence(tenant_id,inspection_run_id);
create index idx_inspection_evidence_item on public.inspection_evidence(tenant_id,inspection_run_item_id);
create index idx_inspection_evidence_uploaded_by on public.inspection_evidence(uploaded_by);

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
  if p_item_id is not null and not exists(select 1 from public.inspection_run_items where tenant_id=p_tenant_id and inspection_run_id=p_run_id and id=p_item_id) then raise exception 'Inspection item does not belong to run'; end if;
  if p_storage_path not like p_tenant_id::text||'/'||p_run_id::text||'/%' then raise exception 'Invalid evidence storage path'; end if;
  insert into public.inspection_evidence(tenant_id,inspection_run_id,inspection_run_item_id,storage_path,file_name,mime_type,file_size,caption,uploaded_by)
  values(p_tenant_id,p_run_id,p_item_id,p_storage_path,p_file_name,p_mime_type,p_file_size,nullif(trim(p_caption),''),auth.uid()) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.register_inspection_evidence(uuid,uuid,uuid,text,text,text,bigint,text) from public,anon;
grant execute on function public.register_inspection_evidence(uuid,uuid,uuid,text,text,text,bigint,text) to authenticated;

create or replace function public.transition_inspection_run(p_tenant_id uuid,p_run_id uuid,p_status text,p_cancellation_reason text default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_run public.inspection_runs;v_pending integer;v_missing_evidence integer;v_role text;
begin
  v_role:=public.tenant_role(p_tenant_id);
  select * into v_run from public.inspection_runs where tenant_id=p_tenant_id and id=p_run_id for update;
  if not found then raise exception 'Inspection run not found'; end if;
  if not public.can_manage_tenant(p_tenant_id) and v_run.assigned_to is distinct from auth.uid() then raise exception 'Inspection is not assigned to user'; end if;

  if p_status='in_progress' and v_run.status='assigned' then
    update public.inspection_runs set status='in_progress',started_at=coalesce(started_at,now()),updated_at=now() where id=p_run_id;
  elsif p_status='completed' and v_run.status in('assigned','in_progress') then
    select count(*) into v_pending from public.inspection_run_items where tenant_id=p_tenant_id and inspection_run_id=p_run_id and mandatory=true and result_status='pending';
    if v_pending>0 then raise exception 'Complete all mandatory inspection items first'; end if;
    select count(*) into v_missing_evidence
    from public.inspection_run_items i
    where i.tenant_id=p_tenant_id and i.inspection_run_id=p_run_id and i.requires_evidence=true
      and not exists(select 1 from public.inspection_evidence e where e.tenant_id=i.tenant_id and e.inspection_run_item_id=i.id);
    if v_missing_evidence>0 then raise exception 'Upload evidence for all items that require it'; end if;
    perform private.ensure_findings_for_run(p_tenant_id,p_run_id);
    update public.inspection_runs set status='completed',started_at=coalesce(started_at,now()),completed_at=now(),updated_at=now() where id=p_run_id;
  elsif p_status='validated' and v_run.status='completed' then
    if v_role not in('owner','admin','planner','supervisor') then raise exception 'Manager role required to validate inspection'; end if;
    update public.inspection_runs set status='validated',validated_at=now(),validated_by=auth.uid(),updated_at=now() where id=p_run_id;
  elsif p_status='cancelled' and v_run.status in('assigned','in_progress') then
    if nullif(trim(coalesce(p_cancellation_reason,'')),'') is null then raise exception 'Cancellation reason is required'; end if;
    if v_role not in('owner','admin','planner','supervisor') then raise exception 'Manager role required to cancel inspection'; end if;
    update public.inspection_runs set status='cancelled',cancellation_reason=trim(p_cancellation_reason),updated_at=now() where id=p_run_id;
  else raise exception 'Invalid inspection transition: % -> %',v_run.status,p_status; end if;
end;
$$;

alter table public.inspection_evidence enable row level security;
create policy inspection_evidence_select on public.inspection_evidence for select to authenticated using(public.is_tenant_member(tenant_id));
revoke insert,update,delete on public.inspection_evidence from authenticated;
grant select on public.inspection_evidence to authenticated;

insert into storage.buckets(id,name,public,file_size_limit)
values('inspection-evidence','inspection-evidence',false,10485760)
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit;

create policy "inspection evidence read"
on storage.objects for select to authenticated
using(bucket_id='inspection-evidence' and public.is_tenant_member(((storage.foldername(name))[1])::uuid));

create policy "inspection evidence upload"
on storage.objects for insert to authenticated
with check(bucket_id='inspection-evidence' and public.is_tenant_member(((storage.foldername(name))[1])::uuid));

create policy "inspection evidence manager delete"
on storage.objects for delete to authenticated
using(bucket_id='inspection-evidence' and public.can_manage_tenant(((storage.foldername(name))[1])::uuid));
