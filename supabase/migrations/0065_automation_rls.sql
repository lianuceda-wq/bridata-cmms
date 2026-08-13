create or replace function public.can_manage_automations(p_tenant_id uuid)
returns boolean language sql stable set search_path=public,pg_temp as $$
  select coalesce(public.tenant_role(p_tenant_id) in ('owner','admin','planner'),false)
$$;

create or replace function public.is_notification_recipient(p_tenant_id uuid,p_notification_id uuid)
returns boolean language sql stable set search_path=public,pg_temp as $$
  select exists(
    select 1
    from public.notification_recipients r
    where r.tenant_id=p_tenant_id
      and r.notification_id=p_notification_id
      and r.user_id=(select auth.uid())
      and r.dismissed_at is null
  )
$$;

drop policy if exists domain_events_select on public.domain_events;
create policy domain_events_select on public.domain_events
for select to authenticated using (public.is_tenant_member(tenant_id));

drop policy if exists automation_rules_select on public.automation_rules;
create policy automation_rules_select on public.automation_rules
for select to authenticated using (public.is_tenant_member(tenant_id));

drop policy if exists automation_rules_insert on public.automation_rules;
create policy automation_rules_insert on public.automation_rules
for insert to authenticated with check (public.can_manage_automations(tenant_id) and is_system=false);

drop policy if exists automation_rules_update on public.automation_rules;
create policy automation_rules_update on public.automation_rules
for update to authenticated
using (public.can_manage_automations(tenant_id) and is_system=false)
with check (public.can_manage_automations(tenant_id) and is_system=false);

drop policy if exists automation_runs_select on public.automation_runs;
create policy automation_runs_select on public.automation_runs
for select to authenticated using (public.is_tenant_member(tenant_id));

drop policy if exists notification_recipients_select on public.notification_recipients;
create policy notification_recipients_select on public.notification_recipients
for select to authenticated
using (user_id=(select auth.uid()) and public.is_tenant_member(tenant_id));

drop policy if exists notification_recipients_update on public.notification_recipients;
create policy notification_recipients_update on public.notification_recipients
for update to authenticated
using (user_id=(select auth.uid()) and public.is_tenant_member(tenant_id))
with check (user_id=(select auth.uid()) and public.is_tenant_member(tenant_id));

drop policy if exists notifications_select on public.notifications;
create policy notifications_select on public.notifications
for select to authenticated using (public.is_notification_recipient(tenant_id,id));

drop policy if exists operational_alerts_select on public.operational_alerts;
create policy operational_alerts_select on public.operational_alerts
for select to authenticated using (public.is_tenant_member(tenant_id));

revoke insert,delete on public.notification_recipients from anon,authenticated;
revoke update on public.notification_recipients from anon,authenticated;
grant update(read_at,dismissed_at) on public.notification_recipients to authenticated;