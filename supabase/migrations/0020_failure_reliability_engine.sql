-- Bridata CMMS - Failure & Reliability Engine

-- Las OT originadas por fallas quedan identificadas explícitamente.
alter table public.work_orders drop constraint if exists work_orders_source_check;
alter table public.work_orders
  add constraint work_orders_source_check
  check (source in ('manual','maintenance_plan','inspection','request','failure'));

create table public.failure_modes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null,
  name text not null,
  category text,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, code)
);
create unique index uq_failure_modes_tenant_id on public.failure_modes(tenant_id,id);

create table public.failure_causes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  failure_mode_id uuid,
  code text not null,
  name text not null,
  category text,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, code),
  foreign key (tenant_id,failure_mode_id) references public.failure_modes(tenant_id,id) on delete set null
);
create unique index uq_failure_causes_tenant_id on public.failure_causes(tenant_id,id);

create table public.failure_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text,
  asset_id uuid not null,
  site_id uuid,
  location_id uuid,
  failure_mode_id uuid,
  failure_cause_id uuid,
  severity text not null default 'medium' check (severity in ('low','medium','high','critical')),
  status text not null default 'open' check (status in ('open','in_repair','restored','closed','cancelled')),
  source text not null default 'manual' check (source in ('manual','inspection','work_order','api','sensor')),
  symptom text,
  description text not null,
  occurred_at timestamptz not null,
  reported_at timestamptz not null default now(),
  repair_started_at timestamptz,
  restored_at timestamptz,
  closed_at timestamptz,
  cancelled_at timestamptz,
  cancellation_reason text,
  root_cause_notes text,
  reported_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id,code),
  foreign key (tenant_id,asset_id) references public.assets(tenant_id,id) on delete restrict,
  foreign key (tenant_id,site_id) references public.sites(tenant_id,id) on delete set null,
  foreign key (tenant_id,location_id) references public.locations(tenant_id,id) on delete set null,
  foreign key (tenant_id,failure_mode_id) references public.failure_modes(tenant_id,id) on delete set null,
  foreign key (tenant_id,failure_cause_id) references public.failure_causes(tenant_id,id) on delete set null,
  constraint failure_event_time_order check (
    reported_at >= occurred_at
    and (repair_started_at is null or repair_started_at >= occurred_at)
    and (restored_at is null or restored_at >= occurred_at)
    and (closed_at is null or restored_at is not null and closed_at >= restored_at)
    and (cancelled_at is null or cancelled_at >= reported_at)
  )
);
create unique index uq_failure_events_tenant_id on public.failure_events(tenant_id,id);
create index idx_failure_events_asset_time on public.failure_events(tenant_id,asset_id,occurred_at desc);
create index idx_failure_events_status on public.failure_events(tenant_id,status,occurred_at desc);
create index idx_failure_events_mode on public.failure_events(tenant_id,failure_mode_id,occurred_at desc);
create index idx_failure_events_cause on public.failure_events(tenant_id,failure_cause_id,occurred_at desc);
create index idx_failure_events_site on public.failure_events(tenant_id,site_id,occurred_at desc);
create index idx_failure_events_location on public.failure_events(tenant_id,location_id,occurred_at desc);
create index idx_failure_events_reported_by on public.failure_events(reported_by);
create index idx_failure_events_created_by on public.failure_events(created_by);

create table public.work_order_failures (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  work_order_id uuid not null,
  failure_event_id uuid not null,
  relation_type text not null default 'primary' check (relation_type in ('primary','supporting','inspection_followup')),
  linked_by uuid references auth.users(id) on delete set null default auth.uid(),
  linked_at timestamptz not null default now(),
  primary key (tenant_id,work_order_id,failure_event_id),
  foreign key (tenant_id,work_order_id) references public.work_orders(tenant_id,id) on delete cascade,
  foreign key (tenant_id,failure_event_id) references public.failure_events(tenant_id,id) on delete cascade
);
create index idx_work_order_failures_failure on public.work_order_failures(tenant_id,failure_event_id);
create index idx_work_order_failures_linked_by on public.work_order_failures(linked_by);
create unique index uq_primary_work_order_per_failure
  on public.work_order_failures(tenant_id,failure_event_id)
  where relation_type='primary';

