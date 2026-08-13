-- Bridata CMMS - Versioned Document Engine

create table public.document_types (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null,
  name text not null,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,code)
);
create unique index uq_document_types_tenant_id on public.document_types(tenant_id,id);

create table public.documents (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  document_type_id uuid,
  code text not null,
  title text not null,
  description text,
  status text not null default 'active' check(status in('active','archived')),
  current_version integer not null default 0 check(current_version>=0),
  effective_from date,
  effective_to date,
  owner_worker_id uuid,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  archived_by uuid references auth.users(id) on delete set null,
  unique(tenant_id,code),
  foreign key(tenant_id,document_type_id) references public.document_types(tenant_id,id) on delete set null,
  foreign key(tenant_id,owner_worker_id) references public.workers(tenant_id,id) on delete set null,
  check(effective_to is null or effective_from is null or effective_to>=effective_from)
);
create unique index uq_documents_tenant_id on public.documents(tenant_id,id);
create index idx_documents_type_status on public.documents(tenant_id,document_type_id,status);
create index idx_documents_owner on public.documents(tenant_id,owner_worker_id);
create index idx_documents_created_by on public.documents(created_by);
create index idx_documents_archived_by on public.documents(archived_by);

create table public.document_versions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  document_id uuid not null,
  version_number integer not null check(version_number>0),
  storage_path text not null,
  file_name text not null,
  mime_type text,
  file_size bigint check(file_size is null or file_size>=0),
  checksum_sha256 text,
  change_notes text,
  uploaded_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  unique(tenant_id,document_id,version_number),
  unique(tenant_id,storage_path),
  foreign key(tenant_id,document_id) references public.documents(tenant_id,id) on delete restrict
);
create unique index uq_document_versions_tenant_id on public.document_versions(tenant_id,id);
create index idx_document_versions_document on public.document_versions(tenant_id,document_id,version_number desc);
create index idx_document_versions_uploaded_by on public.document_versions(uploaded_by);

create table public.document_links (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  document_id uuid not null,
  entity_type text not null check(entity_type in('asset','work_order','failure','inspection','material','worker','maintenance_plan','supplier','purchase_order')),
  entity_id uuid not null,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  unique(tenant_id,document_id,entity_type,entity_id),
  foreign key(tenant_id,document_id) references public.documents(tenant_id,id) on delete cascade
);
create index idx_document_links_entity on public.document_links(tenant_id,entity_type,entity_id);
create index idx_document_links_document on public.document_links(tenant_id,document_id);
create index idx_document_links_created_by on public.document_links(created_by);

create schema if not exists private;
revoke all on schema private from public,anon,authenticated;

create or replace function public.can_manage_documents(p_tenant_id uuid)
returns boolean language sql stable security invoker set search_path=public,pg_temp as $$
  select coalesce(public.tenant_role(p_tenant_id) in('owner','admin','planner','supervisor'),false)
$$;
revoke all on function public.can_manage_documents(uuid) from public,anon;
grant execute on function public.can_manage_documents(uuid) to authenticated;

create or replace function private.document_link_target_exists(p_tenant_id uuid,p_entity_type text,p_entity_id uuid)
returns boolean language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
  return case p_entity_type
    when 'asset' then exists(select 1 from public.assets where tenant_id=p_tenant_id and id=p_entity_id)
    when 'work_order' then exists(select 1 from public.work_orders where tenant_id=p_tenant_id and id=p_entity_id)
    when 'failure' then exists(select 1 from public.failure_events where tenant_id=p_tenant_id and id=p_entity_id)
    when 'inspection' then exists(select 1 from public.inspection_runs where tenant_id=p_tenant_id and id=p_entity_id)
    when 'material' then exists(select 1 from public.materials where tenant_id=p_tenant_id and id=p_entity_id)
    when 'worker' then exists(select 1 from public.workers where tenant_id=p_tenant_id and id=p_entity_id)
    when 'maintenance_plan' then exists(select 1 from public.maintenance_plans where tenant_id=p_tenant_id and id=p_entity_id)
    when 'supplier' then exists(select 1 from public.suppliers where tenant_id=p_tenant_id and id=p_entity_id)
    when 'purchase_order' then exists(select 1 from public.purchase_orders where tenant_id=p_tenant_id and id=p_entity_id)
    else false
  end;
