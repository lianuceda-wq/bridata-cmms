-- Bridata CMMS - Inspection Engine

create table public.inspection_templates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null,
  name text not null,
  description text,
  revision integer not null default 1 check(revision>0),
  status text not null default 'draft' check(status in('draft','active','retired','cancelled')),
  supersedes_id uuid,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,code,revision),
  foreign key(tenant_id,supersedes_id) references public.inspection_templates(tenant_id,id) on delete set null
);
create unique index uq_inspection_templates_tenant_id on public.inspection_templates(tenant_id,id);
create unique index uq_inspection_template_active_code on public.inspection_templates(tenant_id,code) where status='active';
create index idx_inspection_template_supersedes on public.inspection_templates(tenant_id,supersedes_id);
create index idx_inspection_template_created_by on public.inspection_templates(created_by);

create table public.inspection_template_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  template_id uuid not null,
  sequence integer not null default 1 check(sequence>0),
  title text not null,
  instructions text,
  response_type text not null default 'boolean' check(response_type in('boolean','number','choice','text','photo')),
  mandatory boolean not null default true,
  requires_evidence boolean not null default false,
  expected_boolean boolean,
  expected_text text,
  options jsonb not null default '[]'::jsonb,
  unit_id uuid references public.measurement_units(id),
  min_value numeric,
  max_value numeric,
  default_finding_severity text not null default 'medium' check(default_finding_severity in('low','medium','high','critical')),
  created_at timestamptz not null default now(),
  unique(tenant_id,template_id,sequence),
  foreign key(tenant_id,template_id) references public.inspection_templates(tenant_id,id) on delete cascade,
  check(max_value is null or min_value is null or max_value>=min_value),
  check(response_type='number' or (min_value is null and max_value is null and unit_id is null)),
  check(response_type='boolean' or expected_boolean is null),
  check(response_type='choice' or (options='[]'::jsonb and expected_text is null)),
  check(jsonb_typeof(options)='array')
);
create unique index uq_inspection_template_items_tenant_id on public.inspection_template_items(tenant_id,id);
create index idx_inspection_template_items_template on public.inspection_template_items(tenant_id,template_id,sequence);

alter table public.maintenance_routines
  add column if not exists inspection_template_id uuid;
alter table public.maintenance_routines
  add constraint maintenance_routines_inspection_template_fk
  foreign key(tenant_id,inspection_template_id)
  references public.inspection_templates(tenant_id,id) on delete set null;
create index if not exists idx_maintenance_routines_inspection_template on public.maintenance_routines(tenant_id,inspection_template_id);

create table public.inspection_sequences (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  year integer not null,
  value bigint not null default 0,
  primary key(tenant_id,year)
);

create table public.inspection_runs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null,
  template_id uuid not null,
  template_revision integer not null,
  work_order_id uuid,
  asset_id uuid,
  site_id uuid,
  location_id uuid,
  status text not null default 'assigned' check(status in('assigned','in_progress','completed','validated','cancelled')),
  assigned_to uuid references auth.users(id) on delete set null,
  scheduled_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  validated_at timestamptz,
  validated_by uuid references auth.users(id) on delete set null,
  cancellation_reason text,
  notes text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,code),
  foreign key(tenant_id,template_id) references public.inspection_templates(tenant_id,id) on delete restrict,
  foreign key(tenant_id,work_order_id) references public.work_orders(tenant_id,id) on delete cascade,
  foreign key(tenant_id,asset_id) references public.assets(tenant_id,id) on delete restrict,
  foreign key(tenant_id,site_id) references public.sites(tenant_id,id) on delete set null,
  foreign key(tenant_id,location_id) references public.locations(tenant_id,id) on delete set null,
  check(asset_id is not null or location_id is not null),
  check(completed_at is null or started_at is not null and completed_at>=started_at),
  check(validated_at is null or completed_at is not null and validated_at>=completed_at)
);
create unique index uq_inspection_runs_tenant_id on public.inspection_runs(tenant_id,id);
create unique index uq_inspection_run_work_order on public.inspection_runs(tenant_id,work_order_id) where work_order_id is not null;
create index idx_inspection_runs_status on public.inspection_runs(tenant_id,status,scheduled_at);
create index idx_inspection_runs_asset on public.inspection_runs(tenant_id,asset_id,created_at desc);
create index idx_inspection_runs_location on public.inspection_runs(tenant_id,location_id,created_at desc);
create index idx_inspection_runs_assigned on public.inspection_runs(tenant_id,assigned_to,status);
create index idx_inspection_runs_created_by on public.inspection_runs(created_by);
create index idx_inspection_runs_validated_by on public.inspection_runs(validated_by);

