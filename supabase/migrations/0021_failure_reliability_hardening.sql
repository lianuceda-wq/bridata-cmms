-- Bridata CMMS - hardening de confiabilidad

drop policy if exists failure_events_update on public.failure_events;
create policy failure_events_update on public.failure_events
for update to authenticated
using (
  public.can_manage_tenant(tenant_id)
  or (created_by=(select auth.uid()) and status='open')
)
with check (
  public.can_manage_tenant(tenant_id)
  or (created_by=(select auth.uid()) and status='open')
);

create or replace function private.validate_failure_taxonomy()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_cause_mode uuid;
begin
  if new.failure_cause_id is not null then
    select failure_mode_id into v_cause_mode
    from public.failure_causes
    where tenant_id=new.tenant_id and id=new.failure_cause_id and is_active=true;
    if not found then raise exception 'Failure cause not found or inactive'; end if;
    if v_cause_mode is not null and new.failure_mode_id is distinct from v_cause_mode then
      raise exception 'Failure cause does not belong to selected failure mode';
    end if;
  end if;
  if new.failure_mode_id is not null and not exists(
    select 1 from public.failure_modes where tenant_id=new.tenant_id and id=new.failure_mode_id and is_active=true
  ) then raise exception 'Failure mode not found or inactive'; end if;
  return new;
end;
$$;
revoke all on function private.validate_failure_taxonomy() from public,anon,authenticated;
create trigger validate_failure_taxonomy
before insert or update of failure_mode_id,failure_cause_id
on public.failure_events
for each row execute function private.validate_failure_taxonomy();

create or replace function private.validate_labor_session()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_work_order public.work_orders;
begin
  select * into v_work_order from public.work_orders
  where tenant_id=new.tenant_id and id=new.work_order_id;
  if not found then raise exception 'Work order not found'; end if;
  if new.started_at < v_work_order.created_at - interval '1 day' then
    raise exception 'Labor session starts before the work order existed';
  end if;
  if new.ended_at is not null and new.ended_at < new.started_at then
    raise exception 'Labor session end cannot be before start';
  end if;
  return new;
end;
$$;
revoke all on function private.validate_labor_session() from public,anon,authenticated;
create trigger validate_labor_session
before insert or update on public.work_order_labor_sessions
for each row execute function private.validate_labor_session();

-- Índices de FKs que no quedan cubiertos por índices compuestos de consulta.
create index if not exists idx_failure_causes_mode on public.failure_causes(tenant_id,failure_mode_id);
create index if not exists idx_failure_events_asset on public.failure_events(tenant_id,asset_id);
create index if not exists idx_work_order_failures_work_order on public.work_order_failures(tenant_id,work_order_id);
