SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.row_visible (
  rel        regclass,
  key_column name,
  key_value  anyelement
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_role name := coalesce(nullif(current_setting('role', true), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user);
  v_using text;
  v_found boolean;
begin
  if not has_table_privilege(v_role, rel, 'select') then
    return false;
  end if;
  if coalesce((select r.rolbypassrls from pg_catalog.pg_roles r where r.rolname = v_role), false)
    or not (select c.relrowsecurity from pg_catalog.pg_class c where c.oid = rel) then
    v_using := 'true';
  else
    select '(' || coalesce(string_agg('(' || coalesce(pg_catalog.pg_get_expr(p.polqual, p.polrelid), 'true') || ')', ' or ') filter (where p.polpermissive), 'false') || ')'
        || coalesce(' and ' || string_agg('(' || coalesce(pg_catalog.pg_get_expr(p.polqual, p.polrelid), 'true') || ')', ' and ') filter (where not p.polpermissive), '')
      into v_using
    from pg_catalog.pg_policy p
    where p.polrelid = rel
      and p.polcmd in ('r', '*')
      and (0::oid = any (p.polroles) or exists (select 1 from unnest(p.polroles) o where pg_catalog.pg_has_role(v_role, o, 'member')));
  end if;
  execute format('select exists (select 1 from %s where %I = $1 and (%s))', rel, key_column, v_using)
    into v_found using key_value;
  return coalesce(v_found, false);
exception when others then
  return false;
end;
$function$;

REVOKE ALL ON FUNCTION "better_supabase"."row_visible"(regclass, name, anyelement) FROM PUBLIC;
