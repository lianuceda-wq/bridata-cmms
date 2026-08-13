-- Bridata CMMS - People, Teams, Attendance, Tools & PPE

create table public.workers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  supplier_id uuid,
  employee_code text not null,
  full_name text not null,
  worker_type text not null default 'employee' check(worker_type in('employee','contractor')),
  job_title text,
  email text,
  phone text,
  document_id text,
  hire_date date,
  end_date date,
  status text not null default 'active' check(status in('active','inactive')),
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,employee_code),
  unique(tenant_id,user_id),
  foreign key(tenant_id,supplier_id) references public.suppliers(tenant_id,id) on delete set null,
  check(end_date is null or hire_date is null or end_date>=hire_date)
);
create unique index uq_workers_tenant_id on public.workers(tenant_id,id);
create index idx_workers_status on public.workers(tenant_id,status,worker_type);
create index idx_workers_supplier on public.workers(tenant_id,supplier_id);
create index idx_workers_created_by on public.workers(created_by);

create table public.teams (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null,
  name text not null,
  supervisor_worker_id uuid,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,code),
  foreign key(tenant_id,supervisor_worker_id) references public.workers(tenant_id,id) on delete set null
);
create unique index uq_teams_tenant_id on public.teams(tenant_id,id);
create index idx_teams_supervisor on public.teams(tenant_id,supervisor_worker_id);

create table public.team_memberships (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  team_id uuid not null,
  worker_id uuid not null,
  valid_from date not null default current_date,
  valid_to date,
  created_at timestamptz not null default now(),
  foreign key(tenant_id,team_id) references public.teams(tenant_id,id) on delete cascade,
  foreign key(tenant_id,worker_id) references public.workers(tenant_id,id) on delete cascade,
  check(valid_to is null or valid_to>=valid_from)
);
create unique index uq_team_memberships_active on public.team_memberships(tenant_id,team_id,worker_id) where valid_to is null;
create index idx_team_memberships_worker on public.team_memberships(tenant_id,worker_id,valid_from desc);

create table public.skill_catalog (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null,
  name text not null,
  category text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,code)
);
create unique index uq_skill_catalog_tenant_id on public.skill_catalog(tenant_id,id);

create table public.worker_skills (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  worker_id uuid not null,
  skill_id uuid not null,
  level text check(level in('basic','intermediate','advanced','expert')),
  certified_at date,
  expires_at date,
  certificate_reference text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,worker_id,skill_id),
  foreign key(tenant_id,worker_id) references public.workers(tenant_id,id) on delete cascade,
  foreign key(tenant_id,skill_id) references public.skill_catalog(tenant_id,id) on delete cascade,
  check(expires_at is null or certified_at is null or expires_at>=certified_at)
);
create index idx_worker_skills_worker on public.worker_skills(tenant_id,worker_id);
create index idx_worker_skills_skill on public.worker_skills(tenant_id,skill_id);
create index idx_worker_skills_expiry on public.worker_skills(tenant_id,expires_at) where expires_at is not null;

create table public.worker_attendance (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  worker_id uuid not null,
  work_date date not null,
  status text not null check(status in('present','absent','leave','rest','training')),
  notes text,
  registered_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,worker_id,work_date),
  foreign key(tenant_id,worker_id) references public.workers(tenant_id,id) on delete cascade
);
create index idx_worker_attendance_date on public.worker_attendance(tenant_id,work_date,status);
create index idx_worker_attendance_registered_by on public.worker_attendance(registered_by);

create table public.tools (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null,
  name text not null,
  category text,
  manufacturer text,
  model text,
  serial_number text,
  asset_tag text,
  current_warehouse_id uuid,
  status text not null default 'available' check(status in('available','assigned','maintenance','lost','retired')),
  condition text not null default 'good' check(condition in('good','fair','poor','damaged')),
  acquired_at date,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,code),
  foreign key(tenant_id,current_warehouse_id) references public.warehouses(tenant_id,id) on delete set null
);
create unique index uq_tools_tenant_id on public.tools(tenant_id,id);
create index idx_tools_status on public.tools(tenant_id,status,condition);
create index idx_tools_warehouse on public.tools(tenant_id,current_warehouse_id);

