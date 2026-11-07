-- Every trigger a block adds is named bsb_*, and the rate-limit unique indexes
-- end in _key. Renames only: no row moves.
alter trigger "conversations_broadcast" on "better_supabase"."inbox_conversations" rename to "bsb_conversations_broadcast";
alter trigger "inbox_conversation_events_broadcast" on "better_supabase"."inbox_conversation_events" rename to "bsb_inbox_conversation_events_broadcast";
alter trigger "inbox_message_deliveries_broadcast" on "better_supabase"."inbox_message_deliveries" rename to "bsb_inbox_message_deliveries_broadcast";
alter trigger "bookings_engagement" on "better_supabase"."bookings" rename to "bsb_bookings_engagement";
alter trigger "passes_credit_refund" on "better_supabase"."bookings" rename to "bsb_passes_credit_refund";
alter trigger "calendar_attendees_auto_decline" on "better_supabase"."calendar_attendees" rename to "bsb_calendar_attendees_auto_decline";
alter trigger "calendar_events_auto_decline" on "better_supabase"."calendar_events" rename to "bsb_calendar_events_auto_decline";
alter index "better_supabase"."bsb_rate_limit_rules_scope_global" rename to "bsb_rate_limit_rules_scope_global_key";
alter index "better_supabase"."bsb_rate_limit_rules_scope_org" rename to "bsb_rate_limit_rules_scope_org_key";
alter trigger "permission_overrides_bump_authz_versions" on "better_supabase"."permission_overrides" rename to "bsb_permission_overrides_bump_authz_versions";
alter table "better_supabase"."flag_overrides" rename constraint "flag_overrides_unique" to "flag_overrides_key";
alter table "better_supabase"."flag_revisions" rename constraint "flag_revisions_unique" to "flag_revisions_key";
alter table "better_supabase"."bookings" rename constraint "bookings_no_overlap" to "bookings_no_overlap_excl";
alter table "better_supabase"."time_entries" rename constraint "time_entries_no_overlap" to "time_entries_no_overlap_excl";
alter table "better_supabase"."shift_assignments" rename constraint "shift_assignments_no_overlap" to "shift_assignments_no_overlap_excl";

SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.set_flag_override (
  key         text,
  variant     text,
  tenant      uuid DEFAULT NULL::uuid,
  member      uuid DEFAULT NULL::uuid,
  context     text DEFAULT NULL::text,
  context_key text DEFAULT NULL::text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('flags.manage'), false))) then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  if num_nonnulls(tenant, member, context) <> 1 or (context is null) <> (context_key is null) then
    raise exception 'Pass one target: a tenant, a member, or a context with its key' using errcode = '22023', hint = 'FLAGS_OVERRIDE_TARGET';
  end if;
  if variant is null then
    delete from "better_supabase"."flag_overrides" v
    where v."flag_key" = set_flag_override.key
      and v."organization_id" is not distinct from set_flag_override.tenant
      and v."user_id" is not distinct from set_flag_override.member
      and v."context" is not distinct from set_flag_override.context
      and v."context_key" is not distinct from set_flag_override.context_key;
    if not found then
      return false;
    end if;
    perform "better_supabase".emit_event('flag.override_changed', jsonb_build_object('key', set_flag_override.key, 'variant', set_flag_override.variant, 'organizationId', set_flag_override.tenant::text, 'userId', set_flag_override.member, 'context', set_flag_override.context, 'contextKey', set_flag_override.context_key), 'flags/' || set_flag_override.key, (set_flag_override.tenant)::text, null, 'better-supabase/flags');
  perform better_supabase.audit_event(
    event_type => 'flag.override_changed',
    category => 'configuration',
    target_type => 'flag',
    record_id => set_flag_override.key,
    tenant => (set_flag_override.tenant)::uuid,
    metadata => jsonb_build_object('key', set_flag_override.key, 'variant', set_flag_override.variant, 'organizationId', set_flag_override.tenant::text, 'userId', set_flag_override.member, 'context', set_flag_override.context, 'contextKey', set_flag_override.context_key)
  );
    return true;
  end if;
  insert into "better_supabase"."flag_overrides" ("flag_key", "organization_id", "user_id", "context", "context_key", "variant")
  values (set_flag_override.key, set_flag_override.tenant, set_flag_override.member, set_flag_override.context, set_flag_override.context_key, set_flag_override.variant)
  on conflict on constraint flag_overrides_key do update set "variant" = excluded."variant";
  perform "better_supabase".emit_event('flag.override_changed', jsonb_build_object('key', set_flag_override.key, 'variant', set_flag_override.variant, 'organizationId', set_flag_override.tenant::text, 'userId', set_flag_override.member, 'context', set_flag_override.context, 'contextKey', set_flag_override.context_key), 'flags/' || set_flag_override.key, (set_flag_override.tenant)::text, null, 'better-supabase/flags');
  perform better_supabase.audit_event(
    event_type => 'flag.override_changed',
    category => 'configuration',
    target_type => 'flag',
    record_id => set_flag_override.key,
    tenant => (set_flag_override.tenant)::uuid,
    metadata => jsonb_build_object('key', set_flag_override.key, 'variant', set_flag_override.variant, 'organizationId', set_flag_override.tenant::text, 'userId', set_flag_override.member, 'context', set_flag_override.context, 'contextKey', set_flag_override.context_key)
  );
  return true;
end;
$function$;
