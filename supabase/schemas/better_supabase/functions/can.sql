create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and better_supabase.can_user(auth.uid(), scope, scope_id, permission)
$$;

revoke execute on function better_supabase.can(text, uuid, text) from public;

grant execute on function better_supabase.can(text, uuid, text) to anon, authenticated, service_role;