create table public.inspection_run_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  inspection_run_id uuid not null,
  template_item_id uuid,
  sequence integer not null,
  title text not null,
  instructions text,
  response_type text not null check(response_type in('boolean','number','choice','text','photo')),
  mandatory boolean not null,
  requires_evidence boolean not null,
  expected_boolean boolean,
  expected_text text,
  options jsonb not null default '[]'::jsonb,
  unit_id uuid references public.measurement_units(id),
  min_value numeric,
  max_value numeric,
  default_finding_severity text not null check(default_finding_severity in('low','medium','high','critical')),
  response_boolean boolean,
  response_number numeric,
  response_text text,
  result_status text not null default 'pending' check(result_status in('pending','compliant','nonconforming','not_applicable')),
  notes text,
  completed_by uuid references auth.users(id) on delete set null,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  unique(tenant_id,inspection_run_id,sequence),
  foreign key(tenant_id,inspection_run_id) references public.inspection_runs(tenant_id,id) on delete cascade,
  foreign key(tenant_id,template_item_id) references public.inspection_template_items(tenant_id,id) on delete set null
);
create unique index uq_inspection_run_items_tenant_id on public.inspection_run_items(tenant_id,id);
create index idx_inspection_run_items_run on public.inspection_run_items(tenant_id,inspection_run_id,sequence);
create index idx_inspection_run_items_completed_by on public.inspection_run_items(completed_by);

create table public.inspection_findings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  inspection_run_id uuid not null,
  inspection_run_item_id uuid not null,
  severity text not null check(severity in('low','medium','high','critical')),
  status text not null default 'open' check(status in('open','converted','resolved','dismissed')),
  title text not null,
  description text,
  failure_event_id uuid,
  work_order_id uuid,
  resolution_notes text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  resolved_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  unique(tenant_id,inspection_run_item_id),
  foreign key(tenant_id,inspection_run_id) references public.inspection_runs(tenant_id,id) on delete cascade,
  foreign key(tenant_id,inspection_run_item_id) references public.inspection_run_items(tenant_id,id) on delete cascade,
  foreign key(tenant_id,failure_event_id) references public.failure_events(tenant_id,id) on delete set null,
  foreign key(tenant_id,work_order_id) references public.work_orders(tenant_id,id) on delete set null
);
create unique index uq_inspection_findings_tenant_id on public.inspection_findings(tenant_id,id);
create index idx_inspection_findings_run on public.inspection_findings(tenant_id,inspection_run_id,status);
create index idx_inspection_findings_failure on public.inspection_findings(tenant_id,failure_event_id);
create index idx_inspection_findings_work_order on public.inspection_findings(tenant_id,work_order_id);
create index idx_inspection_findings_created_by on public.inspection_findings(created_by);
create index idx_inspection_findings_resolved_by on public.inspection_findings(resolved_by);

create schema if not exists private;
revoke all on schema private from public,anon,authenticated;

create or replace function private.next_inspection_code(p_tenant_id uuid)
returns text language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_year integer:=extract(year from current_date)::integer;v_value bigint;
begin
  insert into public.inspection_sequences(tenant_id,year,value) values(p_tenant_id,v_year,1)
  on conflict(tenant_id,year) do update set value=public.inspection_sequences.value+1
  returning value into v_value;
  return 'INS-'||v_year::text||'-'||lpad(v_value::text,6,'0');
end $$;
revoke all on function private.next_inspection_code(uuid) from public,anon,authenticated;

