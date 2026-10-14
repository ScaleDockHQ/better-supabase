-- Security invoker: the profiles module's column grants and update policy
-- decide what the caller may change.
create or replace function public.update_my_profile(full_name text)
returns void
language plpgsql
volatile
security invoker
set search_path = ''
as $$
begin
  update better_supabase.profiles p
  set full_name = nullif(btrim(update_my_profile.full_name), ''), updated_at = now()
  where p.id = (select auth.uid());
end;
$$;

revoke execute on function public.update_my_profile(text) from public, anon;

grant execute on function public.update_my_profile(text) to authenticated, service_role;
