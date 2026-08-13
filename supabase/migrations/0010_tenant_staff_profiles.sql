-- Bridata CMMS - visibilidad mínima de perfiles entre miembros del mismo tenant.

create policy profiles_tenant_peers_select
on public.profiles
for select to authenticated
using (
  id = (select auth.uid())
  or exists (
    select 1
    from public.tenant_members target
    join public.tenant_members mine
      on mine.tenant_id = target.tenant_id
     and mine.user_id = (select auth.uid())
     and mine.is_active = true
    where target.user_id = profiles.id
      and target.is_active = true
  )
);