create table public.tool_custody (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  tool_id uuid not null,
  worker_id uuid not null,
  work_order_id uuid,
  issued_at timestamptz not null default now(),
  returned_at timestamptz,
  condition_out text not null check(condition_out in('good','fair','poor','damaged')),
  condition_in text check(condition_in in('good','fair','poor','damaged')),
  status text not null default 'active' check(status in('active','returned','lost','damaged')),
  notes text,
  issued_by uuid references auth.users(id) on delete set null default auth.uid(),
  returned_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key(tenant_id,tool_id) references public.tools(tenant_id,id) on delete restrict,
  foreign key(tenant_id,worker_id) references public.workers(tenant_id,id) on delete restrict,
  foreign key(tenant_id,work_order_id) references public.work_orders(tenant_id,id) on delete set null,
  check(returned_at is null or returned_at>=issued_at)
);
create unique index uq_tool_active_custody on public.tool_custody(tenant_id,tool_id) where status='active';
create index idx_tool_custody_worker on public.tool_custody(tenant_id,worker_id,status);
create index idx_tool_custody_work_order on public.tool_custody(tenant_id,work_order_id);
create index idx_tool_custody_issued_by on public.tool_custody(issued_by);
create index idx_tool_custody_returned_by on public.tool_custody(returned_by);

create table public.ppe_catalog (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null,
  name text not null,
  material_id uuid,
  replacement_days integer check(replacement_days is null or replacement_days>0),
  certification_standard text,
  requires_size boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,code),
  foreign key(tenant_id,material_id) references public.materials(tenant_id,id) on delete set null
);
create unique index uq_ppe_catalog_tenant_id on public.ppe_catalog(tenant_id,id);
create index idx_ppe_catalog_material on public.ppe_catalog(tenant_id,material_id);

create table public.ppe_issues (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  ppe_id uuid not null,
  worker_id uuid not null,
  warehouse_id uuid,
  inventory_movement_id uuid,
  quantity numeric not null default 1 check(quantity>0),
  size text,
  issued_at timestamptz not null default now(),
  expires_at date,
  replacement_due date,
  status text not null default 'active' check(status in('active','replaced','returned','lost','disposed')),
  notes text,
  issued_by uuid references auth.users(id) on delete set null default auth.uid(),
  closed_by uuid references auth.users(id) on delete set null,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key(tenant_id,ppe_id) references public.ppe_catalog(tenant_id,id) on delete restrict,
  foreign key(tenant_id,worker_id) references public.workers(tenant_id,id) on delete restrict,
  foreign key(tenant_id,warehouse_id) references public.warehouses(tenant_id,id) on delete set null,
  foreign key(tenant_id,inventory_movement_id) references public.inventory_movements(tenant_id,id) on delete set null
);
create unique index uq_ppe_issues_tenant_id on public.ppe_issues(tenant_id,id);
create index idx_ppe_issues_worker on public.ppe_issues(tenant_id,worker_id,status);
create index idx_ppe_issues_due on public.ppe_issues(tenant_id,replacement_due,status) where replacement_due is not null;
create index idx_ppe_issues_issued_by on public.ppe_issues(issued_by);
create index idx_ppe_issues_closed_by on public.ppe_issues(closed_by);

create schema if not exists private;
revoke all on schema private from public,anon,authenticated;

create or replace function public.can_manage_people(p_tenant_id uuid)
returns boolean language sql stable security invoker set search_path=public,pg_temp as $$
  select coalesce(public.tenant_role(p_tenant_id) in('owner','admin','planner','supervisor'),false)
$$;
revoke all on function public.can_manage_people(uuid) from public,anon;
grant execute on function public.can_manage_people(uuid) to authenticated;

create or replace function public.record_worker_attendance(
 p_tenant_id uuid,p_worker_id uuid,p_work_date date,p_status text,p_notes text default null
)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid;
begin
  if public.tenant_role(p_tenant_id) not in('owner','admin','supervisor') then raise exception 'Attendance must be registered by supervisor/admin'; end if;
  if not exists(select 1 from public.workers where tenant_id=p_tenant_id and id=p_worker_id and status='active') then raise exception 'Worker not found or inactive'; end if;
  insert into public.worker_attendance(tenant_id,worker_id,work_date,status,notes,registered_by)
  values(p_tenant_id,p_worker_id,p_work_date,p_status,nullif(trim(p_notes),''),auth.uid())
  on conflict(tenant_id,worker_id,work_date) do update
    set status=excluded.status,notes=excluded.notes,registered_by=auth.uid(),updated_at=now()
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.record_worker_attendance(uuid,uuid,date,text,text) from public,anon;
grant execute on function public.record_worker_attendance(uuid,uuid,date,text,text) to authenticated;

