SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.prune_deadlines (
  tenant            uuid,
  subject_type      text,
  subject_id        text,
  keep_jurisdiction text    DEFAULT NULL::text,
  pending_only      boolean DEFAULT true
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (prune_deadlines.tenant is not null and coalesce(better_supabase.can('tenant', prune_deadlines.tenant, 'deadlines.write'), false))) then
    raise exception 'not allowed to prune deadlines' using errcode = '42501', hint = 'DEADLINE_FORBIDDEN';
  end if;
  if not coalesce(prune_deadlines.pending_only, true) and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (prune_deadlines.tenant is not null and coalesce(better_supabase.can('tenant', prune_deadlines.tenant, 'deadlines.manage'), false))) then
    raise exception 'not allowed to delete settled deadlines' using errcode = '42501', hint = 'DEADLINE_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."deadline_subject_readable"(prune_deadlines.subject_type, prune_deadlines.subject_id, prune_deadlines.tenant)) then
    raise exception 'not allowed to prune deadlines for this subject' using errcode = '42501', hint = 'DEADLINE_FORBIDDEN';
  end if;
  delete from "better_supabase"."deadlines" x
  where x."tenant_id" = prune_deadlines.tenant
    and x."subject_type" = prune_deadlines.subject_type
    and x."subject_id" = prune_deadlines.subject_id
    and (not coalesce(prune_deadlines.pending_only, true) or x."state" = 'pending')
    and (prune_deadlines.keep_jurisdiction is null or x."jurisdiction" <> prune_deadlines.keep_jurisdiction);
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;
