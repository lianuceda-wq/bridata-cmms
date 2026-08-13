-- Bridata CMMS - hardening de funciones expuestas

revoke all on function public.bootstrap_tenant(text, text) from public;
revoke all on function public.bootstrap_tenant(text, text) from anon;
grant execute on function public.bootstrap_tenant(text, text) to authenticated;

revoke all on function public.is_tenant_member(uuid) from public;
revoke all on function public.is_tenant_member(uuid) from anon;
grant execute on function public.is_tenant_member(uuid) to authenticated;

revoke all on function public.tenant_role(uuid) from public;
revoke all on function public.tenant_role(uuid) from anon;
grant execute on function public.tenant_role(uuid) to authenticated;

revoke all on function public.can_manage_tenant(uuid) from public;
revoke all on function public.can_manage_tenant(uuid) from anon;
grant execute on function public.can_manage_tenant(uuid) to authenticated;

revoke all on function public.can_admin_tenant(uuid) from public;
revoke all on function public.can_admin_tenant(uuid) from anon;
grant execute on function public.can_admin_tenant(uuid) to authenticated;

revoke all on function public.handle_new_user() from public;
revoke all on function public.handle_new_user() from anon;
revoke all on function public.handle_new_user() from authenticated;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

revoke all on function public.set_updated_at() from public;
revoke all on function public.set_updated_at() from anon;
revoke all on function public.set_updated_at() from authenticated;
