-- Bridata CMMS - integridad de horas-hombre y cierre de OT

create unique index if not exists uq_open_labor_session_per_user
on public.work_order_labor_sessions(tenant_id,worker_user_id)
where ended_at is null and worker_user_id is not null;

create or replace function private.validate_labor_session()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_work_order public.work_orders;
begin
  select * into v_work_order
  from public.work_orders
  where tenant_id=new.tenant_id and id=new.work_order_id;
  if not found then raise exception 'Work order not found'; end if;
  if v_work_order.status in ('closed','cancelled') then
    raise exception 'Labor cannot be modified on closed or cancelled work orders';
  end if;
  if new.started_at < v_work_order.created_at - interval '1 day' then
    raise exception 'Labor session starts before the work order existed';
  end if;
  if new.ended_at is not null and new.ended_at < new.started_at then
    raise exception 'Labor session end cannot be before start';
  end if;
  return new;
end;
$$;

create or replace function private.lock_labor_on_closed_work_order()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_tenant uuid;
  v_work_order uuid;
  v_status text;
begin
  if tg_op='DELETE' then
    v_tenant:=old.tenant_id; v_work_order:=old.work_order_id;
  else
    v_tenant:=new.tenant_id; v_work_order:=new.work_order_id;
  end if;
  select status into v_status from public.work_orders where tenant_id=v_tenant and id=v_work_order;
  if v_status in ('closed','cancelled') then raise exception 'Labor is immutable after work order closure/cancellation'; end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function private.lock_labor_on_closed_work_order() from public,anon,authenticated;
create trigger labor_closed_work_order_guard
before delete on public.work_order_labor_sessions
for each row execute function private.lock_labor_on_closed_work_order();

create or replace function private.ensure_labor_closed_before_work_order_completion()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare v_open integer;
begin
  if old.status is distinct from new.status and new.status='completed' then
    select count(*) into v_open
    from public.work_order_labor_sessions ls
    where ls.tenant_id=new.tenant_id and ls.work_order_id=new.id and ls.ended_at is null;
    if v_open>0 then raise exception 'Close all active labor sessions before completing the work order'; end if;
  end if;
  return new;
end;
$$;
revoke all on function private.ensure_labor_closed_before_work_order_completion() from public,anon,authenticated;
create trigger work_order_labor_completion_guard
before update of status on public.work_orders
for each row execute function private.ensure_labor_closed_before_work_order_completion();