create or replace function public.issue_tool(
 p_tenant_id uuid,p_tool_id uuid,p_worker_id uuid,p_work_order_id uuid,p_notes text default null
)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_tool public.tools;v_id uuid;
begin
  if public.tenant_role(p_tenant_id) not in('owner','admin','planner','supervisor','warehouse') then raise exception 'Insufficient tool custody permissions'; end if;
  select * into v_tool from public.tools where tenant_id=p_tenant_id and id=p_tool_id for update;
  if not found or v_tool.status<>'available' or not v_tool.is_active then raise exception 'Tool is not available'; end if;
  if not exists(select 1 from public.workers where tenant_id=p_tenant_id and id=p_worker_id and status='active') then raise exception 'Worker not found or inactive'; end if;
  if p_work_order_id is not null and not exists(select 1 from public.work_orders where tenant_id=p_tenant_id and id=p_work_order_id and status not in('closed','cancelled')) then raise exception 'Work order is not active'; end if;
  insert into public.tool_custody(tenant_id,tool_id,worker_id,work_order_id,condition_out,notes,issued_by)
  values(p_tenant_id,p_tool_id,p_worker_id,p_work_order_id,v_tool.condition,nullif(trim(p_notes),''),auth.uid()) returning id into v_id;
  update public.tools set status='assigned',updated_at=now() where tenant_id=p_tenant_id and id=p_tool_id;
  return v_id;
end $$;
revoke all on function public.issue_tool(uuid,uuid,uuid,uuid,text) from public,anon;
grant execute on function public.issue_tool(uuid,uuid,uuid,uuid,text) to authenticated;

create or replace function public.return_tool(
 p_tenant_id uuid,p_custody_id uuid,p_condition text,p_outcome text default 'returned',p_notes text default null
)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_custody public.tool_custody;v_tool_status text;
begin
  if public.tenant_role(p_tenant_id) not in('owner','admin','planner','supervisor','warehouse') then raise exception 'Insufficient tool custody permissions'; end if;
  select * into v_custody from public.tool_custody where tenant_id=p_tenant_id and id=p_custody_id for update;
  if not found or v_custody.status<>'active' then raise exception 'Active custody not found'; end if;
  if p_outcome not in('returned','lost','damaged') then raise exception 'Invalid custody outcome'; end if;
  if p_condition not in('good','fair','poor','damaged') then raise exception 'Invalid tool condition'; end if;
  update public.tool_custody set status=p_outcome,returned_at=now(),condition_in=p_condition,notes=coalesce(nullif(trim(p_notes),''),notes),returned_by=auth.uid(),updated_at=now()
  where tenant_id=p_tenant_id and id=p_custody_id;
  v_tool_status:=case p_outcome when 'returned' then case when p_condition='damaged' then 'maintenance' else 'available' end when 'lost' then 'lost' else 'maintenance' end;
  update public.tools set status=v_tool_status,condition=p_condition,updated_at=now() where tenant_id=p_tenant_id and id=v_custody.tool_id;
end $$;
revoke all on function public.return_tool(uuid,uuid,text,text,text) from public,anon;
grant execute on function public.return_tool(uuid,uuid,text,text,text) to authenticated;

