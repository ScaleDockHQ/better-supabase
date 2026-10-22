SET local check_function_bodies = off;

DROP FUNCTION "public"."client_notes_reveal"(uuid[]);

CREATE OR REPLACE FUNCTION better_supabase.client_notes_reveal (
  ids uuid[]
)
  RETURNS TABLE (
    id         uuid,
    diagnosis  text,
    birth_date date
  )
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  v_read record;
begin
  if (select auth.uid()) is null and not v_service then
    raise exception 'only signed-in users and the service role reveal client_notes' using errcode = '42501', hint = 'APP_REVEAL_FORBIDDEN';
  end if;
  if coalesce(cardinality(client_notes_reveal.ids), 0) > 500 then
    raise exception 'reveal at most 500 rows of client_notes per call' using errcode = '22023', hint = 'APP_REVEAL_TOO_MANY';
  end if;
  for v_read in
    select t."organization_id" as tenant, jsonb_agg(t.id order by t.id) as ids
    from "public"."client_notes" t
    where t.id = any (client_notes_reveal.ids) and (v_service or ("organization_id" in (select better_supabase.member_organization_ids()) and (select better_supabase.session_active())))
    group by 1
  loop
    perform better_supabase.audit_event(
    event_type => 'client_notes.viewed',
    category => 'read',
    target_type => 'client_notes',
    record_id => case when jsonb_array_length(v_read.ids) = 1 then v_read.ids ->> 0 end,
    summary => 'Revealed ' || jsonb_array_length(v_read.ids)::text || ' ' || 'client_notes' || ' record(s)',
    tenant => (v_read.tenant)::uuid,
    metadata => jsonb_build_object('ids', v_read.ids, 'columns', '["diagnosis","birth_date"]'::jsonb)
  );
  end loop;
  return query
    with r as materialized (
      select t.id, 'tenant:' || (t."organization_id")::text as bs_owner, t."diagnosis", t."birth_date"
      from "public"."client_notes" t
      where t.id = any (client_notes_reveal.ids) and (v_service or ("organization_id" in (select better_supabase.member_organization_ids()) and (select better_supabase.session_active())))
    ),
    k as materialized (
      select o.bs_owner, "better_supabase"."field_key"(o.bs_owner, false) as bs_key
      from (select distinct r.bs_owner from r) o
    )
    select r.id, ("better_supabase"."field_open"(k.bs_key, r."diagnosis"))::text, ("better_supabase"."field_open"(k.bs_key, r."birth_date"))::date
    from r join k on k.bs_owner = r.bs_owner;
end;
$function$;

CREATE OR REPLACE FUNCTION public.client_notes_reveal (
  ids uuid[]
)
  RETURNS TABLE (
    id         uuid,
    diagnosis  text,
    birth_date date
  )
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  select * from "better_supabase"."client_notes_reveal"(ids);
$function$;

REVOKE ALL ON FUNCTION "public"."client_notes_reveal"(uuid[]) FROM PUBLIC, "anon";

REVOKE ALL ON FUNCTION "better_supabase"."client_notes_reveal"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."client_notes_reveal"(uuid[]) TO "authenticated", "service_role";

GRANT EXECUTE ON FUNCTION "public"."client_notes_reveal"(uuid[]) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."client_notes_reveal"(uuid[]) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."client_notes_reveal"(uuid[]) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."client_notes_reveal"(uuid[]) TO "service_role";