create or replace function private.create_inspection_run_core(
 p_tenant_id uuid,p_template_id uuid,p_work_order_id uuid,p_asset_id uuid,p_location_id uuid,p_assigned_to uuid,p_scheduled_at timestamptz,p_created_by uuid
)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_template public.inspection_templates;v_asset public.assets;v_location public.locations;v_run uuid;v_site uuid;
begin
  select * into v_template from public.inspection_templates where tenant_id=p_tenant_id and id=p_template_id and status='active';
  if not found then raise exception 'Inspection template not found or inactive'; end if;
  if p_asset_id is not null then
    select * into v_asset from public.assets where tenant_id=p_tenant_id and id=p_asset_id and is_active=true;
    if not found then raise exception 'Asset not found or inactive'; end if;
    v_site:=v_asset.site_id;
    if p_location_id is null then p_location_id:=v_asset.location_id; end if;
  elsif p_location_id is not null then
    select * into v_location from public.locations where tenant_id=p_tenant_id and id=p_location_id;
    if not found then raise exception 'Location not found'; end if;
    v_site:=v_location.site_id;
  else raise exception 'Asset or location is required'; end if;
  if p_assigned_to is not null and not exists(select 1 from public.tenant_members where tenant_id=p_tenant_id and user_id=p_assigned_to and is_active=true) then raise exception 'Assignee does not belong to tenant'; end if;

  insert into public.inspection_runs(tenant_id,code,template_id,template_revision,work_order_id,asset_id,site_id,location_id,status,assigned_to,scheduled_at,created_by)
  values(p_tenant_id,private.next_inspection_code(p_tenant_id),v_template.id,v_template.revision,p_work_order_id,p_asset_id,v_site,p_location_id,'assigned',p_assigned_to,p_scheduled_at,p_created_by)
  returning id into v_run;

  insert into public.inspection_run_items(
    tenant_id,inspection_run_id,template_item_id,sequence,title,instructions,response_type,mandatory,requires_evidence,
    expected_boolean,expected_text,options,unit_id,min_value,max_value,default_finding_severity
  )
  select tenant_id,v_run,id,sequence,title,instructions,response_type,mandatory,requires_evidence,
         expected_boolean,expected_text,options,unit_id,min_value,max_value,default_finding_severity
  from public.inspection_template_items where tenant_id=p_tenant_id and template_id=p_template_id order by sequence;
  return v_run;
end $$;
revoke all on function private.create_inspection_run_core(uuid,uuid,uuid,uuid,uuid,uuid,timestamptz,uuid) from public,anon,authenticated;

create or replace function public.create_inspection_template(
 p_tenant_id uuid,p_code text,p_name text,p_description text,p_items jsonb
)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_template uuid;v_revision integer;v_previous uuid;v_item jsonb;v_seq integer:=0;
begin
  if public.tenant_role(p_tenant_id) not in('owner','admin','planner','supervisor') then raise exception 'Insufficient template permissions'; end if;
  if nullif(trim(coalesce(p_code,'')),'') is null or nullif(trim(coalesce(p_name,'')),'') is null then raise exception 'Template code and name are required'; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Template requires at least one item'; end if;
  select id,revision into v_previous,v_revision from public.inspection_templates where tenant_id=p_tenant_id and code=upper(trim(p_code)) order by revision desc limit 1;
  v_revision:=coalesce(v_revision,0)+1;
  insert into public.inspection_templates(tenant_id,code,name,description,revision,status,supersedes_id,created_by)
  values(p_tenant_id,upper(trim(p_code)),trim(p_name),nullif(trim(p_description),''),v_revision,'draft',v_previous,auth.uid()) returning id into v_template;
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_seq:=v_seq+1;
    insert into public.inspection_template_items(
      tenant_id,template_id,sequence,title,instructions,response_type,mandatory,requires_evidence,expected_boolean,expected_text,options,unit_id,min_value,max_value,default_finding_severity
    ) values(
      p_tenant_id,v_template,v_seq,trim(v_item->>'title'),nullif(trim(v_item->>'instructions'),''),coalesce(nullif(v_item->>'response_type',''),'boolean'),
      coalesce((v_item->>'mandatory')::boolean,true),coalesce((v_item->>'requires_evidence')::boolean,false),
      nullif(v_item->>'expected_boolean','')::boolean,nullif(v_item->>'expected_text',''),coalesce(v_item->'options','[]'::jsonb),
      nullif(v_item->>'unit_id','')::uuid,nullif(v_item->>'min_value','')::numeric,nullif(v_item->>'max_value','')::numeric,
      coalesce(nullif(v_item->>'default_finding_severity',''),'medium')
    );
  end loop;
  return v_template;
end $$;
revoke all on function public.create_inspection_template(uuid,text,text,text,jsonb) from public,anon;
grant execute on function public.create_inspection_template(uuid,text,text,text,jsonb) to authenticated;