create or replace function public.issue_ppe(
 p_tenant_id uuid,p_ppe_id uuid,p_worker_id uuid,p_warehouse_id uuid,p_quantity numeric,p_size text,p_notes text default null
)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_ppe public.ppe_catalog;v_move uuid;v_id uuid;v_due date;
begin
  if public.tenant_role(p_tenant_id) not in('owner','admin','supervisor','warehouse') then raise exception 'Insufficient PPE permissions'; end if;
  select * into v_ppe from public.ppe_catalog where tenant_id=p_tenant_id and id=p_ppe_id and is_active=true;
  if not found then raise exception 'PPE not found or inactive'; end if;
  if not exists(select 1 from public.workers where tenant_id=p_tenant_id and id=p_worker_id and status='active') then raise exception 'Worker not found or inactive'; end if;
  if p_quantity is null or p_quantity<=0 then raise exception 'Quantity must be greater than zero'; end if;
  if v_ppe.requires_size and nullif(trim(coalesce(p_size,'')),'') is null then raise exception 'PPE size is required'; end if;
  if v_ppe.material_id is not null then
    if p_warehouse_id is null then raise exception 'Warehouse is required for stock-linked PPE'; end if;
    if private.available_unreserved_stock(p_tenant_id,p_warehouse_id,v_ppe.material_id)<p_quantity then raise exception 'Insufficient unreserved PPE stock'; end if;
    v_move:=private.post_inventory_movement_core(p_tenant_id,p_warehouse_id,v_ppe.material_id,'issue',p_quantity,null,'PEN',null,null,null,'manual','Entrega EPP · '||v_ppe.code,now(),auth.uid());
  end if;
  v_due:=case when v_ppe.replacement_days is null then null else current_date+v_ppe.replacement_days end;
  insert into public.ppe_issues(tenant_id,ppe_id,worker_id,warehouse_id,inventory_movement_id,quantity,size,issued_at,replacement_due,notes,issued_by)
  values(p_tenant_id,p_ppe_id,p_worker_id,p_warehouse_id,v_move,p_quantity,nullif(trim(p_size),''),now(),v_due,nullif(trim(p_notes),''),auth.uid()) returning id into v_id;
  return v_id;
end $$;
revoke all on function public.issue_ppe(uuid,uuid,uuid,uuid,numeric,text,text) from public,anon;
grant execute on function public.issue_ppe(uuid,uuid,uuid,uuid,numeric,text,text) to authenticated;

create or replace function public.close_ppe_issue(
 p_tenant_id uuid,p_issue_id uuid,p_status text,p_notes text default null
)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  if public.tenant_role(p_tenant_id) not in('owner','admin','supervisor','warehouse') then raise exception 'Insufficient PPE permissions'; end if;
  if p_status not in('replaced','returned','lost','disposed') then raise exception 'Invalid PPE closure status'; end if;
  update public.ppe_issues set status=p_status,closed_by=auth.uid(),closed_at=now(),notes=coalesce(nullif(trim(p_notes),''),notes),updated_at=now()
  where tenant_id=p_tenant_id and id=p_issue_id and status='active';
  if not found then raise exception 'Active PPE issue not found'; end if;
end $$;
revoke all on function public.close_ppe_issue(uuid,uuid,text,text) from public,anon;
grant execute on function public.close_ppe_issue(uuid,uuid,text,text) to authenticated;

create or replace view public.worker_resource_status with(security_invoker=true) as
select w.tenant_id,w.id worker_id,w.employee_code,w.full_name,w.worker_type,w.job_title,w.status,
  count(distinct tc.id) filter(where tc.status='active') tools_assigned,
  count(distinct pi.id) filter(where pi.status='active') ppe_active,
  count(distinct pi.id) filter(where pi.status='active' and pi.replacement_due is not null and pi.replacement_due<=current_date) ppe_due,
  count(distinct ws.id) filter(where ws.expires_at is not null and ws.expires_at<=current_date+30) certifications_expiring_30d
from public.workers w
left join public.tool_custody tc on tc.tenant_id=w.tenant_id and tc.worker_id=w.id
left join public.ppe_issues pi on pi.tenant_id=w.tenant_id and pi.worker_id=w.id
left join public.worker_skills ws on ws.tenant_id=w.tenant_id and ws.worker_id=w.id
group by w.tenant_id,w.id,w.employee_code,w.full_name,w.worker_type,w.job_title,w.status;

create or replace view public.attendance_kpis_monthly with(security_invoker=true) as
select tenant_id,date_trunc('month',work_date::timestamp) month,
  count(*) records,
  count(*) filter(where status='present') present_count,
  count(*) filter(where status='absent') absent_count,
  round((100.0*count(*) filter(where status='present')/nullif(count(*) filter(where status in('present','absent')),0))::numeric,2) attendance_percent