create table public.failure_status_history (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  failure_event_id uuid not null,
  from_status text,
  to_status text not null,
  changed_by uuid references auth.users(id) on delete set null,
  notes text,
  changed_at timestamptz not null default now(),
  foreign key (tenant_id,failure_event_id) references public.failure_events(tenant_id,id) on delete cascade
);
create index idx_failure_history_event on public.failure_status_history(tenant_id,failure_event_id,changed_at);
create index idx_failure_history_changed_by on public.failure_status_history(changed_by);

-- Horas-hombre reales por trabajador/contratista. La duración se deriva, nunca se digita.
create table public.work_order_labor_sessions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  work_order_id uuid not null,
  worker_user_id uuid references auth.users(id) on delete set null,
  worker_name text,
  worker_type text not null default 'employee' check (worker_type in ('employee','contractor','external')),
  started_at timestamptz not null,
  ended_at timestamptz,
  labor_role text,
  notes text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (tenant_id,work_order_id) references public.work_orders(tenant_id,id) on delete cascade,
  constraint labor_worker_required check (worker_user_id is not null or nullif(trim(coalesce(worker_name,'')),'') is not null),
  constraint labor_time_order check (ended_at is null or ended_at >= started_at)
);
create index idx_labor_sessions_work_order on public.work_order_labor_sessions(tenant_id,work_order_id,started_at);
create index idx_labor_sessions_worker on public.work_order_labor_sessions(worker_user_id,started_at);
create index idx_labor_sessions_created_by on public.work_order_labor_sessions(created_by);

create schema if not exists private;
revoke all on schema private from public,anon,authenticated;