create or replace function public.change_inspection_template_status(p_tenant_id uuid,p_template_id uuid,p_status text)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_template public.inspection_templates;
begin
  if public.tenant_role(p_tenant_id) not in('owner','admin','planner','supervisor') then raise exception 'Insufficient template permissions'; end if;
  select * into v_template from public.inspection_templates where tenant_id=p_tenant_id and id=p_template_id for update;
  if not found then raise exception 'Template not found'; end if;
  if not ((v_template.status='draft' and p_status in('active','cancelled')) or (v_template.status='active' and p_status='retired')) then raise exception 'Invalid template transition'; end if;
  if p_status='active' then
    update public.inspection_templates set status='retired',updated_at=now() where tenant_id=p_tenant_id and code=v_template.code and status='active' and id<>p_template_id;
  end if;
  update public.inspection_templates set status=p_status,updated_at=now() where tenant_id=p_tenant_id and id=p_template_id;
end $$;
revoke all on function public.change_inspection_template_status(uuid,uuid,text) from public,anon;
grant execute on function public.change_inspection_template_status(uuid,uuid,text) to authenticated;

create or replace function public.create_manual_inspection_run(
 p_tenant_id uuid,p_template_id uuid,p_asset_id uuid,p_location_id uuid,p_assigned_to uuid,p_scheduled_at timestamptz default now()
)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  if public.tenant_role(p_tenant_id) not in('owner','admin','planner','supervisor','technician') then raise exception 'Insufficient inspection permissions'; end if;
  if public.tenant_role(p_tenant_id)='technician' and p_assigned_to is distinct from auth.uid() then raise exception 'Technician can only create an inspection assigned to self'; end if;
  return private.create_inspection_run_core(p_tenant_id,p_template_id,null,p_asset_id,p_location_id,p_assigned_to,p_scheduled_at,auth.uid());
end $$;
revoke all on function public.create_manual_inspection_run(uuid,uuid,uuid,uuid,uuid,timestamptz) from public,anon;
grant execute on function public.create_manual_inspection_run(uuid,uuid,uuid,uuid,uuid,timestamptz) to authenticated;

create or replace function private.auto_create_inspection_from_work_order()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_template uuid;
begin
  if new.maintenance_type='inspection' and new.routine_id is not null then
    select inspection_template_id into v_template from public.maintenance_routines where tenant_id=new.tenant_id and id=new.routine_id;
    if v_template is not null and not exists(select 1 from public.inspection_runs where tenant_id=new.tenant_id and work_order_id=new.id) then
      perform private.create_inspection_run_core(new.tenant_id,v_template,new.id,new.asset_id,null,new.assigned_to,new.scheduled_at,new.created_by);
    end if;
  end if;
  return new;
end $$;
revoke all on function private.auto_create_inspection_from_work_order() from public,anon,authenticated;
create trigger auto_create_inspection_from_work_order after insert on public.work_orders for each row execute function private.auto_create_inspection_from_work_order();

create or replace function public.update_inspection_item(
 p_tenant_id uuid,p_run_item_id uuid,p_response_boolean boolean,p_response_number numeric,p_response_text text,p_result_status text,p_notes text
)
returns text language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_item public.inspection_run_items;v_run public.inspection_runs;v_result text;
begin
  select * into v_item from public.inspection_run_items where tenant_id=p_tenant_id and id=p_run_item_id for update;
  if not found then raise exception 'Inspection item not found'; end if;
  select * into v_run from public.inspection_runs where tenant_id=p_tenant_id and id=v_item.inspection_run_id;
  if v_run.status not in('assigned','in_progress') then raise exception 'Inspection is immutable in current status'; end if;
  if public.can_manage_tenant(p_tenant_id) is false and v_run.assigned_to is distinct from auth.uid() then raise exception 'Inspection is not assigned to user'; end if;

  if v_item.response_type='number' then
    if p_response_number is null and v_item.mandatory then raise exception 'Numeric response is required'; end if;
    v_result:=case when p_response_number is null then 'not_applicable' when (v_item.min_value is not null and p_response_number<v_item.min_value) or (v_item.max_value is not null and p_response_number>v_item.max_value) then 'nonconforming' else 'compliant' end;
  elsif v_item.response_type='boolean' then
    if p_response_boolean is null and v_item.mandatory then raise exception 'Boolean response is required'; end if;
    v_result:=case when p_response_boolean is null then 'not_applicable' when v_item.expected_boolean is null or p_response_boolean=v_item.expected_boolean then 'compliant' else 'nonconforming' end;
  elsif v_item.response_type='choice' and v_item.expected_text is not null then
    v_result:=case when nullif(trim(p_response_text),'') is null then case when v_item.mandatory then 'pending' else 'not_applicable' end when trim(p_response_text)=v_item.expected_text then 'compliant' else 'nonconforming' end;
  else
    v_result:=coalesce(nullif(p_result_status,''),case when nullif(trim(p_response_text),'') is null and v_item.mandatory then 'pending' else 'compliant' end);
  end if;
  if v_result not in('pending','compliant','nonconforming','not_applicable') then raise exception 'Invalid result status'; end if;

  update public.inspection_run_items set response_boolean=p_response_boolean,response_number=p_response_number,response_text=nullif(trim(p_response_text),''),result_status=v_result,notes=nullif(trim(p_notes),''),completed_by=case when v_result='pending' then null else auth.uid() end,completed_at=case when v_result='pending' then null else now() end
  where tenant_id=p_tenant_id and id=p_run_item_id;
  return v_result;