from public.worker_attendance group by tenant_id,date_trunc('month',work_date::timestamp);

create trigger workers_updated_at before update on public.workers for each row execute function public.set_updated_at();
create trigger teams_updated_at before update on public.teams for each row execute function public.set_updated_at();
create trigger skills_updated_at before update on public.skill_catalog for each row execute function public.set_updated_at();
create trigger worker_skills_updated_at before update on public.worker_skills for each row execute function public.set_updated_at();
create trigger attendance_updated_at before update on public.worker_attendance for each row execute function public.set_updated_at();
create trigger tools_updated_at before update on public.tools for each row execute function public.set_updated_at();
create trigger tool_custody_updated_at before update on public.tool_custody for each row execute function public.set_updated_at();
create trigger ppe_catalog_updated_at before update on public.ppe_catalog for each row execute function public.set_updated_at();
create trigger ppe_issues_updated_at before update on public.ppe_issues for each row execute function public.set_updated_at();

alter table public.workers enable row level security;alter table public.teams enable row level security;alter table public.team_memberships enable row level security;alter table public.skill_catalog enable row level security;alter table public.worker_skills enable row level security;alter table public.worker_attendance enable row level security;alter table public.tools enable row level security;alter table public.tool_custody enable row level security;alter table public.ppe_catalog enable row level security;alter table public.ppe_issues enable row level security;
create policy workers_select on public.workers for select to authenticated using(public.is_tenant_member(tenant_id));create policy workers_write on public.workers for all to authenticated using(public.can_manage_people(tenant_id)) with check(public.can_manage_people(tenant_id));
create policy teams_select on public.teams for select to authenticated using(public.is_tenant_member(tenant_id));create policy teams_write on public.teams for all to authenticated using(public.can_manage_people(tenant_id)) with check(public.can_manage_people(tenant_id));
create policy team_memberships_select on public.team_memberships for select to authenticated using(public.is_tenant_member(tenant_id));create policy team_memberships_write on public.team_memberships for all to authenticated using(public.can_manage_people(tenant_id)) with check(public.can_manage_people(tenant_id));
create policy skills_select on public.skill_catalog for select to authenticated using(public.is_tenant_member(tenant_id));create policy skills_write on public.skill_catalog for all to authenticated using(public.can_manage_people(tenant_id)) with check(public.can_manage_people(tenant_id));
create policy worker_skills_select on public.worker_skills for select to authenticated using(public.is_tenant_member(tenant_id));create policy worker_skills_write on public.worker_skills for all to authenticated using(public.can_manage_people(tenant_id)) with check(public.can_manage_people(tenant_id));
create policy attendance_select on public.worker_attendance for select to authenticated using(public.is_tenant_member(tenant_id));
create policy tools_select on public.tools for select to authenticated using(public.is_tenant_member(tenant_id));create policy tools_write on public.tools for all to authenticated using(public.tenant_role(tenant_id) in('owner','admin','planner','supervisor','warehouse')) with check(public.tenant_role(tenant_id) in('owner','admin','planner','supervisor','warehouse'));
create policy tool_custody_select on public.tool_custody for select to authenticated using(public.is_tenant_member(tenant_id));
create policy ppe_catalog_select on public.ppe_catalog for select to authenticated using(public.is_tenant_member(tenant_id));create policy ppe_catalog_write on public.ppe_catalog for all to authenticated using(public.tenant_role(tenant_id) in('owner','admin','supervisor','warehouse')) with check(public.tenant_role(tenant_id) in('owner','admin','supervisor','warehouse'));
create policy ppe_issues_select on public.ppe_issues for select to authenticated using(public.is_tenant_member(tenant_id));

grant select on public.workers,public.teams,public.team_memberships,public.skill_catalog,public.worker_skills,public.worker_attendance,public.tools,public.tool_custody,public.ppe_catalog,public.ppe_issues to authenticated;
grant insert,update,delete on public.workers,public.teams,public.team_memberships,public.skill_catalog,public.worker_skills,public.tools,public.ppe_catalog to authenticated;
revoke insert,update,delete on public.worker_attendance,public.tool_custody,public.ppe_issues from authenticated;
grant select on public.worker_resource_status,public.attendance_kpis_monthly to authenticated;
