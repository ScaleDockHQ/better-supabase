SET local check_function_bodies = off;
set lock_timeout = '5s';

CREATE OR REPLACE FUNCTION better_supabase.app_organization_members (
  organization uuid
)
  RETURNS TABLE (
    user_id     uuid,
    role        text,
    full_name   text,
    email       text,
    avatar_url  text,
    avatar_path text,
    joined_at   timestamp with time zone
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  -- The service role lists any organization's members (the workflow tick
  -- route looks up the owner a schedule runs as).
  if not ((select auth.role()) = 'service_role'
    or better_supabase.member_can((select auth.uid()), organization, 'members.read')) then
    raise exception 'Not allowed to list members' using errcode = '42501';
  end if;
  return query
  select m.user_id, r.key, p.full_name, coalesce(p.email, u.email::text), p.avatar_url, p.avatar_path, m.created_at
  from public.memberships m
  join better_supabase.roles r on r.id = m.role
  join auth.users u on u.id = m.user_id
  left join better_supabase.profiles p on p.id = m.user_id
  where m.organization_id = organization
  order by array_position(array['member', 'admin', 'owner'], r.key) desc nulls last, coalesce(p.full_name, u.email::text);
end;
$function$;
