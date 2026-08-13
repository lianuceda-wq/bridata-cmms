-- Bridata CMMS - integridad de usuarios y estado de herramientas

create or replace function private.validate_worker_user_link()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  if new.user_id is not null and not exists(
    select 1 from public.tenant_members tm
    where tm.tenant_id=new.tenant_id and tm.user_id=new.user_id and tm.is_active=true
  ) then
    raise exception 'Linked user must be an active member of the same tenant';
  end if;
  return new;
end;
$$;
revoke all on function private.validate_worker_user_link() from public,anon,authenticated;
create trigger validate_worker_user_link
before insert or update of user_id,tenant_id on public.workers
for each row execute function private.validate_worker_user_link();

create or replace function private.guard_tool_operational_state()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  if (old.status is distinct from new.status or old.condition is distinct from new.condition)
     and current_setting('bridata.tool_state_write',true) is distinct from '1' then
    raise exception 'Tool status/condition can only change through custody operations';
  end if;
  return new;
end;
$$;
revoke all on function private.guard_tool_operational_state() from public,anon,authenticated;
create trigger guard_tool_operational_state
before update of status,condition on public.tools
for each row execute function private.guard_tool_operational_state();

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
  perform set_config('bridata.tool_state_write','1',true);
  update public.tools set status='assigned',updated_at=now() where tenant_id=p_tenant_id and id=p_tool_id;
  perform set_config('bridata.tool_state_write','0',true);
  return v_id;
end;
$$;

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
  perform set_config('bridata.tool_state_write','1',true);
  update public.tools set status=v_tool_status,condition=p_condition,updated_at=now() where tenant_id=p_tenant_id and id=v_custody.tool_id;
  perform set_config('bridata.tool_state_write','0',true);
end;
$$;

create or replace function public.set_tool_service_state(
  p_tenant_id uuid,p_tool_id uuid,p_status text,p_condition text,p_notes text default null
)
returns void
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare v_tool public.tools;
begin
  if public.tenant_role(p_tenant_id) not in('owner','admin','planner','supervisor','warehouse') then raise exception 'Insufficient tool permissions'; end if;
  if p_status not in('available','maintenance','retired') then raise exception 'Invalid manual tool state'; end if;
  if p_condition not in('good','fair','poor','damaged') then raise exception 'Invalid condition'; end if;
  select * into v_tool from public.tools where tenant_id=p_tenant_id and id=p_tool_id for update;
  if not found then raise exception 'Tool not found'; end if;
  if exists(select 1 from public.tool_custody where tenant_id=p_tenant_id and tool_id=p_tool_id and status='active') then raise exception 'Tool has active custody'; end if;
  perform set_config('bridata.tool_state_write','1',true);
  update public.tools set status=p_status,condition=p_condition,is_active=case when p_status='retired' then false else is_active end,updated_at=now()
  where tenant_id=p_tenant_id and id=p_tool_id;
  perform set_config('bridata.tool_state_write','0',true);
  insert into public.audit_logs(tenant_id,user_id,entity_type,entity_id,action,metadata)
  values(p_tenant_id,auth.uid(),'tool',p_tool_id,'tool_state_changed',jsonb_build_object('status',p_status,'condition',p_condition,'notes',p_notes));
end;
$$;
revoke all on function public.set_tool_service_state(uuid,uuid,text,text,text) from public,anon;
grant execute on function public.set_tool_service_state(uuid,uuid,text,text,text) to authenticated;
