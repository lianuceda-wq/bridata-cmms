-- Bridata CMMS - no inferir tiempos de reparación inexistentes

create or replace function private.validate_failure_transition()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  if old.status is not distinct from new.status then return new; end if;

  if not (
    (old.status='open' and new.status in ('in_repair','cancelled')) or
    (old.status='in_repair' and new.status in ('open','restored','cancelled')) or
    (old.status='restored' and new.status in ('in_repair','closed')) or
    (old.status='closed' and new.status='in_repair' and public.can_manage_tenant(new.tenant_id)) or
    (old.status='cancelled' and new.status='open' and public.can_admin_tenant(new.tenant_id))
  ) then
    raise exception 'Invalid failure status transition: % -> %',old.status,new.status;
  end if;

  if new.status='in_repair' then
    new.repair_started_at:=coalesce(new.repair_started_at,now());
    if old.status in ('restored','closed') then
      new.restored_at:=null;
      new.closed_at:=null;
    end if;
  elsif new.status='restored' then
    if new.repair_started_at is null then raise exception 'Repair start time is required before restoration'; end if;
    new.restored_at:=coalesce(new.restored_at,now());
  elsif new.status='closed' then
    if new.restored_at is null then raise exception 'Failure must be restored before closure'; end if;
    new.closed_at:=coalesce(new.closed_at,now());
  elsif new.status='cancelled' then
    if nullif(trim(coalesce(new.cancellation_reason,'')),'') is null then raise exception 'Cancellation reason is required'; end if;
    new.cancelled_at:=coalesce(new.cancelled_at,now());
  end if;

  return new;
end;
$$;
revoke all on function private.validate_failure_transition() from public,anon,authenticated;
