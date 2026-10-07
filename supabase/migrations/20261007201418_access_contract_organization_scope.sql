SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.can_user (
  member     uuid,
  scope      text,
  scope_id   uuid,
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(
    scope in ('tenant', 'organization')
      and r.role is not null
      and exists (
        select 1 from unnest(better_supabase.role_permissions(r.role)) k(key)
        where k.key = '*' or k.key = permission
      ),
    false
  )
  from (select better_supabase.organization_member_role(scope_id, member) as role) r
$function$;