end;
$$;
revoke all on function private.document_link_target_exists(uuid,text,uuid) from public,anon,authenticated;

create or replace function public.create_document(
  p_tenant_id uuid,p_code text,p_title text,p_document_type_id uuid,p_description text,
  p_effective_from date,p_effective_to date,p_owner_worker_id uuid
)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid;
begin
  if not public.can_manage_documents(p_tenant_id) then raise exception 'Insufficient document permissions'; end if;
  if nullif(trim(coalesce(p_code,'')),'') is null or nullif(trim(coalesce(p_title,'')),'') is null then raise exception 'Document code and title are required'; end if;
  if p_document_type_id is not null and not exists(select 1 from public.document_types where tenant_id=p_tenant_id and id=p_document_type_id and is_active=true) then raise exception 'Document type not found or inactive'; end if;
  if p_owner_worker_id is not null and not exists(select 1 from public.workers where tenant_id=p_tenant_id and id=p_owner_worker_id and status='active') then raise exception 'Document owner not found or inactive'; end if;
  insert into public.documents(tenant_id,document_type_id,code,title,description,effective_from,effective_to,owner_worker_id,created_by)
  values(p_tenant_id,p_document_type_id,upper(trim(p_code)),trim(p_title),nullif(trim(p_description),''),p_effective_from,p_effective_to,p_owner_worker_id,auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.create_document(uuid,text,text,uuid,text,date,date,uuid) from public,anon;
grant execute on function public.create_document(uuid,text,text,uuid,text,date,date,uuid) to authenticated;

create or replace function public.register_document_version(
  p_tenant_id uuid,p_document_id uuid,p_storage_path text,p_file_name text,p_mime_type text,p_file_size bigint,p_checksum_sha256 text,p_change_notes text
)
returns integer language plpgsql security definer set search_path=public,private,storage,pg_temp as $$
declare v_document public.documents;v_next integer;
begin
  if not public.can_manage_documents(p_tenant_id) then raise exception 'Insufficient document permissions'; end if;
  select * into v_document from public.documents where tenant_id=p_tenant_id and id=p_document_id for update;
  if not found or v_document.status<>'active' then raise exception 'Document not found or archived'; end if;
  if p_storage_path not like p_tenant_id::text||'/'||p_document_id::text||'/%' then raise exception 'Invalid document storage path'; end if;
  if not exists(select 1 from storage.objects where bucket_id='documents' and name=p_storage_path) then raise exception 'Document file does not exist in storage'; end if;
  v_next:=v_document.current_version+1;
  insert into public.document_versions(tenant_id,document_id,version_number,storage_path,file_name,mime_type,file_size,checksum_sha256,change_notes,uploaded_by)
  values(p_tenant_id,p_document_id,v_next,p_storage_path,p_file_name,p_mime_type,p_file_size,nullif(trim(p_checksum_sha256),''),nullif(trim(p_change_notes),''),auth.uid());
  update public.documents set current_version=v_next,updated_at=now() where tenant_id=p_tenant_id and id=p_document_id;
  return v_next;
end;
$$;
revoke all on function public.register_document_version(uuid,uuid,text,text,text,bigint,text,text) from public,anon;
grant execute on function public.register_document_version(uuid,uuid,text,text,text,bigint,text,text) to authenticated;

create or replace function public.link_document(
  p_tenant_id uuid,p_document_id uuid,p_entity_type text,p_entity_id uuid
)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid;
begin
  if not public.can_manage_documents(p_tenant_id) then raise exception 'Insufficient document permissions'; end if;
  if not exists(select 1 from public.documents where tenant_id=p_tenant_id and id=p_document_id and status='active') then raise exception 'Document not found or archived'; end if;
  if not private.document_link_target_exists(p_tenant_id,p_entity_type,p_entity_id) then raise exception 'Document link target not found in tenant'; end if;
  insert into public.document_links(tenant_id,document_id,entity_type,entity_id,created_by)
  values(p_tenant_id,p_document_id,p_entity_type,p_entity_id,auth.uid())
  on conflict(tenant_id,document_id,entity_type,entity_id) do update set created_by=excluded.created_by
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.link_document(uuid,uuid,text,uuid) from public,anon;
grant execute on function public.link_document(uuid,uuid,text,uuid) to authenticated;

create or replace function public.archive_document(p_tenant_id uuid,p_document_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  if not public.can_manage_documents(p_tenant_id) then raise exception 'Insufficient document permissions'; end if;
  update public.documents set status='archived',archived_at=now(),archived_by=auth.uid(),updated_at=now()
  where tenant_id=p_tenant_id and id=p_document_id and status='active';
  if not found then raise exception 'Active document not found'; end if;
end;
$$;
revoke all on function public.archive_document(uuid,uuid) from public,anon;
grant execute on function public.archive_document(uuid,uuid) to authenticated;

create or replace view public.document_registry with(security_invoker=true) as
select d.tenant_id,d.id,d.code,d.title,d.description,d.status,d.current_version,d.effective_from,d.effective_to,d.owner_worker_id,
       dt.code document_type_code,dt.name document_type_name,
       v.id current_version_id,v.file_name,v.mime_type,v.file_size,v.storage_path,v.created_at version_created_at,
       count(dl.id) links_count,d.created_at,d.updated_at
from public.documents d
left join public.document_types dt on dt.tenant_id=d.tenant_id and dt.id=d.document_type_id
left join public.document_versions v on v.tenant_id=d.tenant_id and v.document_id=d.id and v.version_number=d.current_version
left join public.document_links dl on dl.tenant_id=d.tenant_id and dl.document_id=d.id
group by d.tenant_id,d.id,d.code,d.title,d.description,d.status,d.current_version,d.effective_from,d.effective_to,d.owner_worker_id,dt.code,dt.name,v.id,v.file_name,v.mime_type,v.file_size,v.storage_path,v.created_at,d.created_at,d.updated_at;

create trigger document_types_updated_at before update on public.document_types for each row execute function public.set_updated_at();
create trigger documents_updated_at before update on public.documents for each row execute function public.set_updated_at();

alter table public.document_types enable row level security;
alter table public.documents enable row level security;
alter table public.document_versions enable row level security;
alter table public.document_links enable row level security;
create policy document_types_select on public.document_types for select to authenticated using(public.is_tenant_member(tenant_id));
create policy document_types_write on public.document_types for all to authenticated using(public.can_manage_documents(tenant_id)) with check(public.can_manage_documents(tenant_id));
create policy documents_select on public.documents for select to authenticated using(public.is_tenant_member(tenant_id));
create policy document_versions_select on public.document_versions for select to authenticated using(public.is_tenant_member(tenant_id));
create policy document_links_select on public.document_links for select to authenticated using(public.is_tenant_member(tenant_id));
grant select on public.document_types,public.documents,public.document_versions,public.document_links to authenticated;
grant insert,update,delete on public.document_types to authenticated;
revoke insert,update,delete on public.documents,public.document_versions,public.document_links from authenticated;
grant select on public.document_registry to authenticated;

insert into storage.buckets(id,name,public,file_size_limit)
values('documents','documents',false,52428800)
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit;

create policy "documents read"
on storage.objects for select to authenticated
using(bucket_id='documents' and public.is_tenant_member(((storage.foldername(name))[1])::uuid));

create policy "documents upload"
on storage.objects for insert to authenticated
with check(
  bucket_id='documents'
  and public.can_manage_documents(((storage.foldername(name))[1])::uuid)
  and exists(
    select 1 from public.documents d
    where d.tenant_id=((storage.foldername(name))[1])::uuid
      and d.id=((storage.foldername(name))[2])::uuid
      and d.status='active'
  )
);

create policy "documents controlled delete"
on storage.objects for delete to authenticated
using(
  bucket_id='documents'
  and public.can_manage_documents(((storage.foldername(name))[1])::uuid)
  and not exists(
    select 1 from public.document_versions dv
    where dv.tenant_id=((storage.foldername(name))[1])::uuid and dv.storage_path=name
  )
);
