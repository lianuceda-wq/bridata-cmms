create or replace function public.complete_analytics_api_request(p_request_id bigint,p_row_count integer,p_status_code integer,p_duration_ms integer)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 update public.analytics_api_requests
 set row_count=greatest(coalesce(p_row_count,0),0),status_code=p_status_code,duration_ms=greatest(coalesce(p_duration_ms,0),0)
 where id=p_request_id;
end $$;
revoke all on function public.complete_analytics_api_request(bigint,integer,integer,integer) from public,anon,authenticated;
grant execute on function public.complete_analytics_api_request(bigint,integer,integer,integer) to service_role;
