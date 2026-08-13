create or replace function private.publish_hydraulic_nonconformance_event()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_out integer;v_total integer;
begin
  if old.status is distinct from new.status and new.status='validated' and new.session_type='hydraulic_control' then
    select count(*) filter(where compliance_status='out_of_range'),count(*)
    into v_out,v_total
    from public.operational_readings
    where tenant_id=new.tenant_id and session_id=new.id;

    if v_out>0 then
      perform private.publish_domain_event(
        new.tenant_id,'hydraulic.nonconforming','measurement_session',new.id,
        jsonb_build_object('id',new.id,'code',new.code,'out_of_range',v_out,'total_readings',v_total,'site_id',new.site_id,'location_id',new.location_id,'occurred_at',new.occurred_at),
        null
      );
    end if;
  end if;
  return new;
end $$;

revoke all on function private.publish_hydraulic_nonconformance_event() from public,anon,authenticated;
drop trigger if exists publish_hydraulic_nonconformance_event on public.measurement_sessions;
create trigger publish_hydraulic_nonconformance_event after update of status on public.measurement_sessions for each row execute function private.publish_hydraulic_nonconformance_event();