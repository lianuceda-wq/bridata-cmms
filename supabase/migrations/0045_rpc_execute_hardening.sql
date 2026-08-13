-- Bridata CMMS - RPC execute hardening
-- `add_manual_cost` is an authenticated operational mutation and must never be callable by anon/public.

revoke all on function public.add_manual_cost(uuid, uuid, text, numeric, text, text, timestamptz) from public;
revoke all on function public.add_manual_cost(uuid, uuid, text, numeric, text, text, timestamptz) from anon;
grant execute on function public.add_manual_cost(uuid, uuid, text, numeric, text, text, timestamptz) to authenticated;
