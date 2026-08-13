-- Bridata CMMS - SaaS membership & tenant administration

create table public.tenant_settings (
  tenant_id uuid primary key references public.tenants(id) on delete cascade,
  timezone text not null default 'America/Lima',
  default_currency text not null default 'PEN' check(length(default_currency)=3),
  locale text not null default 'es-PE',
  measurement_system text not null default 'metric' check(measurement_system in('metric','imperial')),
  require_supervisor_validation boolean not null default true,
  hydraulic_capture_mode text not null default 'manual' check(hydraulic_capture_mode in('manual','mixed','automatic')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.tenant_invitations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  email text not null,
  role text not null check(role in('owner','admin','planner','supervisor','technician','viewer','warehouse')),
  token_hash text not null unique,
  status text not null default 'pending' check(status in('pending','accepted','revoked','expired')),
  expires_at timestamptz not null,
  invited_by uuid references auth.users(id) on delete set null default auth.uid(),
  accepted_by uuid references auth.users(id) on delete set null,
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoked_by uuid references auth.users(id) on delete set null
);
create index idx_tenant_invitations_pending on public.tenant_invitations(tenant_id,status,expires_at);
create index idx_tenant_invitations_email on public.tenant_invitations(lower(email),status);
create unique index uq_tenant_pending_invite_email on public.tenant_invitations(tenant_id,lower(email)) where status='pending';
create index idx_tenant_invitations_invited_by on public.tenant_invitations(invited_by);
create index idx_tenant_invitations_accepted_by on public.tenant_invitations(accepted_by);
create index idx_tenant_invitations_revoked_by on public.tenant_invitations(revoked_by);

create or replace function private.ensure_tenant_settings()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  insert into public.tenant_settings(tenant_id) values(new.id) on conflict(tenant_id) do nothing;
  return new;
end $$;
revoke all on function private.ensure_tenant_settings() from public,anon,authenticated;
create trigger ensure_tenant_settings after insert on public.tenants for each row execute function private.ensure_tenant_settings();
insert into public.tenant_settings(tenant_id) select id from public.tenants on conflict(tenant_id) do nothing;

create or replace function public.can_admin_members(p_tenant_id uuid)
returns boolean language sql stable security invoker set search_path=public,pg_temp as $$
  select coalesce(public.tenant_role(p_tenant_id) in('owner','admin'),false)
$$;
revoke all on function public.can_admin_members(uuid) from public,anon;
grant execute on function public.can_admin_members(uuid) to authenticated;

create or replace function public.create_tenant_invitation(
  p_tenant_id uuid,p_email text,p_role text,p_expires_days integer default 7
)
returns text language plpgsql security definer set search_path=public,private,extensions,pg_temp as $$
declare v_role text;v_token uuid;v_email text;
begin
  v_role:=public.tenant_role(p_tenant_id);
  if v_role not in('owner','admin') then raise exception 'Insufficient member administration permissions'; end if;
  if p_role not in('owner','admin','planner','supervisor','technician','viewer','warehouse') then raise exception 'Invalid role'; end if;
  if p_role='owner' and v_role<>'owner' then raise exception 'Only an owner can invite another owner'; end if;
  v_email:=lower(trim(coalesce(p_email,'')));
  if v_email='' or position('@' in v_email)=0 then raise exception 'Valid email is required'; end if;
  if exists(select 1 from public.profiles p join public.tenant_members tm on tm.user_id=p.id where tm.tenant_id=p_tenant_id and lower(p.email)=v_email and tm.is_active=true) then raise exception 'User is already an active tenant member'; end if;
  update public.tenant_invitations set status='revoked',revoked_at=now(),revoked_by=auth.uid()
  where tenant_id=p_tenant_id and lower(email)=v_email and status='pending';
  v_token:=gen_random_uuid();
  insert into public.tenant_invitations(tenant_id,email,role,token_hash,expires_at,invited_by)
  values(p_tenant_id,v_email,p_role,encode(digest(v_token::text,'sha256'),'hex'),now()+make_interval(days=>greatest(1,least(coalesce(p_expires_days,7),30))),auth.uid());
  return v_token::text;
end $$;
revoke all on function public.create_tenant_invitation(uuid,text,text,integer) from public,anon;
grant execute on function public.create_tenant_invitation(uuid,text,text,integer) to authenticated;

create or replace function public.accept_tenant_invitation(p_token text)
returns uuid language plpgsql security definer set search_path=public,private,extensions,auth,pg_temp as $$
declare v_inv public.tenant_invitations;v_email text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select lower(email) into v_email from auth.users where id=auth.uid();
  select * into v_inv from public.tenant_invitations
  where token_hash=encode(digest(trim(p_token),'sha256'),'hex') and status='pending' for update;
  if not found then raise exception 'Invitation not found or already used'; end if;
  if v_inv.expires_at<now() then
    update public.tenant_invitations set status='expired' where id=v_inv.id;
    raise exception 'Invitation expired';
  end if;
  if lower(v_inv.email)<>v_email then raise exception 'Invitation email does not match signed-in account'; end if;
  insert into public.tenant_members(tenant_id,user_id,role,is_active)
  values(v_inv.tenant_id,auth.uid(),v_inv.role,true)
  on conflict(tenant_id,user_id) do update set role=excluded.role,is_active=true;
  update public.tenant_invitations set status='accepted',accepted_by=auth.uid(),accepted_at=now() where id=v_inv.id;
  return v_inv.tenant_id;
end $$;
revoke all on function public.accept_tenant_invitation(text) from public,anon;
grant execute on function public.accept_tenant_invitation(text) to authenticated;

create or replace function private.active_owner_count(p_tenant_id uuid)
returns integer language sql stable security definer set search_path=public,private,pg_temp as $$
  select count(*)::integer from public.tenant_members where tenant_id=p_tenant_id and role='owner' and is_active=true
$$;
revoke all on function private.active_owner_count(uuid) from public,anon,authenticated;

create or replace function public.set_tenant_member_role(p_tenant_id uuid,p_user_id uuid,p_role text)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_actor text;v_current text;
begin
  v_actor:=public.tenant_role(p_tenant_id);
  if v_actor not in('owner','admin') then raise exception 'Insufficient member administration permissions'; end if;
  if p_role not in('owner','admin','planner','supervisor','technician','viewer','warehouse') then raise exception 'Invalid role'; end if;
  select role into v_current from public.tenant_members where tenant_id=p_tenant_id and user_id=p_user_id and is_active=true for update;
  if v_current is null then raise exception 'Active member not found'; end if;
  if (v_current='owner' or p_role='owner') and v_actor<>'owner' then raise exception 'Only owners can manage owner role'; end if;
  if v_current='owner' and p_role<>'owner' and private.active_owner_count(p_tenant_id)<=1 then raise exception 'Tenant must keep at least one active owner'; end if;
  update public.tenant_members set role=p_role where tenant_id=p_tenant_id and user_id=p_user_id;
  insert into public.audit_logs(tenant_id,user_id,entity_type,entity_id,action,metadata)
  values(p_tenant_id,auth.uid(),'tenant_member',p_user_id,'role_changed',jsonb_build_object('from',v_current,'to',p_role));
end $$;
revoke all on function public.set_tenant_member_role(uuid,uuid,text) from public,anon;
grant execute on function public.set_tenant_member_role(uuid,uuid,text) to authenticated;

create or replace function public.set_tenant_member_active(p_tenant_id uuid,p_user_id uuid,p_active boolean)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_actor text;v_current public.tenant_members;
begin
  v_actor:=public.tenant_role(p_tenant_id);
  if v_actor not in('owner','admin') then raise exception 'Insufficient member administration permissions'; end if;
  select * into v_current from public.tenant_members where tenant_id=p_tenant_id and user_id=p_user_id for update;
  if not found then raise exception 'Member not found'; end if;
  if v_current.role='owner' and v_actor<>'owner' then raise exception 'Only owners can manage owners'; end if;
  if v_current.role='owner' and p_active=false and v_current.is_active=true and private.active_owner_count(p_tenant_id)<=1 then raise exception 'Tenant must keep at least one active owner'; end if;
  if p_user_id=auth.uid() and p_active=false then raise exception 'You cannot deactivate your own membership'; end if;
  update public.tenant_members set is_active=p_active where tenant_id=p_tenant_id and user_id=p_user_id;
  insert into public.audit_logs(tenant_id,user_id,entity_type,entity_id,action,metadata)
  values(p_tenant_id,auth.uid(),'tenant_member',p_user_id,case when p_active then 'member_activated' else 'member_deactivated' end,jsonb_build_object('role',v_current.role));
end $$;
revoke all on function public.set_tenant_member_active(uuid,uuid,boolean) from public,anon;
grant execute on function public.set_tenant_member_active(uuid,uuid,boolean) to authenticated;

create or replace function public.revoke_tenant_invitation(p_tenant_id uuid,p_invitation_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  if not public.can_admin_members(p_tenant_id) then raise exception 'Insufficient member administration permissions'; end if;
  update public.tenant_invitations set status='revoked',revoked_at=now(),revoked_by=auth.uid()
  where tenant_id=p_tenant_id and id=p_invitation_id and status='pending';
  if not found then raise exception 'Pending invitation not found'; end if;
end $$;
revoke all on function public.revoke_tenant_invitation(uuid,uuid) from public,anon;
grant execute on function public.revoke_tenant_invitation(uuid,uuid) to authenticated;

create or replace function public.update_tenant_settings(
  p_tenant_id uuid,p_timezone text,p_default_currency text,p_locale text,p_measurement_system text,
  p_require_supervisor_validation boolean,p_hydraulic_capture_mode text
)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  if public.tenant_role(p_tenant_id) not in('owner','admin') then raise exception 'Insufficient tenant settings permissions'; end if;
  if not exists(select 1 from pg_timezone_names where name=p_timezone) then raise exception 'Invalid timezone'; end if;
  if length(p_default_currency)<>3 then raise exception 'Invalid currency'; end if;
  if p_measurement_system not in('metric','imperial') then raise exception 'Invalid measurement system'; end if;
  if p_hydraulic_capture_mode not in('manual','mixed','automatic') then raise exception 'Invalid hydraulic mode'; end if;
  insert into public.tenant_settings(tenant_id,timezone,default_currency,locale,measurement_system,require_supervisor_validation,hydraulic_capture_mode)
  values(p_tenant_id,p_timezone,upper(p_default_currency),p_locale,p_measurement_system,p_require_supervisor_validation,p_hydraulic_capture_mode)
  on conflict(tenant_id) do update set timezone=excluded.timezone,default_currency=excluded.default_currency,locale=excluded.locale,measurement_system=excluded.measurement_system,require_supervisor_validation=excluded.require_supervisor_validation,hydraulic_capture_mode=excluded.hydraulic_capture_mode,updated_at=now();
end $$;
revoke all on function public.update_tenant_settings(uuid,text,text,text,text,boolean,text) from public,anon;
grant execute on function public.update_tenant_settings(uuid,text,text,text,text,boolean,text) to authenticated;

create trigger tenant_settings_updated_at before update on public.tenant_settings for each row execute function public.set_updated_at();
alter table public.tenant_settings enable row level security;
alter table public.tenant_invitations enable row level security;
create policy tenant_settings_select on public.tenant_settings for select to authenticated using(public.is_tenant_member(tenant_id));
create policy tenant_invitations_select on public.tenant_invitations for select to authenticated using(public.can_admin_members(tenant_id));
grant select on public.tenant_settings,public.tenant_invitations to authenticated;
revoke insert,update,delete on public.tenant_settings,public.tenant_invitations from authenticated;
