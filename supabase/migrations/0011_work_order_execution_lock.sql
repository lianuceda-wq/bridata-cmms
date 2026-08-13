-- Bridata CMMS - inmutabilidad de ejecución una vez completada la OT.

create or replace function public.validate_work_order_task_execution()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_work_order_status text;
begin
  if tg_op = 'UPDATE' then
    select status into v_work_order_status
    from public.work_orders
    where tenant_id = new.tenant_id
      and id = new.work_order_id;

    if v_work_order_status in ('completed','validated','closed','cancelled') then
      raise exception 'Work order tasks are locked after completion';
    end if;
  end if;

  if new.status = 'skipped' and new.mandatory then
    raise exception 'A mandatory task cannot be skipped';
  end if;

  if new.status = 'completed' then
    if new.task_type = 'measurement' and new.measurement_value is null then
      raise exception 'Measurement value is required';
    end if;

    if new.task_type = 'measurement' then
      if (new.min_value is not null and new.measurement_value < new.min_value)
         or (new.max_value is not null and new.measurement_value > new.max_value) then
        new.result_status := 'out_of_range';
      else
        new.result_status := coalesce(new.result_status, 'passed');
      end if;
    else
      new.result_status := coalesce(new.result_status, 'passed');
    end if;

    new.completed_by := coalesce(new.completed_by, auth.uid());
    new.completed_at := coalesce(new.completed_at, now());
  else
    new.completed_by := null;
    new.completed_at := null;
    if new.status = 'pending' then
      new.result_status := null;
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.validate_work_order_task_execution() from public, anon, authenticated;
