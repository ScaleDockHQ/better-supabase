SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.update_my_profile (
  attrs jsonb
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  updated integer;
begin
  update "better_supabase"."profiles" p
  set "full_name" = case when update_my_profile.attrs ? 'full_name' then update_my_profile.attrs ->> 'full_name' else p."full_name" end,
    "first_name" = case when update_my_profile.attrs ? 'first_name' then update_my_profile.attrs ->> 'first_name' else p."first_name" end,
    "last_name" = case when update_my_profile.attrs ? 'last_name' then update_my_profile.attrs ->> 'last_name' else p."last_name" end,
    "avatar_url" = case when update_my_profile.attrs ? 'avatar_url' then update_my_profile.attrs ->> 'avatar_url' else p."avatar_url" end,
    "username" = case when update_my_profile.attrs ? 'username' then update_my_profile.attrs ->> 'username' else p."username" end,
    "onboarding" = case when update_my_profile.attrs ? 'onboarding' then update_my_profile.attrs -> 'onboarding' else p."onboarding" end,
    "updated_at" = now()
  where p."id" = (select auth.uid());
  get diagnostics updated = row_count;
  return updated > 0;
end;
$function$;
