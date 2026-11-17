/**
 * `better_supabase.row_visible(rel, column, value)`: whether the calling API
 * role would see the row of `rel` whose `column` equals `value` through the
 * table's select policies. A block function runs as its owner, past RLS, so it
 * calls this to answer a refused action with "forbidden" instead of "not found"
 * when the caller can see the row through a policy the block's read key doesn't
 * cover (ADR 1088). Sub-queries in a policy run with the owner's rights, and
 * any error answers false.
 */
export const ROW_VISIBLE: string = `create or replace function better_supabase.row_visible(rel regclass, key_column name, key_value anyelement)
returns boolean
language plpgsql
stable
set search_path = ''
as $$
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
$$;
revoke execute on function better_supabase.row_visible(regclass, name, anyelement) from public, anon, authenticated;`;