create or replace function private.next_failure_code(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_year text:=to_char(current_date,'YYYY');
  v_value bigint;
begin
  insert into public.tenant_sequences(tenant_id,sequence_key,value)
  values(p_tenant_id,'failure_'||v_year,1)
  on conflict(tenant_id,sequence_key)
  do update set value=public.tenant_sequences.value+1,updated_at=now()
  returning value into v_value;
  return 'FAL-'||v_year||'-'||lpad(v_value::text,6,'0');
end;
$$;
revoke all on function private.next_failure_code(uuid) from public,anon,authenticated;

create or replace function private.prepare_failure_event()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_asset public.assets;
begin
  if new.code is null or btrim(new.code)='' then new.code:=private.next_failure_code(new.tenant_id); end if;
  select * into v_asset from public.assets where tenant_id=new.tenant_id and id=new.asset_id;
  if not found then raise exception 'Asset does not belong to tenant'; end if;
  new.site_id:=coalesce(new.site_id,v_asset.site_id);
  new.location_id:=coalesce(new.location_id,v_asset.location_id);
  if new.reported_at < new.occurred_at then raise exception 'Reported time cannot be before occurrence time'; end if;
  return new;
end;
$$;
revoke all on function private.prepare_failure_event() from public,anon,authenticated;
create trigger prepare_failure_event before insert on public.failure_events for each row execute function private.prepare_failure_event();

create or replace function private.assign_manual_work_order_code()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  if new.code is null or btrim(new.code)='' then new.code:=private.next_work_order_code(new.tenant_id); end if;
  return new;
end;
$$;
revoke all on function private.assign_manual_work_order_code() from public,anon,authenticated;
drop trigger if exists assign_manual_work_order_code on public.work_orders;
create trigger assign_manual_work_order_code before insert on public.work_orders for each row execute function private.assign_manual_work_order_code();

create or replace function private.failure_status_audit()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  if tg_op='INSERT' or old.status is distinct from new.status then
    insert into public.failure_status_history(tenant_id,failure_event_id,from_status,to_status,changed_by)
    values(new.tenant_id,new.id,case when tg_op='INSERT' then null else old.status end,new.status,auth.uid());
  end if;
  return new;
end;
$$;
revoke all on function private.failure_status_audit() from public,anon,authenticated;
create trigger failure_status_audit after insert or update of status on public.failure_events for each row execute function private.failure_status_audit();

create or replace function private.validate_failure_transition()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  if old.status is not distinct from new.status then return new; end if;
  if not (
    (old.status='open' and new.status in ('in_repair','restored','closed','cancelled')) or
    (old.status='in_repair' and new.status in ('open','restored','cancelled')) or
    (old.status='restored' and new.status in ('in_repair','closed')) or
    (old.status='closed' and new.status='in_repair' and public.can_manage_tenant(new.tenant_id)) or
    (old.status='cancelled' and new.status='open' and public.can_admin_tenant(new.tenant_id))
  ) then raise exception 'Invalid failure status transition: % -> %',old.status,new.status; end if;

  if new.status='in_repair' then
    new.repair_started_at:=coalesce(new.repair_started_at,now());
    if old.status in ('restored','closed') then new.restored_at:=null; new.closed_at:=null; end if;
  elsif new.status='restored' then
    new.repair_started_at:=coalesce(new.repair_started_at,new.occurred_at);
    new.restored_at:=coalesce(new.restored_at,now());
  elsif new.status='closed' then
    new.repair_started_at:=coalesce(new.repair_started_at,new.occurred_at);
    new.restored_at:=coalesce(new.restored_at,now());
    new.closed_at:=coalesce(new.closed_at,now());
  elsif new.status='cancelled' then
    if nullif(trim(coalesce(new.cancellation_reason,'')),'') is null then raise exception 'Cancellation reason is required'; end if;
    new.cancelled_at:=coalesce(new.cancelled_at,now());
  end if;
  return new;
end;
$$;
revoke all on function private.validate_failure_transition() from public,anon,authenticated;
create trigger validate_failure_transition before update of status on public.failure_events for each row execute function private.validate_failure_transition();

create or replace function private.sync_failure_from_primary_work_order()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  r record;
begin
  if tg_op<>'UPDATE' or old.status is not distinct from new.status then return new; end if;
  for r in
    select f.id,f.status
    from public.work_order_failures wf
    join public.failure_events f on f.tenant_id=wf.tenant_id and f.id=wf.failure_event_id
    where wf.tenant_id=new.tenant_id and wf.work_order_id=new.id and wf.relation_type='primary'
  loop
    if new.status='in_progress' then
      update public.failure_events set status='in_repair',repair_started_at=coalesce(repair_started_at,new.started_at,now()),restored_at=null,closed_at=null
      where tenant_id=new.tenant_id and id=r.id and status not in ('cancelled');
    elsif new.status='completed' then
      update public.failure_events set status='restored',repair_started_at=coalesce(repair_started_at,new.started_at,occurred_at),restored_at=coalesce(new.completed_at,now())
      where tenant_id=new.tenant_id and id=r.id and status not in ('cancelled');
    elsif new.status='closed' then
      update public.failure_events set status='closed',repair_started_at=coalesce(repair_started_at,new.started_at,occurred_at),restored_at=coalesce(restored_at,new.completed_at,new.closed_at,now()),closed_at=coalesce(new.closed_at,now())
      where tenant_id=new.tenant_id and id=r.id and status not in ('cancelled');
    elsif new.status='cancelled' and r.status='in_repair' then
      update public.failure_events set status='open' where tenant_id=new.tenant_id and id=r.id;
    end if;
  end loop;
  return new;
end;
$$;
revoke all on function private.sync_failure_from_primary_work_order() from public,anon,authenticated;
create trigger sync_failure_from_primary_work_order after update of status on public.work_orders for each row execute function private.sync_failure_from_primary_work_order();

create or replace function public.report_failure(
  p_tenant_id uuid,
  p_asset_id uuid,
  p_occurred_at timestamptz,
  p_severity text,
  p_symptom text,
  p_description text,
  p_failure_mode_id uuid default null,
  p_failure_cause_id uuid default null,
  p_create_work_order boolean default true
)
returns table(failure_id uuid,failure_code text,work_order_id uuid,work_order_code text)
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare
  v_failure_id uuid;
  v_failure_code text;
  v_work_order_id uuid;
  v_work_order_code text;
  v_asset public.assets;
  v_priority text;
begin
  if public.tenant_role(p_tenant_id) not in ('owner','admin','planner','supervisor','technician') then raise exception 'Insufficient permissions'; end if;
  if p_occurred_at is null then raise exception 'Failure occurrence time is required'; end if;
  if nullif(trim(coalesce(p_description,'')),'') is null then raise exception 'Failure description is required'; end if;
  select * into v_asset from public.assets where tenant_id=p_tenant_id and id=p_asset_id and is_active=true;
  if not found then raise exception 'Asset not found or inactive'; end if;
  v_priority:=case p_severity when 'critical' then 'critical' when 'high' then 'high' when 'low' then 'low' else 'medium' end;

  insert into public.failure_events(tenant_id,asset_id,failure_mode_id,failure_cause_id,severity,source,symptom,description,occurred_at,reported_at,reported_by,created_by)
  values(p_tenant_id,p_asset_id,p_failure_mode_id,p_failure_cause_id,coalesce(p_severity,'medium'),'manual',nullif(trim(p_symptom),''),trim(p_description),p_occurred_at,now(),auth.uid(),auth.uid())
  returning id,code into v_failure_id,v_failure_code;

  if p_create_work_order then
    insert into public.work_orders(tenant_id,asset_id,code,title,description,maintenance_type,priority,status,source,scheduled_at,created_by)
    values(p_tenant_id,p_asset_id,null,'Correctivo · '||v_asset.code||' · '||v_failure_code,p_description,'corrective',v_priority,'requested','failure',now(),auth.uid())
    returning id,code into v_work_order_id,v_work_order_code;

    insert into public.work_order_failures(tenant_id,work_order_id,failure_event_id,relation_type,linked_by)
    values(p_tenant_id,v_work_order_id,v_failure_id,'primary',auth.uid());
  end if;

  return query select v_failure_id,v_failure_code,v_work_order_id,v_work_order_code;
end;
$$;
revoke all on function public.report_failure(uuid,uuid,timestamptz,text,text,text,uuid,uuid,boolean) from public,anon;
grant execute on function public.report_failure(uuid,uuid,timestamptz,text,text,text,uuid,uuid,boolean) to authenticated;

-- Eventos temporales derivados del historial de estados; no duplicamos una segunda tabla de reloj.
create or replace view public.work_order_time_events
with(security_invoker=true)
as
select
  h.id,h.tenant_id,h.work_order_id,h.from_status,h.to_status,
  case h.to_status when 'in_progress' then 'work_started_or_resumed' when 'paused' then 'work_paused' when 'completed' then 'work_completed' when 'validated' then 'work_validated' when 'closed' then 'work_closed' else 'status_changed' end as event_type,
  h.changed_by,h.notes,h.changed_at
from public.work_order_status_history h;

create or replace view public.work_order_timing_metrics
with(security_invoker=true)
as
with ordered as (
  select h.*,lead(h.changed_at) over(partition by h.tenant_id,h.work_order_id order by h.changed_at,h.id) as next_changed_at
  from public.work_order_status_history h
), active as (
  select tenant_id,work_order_id,
    sum(extract(epoch from (coalesce(next_changed_at,now())-changed_at))/60.0) filter(where to_status='in_progress') as active_minutes
  from ordered group by tenant_id,work_order_id
)
select wo.tenant_id,wo.id work_order_id,wo.started_at,wo.completed_at,wo.closed_at,
  case when wo.started_at is not null and wo.completed_at is not null then extract(epoch from (wo.completed_at-wo.started_at))/60.0 end elapsed_execution_minutes,
  a.active_minutes,
  case when wo.started_at is not null and wo.completed_at is not null then greatest(0,extract(epoch from (wo.completed_at-wo.started_at))/60.0-coalesce(a.active_minutes,0)) end paused_minutes
from public.work_orders wo left join active a on a.tenant_id=wo.tenant_id and a.work_order_id=wo.id;

create or replace view public.work_order_labor_metrics
with(security_invoker=true)
as
select tenant_id,work_order_id,count(*) labor_records,count(*) filter(where ended_at is null) open_labor_sessions,
  sum(extract(epoch from (coalesce(ended_at,now())-started_at))/3600.0) labor_hours
from public.work_order_labor_sessions group by tenant_id,work_order_id;

create or replace view public.failure_event_metrics
with(security_invoker=true)
as
select f.id,f.tenant_id,f.code,f.asset_id,f.site_id,f.location_id,f.failure_mode_id,f.failure_cause_id,f.severity,f.status,f.occurred_at,f.reported_at,f.repair_started_at,f.restored_at,f.closed_at,
  case when f.reported_at>=f.occurred_at then extract(epoch from(f.reported_at-f.occurred_at))/60.0 end detection_minutes,
  case when f.repair_started_at is not null then extract(epoch from(f.repair_started_at-f.reported_at))/60.0 end response_minutes,
  case when f.repair_started_at is not null and f.restored_at is not null then extract(epoch from(f.restored_at-f.repair_started_at))/60.0 end repair_minutes,
  case when f.restored_at is not null then extract(epoch from(f.restored_at-f.occurred_at))/60.0 end downtime_minutes,
  wf.work_order_id,wo.code work_order_code,wo.status work_order_status
from public.failure_events f
left join public.work_order_failures wf on wf.tenant_id=f.tenant_id and wf.failure_event_id=f.id and wf.relation_type='primary'
left join public.work_orders wo on wo.tenant_id=wf.tenant_id and wo.id=wf.work_order_id;

create or replace view public.asset_reliability_metrics
with(security_invoker=true)
as
with ordered as (
  select f.tenant_id,f.asset_id,f.id,f.occurred_at,f.restored_at,
    lag(f.restored_at) over(partition by f.tenant_id,f.asset_id order by f.occurred_at,f.id) as previous_restored_at
  from public.failure_events f
  where f.status in ('restored','closed') and f.restored_at is not null
), base as (
  select f.tenant_id,f.asset_id,
    count(*) filter(where f.status<>'cancelled') failure_count,
    count(*) filter(where f.occurred_at>=now()-interval '12 months' and f.status<>'cancelled') failures_12m,
    avg(extract(epoch from(f.restored_at-f.repair_started_at))/3600.0) filter(where f.repair_started_at is not null and f.restored_at is not null) mttr_hours,
    avg(extract(epoch from(f.restored_at-f.occurred_at))/3600.0) filter(where f.restored_at is not null) avg_downtime_hours
  from public.failure_events f group by f.tenant_id,f.asset_id
), mtbf as (
  select tenant_id,asset_id,
    avg(extract(epoch from(occurred_at-previous_restored_at))/3600.0) filter(where previous_restored_at is not null and occurred_at>=previous_restored_at) mtbf_hours
  from ordered group by tenant_id,asset_id
)
select b.tenant_id,b.asset_id,b.failure_count,b.failures_12m,round(b.mttr_hours::numeric,2) mttr_hours,round(b.avg_downtime_hours::numeric,2) avg_downtime_hours,round(m.mtbf_hours::numeric,2) mtbf_hours
from base b left join mtbf m on m.tenant_id=b.tenant_id and m.asset_id=b.asset_id;

-- updated_at
create trigger failure_modes_updated_at before update on public.failure_modes for each row execute function public.set_updated_at();
create trigger failure_causes_updated_at before update on public.failure_causes for each row execute function public.set_updated_at();
create trigger failure_events_updated_at before update on public.failure_events for each row execute function public.set_updated_at();
create trigger labor_sessions_updated_at before update on public.work_order_labor_sessions for each row execute function public.set_updated_at();

-- RLS
alter table public.failure_modes enable row level security;
alter table public.failure_causes enable row level security;
alter table public.failure_events enable row level security;
alter table public.work_order_failures enable row level security;
alter table public.failure_status_history enable row level security;
alter table public.work_order_labor_sessions enable row level security;

create policy failure_modes_select on public.failure_modes for select to authenticated using(public.is_tenant_member(tenant_id));
create policy failure_modes_insert on public.failure_modes for insert to authenticated with check(public.can_manage_tenant(tenant_id));
create policy failure_modes_update on public.failure_modes for update to authenticated using(public.can_manage_tenant(tenant_id)) with check(public.can_manage_tenant(tenant_id));
create policy failure_modes_delete on public.failure_modes for delete to authenticated using(public.can_admin_tenant(tenant_id));
create policy failure_causes_select on public.failure_causes for select to authenticated using(public.is_tenant_member(tenant_id));
create policy failure_causes_insert on public.failure_causes for insert to authenticated with check(public.can_manage_tenant(tenant_id));
create policy failure_causes_update on public.failure_causes for update to authenticated using(public.can_manage_tenant(tenant_id)) with check(public.can_manage_tenant(tenant_id));
create policy failure_causes_delete on public.failure_causes for delete to authenticated using(public.can_admin_tenant(tenant_id));

create policy failure_events_select on public.failure_events for select to authenticated using(public.is_tenant_member(tenant_id));
create policy failure_events_insert on public.failure_events for insert to authenticated with check(public.tenant_role(tenant_id) in ('owner','admin','planner','supervisor','technician') and created_by=(select auth.uid()));
create policy failure_events_update on public.failure_events for update to authenticated using(public.can_manage_tenant(tenant_id) or (created_by=(select auth.uid()) and status='open')) with check(public.is_tenant_member(tenant_id));
create policy failure_events_delete on public.failure_events for delete to authenticated using(public.can_admin_tenant(tenant_id) and status='open');

create policy work_order_failures_select on public.work_order_failures for select to authenticated using(public.is_tenant_member(tenant_id));
create policy work_order_failures_insert on public.work_order_failures for insert to authenticated with check(public.can_manage_tenant(tenant_id) or exists(select 1 from public.failure_events f join public.work_orders wo on wo.tenant_id=f.tenant_id where f.tenant_id=work_order_failures.tenant_id and f.id=work_order_failures.failure_event_id and wo.id=work_order_failures.work_order_id and f.created_by=(select auth.uid()) and wo.created_by=(select auth.uid())));
create policy work_order_failures_delete on public.work_order_failures for delete to authenticated using(public.can_manage_tenant(tenant_id));

create policy failure_history_select on public.failure_status_history for select to authenticated using(public.is_tenant_member(tenant_id));

create policy labor_sessions_select on public.work_order_labor_sessions for select to authenticated using(public.is_tenant_member(tenant_id));
create policy labor_sessions_insert on public.work_order_labor_sessions for insert to authenticated with check(public.can_manage_tenant(tenant_id) or (public.tenant_role(tenant_id)='technician' and (worker_user_id=(select auth.uid()) or created_by=(select auth.uid()))));
create policy labor_sessions_update on public.work_order_labor_sessions for update to authenticated using(public.can_manage_tenant(tenant_id) or created_by=(select auth.uid()) or worker_user_id=(select auth.uid())) with check(public.is_tenant_member(tenant_id));
create policy labor_sessions_delete on public.work_order_labor_sessions for delete to authenticated using(public.can_manage_tenant(tenant_id));

grant select on public.failure_modes,public.failure_causes,public.failure_events,public.work_order_failures,public.failure_status_history,public.work_order_labor_sessions to authenticated;
grant insert,update,delete on public.failure_modes,public.failure_causes,public.failure_events,public.work_order_failures,public.work_order_labor_sessions to authenticated;
grant select on public.failure_status_history to authenticated;
grant select on public.work_order_time_events,public.work_order_timing_metrics,public.work_order_labor_metrics,public.failure_event_metrics,public.asset_reliability_metrics to authenticated;
