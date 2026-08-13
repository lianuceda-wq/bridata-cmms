-- La política de peers ya incluye id = auth.uid(), por lo que esta política es redundante.
drop policy if exists profiles_self_select on public.profiles;