end $$;
revoke all on function public.update_inspection_item(uuid,uuid,boolean,numeric,text,text,text) from public,anon;
grant execute on function public.update_inspection_item(uuid,uuid,boolean,numeric,text,text,text) to authenticated;

create or replace function private.ensure_findings_for_run(p_tenant_id uuid,p_run_id uuid)
returns integer language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_count integer:=0;v_item record;
begin
  for v_item in select * from public.inspection_run_items where tenant_id=p_tenant_id and inspection_run_id=p_run_id and result_status='nonconforming' loop
    insert into public.inspection_findings(tenant_id,inspection_run_id,inspection_run_item_id,severity,title,description,created_by)
    values(p_tenant_id,p_run_id,v_item.id,v_item.default_finding_severity,'No conformidad · '||v_item.title,v_item.notes,coalesce(v_item.completed_by,auth.uid()))
    on conflict(tenant_id,inspection_run_item_id) do nothing;
    if found then v_count:=v_count+1; end if;
  end loop;
  return v_count;
end $$;
revoke all on function private.ensure_findings_for_run(uuid,uuid) from public,anon,authenticated;

create or replace function public.transition_inspection_run(p_tenant_id uuid,p_run_id uuid,p_status text,p_cancellation_reason text default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_run public.inspection_runs;v_pending integer;v_role text;
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
end $$;
revoke all on function public.transition_inspection_run(uuid,uuid,text,text) from public,anon;
grant execute on function public.transition_inspection_run(uuid,uuid,text,text) to authenticated;

create or replace function private.guard_work_order_inspection_completion()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_status text;
begin
  if old.status is distinct from new.status and new.status='completed' then
    select status into v_status from public.inspection_runs where tenant_id=new.tenant_id and work_order_id=new.id;
    if v_status is not null and v_status not in('completed','validated') then raise exception 'Complete the linked inspection before completing the work order'; end if;
  end if;
  return new;
end $$;
revoke all on function private.guard_work_order_inspection_completion() from public,anon,authenticated;
create trigger guard_work_order_inspection_completion before update of status on public.work_orders for each row execute function private.guard_work_order_inspection_completion();

create or replace function private.sync_inspection_from_work_order()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  if old.status is distinct from new.status then
    if new.status='in_progress' then update public.inspection_runs set status='in_progress',started_at=coalesce(started_at,new.started_at,now()),updated_at=now() where tenant_id=new.tenant_id and work_order_id=new.id and status='assigned'; end if;
    if new.status in('validated','closed') then update public.inspection_runs set status='validated',completed_at=coalesce(completed_at,new.completed_at,now()),validated_at=coalesce(validated_at,new.validated_at,new.closed_at,now()),validated_by=coalesce(validated_by,auth.uid()),updated_at=now() where tenant_id=new.tenant_id and work_order_id=new.id and status='completed'; end if;
  end if;
  return new;
end $$;
revoke all on function private.sync_inspection_from_work_order() from public,anon,authenticated;
create trigger sync_inspection_from_work_order after update of status on public.work_orders for each row execute function private.sync_inspection_from_work_order();

create or replace function public.convert_inspection_finding_to_failure(p_tenant_id uuid,p_finding_id uuid,p_create_work_order boolean default true)
returns table(failure_id uuid,failure_code text,work_order_id uuid,work_order_code text)
language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_finding public.inspection_findings;v_run public.inspection_runs;v_result record;
begin
  if public.tenant_role(p_tenant_id) not in('owner','admin','planner','supervisor') then raise exception 'Insufficient finding conversion permissions'; end if;
  select * into v_finding from public.inspection_findings where tenant_id=p_tenant_id and id=p_finding_id for update;
  if not found or v_finding.status<>'open' then raise exception 'Finding is not open'; end if;
  select * into v_run from public.inspection_runs where tenant_id=p_tenant_id and id=v_finding.inspection_run_id;
  if v_run.asset_id is null then raise exception 'Finding requires an asset to create a failure'; end if;
  select * into v_result from public.report_failure(p_tenant_id,v_run.asset_id,coalesce(v_run.completed_at,v_run.started_at,v_run.created_at),v_finding.severity,v_finding.title,coalesce(v_finding.description,v_finding.title),null,null,p_create_work_order);
  update public.inspection_findings set status='converted',failure_event_id=v_result.failure_id,work_order_id=v_result.work_order_id where tenant_id=p_tenant_id and id=p_finding_id;
  return query select v_result.failure_id,v_result.failure_code,v_result.work_order_id,v_result.work_order_code;
end $$;
revoke all on function public.convert_inspection_finding_to_failure(uuid,uuid,boolean) from public,anon;
grant execute on function public.convert_inspection_finding_to_failure(uuid,uuid,boolean) to authenticated;

create or replace view public.inspection_run_kpis with(security_invoker=true) as
select r.tenant_id,r.id inspection_run_id,r.code,r.template_id,r.asset_id,r.site_id,r.location_id,r.status,r.scheduled_at,r.started_at,r.completed_at,r.validated_at,
 count(i.id) total_items,count(i.id) filter(where i.result_status='compliant') compliant_items,count(i.id) filter(where i.result_status='nonconforming') nonconforming_items,count(i.id) filter(where i.result_status='pending') pending_items,
 round((100.0*count(i.id) filter(where i.result_status='compliant')/nullif(count(i.id) filter(where i.result_status in('compliant','nonconforming')),0))::numeric,2) compliance_percent,
 count(f.id) filter(where f.status='open') open_findings
from public.inspection_runs r left join public.inspection_run_items i on i.tenant_id=r.tenant_id and i.inspection_run_id=r.id left join public.inspection_findings f on f.tenant_id=r.tenant_id and f.inspection_run_id=r.id
group by r.tenant_id,r.id,r.code,r.template_id,r.asset_id,r.site_id,r.location_id,r.status,r.scheduled_at,r.started_at,r.completed_at,r.validated_at;

create trigger inspection_templates_updated_at before update on public.inspection_templates for each row execute function public.set_updated_at();
create trigger inspection_runs_updated_at before update on public.inspection_runs for each row execute function public.set_updated_at();

alter table public.inspection_templates enable row level security;alter table public.inspection_template_items enable row level security;alter table public.inspection_sequences enable row level security;alter table public.inspection_runs enable row level security;alter table public.inspection_run_items enable row level security;alter table public.inspection_findings enable row level security;
create policy inspection_templates_select on public.inspection_templates for select to authenticated using(public.is_tenant_member(tenant_id));
create policy inspection_template_items_select on public.inspection_template_items for select to authenticated using(public.is_tenant_member(tenant_id));
create policy inspection_runs_select on public.inspection_runs for select to authenticated using(public.is_tenant_member(tenant_id));
create policy inspection_run_items_select on public.inspection_run_items for select to authenticated using(public.is_tenant_member(tenant_id));
create policy inspection_findings_select on public.inspection_findings for select to authenticated using(public.is_tenant_member(tenant_id));
revoke insert,update,delete on public.inspection_templates,public.inspection_template_items,public.inspection_sequences,public.inspection_runs,public.inspection_run_items,public.inspection_findings from authenticated;
grant select on public.inspection_templates,public.inspection_template_items,public.inspection_runs,public.inspection_run_items,public.inspection_findings to authenticated;
grant select on public.inspection_run_kpis to authenticated;
