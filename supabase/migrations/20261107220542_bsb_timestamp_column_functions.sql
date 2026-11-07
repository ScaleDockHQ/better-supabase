SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."calendar_events"
  DROP CONSTRAINT "calendar_events_calendar_id_uid_original_start_key";

DROP FUNCTION "api"."cancel_calendar_occurrence"(uuid, timestamp WITH time zone);

DROP FUNCTION "api"."issue_pass"(uuid, text, uuid, text, text, text, text, uuid, uuid, integer, timestamp WITH time zone, timestamp WITH time zone);

DROP FUNCTION "api"."record_consent"(text, text, text, text, text, uuid, timestamp WITH time zone, jsonb, jsonb);

DROP FUNCTION "api"."reschedule_inbox_message"(uuid, timestamp WITH time zone);

DROP FUNCTION "api"."schedule_inbox_message"(uuid, jsonb, timestamp WITH time zone);

DROP FUNCTION "api"."set_conversation_status"(uuid, text, timestamp WITH time zone);

DROP FUNCTION "api"."set_price"(uuid, text, text, text, uuid, timestamp WITH time zone, timestamp WITH time zone);

DROP FUNCTION "better_supabase"."cancel_calendar_occurrence"(uuid, timestamp WITH time zone);

DROP FUNCTION "better_supabase"."issue_pass"(uuid, text, uuid, text, text, text, text, uuid, uuid, integer, timestamp WITH time zone, timestamp WITH time zone);

DROP FUNCTION "better_supabase"."list_schedules"(text, text);

DROP FUNCTION "better_supabase"."record_consent"(text, text, text, text, text, uuid, timestamp WITH time zone, jsonb, jsonb);

DROP FUNCTION "better_supabase"."reschedule_inbox_message"(uuid, timestamp WITH time zone);

DROP FUNCTION "better_supabase"."schedule_inbox_message"(uuid, jsonb, timestamp WITH time zone);

DROP FUNCTION "better_supabase"."set_conversation_status"(uuid, text, timestamp WITH time zone);

DROP FUNCTION "better_supabase"."set_price"(uuid, text, text, text, uuid, timestamp WITH time zone, timestamp WITH time zone);

CREATE OR REPLACE FUNCTION api.cancel_calendar_occurrence (
  event_id           uuid,
  original_starts_at timestamp with time zone
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."cancel_calendar_occurrence"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.issue_pass (
  tenant       uuid,
  kind         text                     DEFAULT 'ticket'::text,
  holder_user  uuid                     DEFAULT NULL::uuid,
  holder_name  text                     DEFAULT NULL::text,
  holder_email text                     DEFAULT NULL::text,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  booking_id   uuid                     DEFAULT NULL::uuid,
  resource_id  uuid                     DEFAULT NULL::uuid,
  uses_allowed integer                  DEFAULT NULL::integer,
  starts_at    timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  expires_at   timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."issue_pass"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12) $function$;

CREATE OR REPLACE FUNCTION api.record_consent (
  subject_type        text,
  subject_id          text,
  purpose_key         text,
  status              text,
  given_by            text                     DEFAULT 'self'::text,
  given_by_contact_id uuid                     DEFAULT NULL::uuid,
  expires_at          timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  scope               jsonb                    DEFAULT '{}'::jsonb,
  evidence            jsonb                    DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_consent"($1, $2, $3, $4, $5, $6, $7, $8, $9) $function$;

CREATE OR REPLACE FUNCTION api.reschedule_inbox_message (
  scheduled    uuid,
  scheduled_at timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."reschedule_inbox_message"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.schedule_inbox_message (
  conversation uuid,
  input        jsonb,
  scheduled_at timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."schedule_inbox_message"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.set_conversation_status (
  conversation      uuid,
  status            text,
  snooze_expires_at timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_conversation_status"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.set_price (
  variant    uuid,
  currency   text,
  amount     text,
  compare_at text,
  price_list uuid,
  starts_at  timestamp with time zone,
  expires_at timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_price"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_entry_guard()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  if tg_op = 'DELETE' and current_setting('better_supabase.purge_tenant', true) = to_jsonb(old) ->> tg_argv[0] then
    if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and exists (
      select 1 from "better_supabase"."organization_deletions" x
      where x."organization_id"::text = to_jsonb(old) ->> tg_argv[0]
        and x."cancelled_at" is null and x."purged_at" is null and x."purge_at" <= now()
    ) then
      return old;
    end if;
  end if;
  if tg_op = 'UPDATE' and old."status" = 'draft' then
    return new;
  end if;
  if tg_op = 'DELETE' and old."status" = 'draft' then
    return old;
  end if;
  if tg_op = 'UPDATE' and old."status" = 'posted' and new."status" = 'reversed'
    and (to_jsonb(new) - 'status' - 'updated_at')
      = (to_jsonb(old) - 'status' - 'updated_at') then
    return new;
  end if;
  raise exception 'a posted entry can''t be changed or deleted; reverse it' using errcode = '55000', hint = 'ACCOUNTING_ENTRY_POSTED';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_entry_line_guard()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_entry uuid := case when tg_op = 'DELETE' then old."entry_id" else new."entry_id" end;
begin
  if tg_op = 'DELETE' and current_setting('better_supabase.purge_tenant', true) = to_jsonb(old) ->> tg_argv[0] then
    if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and exists (
      select 1 from "better_supabase"."organization_deletions" x
      where x."organization_id"::text = to_jsonb(old) ->> tg_argv[0]
        and x."cancelled_at" is null and x."purged_at" is null and x."purge_at" <= now()
    ) then
      return old;
    end if;
  end if;
  if exists (select 1 from "better_supabase"."accounting_entries" y where y."id" = v_entry and y."status" <> 'draft')
    or (tg_op = 'UPDATE' and exists (select 1 from "better_supabase"."accounting_entries" y where y."id" = old."entry_id" and y."status" <> 'draft')) then
    raise exception 'the lines of a posted entry can''t change; reverse it' using errcode = '55000', hint = 'ACCOUNTING_ENTRY_POSTED';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.advance_workflow_schedule (
  schedule uuid,
  fired    timestamp with time zone,
  next_run timestamp with time zone
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  update "better_supabase"."workflow_schedules" x set "last_run_at" = fired, "next_run_at" = next_run, "lock_expires_at" = null
  where x."id" = schedule and x."next_run_at" = fired;
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.book_with_credit (
  pass_id   uuid,
  service   uuid,
  resource  uuid,
  starts_at timestamp with time zone,
  customer  jsonb                    DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_pass "better_supabase"."passes"%rowtype;
  v_tenant uuid;
  v_booking jsonb;
  v_entry uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_pass from "better_supabase"."passes" x where x."id" = book_with_credit.pass_id for update;
  if not found or not (coalesce(v_pass."holder_user_id" = auth.uid(), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_pass."tenant_id", 'passes.manage'), false))) then
    raise exception 'pass not found' using errcode = 'P0002', hint = 'PASS_NOT_FOUND';
  end if;
  if v_pass."status" <> 'active' then
    raise exception 'the pass is revoked' using errcode = '55000', hint = 'PASS_REVOKED';
  end if;
  if v_pass."uses_allowed" is null or v_pass."booking_id" is not null then
    raise exception 'only a pass with a number of uses and no booking of its own pays for bookings' using errcode = '22023', hint = 'PASS_NOT_CREDITS';
  end if;
  if v_pass."resource_id" is not null and v_pass."resource_id" <> book_with_credit.resource then
    raise exception 'the pass is for another resource' using errcode = '22023', hint = 'PASS_WRONG_RESOURCE';
  end if;
  if book_with_credit.starts_at < v_pass."starts_at" or (v_pass."expires_at" is not null and book_with_credit.starts_at >= v_pass."expires_at") then
    raise exception 'the pass is not valid when the class starts' using errcode = '22023', hint = 'PASS_NOT_VALID';
  end if;
  if v_pass."uses" >= v_pass."uses_allowed" then
    raise exception 'the pass has no credits left' using errcode = '55000', hint = 'PASS_CREDITS_USED_UP';
  end if;
  select sv."tenant_id" into v_tenant from "better_supabase"."booking_services" sv where sv."id" = book_with_credit.service;
  if v_tenant is distinct from v_pass."tenant_id" then
    raise exception 'the service does not exist in the pass''s organization' using errcode = 'P0002', hint = 'PASS_BOOKING_NOT_FOUND';
  end if;
  v_booking := "better_supabase"."hold_booking"(book_with_credit.service, book_with_credit.resource, book_with_credit.starts_at,
    coalesce(book_with_credit.customer, '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object('userId', v_pass."holder_user_id", 'name', v_pass."holder_name", 'email', v_pass."holder_email")), true);
  v_entry := "better_supabase"."ledger_post"(v_pass."tenant_id", 'pass.credit_used',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_pass."tenant_id", 'pass_credits', 'pass:' || v_pass."id"::text, 'Pass credits', 'credit', 0::smallint,
    'passes', v_pass."id"::text, v_pass."holder_user_id", true, 'passes.read', 'passes', jsonb_build_object('passId', v_pass."id")), 'amount', -1),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_pass."tenant_id", 'pass_credits_pool', 'pass-credits:pool', 'Pass credits pool', 'credit', 0::smallint,
    null, null, null, true, 'passes.read', 'passes', null), 'amount', 1)),
      'bookings', (v_booking ->> 'id')::uuid::text, null, 'pass-credit:' || (v_booking ->> 'id')::uuid::text || ':booking', clock_timestamp(),
      jsonb_build_object('passId', v_pass."id", 'reason', 'booking'));
  update "better_supabase"."passes" x set "uses" = x."uses" + 1, "updated_at" = now()
  where x."id" = v_pass."id";
  perform "better_supabase".emit_event('pass.credit_used', jsonb_build_object('organizationId', v_pass."tenant_id"::text, 'id', v_pass."id", 'entryId', v_entry, 'bookingId', (v_booking ->> 'id')::uuid), 'passes/' || v_pass."id"::text, (v_pass."tenant_id")::text, null, 'better-supabase/passes');
  perform better_supabase.audit_event(
    event_type => 'pass.credit_used',
    category => 'access',
    target_type => 'pass',
    record_id => v_pass."id"::text,
    summary => 'booked with a credit of pass',
    tenant => (v_pass."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_pass."tenant_id"::text, 'id', v_pass."id", 'entryId', v_entry, 'bookingId', (v_booking ->> 'id')::uuid)
  );
  return (v_booking - 'accessToken') || jsonb_build_object('passId', v_pass."id", 'creditsLeft', v_pass."uses_allowed" - v_pass."uses" - 1);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_transition_change_request()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_op jsonb;
  v_flag text;
  v_flags text[];
  v_until timestamptz;
  v_paused boolean;
  v_version uuid;
  v_number integer;
  v_graph jsonb;
begin
  if tg_op = 'INSERT' then
    select v."id", v."version" into v_version, v_number
    from "better_supabase"."workflow_versions" v
    join "better_supabase"."workflow_definitions" d on d."id" = v."definition_id"
    where d."slug" = 'change-requests'
      and v."status"::text = 'published'
      and (d."tenant_id"::text = new."organization_id"::text or d."scope"::text = 'system')
    order by d."tenant_id" is null, v."version" desc
    limit 1;
    if v_version is null then
      raise exception 'the machine''s workflow has no published version' using errcode = '55000', hint = 'STATE_LIFECYCLE_UNPUBLISHED';
    end if;
    v_graph := "better_supabase"."lifecycle_graph"(v_version);
    if new."status" is null then
      new."status" := v_graph ->> 'initial';
    end if;
    if new."status" is null or not ((v_graph -> 'order') ? new."status"::text) then
      raise exception 'that status is not a stage of the machine''s workflow' using errcode = '22023', hint = 'STATE_TRANSITION_INVALID';
    end if;
    
    insert into "better_supabase"."subject_lifecycles" ("tenant_id", "subject_type", "subject_id", "version", "workflow_version_id")
    values (new."organization_id", 'change_request', new."id"::text, v_number, v_version)
    on conflict ("subject_type", "subject_id") do update set
      "version" = excluded."version",
      "workflow_version_id" = excluded."workflow_version_id",
      "updated_at" = now();
    return new;
  end if;
  if new."status" is not distinct from old."status" then
    v_op := nullif(current_setting('better_supabase.lifecycle_op', true), '')::jsonb;
    if v_op is not null and v_op ->> 'machine' = 'change_request' and v_op ->> 'id' = new."id"::text then
      case v_op ->> 'op'
        when 'pause' then
          if (v_op ->> 'until') is not null and (v_op ->> 'until')::timestamptz <= now() then
            raise exception 'a pause must end in the future' using errcode = '22023', hint = 'STATE_PAUSE_INVALID';
          end if;
          insert into "better_supabase"."subject_lifecycles" ("tenant_id", "subject_type", "subject_id", "version", "paused_at", "pause_expires_at", "pause_reason", "paused_by_user_id")
          values (new."organization_id", 'change_request', new."id"::text, 1, now(), (v_op ->> 'until')::timestamptz, nullif(v_op ->> 'reason', ''), auth.uid())
          on conflict ("subject_type", "subject_id") do update set
            "paused_at" = excluded."paused_at",
            "pause_expires_at" = excluded."pause_expires_at",
            "pause_reason" = excluded."pause_reason",
            "paused_by_user_id" = excluded."paused_by_user_id",
            "updated_at" = now();
          perform set_config('better_supabase.lifecycle_changed', '1', true);
          perform "better_supabase".emit_event('status.paused', jsonb_build_object('organizationId', new."organization_id"::text, 'subjectType', 'change_request', 'subjectId', new."id"::text, 'until', v_op ->> 'until', 'reason', nullif(v_op ->> 'reason', '')), 'statuses/change_request/' || new."id"::text, (new."organization_id"::text)::text, null, 'better-supabase/state-machine');
        when 'resume' then
          update "better_supabase"."subject_lifecycles" set "paused_at" = null, "pause_expires_at" = null, "pause_reason" = null, "paused_by_user_id" = null, "updated_at" = now()
          where "subject_type" = 'change_request' and "subject_id" = new."id"::text and "paused_at" is not null;
          if found then
            perform set_config('better_supabase.lifecycle_changed', '1', true);
            perform "better_supabase".emit_event('status.resumed', jsonb_build_object('organizationId', new."organization_id"::text, 'subjectType', 'change_request', 'subjectId', new."id"::text), 'statuses/change_request/' || new."id"::text, (new."organization_id"::text)::text, null, 'better-supabase/state-machine');
          end if;
        when 'flag' then
          v_flag := v_op ->> 'flag';
          if v_flag is null or not (v_flag = any ('{}'::text[])) then
            raise exception 'the machine has no such flag' using errcode = '22023', hint = 'STATE_FLAG_UNKNOWN';
          end if;
          select coalesce("flags", '{}') into v_flags from "better_supabase"."subject_lifecycles" where "subject_type" = 'change_request' and "subject_id" = new."id"::text for update;
          v_flags := coalesce(v_flags, '{}');
          if coalesce((v_op ->> 'enabled')::boolean, false) is distinct from (v_flag = any (v_flags)) then
            v_flags := case when coalesce((v_op ->> 'enabled')::boolean, false)
              then v_flags || v_flag else array_remove(v_flags, v_flag) end;
            insert into "better_supabase"."subject_lifecycles" ("tenant_id", "subject_type", "subject_id", "version", "flags")
            values (new."organization_id", 'change_request', new."id"::text, 1, v_flags)
            on conflict ("subject_type", "subject_id") do update set
              "flags" = excluded."flags",
              "updated_at" = now();
            perform set_config('better_supabase.lifecycle_changed', '1', true);
            perform "better_supabase".emit_event('status.flagged', jsonb_build_object('organizationId', new."organization_id"::text, 'subjectType', 'change_request', 'subjectId', new."id"::text, 'flag', v_flag, 'enabled', coalesce((v_op ->> 'enabled')::boolean, false)), 'statuses/change_request/' || new."id"::text, (new."organization_id"::text)::text, null, 'better-supabase/state-machine');
          end if;
        else
          raise exception 'unknown lifecycle change' using errcode = '22023', hint = 'STATE_LIFECYCLE_INVALID';
      end case;
    end if;
    return new;
  end if;
  select "workflow_version_id" into v_version from "better_supabase"."subject_lifecycles"
  where "subject_type" = 'change_request' and "subject_id" = new."id"::text;
  if v_version is null then
    select v."id", v."version" into v_version, v_number
    from "better_supabase"."workflow_versions" v
    join "better_supabase"."workflow_definitions" d on d."id" = v."definition_id"
    where d."slug" = 'change-requests'
      and v."status"::text = 'published'
      and (d."tenant_id"::text = new."organization_id"::text or d."scope"::text = 'system')
    order by d."tenant_id" is null, v."version" desc
    limit 1;
    if v_version is null then
      raise exception 'the machine''s workflow has no published version' using errcode = '55000', hint = 'STATE_LIFECYCLE_UNPUBLISHED';
    end if;
    insert into "better_supabase"."subject_lifecycles" ("tenant_id", "subject_type", "subject_id", "version", "workflow_version_id")
    values (new."organization_id", 'change_request', new."id"::text, v_number, v_version)
    on conflict ("subject_type", "subject_id") do update set
      "version" = excluded."version",
      "workflow_version_id" = excluded."workflow_version_id",
      "updated_at" = now();
  end if;
  v_graph := "better_supabase"."lifecycle_graph"(v_version);
  if not coalesce((v_graph -> 'transitions' -> old."status"::text) ? new."status"::text, false) then
    raise exception 'that status change is not allowed' using errcode = '22023', hint = 'STATE_TRANSITION_INVALID';
  end if;
  select "pause_expires_at", "paused_at" is not null into v_until, v_paused from "better_supabase"."subject_lifecycles" where "subject_type" = 'change_request' and "subject_id" = new."id"::text;
  if coalesce(v_paused, false) then
    if v_until is null or v_until > now() then
      raise exception 'the record is paused; resume it first' using errcode = '55000', hint = 'STATE_PAUSED';
    end if;
    update "better_supabase"."subject_lifecycles" set "paused_at" = null, "pause_expires_at" = null, "pause_reason" = null, "paused_by_user_id" = null, "updated_at" = now()
    where "subject_type" = 'change_request' and "subject_id" = new."id"::text;
    perform "better_supabase".emit_event('status.resumed', jsonb_build_object('organizationId', new."organization_id"::text, 'subjectType', 'change_request', 'subjectId', new."id"::text), 'statuses/change_request/' || new."id"::text, (new."organization_id"::text)::text, null, 'better-supabase/state-machine');
  end if;
  insert into "better_supabase"."status_history" ("tenant_id", "subject_type", "subject_id", "from_status", "to_status", "actor_user_id", "reason", "actor_name", "actor_email", "ip_address", "user_agent")
        values (new."organization_id", 'change_request', new."id"::text, old."status"::text, new."status"::text, coalesce(auth.uid(), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'id', '')::uuid), nullif(current_setting('better_supabase.transition_reason', true), ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'name', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'email', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'ip', '')::inet, nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'userAgent', ''));
  
  perform "better_supabase".emit_event('status.changed', jsonb_build_object('organizationId', new."organization_id"::text, 'subjectType', 'change_request', 'subjectId', new."id"::text, 'from', old."status"::text, 'to', new."status"::text, 'reason', nullif(current_setting('better_supabase.transition_reason', true), '')), 'statuses/change_request/' || new."id"::text, (new."organization_id"::text)::text, null, 'better-supabase/state-machine');
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.calendar_busy_blocks (
  tenant      uuid,
  user_ids    uuid[],
  range_start timestamp with time zone,
  range_end   timestamp with time zone
)
  RETURNS TABLE (
    user_id   uuid,
    kind      text,
    starts_at timestamp with time zone,
    ends_at   timestamp with time zone,
    event_id  uuid,
    declines  boolean
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  return query
  with sources as (
    select m.u as user_id, e."id" as event_id
    from unnest(calendar_busy_blocks.user_ids) m (u)
    join "better_supabase"."calendars" k on k."tenant_id" = calendar_busy_blocks.tenant and k."owner_type" = 'user' and k."owner_id" = m.u::text
    join "better_supabase"."calendar_events" e on e."calendar_id" = k."id"
    union
    select a."user_id" as user_id, e."id" as event_id
    from "better_supabase"."calendar_attendees" a
    join "better_supabase"."calendar_events" e on (e."id" = a."event_id" or e."recurrence_id" = a."event_id")
    where a."tenant_id" = calendar_busy_blocks.tenant
      and a."user_id" = any (calendar_busy_blocks.user_ids)
      and a."response" <> 'declined'
      and not exists (
        select 1 from "better_supabase"."calendar_attendees" d
        where d."event_id" = e."id" and d."user_id" = a."user_id" and d."response" = 'declined'
      )
  ),
  candidates as (
    select distinct s.user_id, e."id" as event_id, e."kind" as kind, e."starts_at" as starts_at, e."ends_at" as ends_at,
      e."tz" as tz, e."rrule" as rrule, e."recurrence_id" as recurrence, e."exdates" as exdates, (e."kind" <> 'event' and e."auto_decline") as declines
    from sources s
    join "better_supabase"."calendar_events" e on e."id" = s.event_id
    where e."tenant_id" = calendar_busy_blocks.tenant
      and e."status" <> 'cancelled'
      and e."transparency" <> 'transparent'
      and e."starts_at" < calendar_busy_blocks.range_end
  )
  select c.user_id, c.kind, c.starts_at, c.ends_at, c.event_id, c.declines
  from candidates c
  where c.rrule is null and c.starts_at < calendar_busy_blocks.range_end and c.ends_at > calendar_busy_blocks.range_start
  union all
  select c.user_id, c.kind, s.at, s.at + (c.ends_at - c.starts_at), c.event_id, c.declines
  from candidates c
  cross join lateral "better_supabase"."calendar_rule_starts"(c.starts_at, c.tz, c.rrule, calendar_busy_blocks.range_start - (c.ends_at - c.starts_at), calendar_busy_blocks.range_end) s (at)
  where c.rrule is not null and c.recurrence is null
    and c.starts_at < calendar_busy_blocks.range_end
    and s.at + (c.ends_at - c.starts_at) > calendar_busy_blocks.range_start
    and not (s.at = any (c.exdates))
    and not exists (
      select 1 from "better_supabase"."calendar_events" o
      where o."recurrence_id" = c.event_id and o."original_starts_at" = s.at
    );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.calendar_feed (
  token text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_link uuid;
  v_subject text;
  v_tenant uuid;
  v_calendar uuid;
  v_creator uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if calendar_feed.token is null or length(calendar_feed.token) < 32 then
    return null;
  end if;
  select l."id", l."subject_id", l."tenant_id", l."created_by" into v_link, v_subject, v_tenant, v_creator
  from "better_supabase"."share_links" l
  where l."token_hash" = encode(extensions.digest(convert_to(calendar_feed.token, 'utf8'), 'sha256'), 'hex')
    and l."subject_type" = 'calendar'
    and l."revoked_at" is null
    and (l."expires_at" is null or l."expires_at" > now())
    and (l."max_uses" is null or l."use_count" < l."max_uses")
    and l."password_hash" is null
  for update;
  if v_subject is null or v_subject !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;
  v_calendar := v_subject::uuid;
  if v_creator is null or not coalesce(better_supabase.can_user(v_creator, 'tenant', v_tenant, 'calendar.read'), false) then
    return null;
  end if;
  update "better_supabase"."share_links" set "use_count" = "use_count" + 1, "last_used_at" = now() where "id" = v_link;
  return (
    select jsonb_build_object(
      'calendar', jsonb_build_object('id', k."id", 'name', k."name", 'tz', k."tz", 'color', k."color"),
      'organization', jsonb_build_object('id', v_tenant, 'name', (select g."name" from "public"."organizations" g where g."id" = v_tenant)),
      'createdBy', v_creator,
      'events', coalesce((
      select jsonb_agg(f.item order by f.starts)
      from (
        select (jsonb_build_object('id', e."id", 'calendarId', e."calendar_id", 'uid', e."uid", 'title', e."title", 'startsAt', e."starts_at", 'endsAt', e."ends_at", 'allDay', e."all_day", 'tz', e."tz", 'status', e."status", 'rrule', e."rrule", 'exdates', to_jsonb(e."exdates"), 'recurrenceId', e."recurrence_id", 'originalStart', e."original_starts_at", 'description', e."description", 'location', e."location", 'color', e."color", 'subjectType', e."subject_type", 'subjectId', e."subject_id") || jsonb_build_object('updatedAt', e."updated_at", 'kind', e."kind", 'transparency', e."transparency", 'autoDecline', e."auto_decline", 'attendees', coalesce((select jsonb_agg(jsonb_build_object('email', a."email", 'name', a."name", 'userId', a."user_id", 'role', a."role", 'response', a."response") order by a."email") from "better_supabase"."calendar_attendees" a where a."event_id" = e."id"), '[]'::jsonb), 'alarms', coalesce((select jsonb_agg(jsonb_build_object('id', l."id", 'method', l."method", 'offsetMinutes', l."offset_minutes", 'related', l."related_to", 'at', l."trigger_at", 'repeat', l."repeat_count", 'repeatMinutes', l."repeat_minutes", 'description', l."description", 'summary', l."summary") order by l."offset_minutes" nulls last, l."trigger_at", l."id") from "better_supabase"."calendar_event_alarms" l where l."event_id" = e."id" and (l."user_id" is null or l."user_id" = (select auth.uid()))), '[]'::jsonb)) - 'alarms') || jsonb_build_object('reminders', coalesce((select jsonb_agg(jsonb_build_object('id', l."id", 'method', l."method", 'offsetMinutes', l."offset_minutes", 'related', l."related_to", 'at', l."trigger_at", 'repeat', l."repeat_count", 'repeatMinutes', l."repeat_minutes", 'description', l."description", 'summary', l."summary") order by l."offset_minutes" nulls last, l."trigger_at", l."id") from "better_supabase"."calendar_event_alarms" l where l."event_id" = e."id" and (l."user_id" is null or l."user_id" = v_creator)), '[]'::jsonb) || coalesce((select jsonb_agg(jsonb_build_object('method', r."method", 'offsetMinutes', r."offset_minutes") order by r."offset_minutes") from "better_supabase"."reminders" r where r."subject_type" = 'calendar_event' and r."subject_id" = e."id"::text and r."user_id" = v_creator), '[]'::jsonb)) as item, e."starts_at" as starts
        from "better_supabase"."calendar_events" e
        join "better_supabase"."calendars" k on k."id" = e."calendar_id"
        where k."id" = v_calendar
          and (e."rrule" is not null or e."ends_at" > now() - interval '366 days')
          and true
        order by e."starts_at"
        limit 5000
      ) f
    ), '[]'::jsonb)
    )
    from "better_supabase"."calendars" k where k."id" = v_calendar and k."tenant_id" = v_tenant
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.cancel_calendar_occurrence (
  event_id           uuid,
  original_starts_at timestamp with time zone
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_id uuid := cancel_calendar_occurrence.event_id;
  v_tenant uuid;
  v_calendar uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "calendar_id" into v_tenant, v_calendar from "better_supabase"."calendar_events"
    where "id" = v_id and "rrule" is not null for update;
  if not found then
    raise exception 'recurring event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  update "better_supabase"."calendar_events" set "exdates" = (
      select array_agg(distinct d order by d) from unnest(array_append("exdates", cancel_calendar_occurrence.original_starts_at)) d
    ), "updated_at" = now()
  where "id" = v_id;
  delete from "better_supabase"."calendar_events" where "recurrence_id" = v_id and "original_starts_at" = cancel_calendar_occurrence.original_starts_at;
  perform "better_supabase".emit_event('calendar_event.updated', jsonb_build_object('organizationId', v_tenant, 'id', v_id, 'calendarId', v_calendar), 'calendar-events/' || v_id::text, (v_tenant)::text, null, 'better-supabase/calendar');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.cancel_organization_deletion (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."organization_deletions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."organization_deletions" x
  where x."organization_id" = cancel_organization_deletion.tenant and x."cancelled_at" is null and x."purged_at" is null
  for update;
  if v_row."organization_id" is null then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."requested_by" = auth.uid(), false) or coalesce(better_supabase.member_can_while_deleting(auth.uid(), cancel_organization_deletion.tenant, 'organization.delete'), false)) then
    raise exception 'You may not cancel this deletion' using errcode = '42501', hint = 'ORGANIZATION_DELETION_FORBIDDEN';
  end if;
  update "better_supabase"."organization_deletions" x set "cancelled_at" = now()
  where x."organization_id" = v_row."organization_id"
  returning * into v_row;
  
  perform "better_supabase".emit_event('organization.deletion_cancelled', jsonb_build_object('organizationId', v_row."organization_id"::text, 'userId', auth.uid(), 'purgeAfter', v_row."purge_at"), 'organizations/' || v_row."organization_id"::text, (v_row."organization_id")::text, null, 'better-supabase/data-lifecycle');
  perform better_supabase.audit_event(
    event_type => 'organization.deletion_cancelled',
    category => 'data',
    target_type => 'organization',
    record_id => v_row."organization_id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'userId', auth.uid(), 'purgeAfter', v_row."purge_at")
  );
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.care_decision_context (
  tenant       uuid,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (care_decision_context.tenant is not null and coalesce(better_supabase.can('tenant', care_decision_context.tenant, 'clinical_decision_support.read'), false))) then
    raise exception 'not allowed to read the decision context' using errcode = '42501', hint = 'CARE_ALERT_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case care_decision_context.subject_type
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (care_decision_context.subject_id)::uuid and s."organization_id"::text = care_decision_context.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (care_decision_context.subject_id)::uuid and s."organization_id"::text = care_decision_context.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (care_decision_context.subject_id)::uuid and s."organization_id"::text = care_decision_context.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (care_decision_context.subject_id)::uuid and s."organization_id"::text = care_decision_context.tenant::text)
      else false
    end and "better_supabase"."can_subject"(care_decision_context.subject_type, care_decision_context.subject_id, 'read'))) then
    raise exception 'the context needs a record of the organization' using errcode = '22023', hint = 'CARE_ALERT_SUBJECT_INVALID';
  end if;
  return jsonb_build_object(
    'organizationId', care_decision_context.tenant,
    'subjectType', care_decision_context.subject_type,
    'subjectId', care_decision_context.subject_id,
    'medications', coalesce((select jsonb_agg(jsonb_build_object('orderId', o."id", 'medicationId', o."medication_id", 'name', mx."name", 'codeSystem', mx."code_system", 'code', mx."code", 'dose', o."dose", 'doseUnit', o."dose_unit", 'asNeeded', o."as_needed", 'maxPerDay', o."max_per_day", 'schedule', o."schedule", 'startsOn', o."starts_on", 'endsOn', o."ends_on") order by mx."name", o."id")
      from "better_supabase"."medication_orders" o join "better_supabase"."medications" mx on mx."id" = o."medication_id" and mx."tenant_id" = o."tenant_id"
    where o."tenant_id" = care_decision_context.tenant and o."subject_type" = care_decision_context.subject_type and o."subject_id" = care_decision_context.subject_id
      and o."status" = 'active' and o."starts_on" <= (now() at time zone 'UTC')::date and (o."ends_on" is null or o."ends_on" >= (now() at time zone 'UTC')::date)), '[]'::jsonb),
    'observations', coalesce((select jsonb_agg(jsonb_build_object('key', q."key", 'code', q."code", 'codeSystem', q."code_system", 'unit', q."unit", 'valueNumber', q."value_number", 'valueText', q."value_text", 'valueCode', q."value_code", 'flag', q."flag", 'observedAt', q."observed_at") order by q."key")
      from (select distinct on (od."id") od."key", od."code", od."code_system", od."unit", ox."value_number", ox."value_text", ox."value_code", ox."flag", ox."observed_at"
        from "better_supabase"."observations" ox join "better_supabase"."observation_definitions" od on od."id" = ox."definition_id"
        where ox."tenant_id" = care_decision_context.tenant and ox."subject_type" = care_decision_context.subject_type and ox."subject_id" = care_decision_context.subject_id and ox."status" <> 'entered_in_error'
        order by od."id", ox."observed_at" desc) q), '[]'::jsonb),
    'consents', coalesce((select jsonb_agg(jsonb_build_object('purpose', pu."key", 'status', cx."status", 'scope', cx."scope", 'grantedAt', cx."granted_at", 'validUntil', cx."expires_at") order by pu."key")
      from "better_supabase"."consents" cx join "better_supabase"."consent_purposes" pu on pu."id" = cx."purpose_id"
      where cx."tenant_id" = care_decision_context.tenant and cx."subject_type" = care_decision_context.subject_type and cx."subject_id" = care_decision_context.subject_id and cx."status" = 'granted'), '[]'::jsonb),
    'carePlan', (select jsonb_build_object('id', px."id", 'title', px."title", 'version', px."version", 'reviewOn', px."review_on")
      from "better_supabase"."care_plans" px
      where px."tenant_id" = care_decision_context.tenant and px."subject_type" = care_decision_context.subject_type and px."subject_id" = care_decision_context.subject_id and px."status" = 'active'
      order by px."version" desc limit 1));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.case_blockers_of (
  target better_supabase.cases
)
  RETURNS text[]
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_kind "better_supabase"."case_kinds";
  v_blockers text[] := '{}';
  v_policy jsonb;
begin
  select * into v_kind from "better_supabase"."case_kinds" y where y."id" = case_blockers_of.target."kind_id";
  if v_kind."requires_root_cause" and coalesce(trim(case_blockers_of.target."root_cause"), '') = '' then
    v_blockers := v_blockers || 'CASE_ROOT_CAUSE_REQUIRED'::text;
  end if;
  if v_kind."requires_actions" and not exists (
    select 1 from "better_supabase"."case_actions" x where x."case_id" = case_blockers_of.target."id" and x."required"
  ) then
    v_blockers := v_blockers || 'CASE_ACTIONS_REQUIRED'::text;
  end if;
  if exists (
    select 1 from "better_supabase"."case_actions" x
    join "better_supabase"."work_items" i on i."id" = x."task_id"
    where x."case_id" = case_blockers_of.target."id" and x."required"
      and i."state" not in ('completed', 'canceled')
  ) then
    v_blockers := v_blockers || 'CASE_ACTIONS_OPEN'::text;
  end if;
  if v_kind."requires_effectiveness" and case_blockers_of.target."effective" is not true then
    v_blockers := v_blockers || 'CASE_EFFECTIVENESS_REQUIRED'::text;
  end if;
  if v_kind."requires_revisions" and exists (
    select 1 from "better_supabase"."relations" r
    join "better_supabase"."drive_nodes" n on n."id"::text = r."target_id"
    where r."kind" = 'affects'
      and r."source_type" = 'case'
      and r."source_id" = case_blockers_of.target."id"::text
      and r."target_type" = 'drive_node'
      and (n."effective_at" is null or n."effective_at" <= case_blockers_of.target."created_at")
  ) then
    v_blockers := v_blockers || 'CASE_DOCUMENTS_NOT_REVISED'::text;
  end if;
  v_policy := "better_supabase"."approval_effective_policy"(case_blockers_of.target."tenant_id", 'case', 'close',
    jsonb_build_object('caseId', case_blockers_of.target."id", 'kind', v_kind."key", 'severity', case_blockers_of.target."severity"));
  if (coalesce(v_policy ->> 'mode', 'authorize') = 'confirm' or jsonb_array_length(coalesce(v_policy -> 'steps', '[]'::jsonb)) > 0)
    and not exists (
      select 1 from "better_supabase"."approval_requests" r
      where r."subject_type" = 'case'
        and r."subject_id" = case_blockers_of.target."id"::text
        and r."action" = 'close'
        and r."status" = 'approved'
    ) then
    v_blockers := v_blockers || 'CASE_APPROVAL_REQUIRED'::text;
  end if;
  return v_blockers;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.change_booking (
  booking      uuid,
  to_status    text,
  reason       text,
  access_token text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_booking "better_supabase"."bookings"%rowtype;
  v_id uuid := change_booking.booking;
  v_calendar uuid;
  v_tz text;
  v_title text;
  v_event uuid;
begin
  select * into v_booking from "better_supabase"."bookings" bk where bk."id" = v_id for update;
  if not found then
    raise exception 'booking not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
  end if;
  if not (
    (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.manage'), false))
    or (change_booking.access_token is not null and v_booking."access_hash" = encode(extensions.digest(convert_to(change_booking.access_token, 'utf8'), 'sha256'), 'hex'))
    or (change_booking.access_token is null and coalesce(v_booking."customer_user_id" = auth.uid(), false) and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.create'), false)))
  ) then
    raise exception 'not allowed to change this booking' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if change_booking.to_status = 'confirmed' then
    if v_booking."status" = 'confirmed' then
      return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason");
    end if;
    if v_booking."status" <> 'hold' or v_booking."hold_expires_at" <= now() then
      raise exception 'the hold has expired or was cancelled' using errcode = '22023', hint = 'BOOKING_HOLD_EXPIRED';
    end if;
    update "better_supabase"."bookings" bk set "status" = 'confirmed', "hold_expires_at" = null, "updated_at" = now()
    where bk."id" = v_id returning * into v_booking;
    select r."calendar_id", r."tz", sv."name" into v_calendar, v_tz, v_title
  from "better_supabase"."booking_resources" r join "better_supabase"."booking_services" sv on sv."id" = v_booking."service_id"
  where r."id" = v_booking."resource_id";
  if v_calendar is not null then
    insert into "better_supabase"."calendar_events" ("tenant_id", "calendar_id", "uid", "title", "starts_at", "ends_at", "tz", "status", "subject_type", "subject_id")
    values (v_booking."tenant_id", v_calendar, 'booking-' || v_booking."id"::text, coalesce(v_booking."customer_name", v_title), lower(v_booking."during"), upper(v_booking."during"), v_tz, 'confirmed', 'booking', v_booking."id"::text)
    on conflict ("calendar_id", "uid", "original_starts_at") do update set "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at"
    returning "id" into v_event;
    update "better_supabase"."bookings" set "calendar_event_id" = v_event where "id" = v_booking."id";
  end if;
    delete from "better_supabase"."reminders" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  delete from "better_supabase"."recurrence_rules" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, lower(v_booking."during"), r."tz", 'FREQ=DAILY;COUNT=1'
  from "better_supabase"."booking_resources" r where r."id" = v_booking."resource_id";
  insert into "better_supabase"."reminders" ("tenant_id", "subject_type", "subject_id", "user_id", "offset_minutes")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, v_booking."customer_user_id", o
  from "better_supabase"."booking_services" sv, unnest(sv."reminder_offsets") o
  where sv."id" = v_booking."service_id";
    perform "better_supabase".emit_event('booking.confirmed', jsonb_build_object('organizationId', v_booking."tenant_id", 'id', v_id, 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id"), 'bookings/' || v_id::text, (v_booking."tenant_id")::text, null, 'better-supabase/bookings');
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_confirm"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  elsif change_booking.to_status = 'cancelled' then
    if v_booking."status" = 'cancelled' then
      return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason");
    end if;
    update "better_supabase"."bookings" bk set "status" = 'cancelled', "hold_expires_at" = null, "cancelled_at" = now(), "cancel_reason" = change_booking.reason, "updated_at" = now()
    where bk."id" = v_id returning * into v_booking;
    if v_booking."calendar_event_id" is not null then
    delete from "better_supabase"."calendar_events" where "id" = v_booking."calendar_event_id";
  end if;
    delete from "better_supabase"."reminders" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  delete from "better_supabase"."recurrence_rules" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
    perform "better_supabase".emit_event('booking.cancelled', jsonb_build_object('organizationId', v_booking."tenant_id", 'id', v_id, 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id"), 'bookings/' || v_id::text, (v_booking."tenant_id")::text, null, 'better-supabase/bookings');
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_cancel"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  else
    raise exception 'change a booking to confirmed or cancelled' using errcode = '22023', hint = 'BOOKING_STATUS_INVALID';
  end if;
  return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.check_in_pass (
  pass_id     uuid,
  nonce       text DEFAULT NULL::text,
  method      text DEFAULT 'qr'::text,
  gate        text DEFAULT NULL::text,
  resource_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_pass "better_supabase"."passes"%rowtype;
  v_row "better_supabase"."pass_check_ins"%rowtype;
  v_reason text;
  v_resource uuid;
  v_capacity integer;
  v_booking "better_supabase"."bookings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if check_in_pass.method is null or check_in_pass.method not in ('qr', 'nfc', 'manual') then
    raise exception 'method is qr, nfc or manual' using errcode = '22023', hint = 'PASS_METHOD_INVALID';
  end if;
  select * into v_pass from "better_supabase"."passes" x where x."id" = check_in_pass.pass_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_pass."tenant_id", 'passes.check_in'), false)) then
    raise exception 'pass not found' using errcode = 'P0002', hint = 'PASS_NOT_FOUND';
  end if;
  v_resource := coalesce(check_in_pass.resource_id, v_pass."resource_id");
  v_reason := case
    when check_in_pass.method <> 'manual' and check_in_pass.nonce is distinct from v_pass."nonce" then 'invalid'
    when v_pass."status" = 'revoked' then 'revoked'
    when now() < v_pass."starts_at" then 'not_yet_valid'
    when v_pass."expires_at" is not null and now() >= v_pass."expires_at" then 'expired'
    when v_pass."uses_allowed" is not null and v_pass."uses" >= v_pass."uses_allowed" then 'used_up'
    when check_in_pass.resource_id is not null and v_pass."resource_id" is not null
      and check_in_pass.resource_id <> v_pass."resource_id" then 'wrong_resource'
  end;
  if v_reason is null and v_pass."booking_id" is not null then
    select * into v_booking from "better_supabase"."bookings" bk where bk."id" = v_pass."booking_id";
    if not found or v_booking."status" = 'cancelled'
      or (v_booking."status" = 'hold' and v_booking."hold_expires_at" <= now()) then
      v_reason := 'booking_cancelled';
    elsif v_booking."status" = 'hold' then
      v_reason := 'booking_unconfirmed';
    elsif now() < lower(v_booking."during") - '1 hour'::interval
      or now() >= upper(v_booking."during") then
      v_reason := 'outside_window';
    end if;
  end if;
  if v_reason is null and v_pass."booking_id" is null and v_resource is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bsb:passes:' || v_resource::text, 0));
    select rs."capacity" into v_capacity from "better_supabase"."booking_resources" rs
      where rs."id" = v_resource and rs."tenant_id" = v_pass."tenant_id";
    if v_capacity is null then
      v_reason := 'wrong_resource';
    elsif ((select count(*) from "better_supabase"."bookings" bk
      where bk."resource_id" = v_resource and (bk."status" = 'confirmed' or (bk."status" = 'hold' and bk."hold_expires_at" > now())) and bk."during" @> now())
      + (select count(*) from "better_supabase"."pass_check_ins" y
      where y."resource_id" = v_resource and y."admitted" and y."booking_id" is null
        and y."created_at" > now() - '2 hours'::interval)) >= v_capacity then
      v_reason := 'full';
    end if;
  end if;
  insert into "better_supabase"."pass_check_ins" ("tenant_id", "pass_id", "resource_id", "booking_id", "gate", "method", "admitted", "reason", "checked_in_by")
  values (v_pass."tenant_id", v_pass."id", v_resource, v_pass."booking_id", check_in_pass.gate, check_in_pass.method, v_reason is null, v_reason, auth.uid())
  returning * into v_row;
  if v_reason is null then
    update "better_supabase"."passes" x set "uses" = x."uses" + 1, "updated_at" = now()
      where x."id" = v_pass."id"
      returning * into v_pass;
    perform "better_supabase".emit_event('pass.admitted', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."pass_id", 'checkInId', v_row."id", 'resourceId', v_row."resource_id", 'bookingId', v_row."booking_id"), 'passes/' || v_row."pass_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/passes');
  else
    perform "better_supabase".emit_event('pass.rejected', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."pass_id", 'checkInId', v_row."id", 'resourceId', v_row."resource_id", 'bookingId', v_row."booking_id", 'reason', v_row."reason"), 'passes/' || v_row."pass_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/passes');
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'passId', v_row."pass_id", 'resourceId', v_row."resource_id", 'bookingId', v_row."booking_id", 'gate', v_row."gate", 'method', v_row."method", 'admitted', v_row."admitted", 'reason', v_row."reason", 'checkedInBy', v_row."checked_in_by", 'createdAt', v_row."created_at") || jsonb_build_object('pass', jsonb_build_object('id', v_pass."id", 'organizationId', v_pass."tenant_id"::text, 'kind', v_pass."kind", 'holderUserId', v_pass."holder_user_id", 'holderName', v_pass."holder_name", 'holderEmail', v_pass."holder_email", 'subjectType', v_pass."subject_type", 'subjectId', v_pass."subject_id", 'bookingId', v_pass."booking_id", 'resourceId', v_pass."resource_id", 'usesAllowed', v_pass."uses_allowed", 'uses', v_pass."uses", 'validFrom', v_pass."starts_at", 'validUntil', v_pass."expires_at", 'status', v_pass."status", 'issuedBy', v_pass."issued_by", 'createdAt', v_pass."created_at", 'updatedAt', v_pass."updated_at", 'revokedAt', v_pass."revoked_at"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.check_rate_limits (
  hits jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  total integer;
  scopes text[] := '{}';
  keys text[] := '{}';
  maxes integer[] := '{}';
  periods interval[] := '{}';
  used integer[] := '{}';
  starts timestamptz[] := '{}';
  hit jsonb;
  rule "better_supabase"."rate_limit_rules";
  counter "better_supabase"."rate_limits";
  limit_max integer;
  limit_period interval;
  current_hits integer;
  first_blocked integer;
  longest integer := 0;
  passed boolean;
  results jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(hits) is distinct from 'array' or jsonb_array_length(hits) = 0 then
    raise exception 'check_rate_limits needs a non-empty array of hits'
      using errcode = '22023', hint = 'RATE_LIMIT_HITS';
  end if;
  total := jsonb_array_length(hits);
  for i in 1 .. total loop
    hit := hits -> (i - 1);
    if coalesce(hit ->> 'scope', '') = '' or (hit ->> 'key') is null then
      raise exception 'Hit % of check_rate_limits needs a scope and a key', i - 1
        using errcode = '22023', hint = 'RATE_LIMIT_HITS';
    end if;
    select * into rule from "better_supabase"."rate_limit_rules" r
    where r."scope" = hit ->> 'scope'
      and (r."organization_id" is null or r."organization_id" = (hit ->> 'organization_id')::uuid)
    order by (r."organization_id" is null)
    limit 1;
    limit_max := coalesce((hit ->> 'max_requests')::integer, rule."max_requests");
    limit_period := coalesce((hit ->> 'period')::interval, rule."period");
    if limit_max is null or limit_period is null then
      raise exception 'No rate limit for %: call set_rate_limit or pass max_requests and period', hit ->> 'scope'
        using errcode = '22023', hint = 'RATE_LIMIT_UNKNOWN';
    end if;
    if limit_max < 1 or limit_period <= interval '0' then
      raise exception 'The rate limit for % needs a positive max_requests and period', hit ->> 'scope'
        using errcode = '22023', hint = 'RATE_LIMIT_HITS';
    end if;
    for j in 1 .. i - 1 loop
      if scopes[j] = hit ->> 'scope' and keys[j] = hit ->> 'key' then
        raise exception 'Hits % and % of check_rate_limits count the same scope % and key; give each limit its own scope', j - 1, i - 1, hit ->> 'scope'
          using errcode = '22023', hint = 'RATE_LIMIT_HITS';
      end if;
    end loop;
    scopes := scopes || (hit ->> 'scope');
    keys := keys || (hit ->> 'key');
    maxes := maxes || limit_max;
    periods := periods || limit_period;
  end loop;

  insert into "better_supabase"."rate_limits" as l ("scope", "key", "window_started_at", "hits", "period")
  select u.scope, u.key, now(), 0, u.period
  from unnest(scopes, keys, periods) as u(scope, key, period)
  order by u.scope, u.key
  on conflict on constraint rate_limits_pkey do nothing;

  perform 1
  from "better_supabase"."rate_limits" l
  join unnest(scopes, keys) as u(scope, key) on l."scope" = u.scope and l."key" = u.key
  order by l."scope", l."key"
  for update of l;

  for i in 1 .. total loop
    select * into counter from "better_supabase"."rate_limits" l
    where l."scope" = scopes[i] and l."key" = keys[i];
    if counter."window_started_at" + periods[i] <= now() then
      used := used || 0;
      starts := starts || now();
    else
      used := used || counter."hits";
      starts := starts || counter."window_started_at";
    end if;
    if used[i] + 1 > maxes[i] then
      longest := greatest(longest, greatest(1, ceil(extract(epoch from starts[i] + periods[i] - now()))::integer));
      first_blocked := coalesce(first_blocked, i - 1);
    end if;
  end loop;

  passed := first_blocked is null;

  if passed then
    for i in 1 .. total loop
      update "better_supabase"."rate_limits" l set
        "window_started_at" = starts[i],
        "hits" = used[i] + 1,
        "period" = periods[i]
      where l."scope" = scopes[i] and l."key" = keys[i];
    end loop;
  end if;

  for i in 1 .. total loop
    current_hits := used[i] + case when passed then 1 else 0 end;
    results := results || jsonb_build_array(jsonb_build_object(
      'allowed', used[i] + 1 <= maxes[i],
      'remaining', greatest(maxes[i] - current_hits, 0),
      'retry_after', case when used[i] + 1 <= maxes[i] then 0
        else greatest(1, ceil(extract(epoch from starts[i] + periods[i] - now()))::integer) end
    ));
  end loop;

  return jsonb_build_object(
    'allowed', passed,
    'blocked', first_blocked,
    'retry_after', longest,
    'results', results
  );
end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.check_request()
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  method text := current_setting('request.method', true);
  path text := current_setting('request.path', true);
  claims jsonb := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  rule "better_supabase"."rate_limit_rules";
  caller text;
  used integer;
  started timestamptz;
  retry integer;
begin
  if method is null or method not in ('POST', 'PATCH', 'PUT', 'DELETE') then
    return;
  end if;
  if current_setting('transaction_read_only', true) = 'on' then
    return;
  end if;
  if claims ->> 'role' = 'service_role' then
    return;
  end if;
  for rule in
    select * from "better_supabase"."rate_limit_rules" r where r."scope" in ('*', path) and r."organization_id" is null order by r."scope"
  loop
    caller := coalesce(
      claims ->> rule."key_claim",
      'ip:' || coalesce(nullif(trim(reverse(split_part(reverse(headers ->> 'x-forwarded-for'), ',', 1))), ''), 'unknown')
    );
    insert into "better_supabase"."rate_limits" as l ("scope", "key", "window_started_at", "hits", "period")
    values (rule."scope", caller, now(), 1, rule."period")
    on conflict on constraint rate_limits_pkey do update set
      "window_started_at" = case when l."window_started_at" + rule."period" <= now() then now() else l."window_started_at" end,
      "hits" = case when l."window_started_at" + rule."period" <= now() then 1 else l."hits" + 1 end,
      "period" = rule."period"
    returning l."hits", l."window_started_at" into used, started;
    if used > rule."max_requests" then
      retry := greatest(1, ceil(extract(epoch from started + rule."period" - now()))::integer);
      raise sqlstate 'PGRST' using
        message = json_build_object(
          'code', 'BS429',
          'message', format('Rate limit for %s exceeded: %s writes per %s', rule."scope", rule."max_requests", rule."period"),
          'details', format('Retry after %s seconds.', retry),
          'hint', null
        )::text,
        detail = json_build_object(
          'status', 429,
          'status_text', 'Too Many Requests',
          'headers', json_build_object('Retry-After', retry::text)
        )::text;
    end if;
  end loop;
end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_due_ai_tasks (
  batch integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_task "better_supabase"."ai_scheduled_tasks"%rowtype;
  v_run "better_supabase"."ai_task_runs"%rowtype;
  v_runs jsonb := '[]';
  v_unscheduled jsonb;
begin
  update "better_supabase"."ai_task_runs" y set "status" = 'failed', "error" = 'timed out', "finished_at" = now()
  where (y."status" = 'running' and y."started_at" < now() - interval '30 minutes')
     or (y."status" = 'queued' and y."created_at" < now() - interval '30 minutes');
  for v_task in
    select * from "better_supabase"."ai_scheduled_tasks" x
    where x."enabled" and x."next_run_at" <= now()
    order by x."next_run_at"
    limit least(greatest(claim_due_ai_tasks.batch, 1), 500)
    for update skip locked
  loop
    insert into "better_supabase"."ai_task_runs" ("task_id", "organization_id", "user_id", "scheduled_at", "chat_id")
    values (v_task."id", v_task."organization_id", v_task."user_id", v_task."next_run_at", v_task."chat_id")
    returning * into v_run;
    update "better_supabase"."ai_scheduled_tasks" x set "next_run_at" = null, "last_run_at" = now() where x."id" = v_task."id";
    perform "better_supabase"."enqueue_job"(queue => 'ai_task_run', payload => jsonb_build_object('run_id', v_run."id"), dedupe_key => 'ai-task:' || v_run."id"::text, dedupe_running => false);
    v_runs := v_runs || jsonb_build_array(jsonb_build_object('id', v_run."id", 'task_id', v_run."task_id", 'organization_id', v_run."organization_id", 'user_id', v_run."user_id", 'status', v_run."status", 'scheduled_at', v_run."scheduled_at", 'chat_id', v_run."chat_id", 'error', v_run."error", 'started_at', v_run."started_at", 'finished_at', v_run."finished_at", 'created_at', v_run."created_at"));
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'cron', x."cron", 'timezone', x."timezone")), '[]')
  into v_unscheduled
  from "better_supabase"."ai_scheduled_tasks" x where x."enabled" and x."next_run_at" is null;
  return jsonb_build_object('runs', v_runs, 'unscheduled', v_unscheduled);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_due_workflow_schedules (
  lease integer DEFAULT 60,
  batch integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  with due as (
    select "id" from "better_supabase"."workflow_schedules"
    where not "paused"
      and "next_run_at" <= now()
      and ("lock_expires_at" is null or "lock_expires_at" < now())
    order by "next_run_at"
    limit greatest(coalesce(batch, 50), 1)
    for update skip locked
  ),
  leased as (
    update "better_supabase"."workflow_schedules" x set "lock_expires_at" = now() + make_interval(secs => greatest(coalesce(lease, 60), 1))
    from due where x."id" = due."id"
    returning x.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', leased."id",
    'tenant', leased."tenant_id",
    'name', leased."name",
    'workflow', leased."workflow",
    'input', leased."input",
    'cron', leased."cron",
    'timezone', leased."timezone",
    'nextRunAt', leased."next_run_at",
    'lastRunAt', leased."last_run_at",
    'paused', leased."paused",
    'createdBy', leased."created_by",
    'createdAt', leased."created_at"
  ) || jsonb_build_object('fireAt', leased."next_run_at") order by leased."next_run_at"), '[]'::jsonb)
  from leased;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_lease (
  scope         text,
  key           text,
  lease_seconds integer DEFAULT 60
)
  RETURNS TABLE (
    lease_state      text,
    lease_holder     uuid,
    lease_expires_at timestamp with time zone,
    retry_after_ms   integer
  )
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  token uuid := gen_random_uuid();
  lease_expires_at timestamptz := now() + make_interval(secs => greatest(coalesce(lease_seconds, 60), 1));
  taken "better_supabase"."job_leases"%rowtype;
begin
  -- A held lease that ran out, or a completed one past its keep time, is taken
  -- over; the new holder token makes the former holder's calls return false.
  insert into "better_supabase"."job_leases" as l ("scope", "key", "holder", "state", "expires_at")
  values (scope, key, token, 'held', lease_expires_at)
  on conflict ("scope", "key") do update
    set "holder" = excluded."holder", "state" = 'held', "expires_at" = excluded."expires_at"
    where l."expires_at" <= now()
  returning * into taken;
  if found then
    return query select 'claimed'::text, token, lease_expires_at, 0;
    return;
  end if;

  select * into taken from "better_supabase"."job_leases" l
  where l."scope" = claim_lease.scope and l."key" = claim_lease.key;
  if not found then
    -- Released between the insert and the read: the caller can retry at once.
    return query select 'busy'::text, null::uuid, null::timestamptz, 0;
    return;
  end if;
  return query select
    case when taken."state" = 'completed' then 'completed' else 'busy' end,
    null::uuid,
    taken."expires_at",
    greatest(ceil(extract(epoch from taken."expires_at" - now()) * 1000)::integer, 0);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_webhook_deliveries (
  max_items    integer  DEFAULT 25,
  lease        interval DEFAULT '00:02:00'::interval,
  max_attempts integer  DEFAULT 8
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  result jsonb;
begin
  update "better_supabase"."webhook_deliveries" v
  set "status" = 'canceled', "lease_expires_at" = null, "last_error" = 'Endpoint is disabled', "processed_at" = now(), "updated_at" = now()
  from "better_supabase"."webhook_endpoints" d
  where d."id" = v."endpoint_id"
    and not d."enabled"
    and v."status" in ('pending', 'retrying');

  update "better_supabase"."webhook_deliveries" v
  set "status" = 'dead', "lease_expires_at" = null, "last_error" = 'The lease ran out on the last attempt', "processed_at" = now(), "updated_at" = now()
  where v."status" = 'delivering'
    and v."lease_expires_at" <= now()
    and v."attempt" >= greatest(1, coalesce(claim_webhook_deliveries.max_attempts, 8));

  with due as (
    select v."id" as id
    from "better_supabase"."webhook_deliveries" v
    where v."status" in ('pending', 'retrying', 'delivering')
      and v."available_at" <= now()
      and (v."lease_expires_at" is null or v."lease_expires_at" <= now())
    order by v."available_at", v."created_at"
    for update skip locked
    limit greatest(1, least(coalesce(claim_webhook_deliveries.max_items, 25), 100))
  ),
  claimed as (
    update "better_supabase"."webhook_deliveries" v
    set "status" = 'delivering',
      "attempt" = v."attempt" + 1,
      "lease_expires_at" = now() + coalesce(claim_webhook_deliveries.lease, '2 minutes'), "updated_at" = now()
    from due
    where v."id" = due.id
    returning v.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', c."id",
    'endpoint_id', c."endpoint_id",
    'type', c."event_type",
    'payload', c."payload",
    'attempt', c."attempt",
    'url', d."url",
    'created_at', c."created_at", 'tenant', c."organization_id", 'event_id', c."event_id", 'run_id', c."run_id", 'subject', c."subject", 'owner', d."created_by", 'principal', case when d."created_by" is null then "better_supabase"."default_service_principal"(d."organization_id") end, 'permissions', d."permissions", 'batch', d."batch", 'signing', d."signing", 'format', d."format", 'credential_ref', d."credential_ref"
  ) order by c."available_at"), '[]')
  into result
  from claimed c
  join "better_supabase"."webhook_endpoints" d on d."id" = c."endpoint_id";
  return result;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_workflow_run_dispatch (
  run   uuid,
  lease integer DEFAULT 60
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_runs"%rowtype;
begin
  update "better_supabase"."workflow_runs" x set "dispatch_expires_at" = now() + make_interval(secs => greatest(coalesce(lease, 60), 1)), "updated_at" = now()
  where x."id" = run
    and x."status" = 'queued'
    and starts_with(x."external_id", 'pending:')
    and (x."dispatch_expires_at" is null or x."dispatch_expires_at" < now())
  returning * into v_row;
  if not found then
    return null;
  end if;
  return jsonb_build_object(
    'id', v_row."id",
    'engine', v_row."engine",
    'externalId', v_row."external_id",
    'definition', v_row."definition",
    'tenant', v_row."tenant_id",
    'actor', v_row."actor_id",
    'status', v_row."status",
    'attributes', v_row."attributes",
    'error', v_row."error",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at",
    'startedAt', v_row."started_at",
    'completedAt', v_row."completed_at",
    'cancelRequestedAt', v_row."cancel_requested_at",
    'subjectType', v_row."subject_type",
    'subjectId', v_row."subject_id",
    'principalKind', v_row."principal_kind",
    'principalId', v_row."principal_id",
    'mode', v_row."mode",
    'triggerNode', v_row."trigger_node",
    'idempotencyKey', v_row."idempotency_key"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_workflow_start_requests (
  lease integer DEFAULT 60,
  batch integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."workflow_start_requests"%rowtype;
  v_out jsonb := '[]'::jsonb;
  v_taken integer := 0;
begin
  for v_row in
    select * from "better_supabase"."workflow_start_requests"
    where "status" = 'pending'
      and "not_before_at" <= now()
      and ("claim_expires_at" is null or "claim_expires_at" < now())
    order by "created_at"
    for update skip locked
  loop
    exit when v_taken >= greatest(coalesce(batch, 50), 1);
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('workflow_admission'), pg_catalog.hashtext(v_row."key"));
    if v_row."concurrency" is null
      or "better_supabase"."workflow_admission_active"(v_row."key") < v_row."concurrency" then
      update "better_supabase"."workflow_start_requests" set "claim_expires_at" = now() + make_interval(secs => greatest(coalesce(lease, 60), 1))
      where "id" = v_row."id";
      v_out := v_out || jsonb_build_array(jsonb_build_object(
        'id', v_row."id",
        'key', v_row."key",
        'workflow', v_row."workflow",
        'input', v_row."input",
        'tenant', v_row."tenant_id",
        'actor', v_row."actor_id",
        'subjectType', v_row."subject_type",
        'subjectId', v_row."subject_id"
      ));
      v_taken := v_taken + 1;
    end if;
  end loop;
  return v_out;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.complete_webhook_delivery (
  delivery uuid,
  outcome  jsonb
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_status text := complete_webhook_delivery.outcome ->> 'status';
  v_attempt integer := (complete_webhook_delivery.outcome ->> 'attempt')::integer;
  v_endpoint uuid;
  v_tenant uuid;
  v_since timestamptz;
  v_result text := 'ok';
begin
  if v_status is null or v_status not in ('succeeded', 'retrying', 'dead', 'canceled') then
    raise exception 'status must be succeeded, retrying, dead or canceled' using errcode = '22023', hint = 'WEBHOOK_STATUS_UNKNOWN';
  end if;
  if v_attempt is null then
    raise exception 'outcome.attempt must be the attempt the claim returned' using errcode = '22023', hint = 'WEBHOOK_ATTEMPT_REQUIRED';
  end if;
  update "better_supabase"."webhook_deliveries" v
  set "status" = v_status,
    "attempt" = case when v_status = 'canceled' then greatest(v."attempt" - 1, 0) else v."attempt" end,
    "available_at" = case when v_status = 'retrying' then coalesce((complete_webhook_delivery.outcome ->> 'retry_at')::timestamptz, now()) else v."available_at" end,
    "lease_expires_at" = null,
    "response_status" = (complete_webhook_delivery.outcome ->> 'response_status')::integer,
    "response_body" = complete_webhook_delivery.outcome ->> 'response_body',
    "duration_ms" = (complete_webhook_delivery.outcome ->> 'duration_ms')::integer,
    "last_error" = complete_webhook_delivery.outcome ->> 'error',
    "processed_at" = case when v_status = 'retrying' then null else now() end,
    "updated_at" = now()
  where v."id" = complete_webhook_delivery.delivery
    and v."attempt" = v_attempt
    and v."status" = 'delivering'
  returning v."endpoint_id" into v_endpoint;
  if not found then
    if exists (select 1 from "better_supabase"."webhook_deliveries" v where v."id" = complete_webhook_delivery.delivery) then
      return 'stale';
    end if;
    raise exception 'Webhook delivery not found' using errcode = 'P0002', hint = 'WEBHOOK_DELIVERY_NOT_FOUND';
  end if;
  if v_status = 'succeeded' then
    update "better_supabase"."webhook_endpoints" d set "first_failed_at" = null
    where d."id" = v_endpoint and d."first_failed_at" is not null;
  elsif v_status in ('retrying', 'dead') then
    update "better_supabase"."webhook_endpoints" d set "first_failed_at" = coalesce(d."first_failed_at", now())
    where d."id" = v_endpoint
    returning d."first_failed_at", d."organization_id" into v_since, v_tenant;
    if v_since <= now() - '5 days'::interval then
      update "better_supabase"."webhook_endpoints" d set "enabled" = false, "disabled_at" = now(), "disabled_reason" = format('Deliveries failed since %s', v_since), "updated_at" = now()
      where d."id" = v_endpoint and d."enabled";
      if found then
        v_result := 'disabled';
        perform "better_supabase".emit_event('webhook_endpoint.disabled', jsonb_build_object('endpointId', v_endpoint, 'organizationId', v_tenant::text, 'failingSince', v_since), 'webhooks/' || v_endpoint::text, (v_tenant::text)::text, 'webhook_endpoint.disabled:' || v_endpoint::text || ':' || v_since::text, 'better-supabase/webhooks-out');
  perform better_supabase.audit_event(
    event_type => 'webhook_endpoint.disabled',
    category => 'integration',
    target_type => 'webhook_endpoint',
    record_id => v_endpoint::text,
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('endpointId', v_endpoint, 'organizationId', v_tenant::text, 'failingSince', v_since),
    idempotency_key => 'webhook_endpoint.disabled:' || v_endpoint::text || ':' || v_since::text
  );
      end if;
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_webhook_delivery"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using complete_webhook_delivery.delivery, v_status;
    end if;
  end;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.consent_active (
  subject_type text,
  subject_id   text,
  purpose_key  text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tenant uuid := ((case consent_active.subject_type
      when 'message' then (select s."tenant_id"::text from "better_supabase"."messages" s where s."id" = (consent_active.subject_id)::uuid)
      when 'conversation' then (select s."tenant_id"::text from "better_supabase"."conversations" s where s."id" = (consent_active.subject_id)::uuid)
      when 'channel' then (select s."tenant_id"::text from "better_supabase"."channels" s where s."id" = (consent_active.subject_id)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (consent_active.subject_id)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (consent_active.subject_id)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (consent_active.subject_id)::uuid)
      when 'course' then (select s."tenant_id"::text from "better_supabase"."courses" s where s."id" = (consent_active.subject_id)::uuid)
      when 'post' then (select s."tenant_id"::text from "better_supabase"."posts" s where s."id" = (consent_active.subject_id)::uuid)
      when 'activity' then (select s."tenant_id"::text from "better_supabase"."activities" s where s."id" = (consent_active.subject_id)::uuid)
      when 'quote' then (select s."tenant_id"::text from "better_supabase"."quotes" s where s."id" = (consent_active.subject_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (consent_active.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (consent_active.subject_id)::uuid)
      when 'invoice' then (select s."tenant_id"::text from "better_supabase"."invoices" s where s."id" = (consent_active.subject_id)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (consent_active.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (consent_active.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (consent_active.subject_id)::uuid)
      when 'rfq' then (select s."tenant_id"::text from "better_supabase"."rfqs" s where s."id" = (consent_active.subject_id)::uuid)
      when 'till' then (select s."tenant_id"::text from "better_supabase"."tills" s where s."id" = (consent_active.subject_id)::uuid)
      when 'order' then (select s."tenant_id"::text from "better_supabase"."orders" s where s."id" = (consent_active.subject_id)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (consent_active.subject_id)::uuid)
      when 'booking' then (select s."tenant_id"::text from "better_supabase"."bookings" s where s."id" = (consent_active.subject_id)::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (consent_active.subject_id)::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (consent_active.subject_id)::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."leases" s where s."id" = (consent_active.subject_id)::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (consent_active.subject_id)::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (consent_active.subject_id)::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (consent_active.subject_id)::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (consent_active.subject_id)::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (consent_active.subject_id)::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (consent_active.subject_id)::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (consent_active.subject_id)::uuid)
      when 'compliance_policy' then (select s."tenant_id"::text from "better_supabase"."compliance_policies" s where s."id" = (consent_active.subject_id)::uuid)
      when 'qualification_type' then (select s."tenant_id"::text from "better_supabase"."qualification_types" s where s."id" = (consent_active.subject_id)::uuid)
      when 'risk' then (select s."tenant_id"::text from "better_supabase"."risks" s where s."id" = (consent_active.subject_id)::uuid)
      when 'case' then (select s."tenant_id"::text from "better_supabase"."cases" s where s."id" = (consent_active.subject_id)::uuid)
      when 'inspection' then (select s."tenant_id"::text from "better_supabase"."inspections" s where s."id" = (consent_active.subject_id)::uuid)
      when 'inspection_program' then (select s."tenant_id"::text from "better_supabase"."inspection_programs" s where s."id" = (consent_active.subject_id)::uuid)
      when 'inspection_finding' then (select s."tenant_id"::text from "better_supabase"."inspection_findings" s where s."id" = (consent_active.subject_id)::uuid)
      when 'form' then (select s."tenant_id"::text from "better_supabase"."forms" s where s."id" = (consent_active.subject_id)::uuid)
      when 'meeting' then (select s."tenant_id"::text from "better_supabase"."meetings" s where s."id" = (consent_active.subject_id)::uuid)
      when 'meeting_decision' then (select s."tenant_id"::text from "better_supabase"."meeting_decisions" s where s."id" = (consent_active.subject_id)::uuid)
      when 'maintenance_plan' then (select s."tenant_id"::text from "better_supabase"."maintenance_plans" s where s."id" = (consent_active.subject_id)::uuid)
      when 'dam_usage_right' then (select s."tenant_id"::text from "better_supabase"."dam_usage_rights" s where s."id" = (consent_active.subject_id)::uuid)
      when 'lims_sample' then (select s."tenant_id"::text from "better_supabase"."lims_samples" s where s."id" = (consent_active.subject_id)::uuid)
      when 'tax_code' then (select s."tenant_id"::text from "better_supabase"."tax_codes" s where s."id" = (consent_active.subject_id)::uuid)
      when 'production_order' then (select s."tenant_id"::text from "better_supabase"."production_orders" s where s."id" = (consent_active.subject_id)::uuid)
      when 'work_center' then (select s."tenant_id"::text from "better_supabase"."work_centers" s where s."id" = (consent_active.subject_id)::uuid)
      when 'bank_account' then (select s."tenant_id"::text from "better_supabase"."bank_accounts" s where s."id" = (consent_active.subject_id)::uuid)
      when 'care_plan' then (select s."tenant_id"::text from "better_supabase"."care_plans" s where s."id" = (consent_active.subject_id)::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (consent_active.subject_id)::uuid)
      when 'content_entry' then (select s."tenant_id"::text from "better_supabase"."content_entries" s where s."id" = (consent_active.subject_id)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (consent_active.subject_id)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (consent_active.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (consent_active.subject_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (consent_active.subject_id)::uuid)
      when 'change_request' then (select s."organization_id"::text from "public"."change_requests" s where s."id" = (consent_active.subject_id)::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (consent_active.subject_id)::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (consent_active.subject_id)::uuid)
      else null::text
    end))::uuid;
  v_purpose uuid;
begin
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or (coalesce(better_supabase.can('tenant', v_tenant, 'consents.read'), false) and coalesce("better_supabase"."can_subject"(consent_active.subject_type, consent_active.subject_id, 'read'), false))
      or ((v_tenant)::text, (consent_active.subject_type)::text, (consent_active.subject_id)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)
      or ((v_tenant)::text, (consent_active.subject_type)::text, (consent_active.subject_id)::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g)
      or exists (select 1 from "better_supabase"."relations" r
      where r."kind" = 'represents' and r."source_type" = 'person'
        and r."tenant_id"::text = (v_tenant)::text
        and r."target_type" = consent_active.subject_type and r."target_id" = (consent_active.subject_id)::text
        and r."data" ->> 'authority' in ('inform', 'act')
        and (case when r."data" ->> 'valid_from' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_from', 'date') then (r."data" ->> 'valid_from')::date <= current_date
      else false end) and (case when r."data" ->> 'valid_until' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_until', 'date') then (r."data" ->> 'valid_until')::date >= current_date
      else false end)
        and ((v_tenant)::text, ('person')::text, (r."source_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g))) then
    return false;
  end if;
  select x."id" into v_purpose from "better_supabase"."consent_purposes" x
  where x."key" = consent_active.purpose_key
    and (x."tenant_id" = v_tenant or x."tenant_id" is null)
    and x."archived_at" is null
  order by (x."tenant_id" is null), x."created_at" desc, x."id"
  limit 1;
  return v_purpose is not null and exists (
    select 1 from "better_supabase"."consents" x
    where x."tenant_id" = v_tenant and x."purpose_id" = v_purpose
      and x."subject_type" = consent_active.subject_type and x."subject_id" = consent_active.subject_id
      and (x."status" = 'granted' and (x."expires_at" is null or x."expires_at" > now()))
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.consent_missing (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  purpose_key  text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_purpose uuid;
  v_basis text;
begin
  if purpose_key is null or tenant is null then
    return false;
  end if;
  select x."id", x."legal_basis"::text into v_purpose, v_basis from "better_supabase"."consent_purposes" x
  where x."key" = purpose_key
    and (x."tenant_id" = tenant or x."tenant_id" is null)
    and x."archived_at" is null
  order by (x."tenant_id" is null), x."created_at" desc, x."id"
  limit 1;
  if v_purpose is null or v_basis <> 'consent' then
    return false;
  end if;
  return not exists (
    select 1 from "better_supabase"."consents" x
    where x."tenant_id" = tenant and x."purpose_id" = v_purpose
      and x."subject_type" = subject_type and x."subject_id" = subject_id
      and (x."status" = 'granted' and (x."expires_at" is null or x."expires_at" > now()))
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_webhook_endpoint (
  tenant uuid,
  fields jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid := create_webhook_endpoint.tenant;
  v_id uuid;
  v_endpoint jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.can('tenant', v_tenant, 'webhooks.manage'), false) then
    raise exception 'Not allowed to manage this webhook endpoint' using errcode = '42501', hint = 'WEBHOOK_FORBIDDEN';
  end if;
  if jsonb_typeof(coalesce(create_webhook_endpoint.fields, '{}')) <> 'object' or exists (
    select 1 from jsonb_each(coalesce(create_webhook_endpoint.fields, '{}')) e
    where case e.key when 'name' then jsonb_typeof(e.value) <> 'string' when 'url' then jsonb_typeof(e.value) <> 'string' when 'enabled' then jsonb_typeof(e.value) <> 'boolean' when 'eventTypes' then (jsonb_typeof(e.value) <> 'array' or exists (select 1 from jsonb_array_elements(e.value) a where jsonb_typeof(a) <> 'string')) when 'permissions' then (jsonb_typeof(e.value) <> 'null' and (jsonb_typeof(e.value) <> 'array' or exists (select 1 from jsonb_array_elements(e.value) a where jsonb_typeof(a) <> 'string'))) when 'batch' then jsonb_typeof(e.value) <> 'boolean' when 'signing' then jsonb_typeof(e.value) <> 'string' when 'format' then jsonb_typeof(e.value) <> 'string' when 'credentialRef' then jsonb_typeof(e.value) not in ('object', 'null') else true end
  ) then
    raise exception 'A webhook endpoint field is unknown or has the wrong type' using errcode = '22023', hint = 'WEBHOOK_ENDPOINT_INVALID';
  end if;
  if create_webhook_endpoint.fields ->> 'url' is null or create_webhook_endpoint.fields ->> 'url' !~* '^https://' then
    raise exception 'A webhook endpoint URL must start with https://' using errcode = '22023', hint = 'WEBHOOK_ENDPOINT_URL';
  end if;
  insert into "better_supabase"."webhook_endpoints" ("organization_id", "url", "enabled", "event_types", "name")
  values (create_webhook_endpoint.tenant, create_webhook_endpoint.fields ->> 'url', coalesce((create_webhook_endpoint.fields ->> 'enabled')::boolean, true), coalesce(array(select jsonb_array_elements_text(create_webhook_endpoint.fields -> 'eventTypes')), '{}'), create_webhook_endpoint.fields ->> 'name')
  returning "id" into v_id;
  if create_webhook_endpoint.fields ?| array['permissions', 'batch', 'signing', 'format', 'credentialRef'] then
    update "better_supabase"."webhook_endpoints" d set "permissions" = case when create_webhook_endpoint.fields ? 'permissions' then case when jsonb_typeof(create_webhook_endpoint.fields -> 'permissions') = 'null' then null else array(select jsonb_array_elements_text(create_webhook_endpoint.fields -> 'permissions')) end else d."permissions" end, "batch" = case when create_webhook_endpoint.fields ? 'batch' then (create_webhook_endpoint.fields ->> 'batch')::boolean else d."batch" end, "signing" = case when create_webhook_endpoint.fields ? 'signing' then create_webhook_endpoint.fields ->> 'signing' else d."signing" end, "format" = case when create_webhook_endpoint.fields ? 'format' then create_webhook_endpoint.fields ->> 'format' else d."format" end, "credential_ref" = case when create_webhook_endpoint.fields ? 'credentialRef' then nullif(create_webhook_endpoint.fields -> 'credentialRef', 'null'::jsonb) else d."credential_ref" end, "updated_at" = now()
  where d."id" = v_id;
  end if;
  select jsonb_build_object('id', d."id", 'tenant', d."organization_id", 'name', d."name", 'url', d."url", 'enabled', d."enabled", 'eventTypes', d."event_types", 'permissions', d."permissions", 'batch', d."batch", 'signing', d."signing", 'format', d."format", 'credentialRef', d."credential_ref", 'failingSince', d."first_failed_at", 'disabledAt', d."disabled_at", 'disabledReason', d."disabled_reason", 'createdBy', d."created_by", 'createdAt', d."created_at", 'updatedAt', d."updated_at") into v_endpoint
  from "better_supabase"."webhook_endpoints" d where d."id" = v_id;
  return v_endpoint;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_workflow_schedule (
  name     text,
  workflow text,
  cron     text,
  next_run timestamp with time zone,
  payload  jsonb                    DEFAULT '{}'::jsonb,
  timezone text                     DEFAULT 'UTC'::text,
  tenant   uuid                     DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_schedules"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (tenant is not null and coalesce(better_supabase.can('tenant', tenant, 'workflows.manage'), false))) then
    raise exception 'You may not schedule workflows here' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_workflow_schedule_create"(text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid)', v_hook::oid::regproc)
        using name, workflow, tenant;
    end if;
  end;
  insert into "better_supabase"."workflow_schedules" as x ("tenant_id", "name", "workflow", "input", "cron", "timezone", "next_run_at", "created_by")
  values (tenant, name, workflow, coalesce(payload -> 'input', '[]'::jsonb), cron, coalesce(timezone, 'UTC'), next_run, (select auth.uid()))
  on conflict on constraint workflow_schedules_tenant_name_key do update set
    "workflow" = excluded."workflow",
    "input" = excluded."input",
    "cron" = excluded."cron",
    "timezone" = excluded."timezone",
    "next_run_at" = excluded."next_run_at",
    "lock_expires_at" = null
  returning * into v_row;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_workflow_schedule_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant_id",
    'name', v_row."name",
    'workflow', v_row."workflow",
    'input', v_row."input",
    'cron', v_row."cron",
    'timezone', v_row."timezone",
    'nextRunAt', v_row."next_run_at",
    'lastRunAt', v_row."last_run_at",
    'paused', v_row."paused",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_bin (
  tenant    uuid,
  page_size integer                  DEFAULT 50,
  before    timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', drive_bin.tenant, 'drive.read'), false)) then
    raise exception 'not allowed to read this organization''s drive' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', b.item_id, 'batchId', b.batch_id, 'count', b.n, 'trashedBy', b.trashed_by, 'trashedAt', b.trashed_at, 'purgeAfter', b.purge_at, 'node', b.node) order by b.trashed_at desc, b.item_id), '[]'::jsonb)
    from (
      select i."id" as item_id, i."batch_id" as batch_id, i."trashed_by" as trashed_by, i."trashed_at" as trashed_at, i."purge_at" as purge_at,
        (select count(*) from "better_supabase"."trash_items" c where c."batch_id" = i."batch_id")::integer as n,
        "better_supabase"."drive_node_json"(x) as node
      from "better_supabase"."trash_items" i
      join "better_supabase"."drive_nodes" x on x."id"::text = i."subject_id"
      where i."tenant_id" = drive_bin.tenant and i."subject_type" = 'drive_node' and i."depth" = 0
        and (drive_bin.before is null or i."trashed_at" < drive_bin.before)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'editor'))
      order by i."trashed_at" desc, i."id"
      limit least(greatest(coalesce(drive_bin.page_size, 50), 1), 200)
    ) b
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_commit (
  node       uuid,
  attachment uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_file "better_supabase"."attachments"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_commit.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer') or "better_supabase"."drive_uploaded_own"(v_node."id")) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor') or "better_supabase"."drive_uploaded_own"(v_node."id")) then
    raise exception 'not allowed to change this file' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if (v_node."lock_expires_at" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."lock_expires_at")::text;
  end if;
  if not exists (
    select 1 from "better_supabase"."attachments" f where f."id" = drive_commit.attachment
      and f."subject_type" = 'drive_node' and f."subject_id" = v_node."id"::text
  ) then
    raise exception 'this upload does not belong to the file' using errcode = 'P0002', hint = 'DRIVE_ATTACHMENT_NOT_FOUND';
  end if;
  perform "better_supabase"."confirm_attachment"(drive_commit.attachment);
  select * into v_file from "better_supabase"."attachments" f where f."id" = drive_commit.attachment;
  if v_node."attachment_id" is distinct from v_file."id" then
    update "better_supabase"."drive_nodes" x set "attachment_id" = v_file."id", "preview_pages" = null, "updated_at" = now()
    where x."id" = v_node."id"
    returning * into v_node;
    perform "better_supabase"."version_insert"(v_node."tenant_id", 'drive_node', v_node."id"::text,
      jsonb_build_object('attachmentId', v_file."id", 'name', v_file."name", 'mimeType', v_file."mime_type", 'size', v_file."size"),
      v_file."bucket" || '/' || v_file."object_path", null, 'manual', false, auth.uid());
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    return jsonb_build_object('id', v_node."id", 'attachmentId', v_file."id", 'committed', true);
  end if;
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_delete (
  node uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_locked "better_supabase"."drive_nodes"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_delete.node;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'owner')) then
    raise exception 'not allowed to delete this item for good' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if "better_supabase"."drive_node_held"(v_node."id") then
    raise exception 'this item is under a legal hold' using errcode = '42501', hint = 'DRIVE_HELD';
  end if;
  select * into v_locked from "better_supabase"."drive_nodes" lk
  where lk."id" in (select s.node_id from "better_supabase"."drive_subtree"(v_node."id") s)
    and (lk."lock_expires_at" > now() and lk."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))
  limit 1;
  if found then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_locked."locked_by", 'lockedUntil', v_locked."lock_expires_at")::text;
  end if;
  delete from "better_supabase"."drive_nodes" x where x."id" in (select s.node_id from "better_supabase"."drive_subtree"(v_node."id") s);
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_document_obsolete (
  node   uuid,
  reason text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_document_obsolete.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be obsoleted' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'owner')) then
    raise exception 'not allowed to withdraw this document' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (v_node."lock_expires_at" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."lock_expires_at")::text;
  end if;
  if v_node."document_status" is distinct from 'effective' then
    raise exception 'only an effective document can be made obsolete' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  perform "better_supabase"."transition"('drive_node', v_node."id"::text, 'obsolete', drive_document_obsolete.reason);
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_node."id";
  perform "better_supabase".emit_event('drive_node.obsoleted', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'reason', drive_document_obsolete.reason), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
  perform better_supabase.audit_event(
    event_type => 'drive_node.obsoleted',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'document made obsolete',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'reason', drive_document_obsolete.reason)
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_document_release (
  node       uuid,
  attachment uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_file "better_supabase"."attachments"%rowtype;
  v_version uuid;
  v_inserted jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or exists (
    select 1 from "better_supabase"."approval_requests" q
    where q."id"::text = nullif(current_setting('better_supabase.approval', true), '')
      and q."status" = 'approved' and q."action" = 'release'
      and q."subject_type" = 'drive_node' and q."subject_id" = drive_document_release.node::text
  )) then
    raise exception 'only an approved release request releases a document' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_document_release.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be released' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  if v_node."document_status" is null or v_node."document_status" not in ('in_review', 'effective') then
    raise exception 'only a document in review or an effective one can be released' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  select * into v_file from "better_supabase"."attachments" f
  where f."id" = drive_document_release.attachment
    and f."subject_type" = 'drive_node' and f."subject_id" = v_node."id"::text
    and f."uploaded_at" is not null;
  if not found then
    raise exception 'that version of the file was not found' using errcode = 'P0002', hint = 'DRIVE_ATTACHMENT_NOT_FOUND';
  end if;
  select r."id" into v_version from "better_supabase"."versions" r
  where r."subject_type" = 'drive_node' and r."subject_id" = v_node."id"::text
    and r."content" ->> 'attachmentId' = v_file."id"::text
  order by r."number" desc limit 1;
  if v_version is null then
    v_inserted := "better_supabase"."version_insert"(v_node."tenant_id", 'drive_node', v_node."id"::text,
      jsonb_build_object('attachmentId', v_file."id", 'name', v_file."name", 'mimeType', v_file."mime_type", 'size', v_file."size"),
      v_file."bucket" || '/' || v_file."object_path", 'effective', 'manual', true, auth.uid());
    v_version := (v_inserted ->> 'id')::uuid;
  else
    update "better_supabase"."versions" r set "label" = 'effective', "frozen" = true where r."id" = v_version;
  end if;
  update "better_supabase"."versions" r set "label" = 'superseded'
  where r."id" = v_node."effective_version_id" and r."id" <> v_version;
  update "better_supabase"."drive_nodes" x set "effective_version_id" = v_version, "effective_at" = now(),
    "next_review_on" = (current_date + make_interval(months => coalesce(v_node."review_interval_months", 12)))::date, "review_notified_for" = null
  where x."id" = v_node."id";
  if v_node."document_status" = 'in_review' then
    perform "better_supabase"."transition"('drive_node', v_node."id"::text, 'effective', 'released');
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_node."id";
  perform "better_supabase".emit_event('drive_node.released', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'versionId', v_version, 'attachmentId', v_file."id"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
  perform better_supabase.audit_event(
    event_type => 'drive_node.released',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'document released',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'versionId', v_version, 'attachmentId', v_file."id")
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_document_save (
  node                   uuid,
  document_type          text,
  owner_id               uuid    DEFAULT NULL::uuid,
  review_interval_months integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_seq bigint;
  v_number text;
  v_entity text;
  v_format text;
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_document_save.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be a controlled document' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to control this document' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (v_node."lock_expires_at" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."lock_expires_at")::text;
  end if;
  if drive_document_save.document_type is null or not (drive_document_save.document_type = any (array['sop', 'policy', 'form']::text[])) then
    raise exception 'that document type is not in options.control.types' using errcode = '22023', hint = 'DRIVE_DOCUMENT_TYPE_UNKNOWN';
  end if;
  if v_node."document_status" = 'obsolete' then
    raise exception 'an obsolete document can''t change' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  if drive_document_save.owner_id is not null and not exists (
    select 1 from "public"."memberships" mu
    where mu."organization_id" = v_node."tenant_id" and mu."user_id" = drive_document_save.owner_id
  ) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'DRIVE_DOCUMENT_OWNER_INVALID';
  end if;
  v_number := v_node."document_number";
  if v_number is null then
    case drive_document_save.document_type
      when 'sop' then
        v_entity := 'drive_document_sop';
        v_format := 'SOP-{n:4}';
      else
        v_entity := 'drive_document';
        v_format := 'DOC-{n:5}';
    end case;
    if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = v_entity then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = v_entity then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    v_seq := "better_supabase"."register_fixed_number"(v_node."tenant_id", v_entity, v_number, now(), '');
    perform set_config('better_supabase.fixed_number', '', true);
  else
    v_seq := "better_supabase"."next_number"(v_node."tenant_id", v_entity, now());
    v_number := better_supabase.format_assigned_number(v_format, v_seq, now());
  end if;
  end if;
  update "better_supabase"."drive_nodes" x set "document_number" = v_number,
    "document_type" = drive_document_save.document_type,
    "document_owner_id" = coalesce(drive_document_save.owner_id, x."document_owner_id", auth.uid()),
    "review_interval_months" = coalesce(drive_document_save.review_interval_months, x."review_interval_months"), "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  if v_node."document_status" is null then
    perform "better_supabase"."transition"('drive_node', v_node."id"::text, 'draft', null);
    select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_node."id";
  end if;
  perform "better_supabase".emit_event('drive_node.document_saved', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'documentType', v_node."document_type", 'ownerId', v_node."document_owner_id"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
  perform better_supabase.audit_event(
    event_type => 'drive_node.document_saved',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'document saved',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'documentType', v_node."document_type", 'ownerId', v_node."document_owner_id")
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_document_submit (
  node       uuid,
  attachment uuid DEFAULT NULL::uuid,
  reason     text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_file "better_supabase"."attachments"%rowtype;
  v_revision integer;
  v_request jsonb;
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_document_submit.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be released' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to submit this document' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (v_node."lock_expires_at" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."lock_expires_at")::text;
  end if;
  if v_node."document_status" is null then
    raise exception 'save the file as a controlled document first' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  if not (v_node."document_status" = 'draft' or (v_node."document_status" in ('in_review', 'effective') and not exists (
    select 1 from "better_supabase"."approval_requests" q
    where q."subject_type" = 'drive_node' and q."subject_id" = v_node."id"::text
      and q."action" = 'release' and q."status" = 'pending'
  ))) then
    raise exception 'only a draft, or an effective document without a pending release, can be submitted' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  select * into v_file from "better_supabase"."attachments" f
  where f."id" = coalesce(drive_document_submit.attachment, v_node."attachment_id")
    and f."subject_type" = 'drive_node' and f."subject_id" = v_node."id"::text
    and f."uploaded_at" is not null;
  if not found then
    raise exception 'that version of the file was not found' using errcode = 'P0002', hint = 'DRIVE_ATTACHMENT_NOT_FOUND';
  end if;
  select r."number" into v_revision from "better_supabase"."versions" r
  where r."subject_type" = 'drive_node' and r."subject_id" = v_node."id"::text
    and r."content" ->> 'attachmentId' = v_file."id"::text
  order by r."number" limit 1;
  if v_node."document_status" = 'draft' then
    perform "better_supabase"."transition"('drive_node', v_node."id"::text, 'in_review', drive_document_submit.reason);
  end if;
  v_request := "better_supabase"."request_approval"(v_node."tenant_id", 'drive_node', v_node."id"::text, 'release',
    drive_document_submit.reason, jsonb_build_object('attachmentId', v_file."id", 'revision', v_revision, 'name', v_file."name"));
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_node."id";
  perform "better_supabase".emit_event('drive_node.submitted', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'attachmentId', v_file."id", 'requestId', v_request ->> 'id'), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
  perform better_supabase.audit_event(
    event_type => 'drive_node.submitted',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'document submitted',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'attachmentId', v_file."id", 'requestId', v_request ->> 'id')
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_hold (
  node  uuid,
  until timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_hold.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'owner')) then
    raise exception 'not allowed to place a legal hold' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if drive_hold.until is null or drive_hold.until <= now() then
    raise exception 'a legal hold needs an end in the future' using errcode = '22023', hint = 'DRIVE_HOLD_INVALID';
  end if;
  update "better_supabase"."drive_nodes" x set "legal_hold_expires_at" = drive_hold.until, "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  perform "better_supabase".emit_event('drive_node.hold_placed', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'legalHoldUntil', v_node."legal_hold_expires_at"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.hold_placed',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'held',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'legalHoldUntil', v_node."legal_hold_expires_at")
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_lock (
  node  uuid,
  until timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  note  text                     DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_until timestamptz := coalesce(drive_lock.until, now() + interval '8 hours');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_lock.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if auth.uid() is null then
    raise exception 'not allowed to check out an item without a user' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if not "better_supabase"."drive_node_writable"(v_node."id") then
    if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
      raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
    end if;
    raise exception 'not allowed to check out this item' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be checked out' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  if v_until <= now() or v_until > now() + interval '30 days' then
    raise exception 'a lock ends in the future and within 30 days' using errcode = '22023', hint = 'DRIVE_LOCK_INVALID';
  end if;
  if length(drive_lock.note) > 500 then
    raise exception 'a lock note is at most 500 characters' using errcode = '22023', hint = 'DRIVE_LOCK_INVALID';
  end if;
  if (v_node."lock_expires_at" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."lock_expires_at")::text;
  end if;
  update "better_supabase"."drive_nodes" x set "locked_by" = auth.uid(), "lock_expires_at" = v_until, "lock_note" = drive_lock.note, "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  perform "better_supabase".emit_event('drive_node.locked', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'lockedBy', v_node."locked_by"::text, 'lockedUntil', v_node."lock_expires_at"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.locked',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'checked out',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'lockedBy', v_node."locked_by"::text, 'lockedUntil', v_node."lock_expires_at")
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_move (
  node     uuid,
  parent   uuid,
  rank     text DEFAULT NULL::text,
  conflict text DEFAULT NULL::text,
  drive    uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_previous uuid;
  v_target uuid;
  v_name text;
  v_role text;
  v_last text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_move.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to move this item' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if (v_node."lock_expires_at" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."lock_expires_at")::text;
  end if;
  if drive_move.rank is not null and drive_move.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'rank must be a key from rankBetween' using errcode = '22023', hint = 'DRIVE_RANK_INVALID';
  end if;
  v_previous := v_node."parent_id";
  if drive_move.parent is null then
    if v_previous is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ("better_supabase"."drive_can"(v_node."id", 'owner') and coalesce(better_supabase.can('tenant', v_node."tenant_id", 'drive.create'), false))) then
      raise exception 'not allowed to move this item to the top of the drive' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
    end if;
  else
    perform "better_supabase"."drive_check_parent"(v_node."tenant_id", drive_move.parent, drive_move.drive);
    if v_node."id" = any ("better_supabase"."drive_ancestors"(drive_move.parent)) then
      raise exception 'a folder can''t move into itself or its own subfolder' using errcode = '22023', hint = 'DRIVE_MOVE_CYCLE';
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_drive_node_move"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_node."id", drive_move.parent;
    end if;
  end;
  if v_previous is distinct from drive_move.parent then
    v_name := "better_supabase"."drive_free_name"(v_node."tenant_id", v_target, drive_move.parent, v_node."name", v_node."id",
      case when "better_supabase"."drive_conflict"(drive_move.conflict) = 'rename' then 'rename' else 'fail' end);
    if drive_move.parent is null and auth.uid() is not null then
      v_role := "better_supabase"."drive_role"(v_node."id");
      insert into "better_supabase"."drive_grants" ("tenant_id", "node_id", "principal_type", "principal_id", "role")
    values (v_node."tenant_id", v_node."id", 'user', auth.uid()::text, v_role)
    on conflict ("node_id", "principal_type", "principal_id") do update set "role" = excluded."role", "access_request" = false;
    end if;
    if drive_move.rank is null then
      select max(x."rank") into v_last from "better_supabase"."drive_nodes" x
      where x."tenant_id" = v_node."tenant_id" and x."parent_id" is not distinct from drive_move.parent and x."deleted_at" is null;
    end if;
    update "better_supabase"."drive_nodes" x set "parent_id" = drive_move.parent, "name" = v_name, "rank" = coalesce(drive_move.rank, case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end), "updated_at" = now()
    where x."id" = v_node."id"
    returning * into v_node;
    perform "better_supabase".emit_event('drive_node.moved', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'parentId', v_node."parent_id", 'previousParentId', v_previous), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.moved',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'moved',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'parentId', v_node."parent_id", 'previousParentId', v_previous)
  );
  elsif drive_move.rank is not null then
    update "better_supabase"."drive_nodes" x set "rank" = drive_move.rank, "updated_at" = now()
    where x."id" = v_node."id"
    returning * into v_node;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_drive_node_move"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_node."id";
    end if;
  end;
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_node_held (
  node uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select exists (
    select 1 from "better_supabase"."drive_nodes" h
    where (h."id" in (select s.node_id from "better_supabase"."drive_subtree"(drive_node_held.node) s)
        or h."id" = any ("better_supabase"."drive_ancestors"(drive_node_held.node)))
      and h."legal_hold_expires_at" is not null and h."legal_hold_expires_at" > now()
  )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_node_json (
  node better_supabase.drive_nodes
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', ($1)."id", 'organizationId', ($1)."tenant_id", 'driveId', null, 'parentId', ($1)."parent_id", 'kind', ($1)."kind", 'name', ($1)."name", 'rank', ($1)."rank", 'source', ($1)."source", 'externalId', ($1)."external_id", 'externalMetadata', ($1)."external_metadata", 'legalHoldUntil', ($1)."legal_hold_expires_at", 'lockedBy', case when ($1)."lock_expires_at" > now() then ($1)."locked_by" end, 'lockedUntil', case when ($1)."lock_expires_at" > now() then ($1)."lock_expires_at" end, 'lockNote', case when ($1)."lock_expires_at" > now() then ($1)."lock_note" end, 'downloadBlocked', ($1)."download_blocked", 'previewPages', ($1)."preview_pages", 'createdBy', ($1)."created_by", 'createdAt', ($1)."created_at", 'updatedAt', ($1)."updated_at", 'deletedAt', ($1)."deleted_at", 'attachmentId', ($1)."attachment_id", 'file', (select jsonb_build_object('mimeType', fa."mime_type", 'size', fa."size", 'status', fa."status", 'uploadedAt', fa."uploaded_at") from "better_supabase"."attachments" fa where fa."id" = ($1)."attachment_id"), 'labels', (select coalesce(jsonb_agg(jsonb_build_object('id', lt."id", 'name', lt."name", 'color', lt."color") order by lt."rank" collate "C", lt."name", lt."id"), '[]'::jsonb)
      from "better_supabase"."taggings" lg join "better_supabase"."tags" lt on lt."id" = lg."tag_id"
      where lg."subject_type" = 'drive_node' and lg."subject_id" = ($1)."id"::text), 'approval', (select jsonb_build_object('id', lr."id", 'status', lr."status", 'createdAt', lr."created_at", 'decidedAt', lr."decided_at")
      from "better_supabase"."approval_requests" lr
      where lr."subject_type" = 'drive_node' and lr."subject_id" = ($1)."id"::text and lr."action" = 'approve'
        and lr."payload" ->> 'attachmentId' = ($1)."attachment_id"::text
      order by lr."created_at" desc, lr."id" limit 1), 'document', case when ($1)."document_status" is null then null else jsonb_build_object('number', ($1)."document_number", 'type', ($1)."document_type", 'status', ($1)."document_status", 'ownerId', ($1)."document_owner_id", 'effectiveVersionId', ($1)."effective_version_id", 'effectiveVersion', (select r."number" from "better_supabase"."versions" r where r."id" = ($1)."effective_version_id"), 'effectiveAttachmentId', (select (r."content" ->> 'attachmentId')::uuid from "better_supabase"."versions" r where r."id" = ($1)."effective_version_id"), 'effectiveFrom', ($1)."effective_at", 'reviewIntervalMonths', ($1)."review_interval_months", 'nextReviewOn', ($1)."next_review_on", 'reviewDue', coalesce(($1)."document_status" = 'effective' and ($1)."next_review_on" <= current_date, false), 'effectiveOnly', not "better_supabase"."drive_can"(($1)."id", 'editor')) end)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_release_hold (
  node uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_release_hold.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'owner')) then
    raise exception 'not allowed to release a legal hold' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  update "better_supabase"."drive_nodes" x set "legal_hold_expires_at" = null, "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  perform "better_supabase".emit_event('drive_node.hold_released', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.hold_released',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'released',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text)
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_rename (
  node     uuid,
  name     text,
  conflict text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_previous text;
  v_name text := "better_supabase"."drive_clean_name"(drive_rename.name);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_rename.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to rename this item' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if (v_node."lock_expires_at" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."lock_expires_at")::text;
  end if;
  if v_name = v_node."name" then
    return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
  end if;
  v_name := "better_supabase"."drive_free_name"(v_node."tenant_id", null, v_node."parent_id", v_name, v_node."id",
    case when "better_supabase"."drive_conflict"(drive_rename.conflict) = 'rename' then 'rename' else 'fail' end);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_drive_node_rename"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_node."id", v_name;
    end if;
  end;
  v_previous := v_node."name";
  update "better_supabase"."drive_nodes" x set "name" = v_name, "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  perform "better_supabase".emit_event('drive_node.renamed', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'name', v_node."name", 'previousName', v_previous), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.renamed',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'renamed',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'name', v_node."name", 'previousName', v_previous)
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_drive_node_rename"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_node."id";
    end if;
  end;
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_restore_revision (
  node    uuid,
  version uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_content jsonb;
  v_file "better_supabase"."attachments"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_restore_revision.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to change this file' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if (v_node."lock_expires_at" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."lock_expires_at")::text;
  end if;
  select r."content" into v_content from "better_supabase"."versions" r
  where r."id" = drive_restore_revision.version
    and r."subject_type" = 'drive_node' and r."subject_id" = v_node."id"::text;
  if v_content is null or v_content ->> 'attachmentId' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'revision not found' using errcode = 'P0002', hint = 'DRIVE_REVISION_NOT_FOUND';
  end if;
  select * into v_file from "better_supabase"."attachments" f where f."id" = (v_content ->> 'attachmentId')::uuid;
  if not found then
    raise exception 'the revision''s file was pruned' using errcode = 'P0002', hint = 'DRIVE_REVISION_NOT_FOUND';
  end if;
  update "better_supabase"."drive_nodes" x set "attachment_id" = v_file."id", "preview_pages" = null, "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  perform "better_supabase"."version_insert"(v_node."tenant_id", 'drive_node', v_node."id"::text,
    v_content, v_file."bucket" || '/' || v_file."object_path", null, 'restore', false, auth.uid());
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_trash (
  node uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_batch uuid := gen_random_uuid();
  v_count integer := 0;
  v_child record;
  v_id uuid;
  v_locked "better_supabase"."drive_nodes"%rowtype;
begin
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_trash.node and x."deleted_at" is null;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to move this item to the bin' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if "better_supabase"."drive_node_held"(v_node."id") then
    raise exception 'this item is under a legal hold' using errcode = '42501', hint = 'DRIVE_HELD';
  end if;
  select * into v_locked from "better_supabase"."drive_nodes" lk
  where lk."id" in (select s.node_id from "better_supabase"."drive_subtree"(v_node."id") s)
    and (lk."lock_expires_at" > now() and lk."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))
  limit 1;
  if found then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_locked."locked_by", 'lockedUntil', v_locked."lock_expires_at")::text;
  end if;
  for v_child in
    select s.node_id, s.depth from "better_supabase"."drive_subtree"(v_node."id") s
    join "better_supabase"."drive_nodes" x on x."id" = s.node_id
    where x."deleted_at" is null
    order by s.depth
  loop
    v_count := v_count + "better_supabase"."trash_cascade"(v_node."tenant_id", 'drive_node', v_child.node_id::text, v_batch, v_child.depth, auth.uid());
  end loop;
  select i."id" into v_id from "better_supabase"."trash_items" i
  where i."subject_type" = 'drive_node' and i."subject_id" = v_node."id"::text;
  return jsonb_build_object('id', v_id, 'batchId', v_batch, 'count', v_count);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_unlock (
  node  uuid,
  force boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_holder uuid;
  v_forced boolean := false;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_unlock.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."lock_expires_at" is null or v_node."lock_expires_at" <= now() then
    if v_node."locked_by" is not null then
      update "better_supabase"."drive_nodes" x set "locked_by" = null, "lock_expires_at" = null, "lock_note" = null
      where x."id" = v_node."id"
      returning * into v_node;
    end if;
    return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
  end if;
  v_holder := v_node."locked_by";
  if v_holder is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    if not coalesce(drive_unlock.force, false) then
      raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."lock_expires_at")::text;
    end if;
    if not "better_supabase"."drive_can"(v_node."id", 'owner') then
      raise exception 'not allowed to break someone else''s lock' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
    end if;
    v_forced := true;
  end if;
  update "better_supabase"."drive_nodes" x set "locked_by" = null, "lock_expires_at" = null, "lock_note" = null, "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  perform "better_supabase".emit_event('drive_node.unlocked', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'lockedBy', v_holder::text, 'forced', v_forced), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.unlocked',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'checked in',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'lockedBy', v_holder::text, 'forced', v_forced)
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_upload_revision (
  node      uuid,
  mime_type text,
  size      bigint
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_attachment jsonb;
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_upload_revision.node and x."deleted_at" is null;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer') or "better_supabase"."drive_uploaded_own"(v_node."id")) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor') or "better_supabase"."drive_uploaded_own"(v_node."id")) then
    raise exception 'not allowed to change this file' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if (v_node."lock_expires_at" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."lock_expires_at")::text;
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'a folder has no content' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  v_attachment := "better_supabase"."create_attachment"(v_node."tenant_id", v_node."name", drive_upload_revision.mime_type, drive_upload_revision.size, 'drive_node', v_node."id"::text);
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    return jsonb_build_object('id', v_node."id", 'attachment', v_attachment);
  end if;
  return jsonb_build_object('node', "better_supabase"."drive_node_json"(v_node), 'attachment', v_attachment);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.due_organization_deletions (
  max_rows integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(to_jsonb(x.*) order by x."purge_at"), '[]'::jsonb)
  from (
    select * from "better_supabase"."organization_deletions" y
    where y."purge_at" <= now() and y."cancelled_at" is null and y."purged_at" is null
    order by y."purge_at"
    limit greatest(1, least(due_organization_deletions.max_rows, 1000))
  ) x
$function$;

CREATE OR REPLACE FUNCTION better_supabase.expire_consents()
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."consents";
  v_purpose "better_supabase"."consent_purposes";
  v_count integer := 0;
begin
  for v_row in
    update "better_supabase"."consents" x set "status" = 'expired'
    where x."status" = 'granted' and x."expires_at" <= now()
    returning x.*
  loop
    select * into v_purpose from "better_supabase"."consent_purposes" y where y."id" = v_row."purpose_id";
    perform "better_supabase".emit_event('consent.expired', jsonb_build_object('organizationId', v_row."tenant_id", 'consentId', v_row."id", 'purposeId', v_row."purpose_id", 'purposeKey', v_purpose."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'givenBy', v_row."given_by"), 'consents/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/consents');
  perform better_supabase.audit_event(
    event_type => 'consent.expired',
    category => 'data',
    target_type => 'consent',
    record_id => v_row."id"::text,
    target_label => v_purpose."title",
    summary => 'a consent expired',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'consentId', v_row."id", 'purposeId', v_row."purpose_id", 'purposeKey', v_purpose."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'givenBy', v_row."given_by")
  );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.finish_import_run (
  run uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_run_id uuid := finish_import_run.run;
  v_run "better_supabase"."import_runs";
  v_entity text;
  v_missing integer;
  v_total integer := 0;
  v_counts jsonb;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id for update;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  v_counts := v_run."counts";

  if v_run."full" then
    for v_entity in select k.key from jsonb_object_keys(v_run."counts") k(key) loop
      select count(*)::integer into v_missing from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."entity" = v_entity
        and x."role" = 'primary' and x."last_run_id" <> v_run_id
        and x."scope" in (select y."scope" from "better_supabase"."import_records" y where y."tenant_id" = v_run."tenant_id" and y."source" = v_run."source" and y."entity" = v_entity and y."last_run_id" = v_run_id);
      if not v_run."dry_run" then
        update "better_supabase"."import_records" x set "went_missing_at" = coalesce(x."went_missing_at", now())
        where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."entity" = v_entity
          and x."last_run_id" <> v_run_id
          and x."scope" in (select y."scope" from "better_supabase"."import_records" y where y."tenant_id" = v_run."tenant_id" and y."source" = v_run."source" and y."entity" = v_entity and y."last_run_id" = v_run_id);
      end if;
      v_counts := jsonb_set(v_counts, array[v_entity, 'missing'], to_jsonb(v_missing));
    end loop;
  end if;

  update "better_supabase"."import_runs" r set "status" = 'completed', "finished_at" = now(), "counts" = v_counts
  where r."id" = v_run_id;

  if not v_run."dry_run" then
    for v_entity in select k.key from jsonb_object_keys(v_counts) k(key) loop
      v_total := v_total + coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0) + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0);
      perform "better_supabase".emit_event('import.entity_completed', jsonb_build_object('organizationId', v_run."tenant_id", 'id', v_run_id, 'entity', v_entity, 'counts', v_counts -> v_entity), 'imports/' || v_run_id::text, (v_run."tenant_id")::text, null, 'better-supabase/imports');
      if coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0) + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0) > 0 then
        perform better_supabase.audit_event(
    event_type => 'import.entity_completed',
    category => 'integration',
    target_type => 'import',
    record_id => v_run_id::text,
    target_label => v_entity,
    summary => 'imported ' || v_entity,
    tenant => (v_run."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_run."tenant_id", 'id', v_run_id, 'entity', v_entity, 'counts', v_counts -> v_entity),
    idempotency_key => 'import:' || v_run_id::text || ':' || v_entity,
    actor_kind => 'integration',
    correlation_id => 'import:' || v_run_id::text
  );
      end if;
    end loop;
    perform "better_supabase".emit_event('import.completed', jsonb_build_object('organizationId', v_run."tenant_id", 'id', v_run_id, 'count', v_total), 'imports/' || v_run_id::text, (v_run."tenant_id")::text, null, 'better-supabase/imports');
  end if;
  return v_counts;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_pass (
  pass_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."passes"%rowtype;
begin
  select * into v_row from "better_supabase"."passes" x where x."id" = get_pass.pass_id;
  if not found or not (coalesce(v_row."holder_user_id" = auth.uid(), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'passes.manage'), false))) then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'kind', v_row."kind", 'holderUserId', v_row."holder_user_id", 'holderName', v_row."holder_name", 'holderEmail', v_row."holder_email", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'bookingId', v_row."booking_id", 'resourceId', v_row."resource_id", 'usesAllowed', v_row."uses_allowed", 'uses', v_row."uses", 'validFrom', v_row."starts_at", 'validUntil', v_row."expires_at", 'status', v_row."status", 'issuedBy', v_row."issued_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'revokedAt', v_row."revoked_at") || jsonb_build_object('nonce', v_row."nonce");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.hit_rate_limit (
  scope           text,
  key             text,
  max_requests    integer  DEFAULT NULL::integer,
  period          interval DEFAULT NULL::interval,
  organization_id uuid     DEFAULT NULL::uuid
)
  RETURNS TABLE (
    allowed     boolean,
    remaining   integer,
    retry_after integer
  )
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  rule "better_supabase"."rate_limit_rules";
  limit_max integer;
  limit_period interval;
  used integer;
  started timestamptz;
begin
  select * into rule from "better_supabase"."rate_limit_rules" r
  where r."scope" = hit_rate_limit.scope
    and (r."organization_id" is null or r."organization_id" = hit_rate_limit.organization_id)
  order by (r."organization_id" is null)
  limit 1;
  limit_max := coalesce(max_requests, rule."max_requests");
  limit_period := coalesce(period, rule."period");
  if limit_max is null or limit_period is null then
    raise exception 'No rate limit for %: call set_rate_limit or pass max_requests and period', scope
      using errcode = '22023', hint = 'RATE_LIMIT_UNKNOWN';
  end if;
  insert into "better_supabase"."rate_limits" as l ("scope", "key", "window_started_at", "hits", "period")
  values (scope, key, now(), 1, limit_period)
  on conflict on constraint rate_limits_pkey do update set
    "window_started_at" = case when l."window_started_at" + limit_period <= now() then now() else l."window_started_at" end,
    "hits" = case when l."window_started_at" + limit_period <= now() then 1 else l."hits" + 1 end,
    "period" = limit_period
  returning l."hits", l."window_started_at" into used, started;
  return query select
    used <= limit_max,
    greatest(limit_max - used, 0),
    case when used <= limit_max then 0
      else greatest(1, ceil(extract(epoch from started + limit_period - now()))::integer) end;
end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.idle_ai_sandboxes (
  batch         integer DEFAULT 50,
  lease_seconds integer DEFAULT 300
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_rows jsonb;
begin
  with due as (
    select y."id" from "better_supabase"."ai_sandboxes" y
    where ((y."status" = 'running' and (y."last_used_at" + make_interval(secs => y."idle_seconds") <= now() or y."expires_at" <= now()))
       or (y."status" = 'stopping' and y."updated_at" <= now() - make_interval(secs => greatest(idle_ai_sandboxes.lease_seconds, 1))))
      and not exists (
        select 1 from "better_supabase"."ai_harness_sessions" z
        where z."chat_id" = y."chat_id" and z."harness_id" = y."harness_id" and z."lock_expires_at" > now()
      )
    order by y."last_used_at"
    limit least(greatest(idle_ai_sandboxes.batch, 1), 500)
    for update skip locked
  ), claimed as (
    update "better_supabase"."ai_sandboxes" x set "status" = 'stopping', "updated_at" = now()
    from due where x."id" = due."id"
    returning x.*
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', claimed."id", 'organization_id', claimed."organization_id", 'user_id', claimed."user_id", 'chat_id', claimed."chat_id", 'harness_id', claimed."harness_id", 'provider', claimed."provider", 'sandbox_id', claimed."sandbox_id", 'container_id', claimed."container_id", 'status', claimed."status", 'metadata', claimed."metadata", 'idle_seconds', claimed."idle_seconds", 'error', claimed."error", 'last_used_at', claimed."last_used_at", 'expires_at', claimed."expires_at", 'stopped_at', claimed."stopped_at", 'created_at', claimed."created_at", 'updated_at', claimed."updated_at")), '[]') into v_rows from claimed;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_apply_batch (
  run    uuid,
  entity text,
  items  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_run_id uuid := import_apply_batch.run;
  v_entity text := import_apply_batch.entity;
  v_items jsonb := import_apply_batch.items;
  v_run "better_supabase"."import_runs";
  v_item jsonb;
  v_call jsonb;
  v_key text;
  v_scope text;
  v_data jsonb;
  v_hash text;
  v_rec "better_supabase"."import_records";
  v_other text;
  v_found boolean;
  v_done boolean;
  v_subject_id text;
  v_subject_type text;
  v_current timestamptz;
  v_out jsonb;
  v_subjects jsonb;
  v_subject jsonb;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
  v_conflicted integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_message text;
  v_hint text;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id;
  if v_entity <> all (array['attachment', 'data_lifecycle_row', 'field_value', 'supplier_item', 'product_identifier', 'discount_group', 'discount_rule', 'stock_count', 'order', 'payment_term', 'document_delivery_preference', 'quote', 'invoice', 'credit_note', 'open_item', 'accounting_account', 'accounting_journal', 'accounting_entry', 'accounting_opening_balance', 'tax_code', 'tax_rate', 'document_template', 'document_text_block', 'customer']::text[]) then
    raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';
  end if;
  if jsonb_typeof(v_items) <> 'array' then
    raise exception 'items must be an array of { key, scope, data, refs }' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  for v_item in select e.value from jsonb_array_elements(v_items) e loop
    v_key := v_item ->> 'key';
    v_scope := coalesce(v_item ->> 'scope', '');
    v_data := v_item -> 'data';

    if v_key is null or v_key = '' or jsonb_typeof(v_data) is distinct from 'object' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', 'IMPORT_ITEM_INVALID', 'message', 'an item needs a key and a data object'));
      continue;
    end if;

    -- jsonb text is key-ordered, so equal content hashes equally.
    v_hash := encode(extensions.digest(v_data::text, 'sha256'), 'hex');

    begin
      v_done := false;
      select * into v_rec from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_scope
        and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary';
      v_found := found;

      if not v_found then
        -- A cloned administration reuses the subjects of the scope it aliases
        -- when the content is equal there.
        for v_other in
          select a."of" from jsonb_to_recordset(v_run."scope_aliases") as a(scope text, "of" text, entities jsonb)
          where a.scope = v_scope
            and (a.entities is null or jsonb_typeof(a.entities) <> 'array' or jsonb_array_length(a.entities) = 0 or a.entities ? v_entity)
        loop
          if exists (
            select 1 from "better_supabase"."import_records" x
            where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_other
              and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary' and x."content_hash" = v_hash
          ) then
            insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_imported_updated_at")
            select x."tenant_id", x."source", v_scope, x."entity", x."external_key", x."role", x."subject_type", x."subject_id", x."content_hash", v_run_id, v_run_id, x."subject_imported_updated_at"
            from "better_supabase"."import_records" x
            where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_other
              and x."entity" = v_entity and x."external_key" = v_key
            on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do nothing;
            v_unchanged := v_unchanged + 1;
            v_done := true;
            exit;
          end if;
        end loop;
      elsif v_rec."content_hash" = v_hash then
        update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "went_missing_at" = null
        where x."tenant_id" = v_rec."tenant_id" and x."source" = v_rec."source" and x."scope" = v_rec."scope"
          and x."entity" = v_rec."entity" and x."external_key" = v_rec."external_key"
          and (x."last_run_id" is distinct from v_run_id or x."went_missing_at" is not null);
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        -- A row a user changed after the last import stays as it is.
        v_current := null;
        case v_entity
        when 'supplier_item' then
          v_current := "better_supabase"."supplier_item_updated_at"(v_rec."subject_id");
        when 'product_identifier' then
          v_current := "better_supabase"."product_identifier_updated_at"(v_rec."subject_id");
        when 'discount_group' then
          v_current := "better_supabase"."discount_group_updated_at"(v_rec."subject_id");
        when 'discount_rule' then
          v_current := "better_supabase"."discount_rule_updated_at"(v_rec."subject_id");
        when 'stock_count' then
          v_current := "better_supabase"."stock_count_updated_at"(v_rec."subject_id");
        when 'order' then
          v_current := "better_supabase"."order_updated_at"(v_rec."subject_id");
        when 'payment_term' then
          v_current := "better_supabase"."payment_term_updated_at"(v_rec."subject_id");
        when 'document_delivery_preference' then
          v_current := "better_supabase"."document_delivery_preference_updated_at"(v_rec."subject_id");
        when 'quote' then
          v_current := "better_supabase"."quote_updated_at"(v_rec."subject_id");
        when 'invoice' then
          v_current := "better_supabase"."invoice_updated_at"(v_rec."subject_id");
        when 'credit_note' then
          v_current := "better_supabase"."invoice_updated_at"(v_rec."subject_id");
        when 'open_item' then
          v_current := "better_supabase"."invoice_updated_at"(v_rec."subject_id");
        when 'tax_code' then
          v_current := "better_supabase"."tax_code_updated_at"(v_rec."subject_id");
        when 'document_template' then
          v_current := "better_supabase"."document_template_updated_at"(v_rec."subject_id");
        when 'document_text_block' then
          v_current := "better_supabase"."document_text_block_updated_at"(v_rec."subject_id");
        when 'customer' then
          v_current := "public"."import_customer_updated_at"(v_rec."subject_id");
          else null;
        end case;
        if v_current is not null and v_rec."subject_imported_updated_at" is not null and v_current > v_rec."subject_imported_updated_at" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "went_missing_at" = null
          where x."id" = v_rec."id";
          v_conflicted := v_conflicted + 1;
          v_done := true;
        end if;
      end if;

      if not v_done then
        v_subject_id := case when v_found then v_rec."subject_id" else null end;
        v_call := v_item || jsonb_build_object('tenant', v_run."tenant_id", 'scope', v_scope);
        case v_entity
      when 'attachment' then
        v_subject_type := 'attachment';
        v_out := "better_supabase"."import_attachment"(v_run_id, v_call, v_subject_id);
      when 'data_lifecycle_row' then
        v_subject_type := 'data_lifecycle_row';
        v_out := "better_supabase"."restore_data_row"(v_run_id, v_call, v_subject_id);
      when 'field_value' then
        v_subject_type := 'field_value';
        v_out := "better_supabase"."import_field_value"(v_run_id, v_call, v_subject_id);
      when 'supplier_item' then
        v_subject_type := 'supplier_item';
        v_out := "better_supabase"."import_supplier_item"(v_run_id, v_call, v_subject_id);
      when 'product_identifier' then
        v_subject_type := 'product_identifier';
        v_out := "better_supabase"."import_product_identifier"(v_run_id, v_call, v_subject_id);
      when 'discount_group' then
        v_subject_type := 'discount_group';
        v_out := "better_supabase"."import_discount_group"(v_run_id, v_call, v_subject_id);
      when 'discount_rule' then
        v_subject_type := 'discount_rule';
        v_out := "better_supabase"."import_discount_rule"(v_run_id, v_call, v_subject_id);
      when 'stock_count' then
        v_subject_type := 'stock_count';
        v_out := "better_supabase"."import_stock_count"(v_run_id, v_call, v_subject_id);
      when 'order' then
        v_subject_type := 'order';
        v_out := "better_supabase"."import_order"(v_run_id, v_call, v_subject_id);
      when 'payment_term' then
        v_subject_type := 'payment_term';
        v_out := "better_supabase"."import_payment_term"(v_run_id, v_call, v_subject_id);
      when 'document_delivery_preference' then
        v_subject_type := 'document_delivery_preference';
        v_out := "better_supabase"."import_document_delivery_preference"(v_run_id, v_call, v_subject_id);
      when 'quote' then
        v_subject_type := 'quote';
        v_out := "better_supabase"."import_quote"(v_run_id, v_call, v_subject_id);
      when 'invoice' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_invoice"(v_run_id, v_call, v_subject_id);
      when 'credit_note' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_credit_note"(v_run_id, v_call, v_subject_id);
      when 'open_item' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_open_item"(v_run_id, v_call, v_subject_id);
      when 'accounting_account' then
        v_subject_type := 'accounting_account';
        v_out := "better_supabase"."import_accounting_account"(v_run_id, v_call, v_subject_id);
      when 'accounting_journal' then
        v_subject_type := 'accounting_journal';
        v_out := "better_supabase"."import_accounting_journal"(v_run_id, v_call, v_subject_id);
      when 'accounting_entry' then
        v_subject_type := 'accounting_entry';
        v_out := "better_supabase"."import_accounting_entry"(v_run_id, v_call, v_subject_id);
      when 'accounting_opening_balance' then
        v_subject_type := 'accounting_opening_balance';
        v_out := "better_supabase"."import_accounting_opening_balance"(v_run_id, v_call, v_subject_id);
      when 'tax_code' then
        v_subject_type := 'tax_code';
        v_out := "better_supabase"."import_tax_code"(v_run_id, v_call, v_subject_id);
      when 'tax_rate' then
        v_subject_type := 'tax_rate';
        v_out := "better_supabase"."import_tax_rate"(v_run_id, v_call, v_subject_id);
      when 'document_template' then
        v_subject_type := 'document_template';
        v_out := "better_supabase"."import_document_template"(v_run_id, v_call, v_subject_id);
      when 'document_text_block' then
        v_subject_type := 'document_text_block';
        v_out := "better_supabase"."import_document_text_block"(v_run_id, v_call, v_subject_id);
      when 'customer' then
        v_subject_type := 'customer';
        v_out := "public"."import_customer"(v_run_id, v_call, v_subject_id);
      else
        raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';
    end case;

        v_subjects := case jsonb_typeof(v_out) when 'array' then v_out else jsonb_build_array(v_out) end;
        if not exists (
          select 1 from jsonb_array_elements(v_subjects) s
          where coalesce(s.value ->> 'role', 'primary') = 'primary' and nullif(s.value ->> 'subjectId', '') is not null
        ) then
          raise exception 'the import target returned no primary subject' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
        end if;

        for v_subject in select s.value from jsonb_array_elements(v_subjects) s loop
          if jsonb_typeof(v_subject -> 'warnings') = 'array' then
            v_warnings := v_warnings || (select coalesce(jsonb_agg(w.value || jsonb_build_object('entity', v_entity, 'key', v_key)), '[]'::jsonb) from jsonb_array_elements(v_subject -> 'warnings') w);
          end if;
          insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_imported_updated_at", "went_missing_at")
          values (
            v_run."tenant_id", v_run."source", v_scope, v_entity, v_key,
            coalesce(v_subject ->> 'role', 'primary'),
            coalesce(v_subject ->> 'subjectType', v_subject_type),
            v_subject ->> 'subjectId',
            v_hash, v_run_id, v_run_id,
            coalesce((v_subject ->> 'updatedAt')::timestamptz, now()),
            null
          )
          on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do update set
            "subject_type" = excluded."subject_type",
            "subject_id" = excluded."subject_id",
            "content_hash" = excluded."content_hash",
            "last_run_id" = excluded."last_run_id",
            "subject_imported_updated_at" = excluded."subject_imported_updated_at",
            "went_missing_at" = null;
        end loop;

        if v_found then
          v_updated := v_updated + 1;
        else
          v_inserted := v_inserted + 1;
        end if;
      end if;
    exception when others then
      get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint;
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), 'message', v_message));
    end;
  end loop;

  return jsonb_build_object('inserted', v_inserted, 'updated', v_updated, 'unchanged', v_unchanged, 'conflicted', v_conflicted, 'errors', v_errors) || case when jsonb_array_length(v_warnings) > 0 then jsonb_build_object('warnings', v_warnings) else '{}'::jsonb end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_calendar_events (
  calendar_id uuid,
  source      jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_item jsonb;
  v_id uuid;
  v_master uuid;
  v_created integer := 0;
  v_updated integer := 0;
  v_skipped integer := 0;
begin
  for v_item in
    select value from jsonb_array_elements(coalesce(import_calendar_events.source -> 'events', '[]'::jsonb))
    order by value ? 'originalStart', value ->> 'uid'
  loop
    v_id := null;
    if v_item ->> 'originalStart' is null then
      select "id" into v_id from "better_supabase"."calendar_events"
        where "calendar_id" = import_calendar_events.calendar_id and "uid" = v_item ->> 'uid' and "original_starts_at" is null;
    else
      select "id" into v_master from "better_supabase"."calendar_events"
        where "calendar_id" = import_calendar_events.calendar_id and "uid" = v_item ->> 'uid' and "original_starts_at" is null and "rrule" is not null;
      if v_master is null then
        v_skipped := v_skipped + 1;
        continue;
      end if;
      select "id" into v_id from "better_supabase"."calendar_events"
        where "calendar_id" = import_calendar_events.calendar_id and "uid" = v_item ->> 'uid'
          and "original_starts_at" = (v_item ->> 'originalStart')::timestamptz;
      v_item := v_item || jsonb_build_object('recurrenceId', v_master);
    end if;
    if v_id is null then
      perform "better_supabase"."save_calendar_event"(import_calendar_events.calendar_id, v_item - 'id');
      v_created := v_created + 1;
    else
      perform "better_supabase"."save_calendar_event"(import_calendar_events.calendar_id, (v_item - 'recurrenceId' - 'originalStart') || jsonb_build_object('id', v_id));
      v_updated := v_updated + 1;
    end if;
  end loop;
  return jsonb_build_object('created', v_created, 'updated', v_updated, 'skipped', v_skipped);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inbox_add_message (
  conversation uuid,
  input        jsonb,
  author_type  text,
  author       uuid,
  direction    text
)
  RETURNS uuid
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_inbox "better_supabase"."inboxes"%rowtype;
  v_id uuid;
  v_at timestamptz := clock_timestamp();
  v_kind text := coalesce(input ->> 'kind', 'message');
  v_body text := coalesce(input ->> 'body', '');
  v_mentions uuid[];
  v_uploads uuid[];
  v_file jsonb;
  v_moved integer;
  v_reopened boolean := false;
  v_claims text;
begin
  select * into v_conv from "better_supabase"."inbox_conversations" where "id" = inbox_add_message.conversation for update;
  select * into v_inbox from "better_supabase"."inboxes" where "id" = v_conv."inbox_id";
  if input ? 'external_id' then
    select d."message_id" into v_id from "better_supabase"."inbox_message_details" d
    where d."conversation_id" = v_conv."id" and d."external_id" = input ->> 'external_id';
    if found then
      return v_id;
    end if;
  end if;
  if v_kind not in ('message', 'note') then
    raise exception 'kind is message or note' using errcode = '22023', hint = 'INBOX_KIND_INVALID';
  end if;
  v_uploads := array(select distinct x::uuid from jsonb_array_elements_text(coalesce(input -> 'attachments', '[]'::jsonb)) x);
  if length(btrim(v_body)) = 0 and cardinality(v_uploads) = 0 and coalesce(jsonb_array_length(input -> 'files'), 0) = 0 then
    raise exception 'a message needs a body or an attachment' using errcode = '22023', hint = 'INBOX_MESSAGE_EMPTY';
  end if;
  if length(v_body) > 20000 then
    raise exception 'a message is at most 20000 characters' using errcode = '22023', hint = 'INBOX_MESSAGE_TOO_LONG';
  end if;
  select coalesce(array_agg(distinct x), '{}') into v_mentions
  from jsonb_array_elements_text(coalesce(input -> 'mentions', '[]'::jsonb)) e(raw)
  cross join lateral (select e.raw::uuid as x) u
  where coalesce(better_supabase.can_user(u.x, 'tenant', v_conv."tenant_id", 'inbox.read'), false);
  insert into "better_supabase"."messages" ("tenant_id", "conversation_id", "author_id", "kind", "body", "mentions", "sent_at", "created_at")
  values (v_conv."tenant_id", v_conv."id", inbox_add_message.author, v_kind, v_body, v_mentions, v_at, v_at)
  returning "id" into v_id;
  perform "better_supabase"."index_record_mentions"(v_id);
  insert into "better_supabase"."inbox_message_details" ("message_id", "tenant_id", "conversation_id", "direction", "author_type", "format", "external_id", "reply_to", "metadata")
  values (
    v_id, v_conv."tenant_id", v_conv."id", inbox_add_message.direction, inbox_add_message.author_type,
    coalesce(input ->> 'format', 'text'), input ->> 'external_id', (input ->> 'reply_to')::uuid, coalesce(input -> 'metadata', '{}'::jsonb)
  );
  if cardinality(v_uploads) > 0 then
    update "better_supabase"."attachments" x set "subject_type" = 'message', "subject_id" = v_id::text
    where x."id" = any (v_uploads)
      and x."organization_id" = v_conv."tenant_id"
      and x."subject_type" = 'conversation' and x."subject_id" = v_conv."id"::text
      and x."status" <> 'infected'
      and (inbox_add_message.author is null or x."uploaded_by" = inbox_add_message.author);
    get diagnostics v_moved = row_count;
    if v_moved <> cardinality(v_uploads) then
      raise exception 'attachments must be your uploads to this conversation' using errcode = '22023', hint = 'INBOX_ATTACHMENT_INVALID';
    end if;
  end if;
  for v_file in select f from jsonb_array_elements(coalesce(input -> 'files', '[]'::jsonb)) f loop
    insert into "better_supabase"."attachments" ("organization_id", "subject_type", "subject_id", "name", "mime_type", "size", "uploaded_by", "scan_detail")
    values (
      v_conv."tenant_id", 'message', v_id::text,
      left(coalesce(nullif(v_file ->> 'name', ''), 'file'), 255),
      lower(coalesce(nullif(v_file ->> 'content_type', ''), 'application/octet-stream')),
      coalesce((v_file ->> 'size')::bigint, 0),
      null,
      jsonb_build_object('source', v_file)::text
    );
  end loop;
  if inbox_add_message.author is not null then
    insert into "better_supabase"."conversation_members" ("conversation_id", "tenant_id", "user_id")
    values (v_conv."id", v_conv."tenant_id", inbox_add_message.author)
    on conflict do nothing;
  end if;
  if v_kind = 'message' then
    v_reopened := inbox_add_message.direction = 'inbound' and v_conv."status" in ('resolved', 'snoozed');
    update "better_supabase"."inbox_conversations" set
      "last_message_at" = v_at,
      "last_inbound_at" = case when inbox_add_message.direction = 'inbound' then v_at else "last_inbound_at" end,
      "last_message_preview" = left(v_body, 140),
      "first_response_at" = case
        when "first_response_at" is null and inbox_add_message.direction = 'outbound' and inbox_add_message.author_type in ('agent', 'bot') then v_at
        else "first_response_at" end,
      "status" = case when v_reopened then 'open' else "status" end,
      "snooze_expires_at" = case when v_reopened then null else "snooze_expires_at" end,
      "resolved_at" = case when v_reopened then null else "resolved_at" end
    where "id" = v_conv."id"
    returning * into v_conv;
    if v_reopened then
      insert into "better_supabase"."inbox_conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'reopened', (select auth.uid()), jsonb_build_object('by', 'contact'));
      perform "better_supabase".emit_event('inbox_conversation.reopened', jsonb_build_object('conversationId', v_conv."id", 'organizationId', v_conv."tenant_id"::text, 'inboxId', v_conv."inbox_id", 'contactId', v_conv."contact_id", 'assigneeId', v_conv."assignee_id", 'status', v_conv."status"), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id")::text, null, 'better-supabase/inbox');
    end if;
  end if;
  if v_kind = 'message' and inbox_add_message.direction = 'inbound' then
    perform "better_supabase".emit_event('inbox_message.received', jsonb_build_object('conversationId', v_conv."id", 'organizationId', v_conv."tenant_id"::text, 'messageId', v_id, 'inboxId', v_conv."inbox_id", 'contactId', v_conv."contact_id"), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id")::text, 'inbox_message.received:' || v_id::text, 'better-supabase/inbox');
    if v_conv."bot_mode" = 'bot' then
      perform "better_supabase"."enqueue_job"(queue => 'inbox_bot', payload => jsonb_build_object('conversation_id', v_conv."id", 'message_id', v_id, 'thread_id', v_conv."thread_id", 'inbox_id', v_conv."inbox_id"), dedupe_key => 'inbox:' || v_conv."id"::text, dedupe_running => false);
    end if;
  if better_supabase.import_run() is null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'inbox.message',
      'tenant', v_conv."tenant_id",
      'subject_type', 'conversation',
      'subject_id', v_conv."id"::text,
      'summary', left(v_body, 140),
      'recipients', case when v_conv."assignee_id" is not null then to_jsonb(array[v_conv."assignee_id"])
    else coalesce((select jsonb_agg(m."user_id") from "better_supabase"."inbox_members" m where m."inbox_id" = v_conv."inbox_id"), '[]'::jsonb) end,
      'key', 'inbox.message:' || v_id::text,
      'data', jsonb_build_object('conversationId', v_conv."id", 'messageId', v_id)
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  end if;
  if v_kind = 'message' and inbox_add_message.direction = 'outbound' and v_inbox."channel" <> 'in_app' then
    insert into "better_supabase"."inbox_message_deliveries" ("tenant_id", "message_id", "channel")
    values (v_conv."tenant_id", v_id, v_inbox."channel")
    on conflict do nothing;
    if not coalesce((input ->> 'delivered_by_caller')::boolean, false) then
      perform "better_supabase"."enqueue_job"(queue => 'inbox_outbound', payload => jsonb_build_object('message_id', v_id, 'conversation_id', v_conv."id", 'inbox_id', v_conv."inbox_id"), dedupe_key => 'inbox-out:' || v_id::text, dedupe_running => false);
    end if;
  end if;
  if cardinality(v_mentions) > 0 then
  if better_supabase.import_run() is null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'inbox.mention',
      'tenant', v_conv."tenant_id",
      'actor', inbox_add_message.author,
      'subject_type', 'conversation',
      'subject_id', v_conv."id"::text,
      'summary', left(v_body, 140),
      'recipients', to_jsonb(v_mentions),
      'key', 'inbox.mention:' || v_id::text,
      'data', jsonb_build_object('conversationId', v_conv."id", 'messageId', v_id)
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  end if;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inspection_calendar_mirror()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_calendar uuid;
begin
  select y."id" into v_calendar from "better_supabase"."calendars" y
  where y."tenant_id" = new."tenant_id" and y."name" = 'Audits'
  order by y."created_at"
  limit 1;
  if v_calendar is null then
    return new;
  end if;
  if new."planned_start" is null or new."status" not in ('planned', 'in_progress') then
    delete from "better_supabase"."calendar_events" x where x."calendar_id" = v_calendar and x."uid" = 'inspection-' || new."id"::text;
    return new;
  end if;
  insert into "better_supabase"."calendar_events" ("tenant_id", "calendar_id", "uid", "title", "starts_at", "ends_at", "all_day", "tz", "status", "subject_type", "subject_id")
  values (new."tenant_id", v_calendar, 'inspection-' || new."id"::text, new."number" || ' ' || new."title",
    (new."planned_start"::timestamp at time zone 'UTC'),
    (coalesce(new."planned_end", new."planned_start") + 1)::timestamp at time zone 'UTC', true, 'UTC', 'confirmed', 'inspection', new."id"::text)
  on conflict ("calendar_id", "uid", "original_starts_at") do update set
    "title" = excluded."title", "starts_at" = excluded."starts_at",
    "ends_at" = excluded."ends_at", "updated_at" = now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.issue_consent_receipt (
  consent_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."consents";
  v_purpose "better_supabase"."consent_purposes";
  v_receipt "better_supabase"."consent_receipts";
  v_id uuid := gen_random_uuid();
  v_issued timestamptz := now();
  v_doc jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."consents" x where x."id" = issue_consent_receipt.consent_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'consents.read'), false) and coalesce("better_supabase"."can_subject"(v_row."subject_type", v_row."subject_id", 'read'), false))
      or ((v_row."tenant_id")::text, (v_row."subject_type")::text, (v_row."subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)
      or ((v_row."tenant_id")::text, (v_row."subject_type")::text, (v_row."subject_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g)
      or exists (select 1 from "better_supabase"."relations" r
      where r."kind" = 'represents' and r."source_type" = 'person'
        and r."tenant_id"::text = (v_row."tenant_id")::text
        and r."target_type" = v_row."subject_type" and r."target_id" = (v_row."subject_id")::text
        and r."data" ->> 'authority' in ('inform', 'act')
        and (case when r."data" ->> 'valid_from' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_from', 'date') then (r."data" ->> 'valid_from')::date <= current_date
      else false end) and (case when r."data" ->> 'valid_until' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_until', 'date') then (r."data" ->> 'valid_until')::date >= current_date
      else false end)
        and ((v_row."tenant_id")::text, ('person')::text, (r."source_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g))) then
    raise exception 'no such consent' using errcode = 'P0002', hint = 'CONSENT_NOT_FOUND';
  end if;
  select * into v_receipt from "better_supabase"."consent_receipts" x where x."consent_id" = v_row."id" and x."status" = v_row."status";
  if found then
    return (v_receipt."receipt" || jsonb_build_object('digest', v_receipt."digest"));
  end if;
  select * into v_purpose from "better_supabase"."consent_purposes" x where x."id" = v_row."purpose_id";
  v_doc := jsonb_build_object(
    'format', 'better-supabase/consent-receipt@1',
    'receiptId', v_id,
    'issuedAt', v_issued,
    'organizationId', v_row."tenant_id",
    'subject', jsonb_build_object('type', v_row."subject_type", 'id', v_row."subject_id"),
    'purpose', jsonb_build_object('key', v_purpose."key", 'title', v_purpose."title", 'version', v_purpose."version", 'legalBasis', v_purpose."legal_basis"),
    'consent', jsonb_build_object('id', v_row."id", 'status', v_row."status", 'givenBy', v_row."given_by", 'grantedAt', v_row."granted_at", 'validUntil', v_row."expires_at", 'withdrawnAt', v_row."withdrawn_at", 'scope', coalesce(v_row."scope", '{}'::jsonb)),
    'evidence', jsonb_build_object(
      'signatureId', v_row."signature_id",
      'submissionId', v_row."submission_id",
      'attachmentId', v_row."attachment_id",
      'signals', (select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'kind', y."kind", 'receivedAt', y."received_at") order by y."received_at", y."id"), '[]'::jsonb) from "better_supabase"."consent_signals" y where v_row."id" = any(y."consent_ids"))
    )
  );
  insert into "better_supabase"."consent_receipts" ("id", "tenant_id", "subject_type", "subject_id", "consent_id", "status", "receipt", "digest", "issued_at")
  values (v_id, v_row."tenant_id", v_row."subject_type", v_row."subject_id", v_row."id", v_row."status", v_doc, encode(sha256(convert_to(v_doc::text, 'UTF8')), 'hex'), v_issued)
  returning * into v_receipt;
  perform "better_supabase".emit_event('consent_receipt.issued', jsonb_build_object('organizationId', v_receipt."tenant_id", 'receiptId', v_receipt."id", 'consentId', v_receipt."consent_id", 'status', v_receipt."status", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id"), 'consent-receipts/' || v_receipt."id"::text, (v_receipt."tenant_id")::text, null, 'better-supabase/consents');
  return (v_receipt."receipt" || jsonb_build_object('digest', v_receipt."digest"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.issue_pass (
  tenant       uuid,
  kind         text                     DEFAULT 'ticket'::text,
  holder_user  uuid                     DEFAULT NULL::uuid,
  holder_name  text                     DEFAULT NULL::text,
  holder_email text                     DEFAULT NULL::text,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  booking_id   uuid                     DEFAULT NULL::uuid,
  resource_id  uuid                     DEFAULT NULL::uuid,
  uses_allowed integer                  DEFAULT NULL::integer,
  starts_at    timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  expires_at   timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."passes"%rowtype;
  v_resource uuid := issue_pass.resource_id;
  v_until timestamptz := issue_pass.expires_at;
  v_booking "better_supabase"."bookings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', issue_pass.tenant, 'passes.manage'), false)) then
    raise exception 'not allowed to issue passes' using errcode = '42501', hint = 'PASS_FORBIDDEN';
  end if;
  if (issue_pass.subject_type is null) <> (issue_pass.subject_id is null) then
    raise exception 'pass both subject_type and subject_id, or neither' using errcode = '22023', hint = 'PASS_SUBJECT_INVALID';
  end if;
  if issue_pass.subject_type is not null
    and (case issue_pass.subject_type
      when 'message' then (select s."tenant_id"::text from "better_supabase"."messages" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'conversation' then (select s."tenant_id"::text from "better_supabase"."conversations" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'channel' then (select s."tenant_id"::text from "better_supabase"."channels" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'course' then (select s."tenant_id"::text from "better_supabase"."courses" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'post' then (select s."tenant_id"::text from "better_supabase"."posts" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'activity' then (select s."tenant_id"::text from "better_supabase"."activities" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'quote' then (select s."tenant_id"::text from "better_supabase"."quotes" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'invoice' then (select s."tenant_id"::text from "better_supabase"."invoices" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'rfq' then (select s."tenant_id"::text from "better_supabase"."rfqs" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'till' then (select s."tenant_id"::text from "better_supabase"."tills" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'order' then (select s."tenant_id"::text from "better_supabase"."orders" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'booking' then (select s."tenant_id"::text from "better_supabase"."bookings" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."leases" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'compliance_policy' then (select s."tenant_id"::text from "better_supabase"."compliance_policies" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'qualification_type' then (select s."tenant_id"::text from "better_supabase"."qualification_types" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'risk' then (select s."tenant_id"::text from "better_supabase"."risks" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'case' then (select s."tenant_id"::text from "better_supabase"."cases" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'inspection' then (select s."tenant_id"::text from "better_supabase"."inspections" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'inspection_program' then (select s."tenant_id"::text from "better_supabase"."inspection_programs" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'inspection_finding' then (select s."tenant_id"::text from "better_supabase"."inspection_findings" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'form' then (select s."tenant_id"::text from "better_supabase"."forms" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'meeting' then (select s."tenant_id"::text from "better_supabase"."meetings" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'meeting_decision' then (select s."tenant_id"::text from "better_supabase"."meeting_decisions" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'maintenance_plan' then (select s."tenant_id"::text from "better_supabase"."maintenance_plans" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'dam_usage_right' then (select s."tenant_id"::text from "better_supabase"."dam_usage_rights" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'lims_sample' then (select s."tenant_id"::text from "better_supabase"."lims_samples" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'tax_code' then (select s."tenant_id"::text from "better_supabase"."tax_codes" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'production_order' then (select s."tenant_id"::text from "better_supabase"."production_orders" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'work_center' then (select s."tenant_id"::text from "better_supabase"."work_centers" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'bank_account' then (select s."tenant_id"::text from "better_supabase"."bank_accounts" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'care_plan' then (select s."tenant_id"::text from "better_supabase"."care_plans" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'content_entry' then (select s."tenant_id"::text from "better_supabase"."content_entries" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'change_request' then (select s."organization_id"::text from "public"."change_requests" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (issue_pass.subject_id)::uuid)
      else null::text
    end) is distinct from issue_pass.tenant::text then
    raise exception 'the record does not exist in this organization' using errcode = 'P0002', hint = 'PASS_SUBJECT_NOT_FOUND';
  end if;
  if issue_pass.holder_user is not null and not exists (select 1 from auth.users u where u.id = issue_pass.holder_user) then
    raise exception 'the holder does not exist' using errcode = 'P0002', hint = 'PASS_HOLDER_NOT_FOUND';
  end if;
  if issue_pass.booking_id is not null then
    select * into v_booking from "better_supabase"."bookings" bk
      where bk."id" = issue_pass.booking_id and bk."tenant_id" = issue_pass.tenant;
    if not found then
      raise exception 'the booking does not exist in this organization' using errcode = 'P0002', hint = 'PASS_BOOKING_NOT_FOUND';
    end if;
    if v_booking."status" = 'cancelled' then
      raise exception 'the booking is cancelled' using errcode = '55000', hint = 'PASS_BOOKING_CANCELLED';
    end if;
    if issue_pass.resource_id is not null and issue_pass.resource_id <> v_booking."resource_id" then
      raise exception 'the booking is for another resource' using errcode = '22023', hint = 'PASS_RESOURCE_MISMATCH';
    end if;
    v_resource := v_booking."resource_id";
    v_until := coalesce(v_until, upper(v_booking."during"));
  elsif issue_pass.resource_id is not null then
    if not exists (
      select 1 from "better_supabase"."booking_resources" rs
      where rs."id" = issue_pass.resource_id and rs."tenant_id" = issue_pass.tenant
    ) then
      raise exception 'the resource does not exist in this organization' using errcode = 'P0002', hint = 'PASS_RESOURCE_NOT_FOUND';
    end if;
  end if;
  if v_until is not null and v_until <= coalesce(issue_pass.starts_at, now()) then
    raise exception 'expires_at must be after starts_at and in the future' using errcode = '22023', hint = 'PASS_VALIDITY_INVALID';
  end if;
  insert into "better_supabase"."passes" ("tenant_id", "kind", "holder_user_id", "holder_name", "holder_email", "subject_type", "subject_id", "booking_id", "resource_id", "uses_allowed", "starts_at", "expires_at", "nonce", "issued_by")
  values (issue_pass.tenant, coalesce(issue_pass.kind, 'ticket'), issue_pass.holder_user, issue_pass.holder_name, lower(btrim(issue_pass.holder_email)),
    issue_pass.subject_type, issue_pass.subject_id, issue_pass.booking_id, v_resource,
    case when issue_pass.booking_id is not null then coalesce(issue_pass.uses_allowed, 1) else issue_pass.uses_allowed end,
    coalesce(issue_pass.starts_at, now()), v_until, encode(extensions.gen_random_bytes(16), 'hex'), auth.uid())
  returning * into v_row;
  perform "better_supabase".emit_event('pass.issued', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'kind', v_row."kind", 'holderUserId', v_row."holder_user_id", 'bookingId', v_row."booking_id"), 'passes/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/passes');
  perform better_supabase.audit_event(
    event_type => 'pass.issued',
    category => 'access',
    target_type => 'pass',
    record_id => v_row."id"::text,
    summary => 'issued pass ' || v_row."kind",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'kind', v_row."kind", 'holderUserId', v_row."holder_user_id", 'bookingId', v_row."booking_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'kind', v_row."kind", 'holderUserId', v_row."holder_user_id", 'holderName', v_row."holder_name", 'holderEmail', v_row."holder_email", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'bookingId', v_row."booking_id", 'resourceId', v_row."resource_id", 'usesAllowed', v_row."uses_allowed", 'uses', v_row."uses", 'validFrom', v_row."starts_at", 'validUntil', v_row."expires_at", 'status', v_row."status", 'issuedBy', v_row."issued_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'revokedAt', v_row."revoked_at") || jsonb_build_object('nonce', v_row."nonce");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ledger_append_only()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  if tg_op = 'DELETE' and current_setting('better_supabase.purge_tenant', true) = to_jsonb(old) ->> tg_argv[0] then
    if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and exists (
      select 1 from "better_supabase"."organization_deletions" x
      where x."organization_id"::text = to_jsonb(old) ->> tg_argv[0]
        and x."cancelled_at" is null and x."purged_at" is null and x."purge_at" <= now()
    ) then
      return old;
    end if;
  end if;
  raise exception 'ledger entries and transactions can''t be changed or deleted; post a reversal' using errcode = '55000', hint = 'LEDGER_APPEND_ONLY';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_ai_task_runs (
  task_id  uuid,
  max_rows integer DEFAULT 20
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'task_id', y."task_id", 'organization_id', y."organization_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") order by y."created_at" desc), '[]')
  from (
    select * from "better_supabase"."ai_task_runs" y0 where y0."task_id" = list_ai_task_runs.task_id
    order by y0."created_at" desc limit least(greatest(list_ai_task_runs.max_rows, 1), 200)
  ) y
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_ai_tasks (
  tenant uuid,
  mine   boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'agent_id', x."agent_id", 'title', x."title", 'prompt', x."prompt", 'cron', x."cron", 'timezone', x."timezone", 'enabled', x."enabled", 'next_run_at', x."next_run_at", 'last_run_at', x."last_run_at", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('last_run', (
    select jsonb_build_object('id', y."id", 'task_id', y."task_id", 'organization_id', y."organization_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") from "better_supabase"."ai_task_runs" y where y."task_id" = x."id" order by y."created_at" desc limit 1
  )) order by x."created_at" desc), '[]')
  from "better_supabase"."ai_scheduled_tasks" x
  where x."organization_id" = list_ai_tasks.tenant and (not list_ai_tasks.mine or x."user_id" = auth.uid())
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_calendar_events (
  calendar_ids uuid[],
  range_start  timestamp with time zone,
  range_end    timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', e."id", 'calendarId', e."calendar_id", 'uid', e."uid", 'title', e."title", 'startsAt', e."starts_at", 'endsAt', e."ends_at", 'allDay', e."all_day", 'tz', e."tz", 'status', e."status", 'rrule', e."rrule", 'exdates', to_jsonb(e."exdates"), 'recurrenceId', e."recurrence_id", 'originalStart', e."original_starts_at", 'description', e."description", 'location', e."location", 'color', e."color", 'subjectType', e."subject_type", 'subjectId', e."subject_id") || jsonb_build_object('updatedAt', e."updated_at", 'kind', e."kind", 'transparency', e."transparency", 'autoDecline', e."auto_decline", 'attendees', coalesce((select jsonb_agg(jsonb_build_object('email', a."email", 'name', a."name", 'userId', a."user_id", 'role', a."role", 'response', a."response") order by a."email") from "better_supabase"."calendar_attendees" a where a."event_id" = e."id"), '[]'::jsonb), 'alarms', coalesce((select jsonb_agg(jsonb_build_object('id', l."id", 'method', l."method", 'offsetMinutes', l."offset_minutes", 'related', l."related_to", 'at', l."trigger_at", 'repeat', l."repeat_count", 'repeatMinutes', l."repeat_minutes", 'description', l."description", 'summary', l."summary") order by l."offset_minutes" nulls last, l."trigger_at", l."id") from "better_supabase"."calendar_event_alarms" l where l."event_id" = e."id" and (l."user_id" is null or l."user_id" = (select auth.uid()))), '[]'::jsonb)) order by e."starts_at", e."id"), '[]'::jsonb)
  from "better_supabase"."calendar_events" e
  where e."calendar_id" = any (list_calendar_events.calendar_ids)
    and e."starts_at" < list_calendar_events.range_end
    and (
      (e."rrule" is null and e."recurrence_id" is null and e."ends_at" > list_calendar_events.range_start)
      or e."rrule" is not null
      or (e."recurrence_id" is not null and (e."ends_at" > list_calendar_events.range_start or e."original_starts_at" >= list_calendar_events.range_start - interval '1 year'))
    )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_consents (
  subject_type    text,
  subject_id      text,
  include_history boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tenant uuid := ((case list_consents.subject_type
      when 'message' then (select s."tenant_id"::text from "better_supabase"."messages" s where s."id" = (list_consents.subject_id)::uuid)
      when 'conversation' then (select s."tenant_id"::text from "better_supabase"."conversations" s where s."id" = (list_consents.subject_id)::uuid)
      when 'channel' then (select s."tenant_id"::text from "better_supabase"."channels" s where s."id" = (list_consents.subject_id)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (list_consents.subject_id)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (list_consents.subject_id)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (list_consents.subject_id)::uuid)
      when 'course' then (select s."tenant_id"::text from "better_supabase"."courses" s where s."id" = (list_consents.subject_id)::uuid)
      when 'post' then (select s."tenant_id"::text from "better_supabase"."posts" s where s."id" = (list_consents.subject_id)::uuid)
      when 'activity' then (select s."tenant_id"::text from "better_supabase"."activities" s where s."id" = (list_consents.subject_id)::uuid)
      when 'quote' then (select s."tenant_id"::text from "better_supabase"."quotes" s where s."id" = (list_consents.subject_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (list_consents.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (list_consents.subject_id)::uuid)
      when 'invoice' then (select s."tenant_id"::text from "better_supabase"."invoices" s where s."id" = (list_consents.subject_id)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (list_consents.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (list_consents.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (list_consents.subject_id)::uuid)
      when 'rfq' then (select s."tenant_id"::text from "better_supabase"."rfqs" s where s."id" = (list_consents.subject_id)::uuid)
      when 'till' then (select s."tenant_id"::text from "better_supabase"."tills" s where s."id" = (list_consents.subject_id)::uuid)
      when 'order' then (select s."tenant_id"::text from "better_supabase"."orders" s where s."id" = (list_consents.subject_id)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (list_consents.subject_id)::uuid)
      when 'booking' then (select s."tenant_id"::text from "better_supabase"."bookings" s where s."id" = (list_consents.subject_id)::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (list_consents.subject_id)::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (list_consents.subject_id)::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."leases" s where s."id" = (list_consents.subject_id)::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (list_consents.subject_id)::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (list_consents.subject_id)::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (list_consents.subject_id)::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (list_consents.subject_id)::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (list_consents.subject_id)::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (list_consents.subject_id)::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (list_consents.subject_id)::uuid)
      when 'compliance_policy' then (select s."tenant_id"::text from "better_supabase"."compliance_policies" s where s."id" = (list_consents.subject_id)::uuid)
      when 'qualification_type' then (select s."tenant_id"::text from "better_supabase"."qualification_types" s where s."id" = (list_consents.subject_id)::uuid)
      when 'risk' then (select s."tenant_id"::text from "better_supabase"."risks" s where s."id" = (list_consents.subject_id)::uuid)
      when 'case' then (select s."tenant_id"::text from "better_supabase"."cases" s where s."id" = (list_consents.subject_id)::uuid)
      when 'inspection' then (select s."tenant_id"::text from "better_supabase"."inspections" s where s."id" = (list_consents.subject_id)::uuid)
      when 'inspection_program' then (select s."tenant_id"::text from "better_supabase"."inspection_programs" s where s."id" = (list_consents.subject_id)::uuid)
      when 'inspection_finding' then (select s."tenant_id"::text from "better_supabase"."inspection_findings" s where s."id" = (list_consents.subject_id)::uuid)
      when 'form' then (select s."tenant_id"::text from "better_supabase"."forms" s where s."id" = (list_consents.subject_id)::uuid)
      when 'meeting' then (select s."tenant_id"::text from "better_supabase"."meetings" s where s."id" = (list_consents.subject_id)::uuid)
      when 'meeting_decision' then (select s."tenant_id"::text from "better_supabase"."meeting_decisions" s where s."id" = (list_consents.subject_id)::uuid)
      when 'maintenance_plan' then (select s."tenant_id"::text from "better_supabase"."maintenance_plans" s where s."id" = (list_consents.subject_id)::uuid)
      when 'dam_usage_right' then (select s."tenant_id"::text from "better_supabase"."dam_usage_rights" s where s."id" = (list_consents.subject_id)::uuid)
      when 'lims_sample' then (select s."tenant_id"::text from "better_supabase"."lims_samples" s where s."id" = (list_consents.subject_id)::uuid)
      when 'tax_code' then (select s."tenant_id"::text from "better_supabase"."tax_codes" s where s."id" = (list_consents.subject_id)::uuid)
      when 'production_order' then (select s."tenant_id"::text from "better_supabase"."production_orders" s where s."id" = (list_consents.subject_id)::uuid)
      when 'work_center' then (select s."tenant_id"::text from "better_supabase"."work_centers" s where s."id" = (list_consents.subject_id)::uuid)
      when 'bank_account' then (select s."tenant_id"::text from "better_supabase"."bank_accounts" s where s."id" = (list_consents.subject_id)::uuid)
      when 'care_plan' then (select s."tenant_id"::text from "better_supabase"."care_plans" s where s."id" = (list_consents.subject_id)::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (list_consents.subject_id)::uuid)
      when 'content_entry' then (select s."tenant_id"::text from "better_supabase"."content_entries" s where s."id" = (list_consents.subject_id)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (list_consents.subject_id)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (list_consents.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (list_consents.subject_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (list_consents.subject_id)::uuid)
      when 'change_request' then (select s."organization_id"::text from "public"."change_requests" s where s."id" = (list_consents.subject_id)::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (list_consents.subject_id)::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (list_consents.subject_id)::uuid)
      else null::text
    end))::uuid;
begin
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or (coalesce(better_supabase.can('tenant', v_tenant, 'consents.read'), false) and coalesce("better_supabase"."can_subject"(list_consents.subject_type, list_consents.subject_id, 'read'), false))
      or ((v_tenant)::text, (list_consents.subject_type)::text, (list_consents.subject_id)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)
      or ((v_tenant)::text, (list_consents.subject_type)::text, (list_consents.subject_id)::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g)
      or exists (select 1 from "better_supabase"."relations" r
      where r."kind" = 'represents' and r."source_type" = 'person'
        and r."tenant_id"::text = (v_tenant)::text
        and r."target_type" = list_consents.subject_type and r."target_id" = (list_consents.subject_id)::text
        and r."data" ->> 'authority' in ('inform', 'act')
        and (case when r."data" ->> 'valid_from' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_from', 'date') then (r."data" ->> 'valid_from')::date <= current_date
      else false end) and (case when r."data" ->> 'valid_until' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_until', 'date') then (r."data" ->> 'valid_until')::date >= current_date
      else false end)
        and ((v_tenant)::text, ('person')::text, (r."source_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g))) then
    raise exception 'not allowed to read the consents of this record' using errcode = '42501', hint = 'CONSENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(l.item order by l.key, l.created desc, l.id), '[]'::jsonb)
    from (
      select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'purposeId', x."purpose_id", 'purposeKey', y."key", 'purposeTitle', y."title", 'purposeVersion', y."version", 'legalBasis', y."legal_basis", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'givenBy', x."given_by", 'givenByContactId', x."given_by_contact_id", 'givenByUserId', x."given_by_user_id", 'status', x."status", 'scope', coalesce(x."scope", '{}'::jsonb), 'grantedAt', x."granted_at", 'validUntil', x."expires_at", 'withdrawnAt', x."withdrawn_at", 'withdrawnReason', x."withdrawn_reason", 'signatureId', x."signature_id", 'submissionId', x."submission_id", 'attachmentId', x."attachment_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'active', (x."status" = 'granted' and (x."expires_at" is null or x."expires_at" > now()))) as item, y."key" as key, x."created_at" as created, x."id" as id,
        row_number() over (partition by y."key" order by x."created_at" desc, x."id" desc) as n
      from "better_supabase"."consents" x
      join "better_supabase"."consent_purposes" y on y."id" = x."purpose_id"
      where x."tenant_id" = v_tenant
        and x."subject_type" = list_consents.subject_type and x."subject_id" = list_consents.subject_id
    ) l
    where coalesce(list_consents.include_history, false) or l.n = 1
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_passes (
  tenant       uuid,
  holder_user  uuid                     DEFAULT NULL::uuid,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  status       text                     DEFAULT NULL::text,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  page_size    integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_passes.tenant, 'passes.read'), false)) then
    raise exception 'not allowed to read passes' using errcode = '42501', hint = 'PASS_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(z.item order by z.created desc, z.id desc), '[]'::jsonb)
    from (
      select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'kind', x."kind", 'holderUserId', x."holder_user_id", 'holderName', x."holder_name", 'holderEmail', x."holder_email", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'bookingId', x."booking_id", 'resourceId', x."resource_id", 'usesAllowed', x."uses_allowed", 'uses', x."uses", 'validFrom', x."starts_at", 'validUntil', x."expires_at", 'status', x."status", 'issuedBy', x."issued_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'revokedAt', x."revoked_at") as item, x."created_at" as created, x."id" as id
      from "better_supabase"."passes" x
      where x."tenant_id" = list_passes.tenant
        and (list_passes.holder_user is null or x."holder_user_id" = list_passes.holder_user)
        and (list_passes.subject_type is null or (x."subject_type" = list_passes.subject_type and x."subject_id" = list_passes.subject_id))
        and (list_passes.status is null or x."status" = list_passes.status)
        and (list_passes.before is null or x."created_at" < list_passes.before)
      order by x."created_at" desc, x."id" desc
      limit least(greatest(coalesce(list_passes.page_size, 50), 1), 500)
    ) z
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_scheduled_inbox_messages (
  conversation uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(to_jsonb(s) order by s."scheduled_at", s."id"), '[]'::jsonb)
  from "better_supabase"."scheduled_inbox_messages" s
  where s."author_id" = (select auth.uid())
    and (list_scheduled_inbox_messages.conversation is null or s."conversation_id" = list_scheduled_inbox_messages.conversation);
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_schedules (
  name_prefix text DEFAULT NULL::text,
  for_tenant  text DEFAULT NULL::text
)
  RETURNS TABLE (
    job_name        text,
    schedule        text,
    timezone        text,
    queue           text,
    tenant          text,
    next_run        timestamp with time zone,
    last_run        timestamp with time zone,
    lock_expires_at timestamp with time zone,
    created_at      timestamp with time zone,
    payload         jsonb
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_jobs regclass := pg_catalog.to_regclass('cron.job');
begin
  if v_jobs is null or list_schedules.for_tenant is not null then
    return;
  end if;
  return query execute format(
    'select j.jobname::text, j.schedule::text, ''UTC''::text, null::text, null::text, null::timestamptz, null::timestamptz, null::timestamptz, null::timestamptz, null::jsonb
     from %s j where $1 is null or starts_with(j.jobname, $1) order by j.jobname', v_jobs)
    using name_prefix;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_trash (
  tenant       uuid,
  subject_type text                     DEFAULT NULL::text,
  page_size    integer                  DEFAULT 50,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_rows jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_trash.tenant, 'trash.read'), false)) then
    raise exception 'not allowed to read this organization''s trash' using errcode = '42501', hint = 'TRASH_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', t."id", 'subjectType', t."subject_type", 'subjectId', t."subject_id", 'title', t."title", 'batchId', t."batch_id", 'count', t.n, 'trashedBy', t."trashed_by", 'trashedAt', t."trashed_at", 'purgeAfter', t."purge_at") order by t."trashed_at" desc, t."id"), '[]'::jsonb)
    into v_rows
  from (
    select x.*, (select count(*) from "better_supabase"."trash_items" b where b."batch_id" = x."batch_id")::integer as n
    from "better_supabase"."trash_items" x
    where x."tenant_id" = list_trash.tenant
      and x."depth" = 0
      and (list_trash.subject_type is null or x."subject_type" = list_trash.subject_type)
      and (list_trash.before is null or x."trashed_at" < list_trash.before)
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case x."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'cases.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tax.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'banking.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id" and (coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end)
    order by x."trashed_at" desc, x."id"
    limit least(greatest(coalesce(list_trash.page_size, 50), 1), 200)
  ) t;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_webhook_endpoints (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid := list_webhook_endpoints.tenant;
  v_endpoints jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.can('tenant', v_tenant, 'webhooks.read'), false) then
    raise exception 'Not allowed to manage this webhook endpoint' using errcode = '42501', hint = 'WEBHOOK_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', d."id", 'tenant', d."organization_id", 'name', d."name", 'url', d."url", 'enabled', d."enabled", 'eventTypes', d."event_types", 'permissions', d."permissions", 'batch', d."batch", 'signing', d."signing", 'format', d."format", 'credentialRef', d."credential_ref", 'failingSince', d."first_failed_at", 'disabledAt', d."disabled_at", 'disabledReason', d."disabled_reason", 'createdBy', d."created_by", 'createdAt', d."created_at", 'updatedAt', d."updated_at") order by d."created_at" desc, d."id"), '[]')
  into v_endpoints
  from "better_supabase"."webhook_endpoints" d
  where d."organization_id" = list_webhook_endpoints.tenant;
  return v_endpoints;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.load_ai_harness_session (
  chat    uuid,
  harness text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_harness_sessions";
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."ai_harness_sessions" x
  where x."chat_id" = load_ai_harness_session.chat and x."harness_id" = load_ai_harness_session.harness;
  if not found then
    return null;
  end if;
  return jsonb_build_object('chat_id', v_row."chat_id", 'harness_id', v_row."harness_id", 'owner_id', v_row."owner_id", 'resume_state', v_row."resume_state", 'continue_state', v_row."continue_state", 'sandbox_id', (select y."sandbox_id" from "better_supabase"."ai_sandboxes" y where y."chat_id" = v_row."chat_id" and y."harness_id" = v_row."harness_id" and y."status" <> 'stopped' order by y."last_used_at" desc limit 1), 'status', v_row."status", 'lock_holder', v_row."lock_holder", 'lock_expires_at', v_row."lock_expires_at", 'last_active_at', v_row."last_active_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.lock_ai_harness_session (
  chat        uuid,
  harness     text,
  holder      text,
  ttl_seconds integer DEFAULT 300
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_chat "better_supabase"."ai_chats";
  v_row "better_supabase"."ai_harness_sessions";
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  if nullif(lock_ai_harness_session.harness, '') is null then
    raise exception 'A harness session needs a harness id' using errcode = '22023', hint = 'AI_HARNESS_INVALID';
  end if;
  if nullif(lock_ai_harness_session.holder, '') is null
    or coalesce(lock_ai_harness_session.ttl_seconds, 0) not between 1 and 86400 then
    raise exception 'A lock needs a holder and a ttl between 1 and 86400 seconds' using errcode = '22023', hint = 'AI_HARNESS_INVALID';
  end if;
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = lock_ai_harness_session.chat;
  if not found then
    raise exception 'No chat %', lock_ai_harness_session.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_harness_sessions" ("chat_id", "harness_id", "owner_id")
  values (v_chat."id", lock_ai_harness_session.harness, v_chat."owner_id")
  on conflict ("chat_id", "harness_id") do nothing;
  select * into v_row from "better_supabase"."ai_harness_sessions" x
  where x."chat_id" = v_chat."id" and x."harness_id" = lock_ai_harness_session.harness
  for update;
  if v_row."lock_expires_at" > now() and v_row."lock_holder" is distinct from lock_ai_harness_session.holder then
    return false;
  end if;
  update "better_supabase"."ai_harness_sessions" x set
    "lock_holder" = lock_ai_harness_session.holder,
    "lock_expires_at" = now() + make_interval(secs => lock_ai_harness_session.ttl_seconds),
    "updated_at" = now()
  where x."chat_id" = v_row."chat_id" and x."harness_id" = v_row."harness_id";
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.mark_workflow_start_request (
  request uuid,
  run     text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  update "better_supabase"."workflow_start_requests" x set "status" = 'started', "run_id" = run, "started_at" = now(), "claim_expires_at" = null
  where x."id" = request and x."status" = 'pending';
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.meeting_calendar_mirror()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_calendar uuid;
begin
  select y."id" into v_calendar from "better_supabase"."calendars" y
  where y."tenant_id" = new."tenant_id" and y."name" = 'Meetings'
  order by y."created_at"
  limit 1;
  if v_calendar is null then
    return new;
  end if;
  if new."status" not in ('planned', 'in_progress') then
    delete from "better_supabase"."calendar_events" x where x."calendar_id" = v_calendar and x."uid" = 'meeting-' || new."id"::text;
    return new;
  end if;
  insert into "better_supabase"."calendar_events" ("tenant_id", "calendar_id", "uid", "title", "starts_at", "ends_at", "all_day", "tz", "status", "subject_type", "subject_id")
  values (new."tenant_id", v_calendar, 'meeting-' || new."id"::text, new."title",
    new."starts_at", coalesce(new."ends_at", new."starts_at" + interval '1 hour'), false, 'UTC', 'confirmed', 'meeting', new."id"::text)
  on conflict ("calendar_id", "uid", "original_starts_at") do update set
    "title" = excluded."title", "starts_at" = excluded."starts_at",
    "ends_at" = excluded."ends_at", "updated_at" = now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.messaging_messages_json (
  ids uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  with page_rows as (
    select m.* from "better_supabase"."messages" m where m."id" = any (messaging_messages_json.ids)
  ),
  a as (select "better_supabase"."message_authors"(messaging_messages_json.ids) as authors),
  f as (
    select coalesce(jsonb_object_agg(g.id, g.files), '{}'::jsonb) as files
    from (
      select a."subject_id" as id, jsonb_agg(jsonb_build_object('id', a."id", 'name', a."name", 'mimeType', a."mime_type", 'size', a."size", 'status', a."status") order by a."created_at", a."id") as files
      from "better_supabase"."attachments" a
      where a."subject_type" = 'message'
        and a."subject_id" = any (array(select x::text from unnest(messaging_messages_json.ids) x))
        and a."status" <> 'infected'
      group by a."subject_id"
    ) g
  ),
  r as (
    select coalesce(jsonb_object_agg(g.tenant, "better_supabase"."reaction_summary"(g.tenant, 'message', g.ids)), '{}'::jsonb) as reactions
    from (
      select m."tenant_id" as tenant, array_agg(m."id"::text) as ids from page_rows m group by m."tenant_id"
    ) g
  )
  select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object('author', a.authors -> x.id::text) || jsonb_build_object('attachments', coalesce(f.files -> x.id::text, '[]'::jsonb)) || jsonb_build_object('reactions', coalesce(r.reactions -> x."tenant_id"::text -> x.id::text, '[]'::jsonb)) order by coalesce(x."sent_at", x."scheduled_at", x."created_at"), x."id"), '[]'::jsonb)
  from page_rows x, a, f, r
$function$;

CREATE OR REPLACE FUNCTION better_supabase.move_booking (
  booking   uuid,
  starts_at timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_old "better_supabase"."bookings"%rowtype;
  v_booking "better_supabase"."bookings"%rowtype;
  v_capacity integer;
  v_length interval;
  v_before interval;
  v_after interval;
  v_moved boolean := false;
  v_calendar uuid;
  v_tz text;
  v_title text;
  v_event uuid;
begin
  select * into v_old from "better_supabase"."bookings" bk where bk."id" = move_booking.booking for update;
  if not found then
    raise exception 'booking not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
  end if;
  if v_old."status" = 'cancelled' then
    raise exception 'a cancelled booking can''t move' using errcode = '22023', hint = 'BOOKING_STATUS_INVALID';
  end if;
  v_booking := v_old;
  if lower(v_old."during") = move_booking.starts_at then
    return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason");
  end if;
  v_length := upper(v_old."during") - lower(v_old."during");
  v_before := lower(v_old."during") - lower(v_old."blocked");
  v_after := upper(v_old."blocked") - upper(v_old."during");
  update "better_supabase"."bookings" bk set "status" = 'cancelled', "hold_expires_at" = null, "cancelled_at" = now(), "cancel_reason" = 'bs:moving'
  where bk."id" = v_old."id";
  if not exists (
    select 1 from "better_supabase"."booking_slots"(v_old."service_id", move_booking.starts_at, move_booking.starts_at + v_length, null, v_old."resource_id") t
    where t.starts_at = move_booking.starts_at
  ) then
    raise exception 'that time is not an open slot' using errcode = '23P01', hint = 'BOOKING_SLOT_UNAVAILABLE';
  end if;
  select rs."capacity" into v_capacity from "better_supabase"."booking_resources" rs where rs."id" = v_old."resource_id";
  for v_seat in 1..v_capacity loop
    begin
      update "better_supabase"."bookings" bk set "status" = v_old."status", "hold_expires_at" = v_old."hold_expires_at", "cancelled_at" = null, "cancel_reason" = null,
        "seat" = v_seat,
        "during" = tstzrange(move_booking.starts_at, move_booking.starts_at + v_length),
        "blocked" = tstzrange(move_booking.starts_at - v_before, move_booking.starts_at + v_length + v_after),
        "updated_at" = now()
      where bk."id" = v_old."id"
      returning * into v_booking;
      v_moved := true;
      exit;
    exception when exclusion_violation then
      null;
    end;
  end loop;
  if not v_moved then
    raise exception 'that time was just taken' using errcode = '23P01', hint = 'BOOKING_SLOT_UNAVAILABLE';
  end if;
  if v_booking."status" = 'confirmed' then
    if v_old."calendar_event_id" is not null then
    delete from "better_supabase"."calendar_events" where "id" = v_old."calendar_event_id";
  end if;
    delete from "better_supabase"."reminders" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  delete from "better_supabase"."recurrence_rules" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
    select r."calendar_id", r."tz", sv."name" into v_calendar, v_tz, v_title
  from "better_supabase"."booking_resources" r join "better_supabase"."booking_services" sv on sv."id" = v_booking."service_id"
  where r."id" = v_booking."resource_id";
  if v_calendar is not null then
    insert into "better_supabase"."calendar_events" ("tenant_id", "calendar_id", "uid", "title", "starts_at", "ends_at", "tz", "status", "subject_type", "subject_id")
    values (v_booking."tenant_id", v_calendar, 'booking-' || v_booking."id"::text, coalesce(v_booking."customer_name", v_title), lower(v_booking."during"), upper(v_booking."during"), v_tz, 'confirmed', 'booking', v_booking."id"::text)
    on conflict ("calendar_id", "uid", "original_starts_at") do update set "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at"
    returning "id" into v_event;
    update "better_supabase"."bookings" set "calendar_event_id" = v_event where "id" = v_booking."id";
  end if;
    delete from "better_supabase"."reminders" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  delete from "better_supabase"."recurrence_rules" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, lower(v_booking."during"), r."tz", 'FREQ=DAILY;COUNT=1'
  from "better_supabase"."booking_resources" r where r."id" = v_booking."resource_id";
  insert into "better_supabase"."reminders" ("tenant_id", "subject_type", "subject_id", "user_id", "offset_minutes")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, v_booking."customer_user_id", o
  from "better_supabase"."booking_services" sv, unnest(sv."reminder_offsets") o
  where sv."id" = v_booking."service_id";
  end if;
  perform "better_supabase".emit_event('booking.rescheduled', jsonb_build_object('organizationId', v_booking."tenant_id", 'id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id"), 'bookings/' || v_booking."id"::text, (v_booking."tenant_id")::text, null, 'better-supabase/bookings');
  return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.my_passes()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'kind', x."kind", 'holderUserId', x."holder_user_id", 'holderName', x."holder_name", 'holderEmail', x."holder_email", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'bookingId', x."booking_id", 'resourceId', x."resource_id", 'usesAllowed', x."uses_allowed", 'uses', x."uses", 'validFrom', x."starts_at", 'validUntil', x."expires_at", 'status', x."status", 'issuedBy', x."issued_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'revokedAt', x."revoked_at") || jsonb_build_object('nonce', x."nonce") order by x."starts_at", x."id"), '[]'::jsonb)
  from "better_supabase"."passes" x
  where x."holder_user_id" = auth.uid()
    and x."status" = 'active'
    and (x."expires_at" is null or x."expires_at" > now())
    and not better_supabase.tenant_disabled(x."tenant_id")
$function$;

CREATE OR REPLACE FUNCTION better_supabase.note_signing_key_exp (
  kid text,
  exp timestamp with time zone
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  update "better_supabase"."signing_keys" k set "publish_expires_at" = note_signing_key_exp.exp
  where k."kid" = note_signing_key_exp.kid
    and (k."publish_expires_at" is null or k."publish_expires_at" < note_signing_key_exp.exp);
  return exists (select 1 from "better_supabase"."signing_keys" k where k."kid" = note_signing_key_exp.kid);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.organization_credential_refs (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_entry record;
  v_type text;
  v_refs jsonb;
  v_all jsonb := '[]'::jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role purges organizations' using errcode = '42501', hint = 'ORGANIZATION_DELETION_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "better_supabase"."organization_deletions" x
    where x."organization_id" = organization_credential_refs.tenant and x."cancelled_at" is null
      and x."purged_at" is null and x."purge_at" <= now()
  ) then
    raise exception 'No due deletion for this organization' using errcode = 'P0002', hint = 'ORGANIZATION_DELETION_NOT_DUE';
  end if;
  if exists (
    select 1 from "better_supabase"."legal_holds" x
    where x."released_at" is null
      and (x."organization_id" is null or x."organization_id" = organization_credential_refs.tenant)
  ) then
    raise exception 'A legal hold covers this organization, so it can''t be purged' using errcode = 'P0001', hint = 'ORGANIZATION_LEGAL_HOLD';
  end if;
  for v_entry in
    select c.name, c.tbl, c.col, c.user_col, t.col as tenant_col
    from "better_supabase"."data_lifecycle_credentials"() c
    join "better_supabase"."data_lifecycle_tables"() t on t.subject = 'organization' and t.name = c.name and t.purge
    where to_regclass(c.tbl) is not null
    order by c.name, c.col
  loop
    select pg_catalog.format_type(a.atttypid, a.atttypmod) into v_type
    from pg_catalog.pg_attribute a
    where a.attrelid = to_regclass(v_entry.tbl) and a.attname = v_entry.tenant_col and not a.attisdropped;
    execute format(
      'select coalesce(jsonb_agg(jsonb_build_object(''table'', $2, ''column'', $3, ''ref'', r.ref, ''user_id'', r.user_id, ''in_tenant'', not (jsonb_typeof(r.ref -> ''tenant'') is distinct from ''string'' or (r.ref ->> ''tenant'') is distinct from ($1)::text))), ''[]''::jsonb)
       from (select t.%I as ref, %s as user_id from %s t where t.%I = $1::%s) r
       where jsonb_typeof(r.ref) = ''object''',
      v_entry.col,
      case when v_entry.user_col is null then 'null::text' else format('t.%I::text', v_entry.user_col) end,
      v_entry.tbl, v_entry.tenant_col, v_type
    ) into v_refs
    using organization_credential_refs.tenant::text, v_entry.name, v_entry.col;
    v_all := v_all || v_refs;
  end loop;
  return v_all;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.outbox_ack (
  consumer text,
  owner    text,
  upto     bigint DEFAULT NULL::bigint
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  update "better_supabase"."outbox_consumers" k
  set ("cursor_xid", "cursor_position") = (
      select e."xid", e."position" from "better_supabase"."outbox_events" e where e."position" = upto
    ),
    "attempts" = 0, "last_error" = null, "retry_at" = null,
    "lease_owner" = null, "lease_expires_at" = null, "updated_at" = now()
  where k."name" = consumer and k."lease_owner" = owner
    and upto is not null
    and exists (select 1 from "better_supabase"."outbox_events" e where e."position" = upto and (e."xid", e."position") > (k."cursor_xid", k."cursor_position"));
  if found then
    return true;
  end if;
  update "better_supabase"."outbox_consumers" k
  set "lease_owner" = null, "lease_expires_at" = null, "updated_at" = now()
  where k."name" = consumer and k."lease_owner" = owner;
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.outbox_claim (
  consumer   text,
  owner      text,
  max_events integer  DEFAULT 100,
  lease      interval DEFAULT '00:01:00'::interval
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  c "better_supabase"."outbox_consumers";
  events jsonb;
begin
  update "better_supabase"."outbox_consumers" k
  set "lease_owner" = owner, "lease_expires_at" = now() + lease, "updated_at" = now()
  where k."name" = consumer
    and (k."lease_expires_at" is null or k."lease_expires_at" < now() or k."lease_owner" = owner)
    and (k."retry_at" is null or k."retry_at" <= now())
  returning k.* into c;
  if not found then
    if not exists (select 1 from "better_supabase"."outbox_consumers" k where k."name" = consumer) then
      raise exception 'Unknown outbox consumer %', consumer using errcode = 'P0002', hint = 'OUTBOX_UNKNOWN_CONSUMER';
    end if;
    return '[]';
  end if;
  select jsonb_agg(x.event order by x.n) into events
  from (
    select jsonb_build_object(
    'position', e."position",
    'id', e."id",
    'type', e."type",
    'payload', e."payload",
    'created_at', e."created_at",
    'source', e."source",
    'subject', e."subject",
    'tenant', e."organization_id",
    'key', e."key",
    'actor_id', e."actor_id"
  ) as event, row_number() over (order by e."xid", e."position") as n
    from "better_supabase"."outbox_events" e
    where (e."xid", e."position") > (c."cursor_xid", c."cursor_position")
      and e."xid" < pg_snapshot_xmin(pg_current_snapshot())
      and (c."types" is null or exists (
        select 1 from unnest(c."types") p
        where p = '*' or p = e."type"
          or (right(p, 2) = '.*' and starts_with(e."type", left(p, -1)))
      ))
    order by e."xid", e."position"
    limit case when c."attempts" > 0 then 1 else max_events end
  ) x;
  if events is null then
    update "better_supabase"."outbox_consumers" k
    set ("cursor_xid", "cursor_position") = (
      select e."xid", e."position" from "better_supabase"."outbox_events" e
      where (e."xid", e."position") > (c."cursor_xid", c."cursor_position") and e."xid" < pg_snapshot_xmin(pg_current_snapshot())
      order by e."xid" desc, e."position" desc
      limit 1
    )
    where k."name" = consumer
      and exists (select 1 from "better_supabase"."outbox_events" e where (e."xid", e."position") > (c."cursor_xid", c."cursor_position") and e."xid" < pg_snapshot_xmin(pg_current_snapshot()));
  end if;
  return coalesce(events, '[]');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.outbox_fail (
  consumer     text,
  owner        text,
  failed       bigint   DEFAULT NULL::bigint,
  error        text     DEFAULT NULL::text,
  max_attempts integer  DEFAULT 10,
  max_backoff  interval DEFAULT '00:10:00'::interval
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  c "better_supabase"."outbox_consumers";
begin
  update "better_supabase"."outbox_consumers" k
  set "attempts" = k."attempts" + 1, "last_error" = left(error, 4000),
    "lease_owner" = null, "lease_expires_at" = null, "updated_at" = now()
  where k."name" = consumer and k."lease_owner" = owner
  returning k.* into c;
  if not found then
    return null;
  end if;
  if failed is not null and c."attempts" >= greatest(coalesce(max_attempts, 10), 1) then
    insert into "better_supabase"."outbox_dead_letters" ("consumer", "position", "event_id", "type", "event", "attempts", "error")
    select consumer, e."position", e."id"::text, e."type", jsonb_build_object(
    'position', e."position",
    'id', e."id",
    'type', e."type",
    'payload', e."payload",
    'created_at', e."created_at",
    'source', e."source",
    'subject', e."subject",
    'tenant', e."organization_id",
    'key', e."key",
    'actor_id', e."actor_id"
  ), c."attempts", c."last_error"
    from "better_supabase"."outbox_events" e
    where e."position" = failed and (e."xid", e."position") > (c."cursor_xid", c."cursor_position")
    on conflict do nothing;
    update "better_supabase"."outbox_consumers" k
    set ("cursor_xid", "cursor_position") = (
        select e."xid", e."position" from "better_supabase"."outbox_events" e where e."position" = failed
      ),
      "attempts" = 0, "retry_at" = null
    where k."name" = consumer
      and exists (select 1 from "better_supabase"."outbox_events" e where e."position" = failed and (e."xid", e."position") > (k."cursor_xid", k."cursor_position"));
    if found then
      return 'dead';
    end if;
  end if;
  update "better_supabase"."outbox_consumers" k
  set "retry_at" = now() + least(
    coalesce(max_backoff, '10 minutes'),
    interval '1 second' * power(2, least(c."attempts", 20))
  )
  where k."name" = consumer;
  return 'retrying';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.pending_inbound_events (
  max          integer DEFAULT 100,
  max_attempts integer DEFAULT 5
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(to_jsonb(e) order by e."received_at"), '[]'::jsonb)
  from (
    select * from "better_supabase"."inbox_inbound_events" x
    where x."attempts" < coalesce(max_attempts, 5)
      and (
        (x."status" in ('received', 'failed') and x."available_at" <= now())
        or (x."status" = 'processing' and x."lock_expires_at" < now())
      )
    order by x."received_at"
    limit least(greatest(coalesce(max, 100), 1), 1000)
  ) e;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.place_booking (
  service       uuid,
  resource      uuid,
  starts_at     timestamp with time zone,
  customer      jsonb,
  confirm       boolean,
  customer_user uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_customer jsonb := coalesce(place_booking.customer, '{}'::jsonb);
  v_service "better_supabase"."booking_services"%rowtype;
  v_capacity integer;
  v_during tstzrange;
  v_blocked tstzrange;
  v_status text := case when coalesce(place_booking.confirm, false) then 'confirmed' else 'hold' end;
  v_expires timestamptz;
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_id uuid;
  v_seat integer;
  v_booking "better_supabase"."bookings"%rowtype;
  v_calendar uuid;
  v_tz text;
  v_title text;
  v_event uuid;
begin
  select * into v_service from "better_supabase"."booking_services" sv where sv."id" = place_booking.service and sv."active";
  if not found then
    raise exception 'service not found' using errcode = 'P0002', hint = 'BOOKING_SERVICE_NOT_FOUND';
  end if;
  select rs."capacity" into v_capacity from "better_supabase"."booking_resources" rs
    where rs."id" = place_booking.resource and rs."tenant_id" = v_service."tenant_id" and rs."active";
  if not found then
    raise exception 'resource not found' using errcode = 'P0002', hint = 'BOOKING_RESOURCE_NOT_FOUND';
  end if;
  v_during := tstzrange(place_booking.starts_at, place_booking.starts_at + v_service."duration");
  v_blocked := tstzrange(place_booking.starts_at - v_service."buffer_before", upper(v_during) + v_service."buffer_after");
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_booking_reserve"(uuid, uuid, uuid, tstzrange, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid, $4::tstzrange, $5::jsonb)', v_hook::oid::regproc)
        using v_service."tenant_id", place_booking.service, place_booking.resource, v_during, v_customer;
    end if;
  end;
  perform "better_supabase"."expire_booking_holds_in"(place_booking.resource, v_blocked);
  if not exists (
    select 1 from "better_supabase"."booking_slots"(place_booking.service, place_booking.starts_at, upper(v_during), null, place_booking.resource) t
    where t.starts_at = place_booking.starts_at
  ) then
    raise exception 'that time is not an open slot' using errcode = '23P01', hint = 'BOOKING_SLOT_UNAVAILABLE';
  end if;
  if v_status = 'hold' then
    v_expires := now() + v_service."hold_for";
  end if;
  for v_seat in 1..v_capacity loop
    begin
      insert into "better_supabase"."bookings" ("tenant_id", "resource_id", "service_id", "seat", "during", "blocked", "status", "hold_expires_at", "customer_name", "customer_email", "customer_user_id", "notes", "access_hash", "created_by")
      values (v_service."tenant_id", place_booking.resource, place_booking.service, v_seat, v_during, v_blocked, v_status, v_expires, v_customer ->> 'name', lower(v_customer ->> 'email'), place_booking.customer_user, v_customer ->> 'notes', encode(extensions.digest(convert_to(v_token, 'utf8'), 'sha256'), 'hex'), auth.uid())
      returning * into v_booking;
      v_id := v_booking."id";
      exit;
    exception when exclusion_violation then
      null;
    end;
  end loop;
  if v_id is null then
    raise exception 'that time was just taken' using errcode = '23P01', hint = 'BOOKING_SLOT_UNAVAILABLE';
  end if;
  perform "better_supabase".emit_event('booking.reserved', jsonb_build_object('organizationId', v_booking."tenant_id", 'id', v_id, 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id"), 'bookings/' || v_id::text, (v_booking."tenant_id")::text, null, 'better-supabase/bookings');
  if v_status = 'confirmed' then
    select r."calendar_id", r."tz", sv."name" into v_calendar, v_tz, v_title
  from "better_supabase"."booking_resources" r join "better_supabase"."booking_services" sv on sv."id" = v_booking."service_id"
  where r."id" = v_booking."resource_id";
  if v_calendar is not null then
    insert into "better_supabase"."calendar_events" ("tenant_id", "calendar_id", "uid", "title", "starts_at", "ends_at", "tz", "status", "subject_type", "subject_id")
    values (v_booking."tenant_id", v_calendar, 'booking-' || v_booking."id"::text, coalesce(v_booking."customer_name", v_title), lower(v_booking."during"), upper(v_booking."during"), v_tz, 'confirmed', 'booking', v_booking."id"::text)
    on conflict ("calendar_id", "uid", "original_starts_at") do update set "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at"
    returning "id" into v_event;
    update "better_supabase"."bookings" set "calendar_event_id" = v_event where "id" = v_booking."id";
  end if;
    delete from "better_supabase"."reminders" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  delete from "better_supabase"."recurrence_rules" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, lower(v_booking."during"), r."tz", 'FREQ=DAILY;COUNT=1'
  from "better_supabase"."booking_resources" r where r."id" = v_booking."resource_id";
  insert into "better_supabase"."reminders" ("tenant_id", "subject_type", "subject_id", "user_id", "offset_minutes")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, v_booking."customer_user_id", o
  from "better_supabase"."booking_services" sv, unnest(sv."reminder_offsets") o
  where sv."id" = v_booking."service_id";
    perform "better_supabase".emit_event('booking.confirmed', jsonb_build_object('organizationId', v_booking."tenant_id", 'id', v_id, 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id"), 'bookings/' || v_id::text, (v_booking."tenant_id")::text, null, 'better-supabase/bookings');
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_confirm"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  end if;
  if v_status = 'hold' then
    perform "better_supabase"."enqueue_job"(queue => 'bookings.expire-holds', payload => jsonb_build_object('bookingId', v_id), delay => ceil(extract(epoch from (v_expires - now())))::integer + 1, dedupe_key => 'bookings:expire:' || v_id::text, dedupe_running => false);
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_reserve"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason") || jsonb_build_object('accessToken', v_token);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.publish_due_inbox_messages (
  max_rows integer DEFAULT 100
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."scheduled_inbox_messages"%rowtype;
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_count integer := 0;
begin
  for v_row in
    select * from "better_supabase"."scheduled_inbox_messages"
    where "scheduled_at" <= now()
    order by "scheduled_at", "id"
    limit greatest(coalesce(max_rows, 100), 1)
    for update skip locked
  loop
    delete from "better_supabase"."scheduled_inbox_messages" where "id" = v_row."id";
    if not coalesce(better_supabase.can_user(v_row."author_id", 'tenant', v_row."tenant_id", 'inbox.reply'), false) then
      continue;
    end if;
    perform "better_supabase"."inbox_add_message"(v_row."conversation_id", v_row."input", 'agent', v_row."author_id", 'outbound');
    select * into v_conv from "better_supabase"."inbox_conversations" where "id" = v_row."conversation_id";
    if v_conv."bot_mode" = 'bot' then
      update "better_supabase"."inbox_conversations" set "bot_mode" = 'human' where "id" = v_conv."id" returning * into v_conv;
      insert into "better_supabase"."inbox_conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
    values (v_conv."tenant_id", v_conv."id", 'handoff', v_row."author_id", jsonb_build_object('from', 'bot', 'to', 'human', 'reason', 'agent_reply'));
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.publish_due_messages (
  max_rows integer DEFAULT 100
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
  v_sent integer := 0;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'publish_due_messages runs as the service role' using errcode = '42501', hint = 'MESSAGING_FORBIDDEN';
  end if;
  for v_id in
    select m."id" from "better_supabase"."messages" m
    where m."sent_at" is null and m."deleted_at" is null and m."scheduled_at" <= now()
    order by m."scheduled_at", m."id"
    limit least(greatest(coalesce(publish_due_messages.max_rows, 100), 1), 1000)
    for update skip locked
  loop
    update "better_supabase"."messages" m set "sent_at" = now() where m."id" = v_id;
    perform "better_supabase"."messaging_message_sent"(v_id);
    v_sent := v_sent + 1;
  end loop;
  return v_sent;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_expired_trash (
  max_batches integer DEFAULT 100
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_batch uuid;
  v_count integer := 0;
begin
  for v_batch in
    select t."batch_id" from "better_supabase"."trash_items" t
    where t."depth" = 0 and t."purge_at" <= now()
      and not "better_supabase"."is_held"('trash', (t."tenant_id")::text)
    order by t."purge_at"
    limit greatest(coalesce(purge_expired_trash.max_batches, 100), 1)
  loop
    v_count := v_count + "better_supabase"."trash_purge_batch"(v_batch);
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_organization (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."organization_deletions";
  v_table record;
  v_type text;
  v_count bigint;
  v_deleted jsonb := '{}'::jsonb;
  v_pending text[];
  v_left text[];
  v_name text;
  v_pass integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role purges organizations' using errcode = '42501', hint = 'ORGANIZATION_DELETION_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."organization_deletions" x
  where x."organization_id" = purge_organization.tenant and x."cancelled_at" is null and x."purged_at" is null
  for update;
  if v_row."organization_id" is null or v_row."purge_at" > now() then
    raise exception 'No due deletion for this organization' using errcode = 'P0002', hint = 'ORGANIZATION_DELETION_NOT_DUE';
  end if;
  if exists (
    select 1 from "better_supabase"."legal_holds" x
    where x."released_at" is null
      and (x."organization_id" is null or x."organization_id" = purge_organization.tenant)
  ) then
    raise exception 'A legal hold covers this organization, so it can''t be purged' using errcode = 'P0001', hint = 'ORGANIZATION_LEGAL_HOLD';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."on_organization_purge"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using purge_organization.tenant;
    end if;
  end;
  -- Tables go in reverse order; a table whose rows another table still
  -- references (a restricting foreign key) waits for a later pass.
  v_pending := array(
    select t.name from "better_supabase"."data_lifecycle_tables"() t
    where t.subject = 'organization' and t.purge and to_regclass(t.tbl) is not null
      and to_regclass(t.tbl) <> to_regclass('"better_supabase"."organization_deletions"') and to_regclass(t.tbl) is distinct from to_regclass('"public"."organizations"')
    order by (row_number() over ()) desc
  );
  perform set_config('better_supabase.purge_tenant', purge_organization.tenant::text, true);
  for v_pass in 1..10 loop
    exit when cardinality(v_pending) = 0;
    v_left := '{}';
    foreach v_name in array v_pending loop
      select * into v_table from "better_supabase"."data_lifecycle_tables"() t
      where t.subject = 'organization' and t.name = v_name;
      select pg_catalog.format_type(a.atttypid, a.atttypmod) into v_type
      from pg_catalog.pg_attribute a
      where a.attrelid = to_regclass(v_table.tbl) and a.attname = v_table.col and not a.attisdropped;
      begin
        execute format('delete from %s t where t.%I = $1::%s', v_table.tbl, v_table.col, v_type)
          using purge_organization.tenant::text;
        get diagnostics v_count = row_count;
        v_deleted := v_deleted || jsonb_build_object(v_name, coalesce((v_deleted ->> v_name)::bigint, 0) + v_count);
      exception when foreign_key_violation or restrict_violation or check_violation then
        -- Another table's rows still point here (or a set null action breaks
        -- a check on them): try again after the other tables.
        v_left := v_left || v_name;
      end;
    end loop;
    if v_left = v_pending then
      raise exception 'Rows in % still have references the purge does not delete', array_to_string(v_left, ', ')
        using errcode = '23503', hint = 'ORGANIZATION_PURGE_BLOCKED';
    end if;
    v_pending := v_left;
  end loop;
  perform set_config('better_supabase.purge_tenant', '', true);
  update "better_supabase"."organization_deletions" x set "purged_at" = now() where x."organization_id" = v_row."organization_id" returning * into v_row;
  begin
    delete from "public"."organizations" where "id" = purge_organization.tenant;
  exception when foreign_key_violation or restrict_violation then
    raise exception 'Rows still reference the organization: %', sqlerrm
      using errcode = '23503', hint = 'ORGANIZATION_PURGE_BLOCKED';
  end;
  perform "better_supabase".emit_event('organization.purged', jsonb_build_object('organizationId', v_row."organization_id"::text, 'userId', null::uuid, 'purgeAfter', v_row."purge_at"), 'organizations/' || v_row."organization_id"::text, (null)::text, 'organization.purged:' || v_row."organization_id"::text, 'better-supabase/data-lifecycle');
  perform better_supabase.audit_event(
    event_type => 'organization.purged',
    category => 'data',
    target_type => 'organization',
    record_id => v_row."organization_id"::text,
    tenant => (null)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'userId', null::uuid, 'purgeAfter', v_row."purge_at"),
    idempotency_key => 'organization.purged:' || v_row."organization_id"::text
  );
  return jsonb_build_object('organizationId', v_row."organization_id"::text, 'deleted', v_deleted);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_rate_limits (
  batch integer DEFAULT 10000
)
  RETURNS integer
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  with expired as (
    select l."scope", l."key" from "better_supabase"."rate_limits" l
    left join "better_supabase"."rate_limit_rules" r on r."scope" = l."scope" and r."organization_id" is null
    where l."window_started_at" + coalesce(l."period", r."period", interval '1 day') <= now()
    limit batch
  ),
  purged as (
    delete from "better_supabase"."rate_limits" l
    using expired e
    where l."scope" = e.scope and l."key" = e.key
    returning 1
  )
  select count(*)::integer from purged
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_signing_keys (
  grace interval DEFAULT NULL::interval
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  delete from "better_supabase"."signing_keys" k
  where k."state" = 'retired' and not (k."state" = 'active' or k."publish_expires_at" + coalesce(grace, '5 minutes'::interval) > now());
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_consent (
  subject_type        text,
  subject_id          text,
  purpose_key         text,
  status              text,
  given_by            text                     DEFAULT 'self'::text,
  given_by_contact_id uuid                     DEFAULT NULL::uuid,
  expires_at          timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  scope               jsonb                    DEFAULT '{}'::jsonb,
  evidence            jsonb                    DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_purpose "better_supabase"."consent_purposes";
  v_row "better_supabase"."consents";
  v_given_by text := coalesce(record_consent.given_by, 'self');
  v_contact uuid := record_consent.given_by_contact_id;
  v_scope jsonb := coalesce(record_consent.scope, '{}'::jsonb);
  v_evidence jsonb := coalesce(record_consent.evidence, '{}'::jsonb);
  v_until timestamptz := record_consent.expires_at;
  v_signature uuid;
  v_submission uuid;
  v_attachment uuid;
  v_representative uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  v_tenant := ((case record_consent.subject_type
      when 'message' then (select s."tenant_id"::text from "better_supabase"."messages" s where s."id" = (record_consent.subject_id)::uuid)
      when 'conversation' then (select s."tenant_id"::text from "better_supabase"."conversations" s where s."id" = (record_consent.subject_id)::uuid)
      when 'channel' then (select s."tenant_id"::text from "better_supabase"."channels" s where s."id" = (record_consent.subject_id)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (record_consent.subject_id)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (record_consent.subject_id)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (record_consent.subject_id)::uuid)
      when 'course' then (select s."tenant_id"::text from "better_supabase"."courses" s where s."id" = (record_consent.subject_id)::uuid)
      when 'post' then (select s."tenant_id"::text from "better_supabase"."posts" s where s."id" = (record_consent.subject_id)::uuid)
      when 'activity' then (select s."tenant_id"::text from "better_supabase"."activities" s where s."id" = (record_consent.subject_id)::uuid)
      when 'quote' then (select s."tenant_id"::text from "better_supabase"."quotes" s where s."id" = (record_consent.subject_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (record_consent.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (record_consent.subject_id)::uuid)
      when 'invoice' then (select s."tenant_id"::text from "better_supabase"."invoices" s where s."id" = (record_consent.subject_id)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (record_consent.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (record_consent.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (record_consent.subject_id)::uuid)
      when 'rfq' then (select s."tenant_id"::text from "better_supabase"."rfqs" s where s."id" = (record_consent.subject_id)::uuid)
      when 'till' then (select s."tenant_id"::text from "better_supabase"."tills" s where s."id" = (record_consent.subject_id)::uuid)
      when 'order' then (select s."tenant_id"::text from "better_supabase"."orders" s where s."id" = (record_consent.subject_id)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (record_consent.subject_id)::uuid)
      when 'booking' then (select s."tenant_id"::text from "better_supabase"."bookings" s where s."id" = (record_consent.subject_id)::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (record_consent.subject_id)::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (record_consent.subject_id)::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."leases" s where s."id" = (record_consent.subject_id)::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (record_consent.subject_id)::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (record_consent.subject_id)::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (record_consent.subject_id)::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (record_consent.subject_id)::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (record_consent.subject_id)::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (record_consent.subject_id)::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (record_consent.subject_id)::uuid)
      when 'compliance_policy' then (select s."tenant_id"::text from "better_supabase"."compliance_policies" s where s."id" = (record_consent.subject_id)::uuid)
      when 'qualification_type' then (select s."tenant_id"::text from "better_supabase"."qualification_types" s where s."id" = (record_consent.subject_id)::uuid)
      when 'risk' then (select s."tenant_id"::text from "better_supabase"."risks" s where s."id" = (record_consent.subject_id)::uuid)
      when 'case' then (select s."tenant_id"::text from "better_supabase"."cases" s where s."id" = (record_consent.subject_id)::uuid)
      when 'inspection' then (select s."tenant_id"::text from "better_supabase"."inspections" s where s."id" = (record_consent.subject_id)::uuid)
      when 'inspection_program' then (select s."tenant_id"::text from "better_supabase"."inspection_programs" s where s."id" = (record_consent.subject_id)::uuid)
      when 'inspection_finding' then (select s."tenant_id"::text from "better_supabase"."inspection_findings" s where s."id" = (record_consent.subject_id)::uuid)
      when 'form' then (select s."tenant_id"::text from "better_supabase"."forms" s where s."id" = (record_consent.subject_id)::uuid)
      when 'meeting' then (select s."tenant_id"::text from "better_supabase"."meetings" s where s."id" = (record_consent.subject_id)::uuid)
      when 'meeting_decision' then (select s."tenant_id"::text from "better_supabase"."meeting_decisions" s where s."id" = (record_consent.subject_id)::uuid)
      when 'maintenance_plan' then (select s."tenant_id"::text from "better_supabase"."maintenance_plans" s where s."id" = (record_consent.subject_id)::uuid)
      when 'dam_usage_right' then (select s."tenant_id"::text from "better_supabase"."dam_usage_rights" s where s."id" = (record_consent.subject_id)::uuid)
      when 'lims_sample' then (select s."tenant_id"::text from "better_supabase"."lims_samples" s where s."id" = (record_consent.subject_id)::uuid)
      when 'tax_code' then (select s."tenant_id"::text from "better_supabase"."tax_codes" s where s."id" = (record_consent.subject_id)::uuid)
      when 'production_order' then (select s."tenant_id"::text from "better_supabase"."production_orders" s where s."id" = (record_consent.subject_id)::uuid)
      when 'work_center' then (select s."tenant_id"::text from "better_supabase"."work_centers" s where s."id" = (record_consent.subject_id)::uuid)
      when 'bank_account' then (select s."tenant_id"::text from "better_supabase"."bank_accounts" s where s."id" = (record_consent.subject_id)::uuid)
      when 'care_plan' then (select s."tenant_id"::text from "better_supabase"."care_plans" s where s."id" = (record_consent.subject_id)::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (record_consent.subject_id)::uuid)
      when 'content_entry' then (select s."tenant_id"::text from "better_supabase"."content_entries" s where s."id" = (record_consent.subject_id)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (record_consent.subject_id)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (record_consent.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (record_consent.subject_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (record_consent.subject_id)::uuid)
      when 'change_request' then (select s."organization_id"::text from "public"."change_requests" s where s."id" = (record_consent.subject_id)::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (record_consent.subject_id)::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (record_consent.subject_id)::uuid)
      else null::text
    end))::uuid;
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or (coalesce(better_supabase.can('tenant', v_tenant, 'consents.record'), false) and coalesce("better_supabase"."can_subject"(record_consent.subject_type, record_consent.subject_id, 'read'), false))
      or ((v_tenant)::text, (record_consent.subject_type)::text, (record_consent.subject_id)::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g)
      or exists (select 1 from "better_supabase"."relations" r
      where r."kind" = 'represents' and r."source_type" = 'person'
        and r."tenant_id"::text = (v_tenant)::text
        and r."target_type" = record_consent.subject_type and r."target_id" = (record_consent.subject_id)::text
        and r."data" ->> 'authority' = 'act'
        and (case when r."data" ->> 'valid_from' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_from', 'date') then (r."data" ->> 'valid_from')::date <= current_date
      else false end) and (case when r."data" ->> 'valid_until' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_until', 'date') then (r."data" ->> 'valid_until')::date >= current_date
      else false end)
        and ((v_tenant)::text, ('person')::text, (r."source_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g))) then
    raise exception 'not allowed to record consent for this record' using errcode = '42501', hint = 'CONSENT_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_tenant, 'consents.record'), false) and coalesce("better_supabase"."can_subject"(record_consent.subject_type, record_consent.subject_id, 'read'), false))) then
    v_representative := (select r."source_id"::uuid from "better_supabase"."relations" r
      where r."kind" = 'represents' and r."source_type" = 'person'
        and r."tenant_id"::text = (v_tenant)::text
        and r."target_type" = record_consent.subject_type and r."target_id" = (record_consent.subject_id)::text
        and r."data" ->> 'authority' = 'act'
        and (case when r."data" ->> 'valid_from' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_from', 'date') then (r."data" ->> 'valid_from')::date <= current_date
      else false end) and (case when r."data" ->> 'valid_until' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_until', 'date') then (r."data" ->> 'valid_until')::date >= current_date
      else false end)
        and ((v_tenant)::text, ('person')::text, (r."source_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g)
      order by r."source_id" limit 1);
    if v_representative is not null then
      v_given_by := 'representative';
      v_contact := v_representative;
    else
      v_given_by := 'self';
      v_contact := null;
    end if;
  end if;
  if record_consent.status is null or record_consent.status not in ('granted', 'refused') then
    raise exception 'status is granted or refused; withdraw_consent withdraws a consent' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  if v_given_by not in ('self', 'representative') then
    raise exception 'given_by is self or representative' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  if v_given_by = 'self' and v_contact is not null then
    raise exception 'only a representative''s consent names a contact' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  if v_given_by = 'representative' then
    if v_contact is null then
      raise exception 'a representative''s consent names the contact who gave it' using errcode = '22023', hint = 'CONSENT_INVALID';
    end if;
    if not exists (select 1 from "better_supabase"."relations" r
      where r."kind" = 'represents' and r."source_type" = 'person'
        and r."tenant_id"::text = (v_tenant)::text
        and r."target_type" = record_consent.subject_type and r."target_id" = (record_consent.subject_id)::text
        and r."data" ->> 'authority' = 'act'
        and (case when r."data" ->> 'valid_from' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_from', 'date') then (r."data" ->> 'valid_from')::date <= current_date
      else false end) and (case when r."data" ->> 'valid_until' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_until', 'date') then (r."data" ->> 'valid_until')::date >= current_date
      else false end)
        and r."source_id" = (v_contact)::text) then
      raise exception 'the contact doesn''t represent this record with authority to act' using errcode = '22023', hint = 'CONSENT_INVALID';
    end if;
  end if;
  if jsonb_typeof(v_scope) <> 'object' or jsonb_typeof(v_evidence) <> 'object' then
    raise exception 'scope and evidence are JSON objects' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  select * into v_purpose from "better_supabase"."consent_purposes" x
  where x."key" = record_consent.purpose_key
    and (x."tenant_id" = v_tenant or x."tenant_id" is null)
    and x."archived_at" is null
  order by (x."tenant_id" is null), x."created_at" desc, x."id"
  limit 1;
  if not found then
    if exists (
      select 1 from "better_supabase"."consent_purposes" x
      where x."key" = record_consent.purpose_key and (x."tenant_id" = v_tenant or x."tenant_id" is null)
    ) then
      raise exception 'the consent purpose is archived' using errcode = '22023', hint = 'CONSENT_PURPOSE_ARCHIVED';
    end if;
    raise exception 'no such consent purpose' using errcode = 'P0002', hint = 'CONSENT_PURPOSE_NOT_FOUND';
  end if;
  if v_evidence ? 'signatureId' and not pg_input_is_valid(v_evidence ->> 'signatureId', 'uuid') then
    raise exception 'evidence.signatureId is not a uuid' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  v_signature := (v_evidence ->> 'signatureId')::uuid;
  if v_signature is not null and not exists (
    select 1 from "better_supabase"."signatures" x
    where x."id" = v_signature and x."tenant_id"::text = v_tenant::text
  ) then
    raise exception 'evidence.signatureId is not a signature of this organization' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  if v_evidence ? 'submissionId' and not pg_input_is_valid(v_evidence ->> 'submissionId', 'uuid') then
    raise exception 'evidence.submissionId is not a uuid' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  v_submission := (v_evidence ->> 'submissionId')::uuid;
  if v_submission is not null and not exists (
    select 1 from "better_supabase"."form_submissions" x
    where x."id" = v_submission and x."tenant_id"::text = v_tenant::text
  ) then
    raise exception 'evidence.submissionId is not a form submission of this organization' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  if v_evidence ? 'attachmentId' and not pg_input_is_valid(v_evidence ->> 'attachmentId', 'uuid') then
    raise exception 'evidence.attachmentId is not a uuid' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  v_attachment := (v_evidence ->> 'attachmentId')::uuid;
  if v_attachment is not null and not exists (
    select 1 from "better_supabase"."attachments" x
    where x."id" = v_attachment and x."organization_id"::text = v_tenant::text
  ) then
    raise exception 'evidence.attachmentId is not an attachment of this organization' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  if record_consent.status = 'granted' and v_purpose."requires_signature" and v_signature is null then
    raise exception 'this purpose needs a signature to grant consent' using errcode = '22023', hint = 'CONSENT_SIGNATURE_REQUIRED';
  end if;
  if record_consent.status = 'refused' then
    v_until := null;
  elsif v_until is null and v_purpose."valid_months" is not null then
    v_until := now() + make_interval(months => v_purpose."valid_months");
  end if;
  if v_until is not null and v_until <= now() then
    raise exception 'expires_at is in the past' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_consent_record"(uuid, text, text, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid, $5::text)', v_hook::oid::regproc)
        using v_tenant, record_consent.subject_type, record_consent.subject_id, v_purpose."id", record_consent.status;
    end if;
  end;
  update "better_supabase"."consents" x set
    "status" = 'withdrawn',
    "withdrawn_at" = now(), "withdrawn_reason" = 'superseded'
  where x."subject_type" = record_consent.subject_type and x."subject_id" = record_consent.subject_id
    and x."tenant_id" = v_tenant and x."status" = 'granted'
    and x."purpose_id" in (
      select y."id" from "better_supabase"."consent_purposes" y
      where y."key" = v_purpose."key" and (y."tenant_id" = v_tenant or y."tenant_id" is null)
    );
  insert into "better_supabase"."consents" ("tenant_id", "purpose_id", "subject_type", "subject_id", "given_by", "given_by_contact_id", "given_by_user_id", "status", "scope", "expires_at", "signature_id", "submission_id", "attachment_id", "created_by")
  values (v_tenant, v_purpose."id", record_consent.subject_type, record_consent.subject_id, v_given_by, v_contact, auth.uid(), record_consent.status, v_scope, v_until, v_signature, v_submission, v_attachment, auth.uid())
  returning * into v_row;
  if record_consent.status = 'granted' then
    perform "better_supabase".emit_event('consent.granted', jsonb_build_object('organizationId', v_row."tenant_id", 'consentId', v_row."id", 'purposeId', v_row."purpose_id", 'purposeKey', v_purpose."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'givenBy', v_row."given_by"), 'consents/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/consents');
  perform better_supabase.audit_event(
    event_type => 'consent.granted',
    category => 'data',
    target_type => 'consent',
    record_id => v_row."id"::text,
    target_label => v_purpose."title",
    summary => 'recorded a consent',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'consentId', v_row."id", 'purposeId', v_row."purpose_id", 'purposeKey', v_purpose."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'givenBy', v_row."given_by")
  );
  else
    perform "better_supabase".emit_event('consent.refused', jsonb_build_object('organizationId', v_row."tenant_id", 'consentId', v_row."id", 'purposeId', v_row."purpose_id", 'purposeKey', v_purpose."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'givenBy', v_row."given_by"), 'consents/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/consents');
  perform better_supabase.audit_event(
    event_type => 'consent.refused',
    category => 'data',
    target_type => 'consent',
    record_id => v_row."id"::text,
    target_label => v_purpose."title",
    summary => 'recorded a refused consent',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'consentId', v_row."id", 'purposeId', v_row."purpose_id", 'purposeKey', v_purpose."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'givenBy', v_row."given_by")
  );
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_consent_record"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'purposeId', v_row."purpose_id", 'purposeKey', v_purpose."key", 'purposeTitle', v_purpose."title", 'purposeVersion', v_purpose."version", 'legalBasis', v_purpose."legal_basis", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'givenBy', v_row."given_by", 'givenByContactId', v_row."given_by_contact_id", 'givenByUserId', v_row."given_by_user_id", 'status', v_row."status", 'scope', coalesce(v_row."scope", '{}'::jsonb), 'grantedAt', v_row."granted_at", 'validUntil', v_row."expires_at", 'withdrawnAt', v_row."withdrawn_at", 'withdrawnReason', v_row."withdrawn_reason", 'signatureId', v_row."signature_id", 'submissionId', v_row."submission_id", 'attachmentId', v_row."attachment_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'active', (v_row."status" = 'granted' and (v_row."expires_at" is null or v_row."expires_at" > now())));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.redeliver_webhook (
  delivery uuid
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_endpoint uuid;
  v_status text;
  v_tenant uuid;
  v_enabled boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select v."endpoint_id", v."status" into v_endpoint, v_status
  from "better_supabase"."webhook_deliveries" v where v."id" = redeliver_webhook.delivery;
  if not found then
    raise exception 'Webhook delivery not found' using errcode = 'P0002', hint = 'WEBHOOK_DELIVERY_NOT_FOUND';
  end if;
  select d."organization_id", d."enabled" into v_tenant, v_enabled
  from "better_supabase"."webhook_endpoints" d where d."id" = v_endpoint;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.can('tenant', v_tenant, 'webhooks.manage'), false) then
    raise exception 'Not allowed to manage this webhook endpoint' using errcode = '42501', hint = 'WEBHOOK_FORBIDDEN';
  end if;
  if v_status in ('pending', 'delivering') then
    raise exception 'The delivery is still in progress' using errcode = '55000', hint = 'WEBHOOK_DELIVERY_IN_PROGRESS';
  end if;
  if not v_enabled then
    raise exception 'Webhook endpoint is disabled' using errcode = '55000', hint = 'WEBHOOK_ENDPOINT_DISABLED';
  end if;
  update "better_supabase"."webhook_deliveries" v
  set "status" = 'pending', "attempt" = 0, "available_at" = now(), "lease_expires_at" = null, "processed_at" = null, "last_error" = null, "updated_at" = now()
  where v."id" = redeliver_webhook.delivery;
  return redeliver_webhook.delivery;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_organization_deletion (
  tenant uuid,
  grace  interval DEFAULT '30 days'::interval
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."organization_deletions";
  v_disabled boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.can('tenant', request_organization_deletion.tenant, 'organization.delete'), false) then
    raise exception 'You may not delete this organization' using errcode = '42501', hint = 'ORGANIZATION_DELETION_FORBIDDEN';
  end if;
  if request_organization_deletion.grace < interval '0' then
    raise exception 'grace must not be negative' using errcode = '22023', hint = 'ORGANIZATION_DELETION_GRACE';
  end if;
  if exists (select 1 from "better_supabase"."organization_deletions" x where x."organization_id" = request_organization_deletion.tenant and x."purged_at" is not null) then
    raise exception 'The organization was already purged' using errcode = 'P0002', hint = 'ORGANIZATION_PURGED';
  end if;
  v_disabled := false;
  insert into "better_supabase"."organization_deletions" as x ("organization_id", "requested_by", "purge_at", "previously_disabled")
  values (request_organization_deletion.tenant, auth.uid(), now() + request_organization_deletion.grace, coalesce(v_disabled, false))
  on conflict ("organization_id") do update set
    "requested_by" = excluded."requested_by",
    "requested_at" = now(),
    "purge_at" = excluded."purge_at",
    "previously_disabled" = case when x."cancelled_at" is null then x."previously_disabled" else excluded."previously_disabled" end,
    "cancelled_at" = null
  returning * into v_row;
  perform "better_supabase".emit_event('organization.deletion_requested', jsonb_build_object('organizationId', v_row."organization_id"::text, 'userId', auth.uid(), 'purgeAfter', v_row."purge_at"), 'organizations/' || v_row."organization_id"::text, (v_row."organization_id")::text, null, 'better-supabase/data-lifecycle');
  perform better_supabase.audit_event(
    event_type => 'organization.deletion_requested',
    category => 'data',
    target_type => 'organization',
    record_id => v_row."organization_id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'userId', auth.uid(), 'purgeAfter', v_row."purge_at")
  );
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_workflow_start (
  key          text,
  workflow     text,
  payload      jsonb    DEFAULT '{}'::jsonb,
  tenant       uuid     DEFAULT NULL::uuid,
  actor        uuid     DEFAULT NULL::uuid,
  concurrency  integer  DEFAULT NULL::integer,
  debounce     interval DEFAULT NULL::interval,
  singleton    boolean  DEFAULT false,
  subject_type text     DEFAULT NULL::text,
  subject_id   text     DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_id uuid;
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_workflow_start_request"(text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid)', v_hook::oid::regproc)
        using request_workflow_start.key, request_workflow_start.workflow, request_workflow_start.tenant;
    end if;
  end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('workflow_admission'), pg_catalog.hashtext(key));
  if coalesce(singleton, false) and (
    "better_supabase"."workflow_admission_active"(key) > 0
    or exists (select 1 from "better_supabase"."workflow_start_requests" x where x."key" = key and x."status" = 'pending')
  ) then
    return jsonb_build_object('id', null, 'status', 'dropped');
  end if;
  if debounce is not null then
    update "better_supabase"."workflow_start_requests" x set "status" = 'superseded'
    where x."key" = key and x."status" = 'pending'
      and (x."claim_expires_at" is null or x."claim_expires_at" < now());
  end if;
  insert into "better_supabase"."workflow_start_requests" ("key", "workflow", "input", "tenant_id", "actor_id", "concurrency", "not_before_at", "subject_type", "subject_id")
  values (key, workflow, coalesce(payload -> 'input', '[]'::jsonb), tenant, actor, case when coalesce(singleton, false) then 1 else concurrency end, now() + coalesce(debounce, interval '0'), subject_type, subject_id)
  returning "id" into v_id;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_workflow_start_request"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'status', 'pending');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reschedule_inbox_message (
  scheduled    uuid,
  scheduled_at timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."scheduled_inbox_messages"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."scheduled_inbox_messages" where "id" = reschedule_inbox_message.scheduled and "author_id" = (select auth.uid()) for update;
  if not found then
    raise exception 'scheduled message not found' using errcode = 'P0002', hint = 'SCHEDULED_MESSAGE_NOT_FOUND';
  end if;
  if reschedule_inbox_message.scheduled_at is null or reschedule_inbox_message.scheduled_at <= now() then
    raise exception 'scheduled_at must be in the future' using errcode = '22023', hint = 'INBOX_SCHEDULE_TIME';
  end if;
  update "better_supabase"."scheduled_inbox_messages" set "scheduled_at" = reschedule_inbox_message.scheduled_at
  where "id" = v_row."id"
  returning * into v_row;
  perform "better_supabase"."enqueue_job"(queue => 'inbox_schedule', payload => jsonb_build_object('type', 'inbox.publish', 'scheduled_id', v_row."id"), delay => greatest(ceil(extract(epoch from (v_row."scheduled_at" - now())))::integer, 0), dedupe_key => 'inbox-publish:' || v_row."id"::text || ':' || extract(epoch from v_row."scheduled_at")::text, dedupe_running => false);
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reset_webhook_endpoint()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  if new."enabled" and not old."enabled" then
    new."first_failed_at" := null;
    new."disabled_at" := null;
    new."disabled_reason" := null;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.resolve_share_link (
  token    text,
  password text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_link "better_supabase"."share_links"%rowtype;
  v_retry integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_link
  from "better_supabase"."share_links" l
  where l."token_hash" = encode(extensions.digest(convert_to(resolve_share_link.token, 'utf8'), 'sha256'), 'hex')
    and l."revoked_at" is null
    and (l."expires_at" is null or l."expires_at" > now())
    and (l."max_uses" is null or l."use_count" < l."max_uses")
  for update;
  if not found then
    return null;
  end if;
  if v_link."password_hash" is not null then
    if resolve_share_link.password is null then
      return jsonb_build_object('passwordRequired', true);
    end if;
    select greatest(1, ceil(extract(epoch from k."window_started_at" + k."period" - now()))::integer) into v_retry
    from "better_supabase"."rate_limits" k
    where k."scope" = 'share_link_password' and k."key" = v_link."id"::text
      and k."window_started_at" + k."period" > now()
      and k."hits" >= coalesce((select q."max_requests" from "better_supabase"."rate_limit_rules" q where q."scope" = 'share_link_password'), 10);
    if v_retry is not null then
      raise exception 'too many wrong passwords for this link' using errcode = 'BS429', hint = 'SHARE_LINK_RATE_LIMITED', detail = 'retry after ' || v_retry;
    end if;
    if extensions.crypt(resolve_share_link.password, v_link."password_hash") <> v_link."password_hash" then
      perform 1 from "better_supabase"."hit_rate_limit"('share_link_password', v_link."id"::text, case when exists (select 1 from "better_supabase"."rate_limit_rules" q where q."scope" = 'share_link_password') then null else 10 end, case when exists (select 1 from "better_supabase"."rate_limit_rules" q where q."scope" = 'share_link_password') then null else interval '15 minutes' end);
      return jsonb_build_object('passwordRequired', true);
    end if;
  end if;
  update "better_supabase"."share_links" set "use_count" = "use_count" + 1, "last_used_at" = now() where "id" = v_link."id";
  return jsonb_build_object('id', v_link."id", 'organizationId', v_link."tenant_id", 'subjectType', v_link."subject_type", 'subjectId', v_link."subject_id", 'role', v_link."role", 'versionId', v_link."version_id", 'expiresAt', v_link."expires_at", 'maxUses', v_link."max_uses", 'downloadAllowed', v_link."download_allowed", 'passwordRequired', v_link."password_hash" is not null);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.revoke_pass (
  pass_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."passes"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."passes" x where x."id" = revoke_pass.pass_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'passes.manage'), false)) then
    raise exception 'pass not found' using errcode = 'P0002', hint = 'PASS_NOT_FOUND';
  end if;
  if v_row."status" <> 'revoked' then
    update "better_supabase"."passes" x set "status" = 'revoked', "revoked_at" = now(), "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    perform "better_supabase".emit_event('pass.revoked', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id"), 'passes/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/passes');
  perform better_supabase.audit_event(
    event_type => 'pass.revoked',
    category => 'access',
    target_type => 'pass',
    record_id => v_row."id"::text,
    summary => 'revoked pass ' || v_row."kind",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'kind', v_row."kind", 'holderUserId', v_row."holder_user_id", 'holderName', v_row."holder_name", 'holderEmail', v_row."holder_email", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'bookingId', v_row."booking_id", 'resourceId', v_row."resource_id", 'usesAllowed', v_row."uses_allowed", 'uses', v_row."uses", 'validFrom', v_row."starts_at", 'validUntil', v_row."expires_at", 'status', v_row."status", 'issuedBy', v_row."issued_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'revokedAt', v_row."revoked_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_ai_harness_session (
  chat    uuid,
  harness text,
  fields  jsonb,
  holder  text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_chat "better_supabase"."ai_chats";
  v_row "better_supabase"."ai_harness_sessions";
  v_status text := save_ai_harness_session.fields ->> 'status';
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  if nullif(save_ai_harness_session.harness, '') is null then
    raise exception 'A harness session needs a harness id' using errcode = '22023', hint = 'AI_HARNESS_INVALID';
  end if;
  if jsonb_typeof(save_ai_harness_session.fields) is distinct from 'object'
    or (v_status is not null and v_status not in ('active', 'idle', 'stopped', 'error')) then
    raise exception 'fields must be an object and status active, idle, stopped or error' using errcode = '22023', hint = 'AI_HARNESS_INVALID';
  end if;
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = save_ai_harness_session.chat;
  if not found then
    raise exception 'No chat %', save_ai_harness_session.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_harness_sessions" ("chat_id", "harness_id", "owner_id")
  values (v_chat."id", save_ai_harness_session.harness, v_chat."owner_id")
  on conflict ("chat_id", "harness_id") do nothing;
  select * into v_row from "better_supabase"."ai_harness_sessions" x
  where x."chat_id" = v_chat."id" and x."harness_id" = save_ai_harness_session.harness
  for update;
  if v_row."lock_expires_at" > now() and v_row."lock_holder" is distinct from save_ai_harness_session.holder then
    raise exception 'Harness session % is locked', save_ai_harness_session.harness using errcode = '55P03', hint = 'AI_HARNESS_LOCKED';
  end if;
  update "better_supabase"."ai_harness_sessions" x set
    "resume_state" = case when save_ai_harness_session.fields ? 'resume_state' then save_ai_harness_session.fields -> 'resume_state' else x."resume_state" end,
    "continue_state" = case when save_ai_harness_session.fields ? 'continue_state' then save_ai_harness_session.fields -> 'continue_state' else x."continue_state" end,
    -- A save without a status is a turn using the sandbox: an idle session
    -- turns active again.
    "status" = coalesce(v_status, case when x."status" = 'idle' then 'active' else x."status" end),
    "last_active_at" = now(),
    "updated_at" = now()
  where x."chat_id" = v_row."chat_id" and x."harness_id" = v_row."harness_id"
  returning * into v_row;
  if save_ai_harness_session.fields ? 'sandbox_id' then
    if nullif(save_ai_harness_session.fields ->> 'sandbox_id', '') is null then
      update "better_supabase"."ai_sandboxes" y set "status" = 'stopped', "stopped_at" = now(), "updated_at" = now()
      where y."chat_id" = v_row."chat_id" and y."harness_id" = v_row."harness_id" and y."status" <> 'stopped';
    else
      insert into "better_supabase"."ai_sandboxes" as cur ("organization_id", "user_id", "chat_id", "harness_id", "provider", "sandbox_id")
      values (v_chat."organization_id", v_chat."owner_id", v_chat."id", v_row."harness_id", coalesce(nullif(save_ai_harness_session.fields ->> 'sandbox_provider', ''), 'harness'), save_ai_harness_session.fields ->> 'sandbox_id')
      on conflict ("provider", "sandbox_id") do update set
        "chat_id" = excluded."chat_id",
        "harness_id" = excluded."harness_id",
        "status" = 'running',
        "error" = null,
        "stopped_at" = null,
        "last_used_at" = now(),
        "updated_at" = now()
      where cur."organization_id" is not distinct from excluded."organization_id";
      if not found then
        raise exception 'sandbox % belongs to another tenant', save_ai_harness_session.fields ->> 'sandbox_id' using errcode = '42501', hint = 'AI_SANDBOX_FORBIDDEN';
      end if;
    end if;
  elsif save_ai_harness_session.fields ->> 'status' is null then
    update "better_supabase"."ai_sandboxes" y set "last_used_at" = now(), "updated_at" = now()
    where y."chat_id" = v_row."chat_id" and y."harness_id" = v_row."harness_id" and y."status" = 'running';
  end if;
  return jsonb_build_object('chat_id', v_row."chat_id", 'harness_id', v_row."harness_id", 'owner_id', v_row."owner_id", 'resume_state', v_row."resume_state", 'continue_state', v_row."continue_state", 'sandbox_id', (select y."sandbox_id" from "better_supabase"."ai_sandboxes" y where y."chat_id" = v_row."chat_id" and y."harness_id" = v_row."harness_id" and y."status" <> 'stopped' order by y."last_used_at" desc limit 1), 'status', v_row."status", 'lock_holder', v_row."lock_holder", 'lock_expires_at', v_row."lock_expires_at", 'last_active_at', v_row."last_active_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_calendar_event (
  calendar_id uuid,
  item        jsonb,
  actor       uuid  DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_item jsonb := coalesce(save_calendar_event.item, '{}'::jsonb);
  v_tenant uuid;
  v_tz text;
  v_id uuid := nullif(v_item ->> 'id', '')::uuid;
  v_master uuid := nullif(v_item ->> 'recurrenceId', '')::uuid;
  v_uid text := nullif(v_item ->> 'uid', '');
  v_created boolean := false;
  v_actor uuid := coalesce(save_calendar_event.actor, auth.uid());
  v_exdates timestamptz[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "tz" into v_tenant, v_tz from "better_supabase"."calendars" where "id" = save_calendar_event.calendar_id;
  if not found then
    raise exception 'calendar not found' using errcode = 'P0002', hint = 'CALENDAR_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if save_calendar_event.actor is not null and save_calendar_event.actor is distinct from auth.uid() and auth.role() <> 'service_role' then
    raise exception 'only the service role saves an event as another user' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;

  if v_item ? 'status' and v_item ->> 'status' not in ('confirmed', 'tentative', 'cancelled') then
    raise exception 'status must be confirmed, tentative or cancelled' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  if v_item ? 'kind' and v_item ->> 'kind' not in ('event', 'out_of_office', 'focus_time') then
    raise exception 'kind must be event, out_of_office or focus_time' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  if v_item ? 'transparency' and v_item ->> 'transparency' not in ('opaque', 'transparent') then
    raise exception 'transparency must be opaque or transparent' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  if v_item ? 'tz' and not exists (select 1 from pg_catalog.pg_timezone_names where name = v_item ->> 'tz') then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'CALENDAR_TZ_INVALID';
  end if;
  select coalesce(array_agg(value::timestamptz order by value::timestamptz), '{}')
    into v_exdates from jsonb_array_elements_text(coalesce(v_item -> 'exdates', '[]'::jsonb));
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_calendar_event_save"(uuid, uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::jsonb)', v_hook::oid::regproc)
        using v_tenant, save_calendar_event.calendar_id, v_item;
    end if;
  end;
  if v_id is null then
    if v_master is not null then
      select "uid" into v_uid from "better_supabase"."calendar_events"
        where "id" = v_master and "calendar_id" = save_calendar_event.calendar_id and "recurrence_id" is null and "rrule" is not null;
      if not found or v_item ->> 'originalStart' is null then
        raise exception 'an override needs a recurring event and an originalStart' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
      end if;
    end if;
    if v_item ->> 'startsAt' is null or v_item ->> 'endsAt' is null then
      raise exception 'an event needs startsAt and endsAt' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
    end if;
    v_id := gen_random_uuid();
    v_uid := coalesce(v_uid, v_id::text);
    insert into "better_supabase"."calendar_events" ("id", "tenant_id", "calendar_id", "uid", "recurrence_id", "original_starts_at", "title", "starts_at", "ends_at", "all_day", "tz", "status", "rrule", "exdates", "description", "location", "color", "kind", "transparency", "auto_decline", "subject_type", "subject_id", "created_by")
    values (v_id, v_tenant, save_calendar_event.calendar_id, v_uid, v_master, (v_item ->> 'originalStart')::timestamptz, coalesce(v_item ->> 'title', ''), (v_item ->> 'startsAt')::timestamptz, (v_item ->> 'endsAt')::timestamptz, coalesce((v_item ->> 'allDay')::boolean, false), coalesce(v_item ->> 'tz', v_tz), coalesce(v_item ->> 'status', 'confirmed'), nullif(v_item ->> 'rrule', ''), v_exdates, v_item ->> 'description', v_item ->> 'location', v_item ->> 'color', coalesce(v_item ->> 'kind', 'event'), coalesce(v_item ->> 'transparency', 'opaque'), coalesce((v_item ->> 'autoDecline')::boolean, false), v_item ->> 'subjectType', v_item ->> 'subjectId', v_actor);
    v_created := true;
  else
    update "better_supabase"."calendar_events" set
    "title" = case when v_item ? 'title' then coalesce(v_item ->> 'title', '') else "title" end,
    "starts_at" = case when v_item ? 'startsAt' then (v_item ->> 'startsAt')::timestamptz else "starts_at" end,
    "ends_at" = case when v_item ? 'endsAt' then (v_item ->> 'endsAt')::timestamptz else "ends_at" end,
    "all_day" = case when v_item ? 'allDay' then coalesce((v_item ->> 'allDay')::boolean, false) else "all_day" end,
    "tz" = case when v_item ? 'tz' then coalesce(v_item ->> 'tz', v_tz) else "tz" end,
    "status" = case when v_item ? 'status' then coalesce(v_item ->> 'status', 'confirmed') else "status" end,
    "rrule" = case when v_item ? 'rrule' then nullif(v_item ->> 'rrule', '') else "rrule" end,
    "description" = case when v_item ? 'description' then v_item ->> 'description' else "description" end,
    "location" = case when v_item ? 'location' then v_item ->> 'location' else "location" end,
    "color" = case when v_item ? 'color' then v_item ->> 'color' else "color" end,
    "kind" = case when v_item ? 'kind' then coalesce(v_item ->> 'kind', 'event') else "kind" end,
    "transparency" = case when v_item ? 'transparency' then coalesce(v_item ->> 'transparency', 'opaque') else "transparency" end,
    "auto_decline" = case when v_item ? 'autoDecline' then coalesce((v_item ->> 'autoDecline')::boolean, false) else "auto_decline" end,
    "subject_type" = case when v_item ? 'subjectType' then v_item ->> 'subjectType' else "subject_type" end,
    "subject_id" = case when v_item ? 'subjectId' then v_item ->> 'subjectId' else "subject_id" end,
    "exdates" = case when v_item ? 'exdates' then v_exdates else "exdates" end,
    "updated_at" = now()
    where "id" = v_id and "calendar_id" = save_calendar_event.calendar_id
    returning "uid" into v_uid;
    if not found then
      raise exception 'event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
    end if;
  end if;
  if v_item ? 'alarms' then
    if jsonb_typeof(v_item -> 'alarms') <> 'array' or jsonb_array_length(v_item -> 'alarms') > 20 then
      raise exception 'alarms must be an array of at most 20' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
    end if;
    if exists (
      select 1 from jsonb_array_elements(v_item -> 'alarms') x
      where jsonb_typeof(x) <> 'object'
        or coalesce(x ->> 'method', 'display') not in ('display', 'email', 'audio')
        or coalesce(x ->> 'related', 'start') not in ('start', 'end')
        or (x ->> 'offsetMinutes' is null) = (x ->> 'at' is null)
        or abs(coalesce((x ->> 'offsetMinutes')::integer, 0)) > 525600
        or coalesce((x ->> 'repeat')::integer, 0) < 0
        or (coalesce((x ->> 'repeat')::integer, 0) > 0) <> (x ->> 'repeatMinutes' is not null)
        or coalesce((x ->> 'repeatMinutes')::integer, 1) <= 0
    ) then
      raise exception 'each alarm needs a method of display, email or audio, offsetMinutes or at, and repeat with repeatMinutes' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
    end if;
    delete from "better_supabase"."calendar_event_alarms" where "event_id" = v_id and "user_id" is null;
    insert into "better_supabase"."calendar_event_alarms" ("tenant_id", "event_id", "offset_minutes", "method", "related_to", "trigger_at", "repeat_count", "repeat_minutes", "description", "summary")
    select v_tenant, v_id, (x ->> 'offsetMinutes')::integer, coalesce(x ->> 'method', 'display'), coalesce(x ->> 'related', 'start'), (x ->> 'at')::timestamptz, coalesce((x ->> 'repeat')::integer, 0), (x ->> 'repeatMinutes')::integer, x ->> 'description', x ->> 'summary'
    from jsonb_array_elements(v_item -> 'alarms') x;
  end if;
  if exists (select 1 from "better_supabase"."calendar_events" where "id" = v_id and "ends_at" < "starts_at") then
    raise exception 'endsAt must not be before startsAt' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
  select e."tenant_id", 'calendar_event', e."id"::text, e."starts_at", e."tz", coalesce(e."rrule", 'FREQ=DAILY;COUNT=1')
  from "better_supabase"."calendar_events" e where e."id" = v_id
  on conflict ("tenant_id", "subject_type", "subject_id")
  do update set "dtstart" = excluded."dtstart", "tzid" = excluded."tzid", "rrule" = excluded."rrule";
  if v_created then
    perform "better_supabase".emit_event('calendar_event.created', jsonb_build_object('organizationId', v_tenant, 'id', v_id, 'calendarId', save_calendar_event.calendar_id), 'calendar-events/' || v_id::text, (v_tenant)::text, null, 'better-supabase/calendar');
  else
    perform "better_supabase".emit_event('calendar_event.updated', jsonb_build_object('organizationId', v_tenant, 'id', v_id, 'calendarId', save_calendar_event.calendar_id), 'calendar-events/' || v_id::text, (v_tenant)::text, null, 'better-supabase/calendar');
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_calendar_event_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'uid', v_uid, 'created', v_created);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.schedule_inbox_message (
  conversation uuid,
  input        jsonb,
  scheduled_at timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_row "better_supabase"."scheduled_inbox_messages"%rowtype;
  v_input jsonb := coalesce(input, '{}'::jsonb) - 'files' - 'external_id' - 'author_type' - 'delivered_by_caller';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."inbox_conversations" where "id" = schedule_inbox_message.conversation;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if (select auth.uid()) is null or not coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.reply'), false) then
    raise exception 'not allowed to reply in this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if coalesce(v_input ->> 'kind', 'message') <> 'message' then
    raise exception 'only messages can be scheduled' using errcode = '22023', hint = 'INBOX_KIND_INVALID';
  end if;
  if length(btrim(coalesce(v_input ->> 'body', ''))) = 0 and coalesce(jsonb_array_length(v_input -> 'attachments'), 0) = 0 then
    raise exception 'a message needs a body or an attachment' using errcode = '22023', hint = 'INBOX_MESSAGE_EMPTY';
  end if;
  if length(coalesce(v_input ->> 'body', '')) > 20000 then
    raise exception 'a message is at most 20000 characters' using errcode = '22023', hint = 'INBOX_MESSAGE_TOO_LONG';
  end if;
  if schedule_inbox_message.scheduled_at is null or schedule_inbox_message.scheduled_at <= now() then
    raise exception 'scheduled_at must be in the future' using errcode = '22023', hint = 'INBOX_SCHEDULE_TIME';
  end if;
  insert into "better_supabase"."scheduled_inbox_messages" ("tenant_id", "conversation_id", "author_id", "input", "scheduled_at")
  values (v_conv."tenant_id", v_conv."id", (select auth.uid()), v_input, schedule_inbox_message.scheduled_at)
  returning * into v_row;
  perform "better_supabase"."enqueue_job"(queue => 'inbox_schedule', payload => jsonb_build_object('type', 'inbox.publish', 'scheduled_id', v_row."id"), delay => greatest(ceil(extract(epoch from (v_row."scheduled_at" - now())))::integer, 0), dedupe_key => 'inbox-publish:' || v_row."id"::text || ':' || extract(epoch from v_row."scheduled_at")::text, dedupe_running => false);
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.send_message (
  conversation uuid,
  body         text,
  attrs        jsonb  DEFAULT '{}'::jsonb,
  attachments  uuid[] DEFAULT '{}'::uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."conversations";
  v_id uuid;
  v_parent uuid := nullif(send_message.attrs ->> 'parentId', '')::uuid;
  v_root uuid;
  v_parsed jsonb := "better_supabase"."parse_mentions"(send_message.body);
  v_mentions uuid[];
  v_scheduled timestamptz := nullif(send_message.attrs ->> 'scheduledFor', '')::timestamptz;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."conversations" c where c."id" = send_message.conversation;
  if not found or not "better_supabase"."can_conversation"(v_conv."id", 'read') then
    raise exception 'no such conversation you can read' using errcode = 'P0002', hint = 'MESSAGING_NOT_FOUND';
  end if;
  if v_conv."kind" = 'inbox' then
    raise exception 'write to an inbox conversation through send_inbox_message' using errcode = '42501', hint = 'MESSAGING_FORBIDDEN';
  end if;
  if v_conv."access" = 'tenant' and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and v_conv."archived_at" is null
    and coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'messages.send'), false) then
    perform "better_supabase"."add_conversation_members"(v_conv."id", array[auth.uid()]);
  end if;
  if not "better_supabase"."can_conversation"(v_conv."id", 'send') then
    raise exception 'not allowed to send messages here' using errcode = '42501', hint = 'MESSAGING_FORBIDDEN';
  end if;
  if nullif(trim(coalesce(send_message.body, '')), '') is null and cardinality(coalesce(send_message.attachments, '{}')) = 0 then
    raise exception 'a message needs a body or a file' using errcode = '23502', hint = 'MESSAGING_BODY_REQUIRED';
  end if;
  if v_parent is not null then
    select m."thread_id" into v_root from "better_supabase"."messages" m
    where m."id" = v_parent and m."conversation_id" = v_conv."id"
      and m."sent_at" is not null and m."deleted_at" is null;
    if not found then
      raise exception 'reply to a sent message in the same conversation' using errcode = '22023', hint = 'MESSAGING_PARENT_INVALID';
    end if;
    -- One level of threads: a reply to a reply joins the root's thread.
    v_parent := coalesce(v_root, v_parent);
  end if;
  if v_parent is null and send_message.attrs -> 'anchor' ->> 'kind' = 'file' then
    if not "better_supabase"."messaging_file_anchor_valid"(send_message.attrs -> 'anchor') then
      raise exception 'a file anchor needs an attachmentId, a page from 1, a region inside 0 to 1 and a time span from 0' using errcode = '22023', hint = 'MESSAGING_ANCHOR_INVALID';
    end if;
    if not exists (
      select 1 from "better_supabase"."attachments" a
      where a."id" = (send_message.attrs -> 'anchor' ->> 'attachmentId')::uuid
        and a."organization_id" = v_conv."tenant_id"
        and a."status" <> 'infected'
        and ((a."subject_type" = v_conv."subject_type" and a."subject_id" = v_conv."subject_id")
          or (a."subject_type" = 'message' and exists (
            select 1 from "better_supabase"."messages" m
            where m."id"::text = a."subject_id" and m."conversation_id" = v_conv."id")))
    ) then
      raise exception 'anchor the message to a file on this record or in this conversation' using errcode = '22023', hint = 'MESSAGING_ANCHOR_INVALID';
    end if;
  end if;
  if v_scheduled is not null and v_scheduled <= now() then
    v_scheduled := null;
  end if;
  v_mentions := array(
    select distinct x from (
      select (jsonb_array_elements_text(coalesce(send_message.attrs -> 'mentions', '[]'::jsonb)))::uuid as x
      union
      select (jsonb_array_elements_text(v_parsed -> 'users'))::uuid
    ) s
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_message_send"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using send_message.conversation, send_message.body, send_message.attrs;
    end if;
  end;
  begin
    insert into "better_supabase"."messages" ("tenant_id", "conversation_id", "parent_id", "thread_id", "author_id", "body", "document", "anchor",
      "mentions", "mention_scope", "broadcast", "scheduled_at", "sent_at")
    values (v_conv."tenant_id", v_conv."id", v_parent, case when v_parent is null then null else coalesce(v_root, v_parent) end,
      auth.uid(), coalesce(send_message.body, ''), send_message.attrs -> 'document',
      case when v_parent is null then send_message.attrs -> 'anchor' end, v_mentions,
      case when v_conv."access" = 'subject' then null else v_parsed ->> 'scope' end,
      v_parent is not null and coalesce((send_message.attrs ->> 'broadcast')::boolean, false),
      v_scheduled, case when v_scheduled is null then now() end)
    returning "id" into v_id;
  exception when check_violation or invalid_text_representation or datetime_field_overflow then
    raise exception 'a message field has an invalid value' using errcode = '22023', hint = 'MESSAGING_MESSAGE_INVALID';
  end;
  -- Files the caller uploaded to the conversation move onto the message.
  if cardinality(coalesce(send_message.attachments, '{}')) > 0 then
    update "better_supabase"."attachments" a
    set "subject_type" = 'message', "subject_id" = v_id::text
    where a."id" = any (send_message.attachments)
      and a."organization_id" = v_conv."tenant_id"
      and a."subject_type" = 'conversation' and a."subject_id" = v_conv."id"::text
      and a."uploaded_by" = auth.uid()
      and a."status" <> 'infected';
    get diagnostics v_count = row_count;
    if v_count <> cardinality(array(select distinct x from unnest(send_message.attachments) x)) then
      raise exception 'attach files you uploaded to this conversation' using errcode = '22023', hint = 'MESSAGING_ATTACHMENT_INVALID';
    end if;
  end if;
  if v_scheduled is null then
    perform "better_supabase"."messaging_message_sent"(v_id);
  else
    perform "better_supabase"."enqueue_job"(queue => 'messaging', payload => jsonb_build_object('type', 'message.publish', 'messageId', v_id), delay => greatest(ceil(extract(epoch from (v_scheduled - now())))::integer, 0), dedupe_key => 'message.publish:' || v_id::text, dedupe_running => false);
    null;
  end if;
  return "better_supabase"."messaging_messages_json"(array[v_id]) -> 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_conversation_status (
  conversation      uuid,
  status            text,
  snooze_expires_at timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_before text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."inbox_conversations" where "id" = set_conversation_status.conversation for update;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.reply'), false)) then
    raise exception 'not allowed to change this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if status = 'snoozed' and (snooze_expires_at is null or snooze_expires_at <= now()) then
    raise exception 'snoozing needs a snooze_expires_at in the future' using errcode = '22023', hint = 'INBOX_SNOOZE_UNTIL';
  end if;
  v_before := v_conv."status";
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_inbox_conversation_status_change"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_conv."id", set_conversation_status.status;
    end if;
  end;
  update "better_supabase"."inbox_conversations" set
    "status" = set_conversation_status.status,
    "snooze_expires_at" = case when set_conversation_status.status = 'snoozed' then set_conversation_status.snooze_expires_at end,
    "resolved_at" = case when set_conversation_status.status = 'resolved' then now() end
  where "id" = v_conv."id"
  returning * into v_conv;
  if status = 'snoozed' then
    perform "better_supabase"."enqueue_job"(queue => 'inbox_schedule', payload => jsonb_build_object('type', 'inbox.wake', 'conversation_id', v_conv."id"), delay => greatest(ceil(extract(epoch from (set_conversation_status.snooze_expires_at - now())))::integer, 0), dedupe_key => 'inbox-wake:' || v_conv."id"::text || ':' || extract(epoch from set_conversation_status.snooze_expires_at)::text, dedupe_running => false);
  end if;
  if v_before is distinct from status then
    insert into "better_supabase"."inbox_conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'status', (select auth.uid()), jsonb_build_object('from', v_before, 'to', set_conversation_status.status));
    if status = 'resolved' then
      perform "better_supabase".emit_event('inbox_conversation.resolved', jsonb_build_object('conversationId', v_conv."id", 'organizationId', v_conv."tenant_id"::text, 'inboxId', v_conv."inbox_id", 'contactId', v_conv."contact_id", 'assigneeId', v_conv."assignee_id", 'status', v_conv."status"), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id")::text, null, 'better-supabase/inbox');
    elsif v_before = 'resolved' then
      perform "better_supabase".emit_event('inbox_conversation.reopened', jsonb_build_object('conversationId', v_conv."id", 'organizationId', v_conv."tenant_id"::text, 'inboxId', v_conv."inbox_id", 'contactId', v_conv."contact_id", 'assigneeId', v_conv."assignee_id", 'status', v_conv."status"), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id")::text, null, 'better-supabase/inbox');
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_inbox_conversation_status_change"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_conv."id";
    end if;
  end;
  return "better_supabase"."inbox_conversation_json"(v_conv."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_inbound_event_status (
  event    uuid,
  status   text,
  error    text     DEFAULT NULL::text,
  retry_in interval DEFAULT NULL::interval,
  lease    interval DEFAULT '00:05:00'::interval
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  update "better_supabase"."inbox_inbound_events" e set
    "status" = status,
    "error" = error,
    "available_at" = case when status = 'failed' then now() + coalesce(retry_in, least(interval '1 hour', interval '1 second' * power(2, e."attempts"))) else e."available_at" end,
    "lock_expires_at" = case when status = 'processing' then now() + coalesce(lease, interval '5 minutes') else null end,
    "attempts" = e."attempts" + case when status = 'processing' then 1 else 0 end,
    "processed_at" = case when status in ('processed', 'ignored') then now() else e."processed_at" end
  where e."id" = event;
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_price (
  variant    uuid,
  currency   text,
  amount     text,
  compare_at text,
  price_list uuid,
  starts_at  timestamp with time zone,
  expires_at timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_amount bigint := case when set_price.amount ~ '^[0-9]{1,18}$' then set_price.amount::bigint end;
  v_compare bigint := case when set_price.compare_at ~ '^[0-9]{1,18}$' then set_price.compare_at::bigint end;
  v_id uuid;
  v_previous bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."product_variants" x where x."id" = set_price.variant for update;
  if v_tenant is null then
    raise exception 'variant not found' using errcode = 'P0002', hint = 'CATALOG_VARIANT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if "better_supabase"."currency_minor_units"(set_price.currency) is null then
    raise exception 'not an ISO 4217 currency code' using errcode = '22023', hint = 'CATALOG_CURRENCY_INVALID';
  end if;
  if v_amount is null then
    raise exception 'the amount must be a whole number of minor units' using errcode = '22023', hint = 'CATALOG_AMOUNT_INVALID';
  end if;
  if set_price.compare_at is not null and (v_compare is null or v_compare <= v_amount) then
    raise exception 'the compare-at amount must be above the amount' using errcode = '22023', hint = 'CATALOG_COMPARE_AT_INVALID';
  end if;
  if set_price.expires_at is not null and set_price.expires_at <= coalesce(set_price.starts_at, '-infinity'::timestamptz) then
    raise exception 'expires_at must be after starts_at' using errcode = '22023', hint = 'CATALOG_VALIDITY_INVALID';
  end if;
  if set_price.price_list is not null and not exists (select 1 from "better_supabase"."catalog_price_lists" x where x."id" = set_price.price_list and x."tenant_id" = v_tenant) then
    raise exception 'price list not found' using errcode = 'P0002', hint = 'CATALOG_PRICE_LIST_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_price_set"(uuid, text, bigint, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::bigint, $4::uuid)', v_hook::oid::regproc)
        using set_price.variant, set_price.currency, v_amount, set_price.price_list;
    end if;
  end;
  select x."id", x."amount" into v_id, v_previous from "better_supabase"."product_prices" x
  where x."variant_id" = set_price.variant and x."currency" = set_price.currency and x."price_list_id" is not distinct from set_price.price_list
    and x."starts_at" is not distinct from set_price.starts_at and x."expires_at" is not distinct from set_price.expires_at;
  if exists (
    select 1 from "better_supabase"."product_prices" x
    where x."variant_id" = set_price.variant and x."currency" = set_price.currency and x."price_list_id" is not distinct from set_price.price_list
      and x."id" is distinct from v_id
      and tstzrange(coalesce(x."starts_at", '-infinity'::timestamptz), coalesce(x."expires_at", 'infinity'::timestamptz), '[)') && tstzrange(coalesce(set_price.starts_at, '-infinity'::timestamptz), coalesce(set_price.expires_at, 'infinity'::timestamptz), '[)')
  ) then
    raise exception 'another price of this variant, currency and list covers part of this window' using errcode = '23P01', hint = 'CATALOG_PRICE_OVERLAP';
  end if;
  if v_id is null then
    insert into "better_supabase"."product_prices" ("tenant_id", "variant_id", "currency", "amount", "price_list_id", "compare_at_amount", "starts_at", "expires_at")
    values (v_tenant, set_price.variant, set_price.currency, v_amount, set_price.price_list, v_compare, set_price.starts_at, set_price.expires_at)
    returning "id" into v_id;
  else
    update "better_supabase"."product_prices" x set "amount" = v_amount, "compare_at_amount" = v_compare, "updated_at" = now()
    where x."id" = v_id;
  end if;
  if v_previous is distinct from v_amount then
    perform "better_supabase".emit_event('catalog.price_changed', jsonb_build_object('organizationId', v_tenant, 'id', v_id, 'variantId', set_price.variant, 'priceListId', set_price.price_list, 'currency', set_price.currency, 'amount', v_amount::text, 'previousAmount', v_previous::text), 'prices/' || v_id::text, (v_tenant)::text, null, 'better-supabase/catalog');
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_price_set"(uuid, bigint)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::bigint)', v_hook::oid::regproc)
        using v_id, v_previous;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'amount', v_amount::text, 'previousAmount', v_previous::text);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_workflow_run_engine (
  run         uuid,
  engine      text,
  external_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_runs"%rowtype;
  v_other "better_supabase"."workflow_runs"%rowtype;
begin
  select * into v_row from "better_supabase"."workflow_runs" x where x."id" = run for update;
  if not found then
    return null;
  end if;
  select * into v_other from "better_supabase"."workflow_runs" x
  where x."engine" = engine and x."external_id" = external_id and x."id" <> run
  for update;
  if found then
    delete from "better_supabase"."workflow_runs" x where x."id" = run;
    update "better_supabase"."workflow_runs" x set "idempotency_key" = coalesce(x."idempotency_key", v_row."idempotency_key"),
      "attributes" = v_row."attributes" || x."attributes",
      "tenant_id" = coalesce(x."tenant_id", v_row."tenant_id"),
      "actor_id" = coalesce(x."actor_id", v_row."actor_id"),
      "updated_at" = now()
    where x."id" = v_other."id"
    returning * into v_row;
    return jsonb_build_object(
    'id', v_row."id",
    'engine', v_row."engine",
    'externalId', v_row."external_id",
    'definition', v_row."definition",
    'tenant', v_row."tenant_id",
    'actor', v_row."actor_id",
    'status', v_row."status",
    'attributes', v_row."attributes",
    'error', v_row."error",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at",
    'startedAt', v_row."started_at",
    'completedAt', v_row."completed_at",
    'cancelRequestedAt', v_row."cancel_requested_at",
    'subjectType', v_row."subject_type",
    'subjectId', v_row."subject_id",
    'principalKind', v_row."principal_kind",
    'principalId', v_row."principal_id",
    'mode', v_row."mode",
    'triggerNode', v_row."trigger_node",
    'idempotencyKey', v_row."idempotency_key"
  );
  end if;
  update "better_supabase"."workflow_runs" x set "engine" = engine, "external_id" = external_id, "dispatch_expires_at" = null, "updated_at" = now()
  where x."id" = run
  returning * into v_row;
  return jsonb_build_object(
    'id', v_row."id",
    'engine', v_row."engine",
    'externalId', v_row."external_id",
    'definition', v_row."definition",
    'tenant', v_row."tenant_id",
    'actor', v_row."actor_id",
    'status', v_row."status",
    'attributes', v_row."attributes",
    'error', v_row."error",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at",
    'startedAt', v_row."started_at",
    'completedAt', v_row."completed_at",
    'cancelRequestedAt', v_row."cancel_requested_at",
    'subjectType', v_row."subject_type",
    'subjectId', v_row."subject_id",
    'principalKind', v_row."principal_kind",
    'principalId', v_row."principal_id",
    'mode', v_row."mode",
    'triggerNode', v_row."trigger_node",
    'idempotencyKey', v_row."idempotency_key"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.shipment_events_append_only()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  if tg_op = 'DELETE' and current_setting('better_supabase.purge_tenant', true) = to_jsonb(old) ->> tg_argv[0] then
    if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and exists (
      select 1 from "better_supabase"."organization_deletions" x
      where x."organization_id"::text = to_jsonb(old) ->> tg_argv[0]
        and x."cancelled_at" is null and x."purged_at" is null and x."purge_at" <= now()
    ) then
      return old;
    end if;
  end if;
  raise exception 'tracking events can''t be changed or deleted; record a later event' using errcode = '55000', hint = 'SHIPMENT_EVENTS_APPEND_ONLY';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.signing_jwks (
  owner_type text,
  owner_id   text,
  grace      interval DEFAULT NULL::interval
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  return jsonb_build_object('keys', coalesce((
    select jsonb_agg(k."public_jwk" || jsonb_build_object('kid', k."kid", 'use', 'sig')
      order by k."created_at" desc)
    from "better_supabase"."signing_keys" k
    where k."owner_type" = signing_jwks.owner_type
      and k."owner_id" = signing_jwks.owner_id
      and (k."state" = 'active' or k."publish_expires_at" + coalesce(grace, '5 minutes'::interval) > now())
  ), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.split_calendar_event (
  event_id     uuid,
  split_at     timestamp with time zone,
  before_rrule text,
  item         jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_id uuid := split_calendar_event.event_id;
  v_tenant uuid;
  v_calendar uuid;
  v_uid text;
  v_starts timestamptz;
  v_exdates timestamptz[];
  v_new jsonb;
  v_new_id uuid;
  v_new_uid text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "calendar_id", "uid", "starts_at", "exdates"
    into v_tenant, v_calendar, v_uid, v_starts, v_exdates
  from "better_supabase"."calendar_events" where "id" = v_id and "rrule" is not null for update;
  if not found then
    raise exception 'recurring event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if split_calendar_event.split_at <= v_starts or nullif(split_calendar_event.before_rrule, '') is null then
    raise exception 'split at a later occurrence, with the rule that ends the series before it' using errcode = '22023', hint = 'CALENDAR_SPLIT_INVALID';
  end if;
  v_new_uid := v_uid || '-' || to_char(split_calendar_event.split_at at time zone 'UTC', 'YYYYMMDD"T"HH24MISS"Z"');
  update "better_supabase"."calendar_events" set "rrule" = split_calendar_event.before_rrule,
    "exdates" = coalesce((select array_agg(d order by d) from unnest(v_exdates) d where d < split_calendar_event.split_at), '{}'),
    "updated_at" = now()
  where "id" = v_id;
  insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
  select e."tenant_id", 'calendar_event', e."id"::text, e."starts_at", e."tz", coalesce(e."rrule", 'FREQ=DAILY;COUNT=1')
  from "better_supabase"."calendar_events" e where e."id" = v_id
  on conflict ("tenant_id", "subject_type", "subject_id")
  do update set "dtstart" = excluded."dtstart", "tzid" = excluded."tzid", "rrule" = excluded."rrule";
  v_new := "better_supabase"."save_calendar_event"(v_calendar, (coalesce(split_calendar_event.item, '{}'::jsonb) - 'id' - 'recurrenceId' - 'originalStart') || jsonb_build_object(
    'uid', v_new_uid,
    'exdates', coalesce((select jsonb_agg(d order by d) from unnest(v_exdates) d where d >= split_calendar_event.split_at), '[]'::jsonb)
  ));
  v_new_id := (v_new ->> 'id')::uuid;
  update "better_supabase"."calendar_events" set "recurrence_id" = v_new_id, "uid" = v_new_uid, "updated_at" = now()
  where "recurrence_id" = v_id and "original_starts_at" >= split_calendar_event.split_at;
  perform "better_supabase".emit_event('calendar_event.updated', jsonb_build_object('organizationId', v_tenant, 'id', v_id, 'calendarId', v_calendar), 'calendar-events/' || v_id::text, (v_tenant)::text, null, 'better-supabase/calendar');
  return jsonb_build_object('id', v_new_id, 'uid', v_new_uid);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.start_ai_task_run (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_run "better_supabase"."ai_task_runs"%rowtype;
  v_task "better_supabase"."ai_scheduled_tasks"%rowtype;
begin
  update "better_supabase"."ai_task_runs" y set "status" = 'running', "started_at" = now()
  where y."id" = start_ai_task_run.id and y."status" = 'queued'
  returning * into v_run;
  if not found then
    return null;
  end if;
  select * into v_task from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_run."task_id";
  return jsonb_build_object('id', v_run."id", 'task_id', v_run."task_id", 'organization_id', v_run."organization_id", 'user_id', v_run."user_id", 'status', v_run."status", 'scheduled_at', v_run."scheduled_at", 'chat_id', v_run."chat_id", 'error', v_run."error", 'started_at', v_run."started_at", 'finished_at', v_run."finished_at", 'created_at', v_run."created_at") || jsonb_build_object('task', jsonb_build_object('id', v_task."id", 'organization_id', v_task."organization_id", 'user_id', v_task."user_id", 'chat_id', v_task."chat_id", 'agent_id', v_task."agent_id", 'title', v_task."title", 'prompt', v_task."prompt", 'cron', v_task."cron", 'timezone', v_task."timezone", 'enabled', v_task."enabled", 'next_run_at', v_task."next_run_at", 'last_run_at', v_task."last_run_at", 'created_at', v_task."created_at", 'updated_at', v_task."updated_at"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.status_state (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_status text;
  v_tenant text;
  v_step integer;
  v_paused boolean := false;
  v_life "better_supabase"."subject_lifecycles"%rowtype;
  v_order text[];
begin
  case status_state.subject_type
    when 'work_item' then
      select s."state"::text, s."tenant_id"::text into v_status, v_tenant
      from "better_supabase"."work_items" s where s."id" = (status_state.subject_id)::uuid;
      if not found then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;

      v_step := array_position('{triage,backlog,unstarted,started,completed}'::text[], v_status);
      return jsonb_build_object(
        'organizationId', v_tenant, 'subjectType', 'work_item', 'subjectId', status_state.subject_id,
        'status', v_status, 'order', to_jsonb('{triage,backlog,unstarted,started,completed}'::text[]), 'step', v_step, 'steps', 5, 'progress', case when v_step is null then null when 5 = 1 then 1 else round((v_step - 1)::numeric / 4, 4) end,
        'version', null, 'flags', '[]'::jsonb, 'paused', false, 'pausedAt', null, 'pausedUntil', null, 'pauseReason', null);
    when 'change_request' then
      select s."status"::text, s."organization_id"::text into v_status, v_tenant
      from "public"."change_requests" s where s."id" = (status_state.subject_id)::uuid;
      if not found then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;
      select * into v_life from "better_supabase"."subject_lifecycles" x
      where x."subject_type" = 'change_request' and x."subject_id" = status_state.subject_id;
      v_paused := v_life."paused_at" is not null and (v_life."pause_expires_at" is null or v_life."pause_expires_at" > now());
      v_order := coalesce(array(select jsonb_array_elements_text("better_supabase"."lifecycle_graph"(v_life."workflow_version_id") -> 'order')), '{}'::text[]);
      v_step := array_position(v_order, v_status);
      return jsonb_build_object(
        'organizationId', v_tenant, 'subjectType', 'change_request', 'subjectId', status_state.subject_id,
        'status', v_status, 'order', to_jsonb(v_order), 'step', v_step, 'steps', nullif(cardinality(v_order), 0), 'progress', case when v_step is null then null when cardinality(v_order) = 1 then 1 else round((v_step - 1)::numeric / (cardinality(v_order) - 1), 4) end,
        'version', v_life."version", 'flags', to_jsonb(coalesce(v_life."flags", '{}')),
        'paused', v_paused, 'pausedAt', case when v_paused then v_life."paused_at" end,
        'pausedUntil', case when v_paused then v_life."pause_expires_at" end,
        'pauseReason', case when v_paused then v_life."pause_reason" end, 'workflow', 'change-requests', 'workflowVersionId', v_life."workflow_version_id");
    when 'drive_node' then
      select s."document_status"::text, s."tenant_id"::text into v_status, v_tenant
      from "better_supabase"."drive_nodes" s where s."id" = (status_state.subject_id)::uuid;
      if not found then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;

      v_step := array_position(null::text[], v_status);
      return jsonb_build_object(
        'organizationId', v_tenant, 'subjectType', 'drive_node', 'subjectId', status_state.subject_id,
        'status', v_status, 'order', to_jsonb(null::text[]), 'step', v_step, 'steps', null, 'progress', null,
        'version', null, 'flags', '[]'::jsonb, 'paused', false, 'pausedAt', null, 'pausedUntil', null, 'pauseReason', null);
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.trash_cascade (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  batch        uuid,
  depth        integer,
  actor        uuid
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_title text;
  v_count integer := 1;
  v_child text;
  v_item "better_supabase"."trash_items"%rowtype;
begin
  case trash_cascade.subject_type
    when 'message' then
      update "better_supabase"."messages" s set "deleted_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."deleted_at" is null
        returning s."body"::text into v_title;
    when 'conversation' then
      update "better_supabase"."conversations" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."title"::text into v_title;
    when 'deal' then
      update "better_supabase"."deals" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."name"::text into v_title;
    when 'work_item' then
      update "better_supabase"."work_items" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."title"::text into v_title;
    when 'risk' then
      update "better_supabase"."risks" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."title"::text into v_title;
    when 'case' then
      update "better_supabase"."cases" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."title"::text into v_title;
    when 'inspection_program' then
      update "better_supabase"."inspection_programs" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."name"::text into v_title;
    when 'tax_code' then
      update "better_supabase"."tax_codes" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."name"::text into v_title;
    when 'work_center' then
      update "better_supabase"."work_centers" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."name"::text into v_title;
    when 'bank_account' then
      update "better_supabase"."bank_accounts" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."name"::text into v_title;
    when 'customer' then
      update "public"."customers" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."organization_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."name"::text into v_title;
    when 'drive_node' then
      update "better_supabase"."drive_nodes" s set "deleted_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."deleted_at" is null
        returning s."name"::text into v_title;
    when 'project' then
      update "public"."projects" s set "deleted_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."organization_id" = trash_cascade.tenant
          and s."deleted_at" is null
        returning s."name"::text into v_title;
    else
      raise exception 'this subject type has no deletedAt column' using errcode = '22023', hint = 'TRASH_UNSUPPORTED';
  end case;
  if not found then
    return 0;
  end if;
  delete from "better_supabase"."trash_items" i
    where i."subject_type" = trash_cascade.subject_type and i."subject_id" = trash_cascade.subject_id;
  insert into "better_supabase"."trash_items" ("tenant_id", "subject_type", "subject_id", "title", "batch_id", "depth", "trashed_by", "trashed_at", "purge_at")
  values (trash_cascade.tenant, trash_cascade.subject_type, trash_cascade.subject_id, v_title, trash_cascade.batch, trash_cascade.depth, trash_cascade.actor, now(), now() + make_interval(days => 30))
  returning * into v_item;
  perform "better_supabase".emit_event('subject.trashed', jsonb_build_object('organizationId', v_item."tenant_id", 'subjectType', v_item."subject_type", 'subjectId', v_item."subject_id", 'id', v_item."id", 'batchId', v_item."batch_id"), 'trash-items/' || v_item."id"::text, (v_item."tenant_id")::text, null, 'better-supabase/trash');
  perform better_supabase.audit_event(
    event_type => 'subject.trashed',
    category => 'data',
    target_type => 'trash_item',
    record_id => v_item."id"::text,
    summary => 'trashed' || ' ' || v_item."subject_type" || ' ' || v_item."subject_id",
    tenant => (v_item."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_item."tenant_id", 'subjectType', v_item."subject_type", 'subjectId', v_item."subject_id", 'id', v_item."id", 'batchId', v_item."batch_id")
  );
  
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unlock_ai_harness_session (
  chat    uuid,
  harness text,
  holder  text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  update "better_supabase"."ai_harness_sessions" x set "lock_holder" = null, "lock_expires_at" = null, "updated_at" = now()
  where x."chat_id" = unlock_ai_harness_session.chat
    and x."harness_id" = unlock_ai_harness_session.harness
    and x."lock_holder" = unlock_ai_harness_session.holder;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_webhook_endpoint (
  endpoint uuid,
  fields   jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_endpoint jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select d."organization_id" into v_tenant
  from "better_supabase"."webhook_endpoints" d where d."id" = update_webhook_endpoint.endpoint;
  if not found then
    raise exception 'Webhook endpoint not found' using errcode = 'P0002', hint = 'WEBHOOK_ENDPOINT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.can('tenant', v_tenant, 'webhooks.manage'), false) then
    raise exception 'Not allowed to manage this webhook endpoint' using errcode = '42501', hint = 'WEBHOOK_FORBIDDEN';
  end if;
  if jsonb_typeof(coalesce(update_webhook_endpoint.fields, '{}')) <> 'object' or exists (
    select 1 from jsonb_each(coalesce(update_webhook_endpoint.fields, '{}')) e
    where case e.key when 'name' then jsonb_typeof(e.value) <> 'string' when 'url' then jsonb_typeof(e.value) <> 'string' when 'enabled' then jsonb_typeof(e.value) <> 'boolean' when 'eventTypes' then (jsonb_typeof(e.value) <> 'array' or exists (select 1 from jsonb_array_elements(e.value) a where jsonb_typeof(a) <> 'string')) when 'permissions' then (jsonb_typeof(e.value) <> 'null' and (jsonb_typeof(e.value) <> 'array' or exists (select 1 from jsonb_array_elements(e.value) a where jsonb_typeof(a) <> 'string'))) when 'batch' then jsonb_typeof(e.value) <> 'boolean' when 'signing' then jsonb_typeof(e.value) <> 'string' when 'format' then jsonb_typeof(e.value) <> 'string' when 'credentialRef' then jsonb_typeof(e.value) not in ('object', 'null') else true end
  ) then
    raise exception 'A webhook endpoint field is unknown or has the wrong type' using errcode = '22023', hint = 'WEBHOOK_ENDPOINT_INVALID';
  end if;
  if update_webhook_endpoint.fields ? 'url' then
    if update_webhook_endpoint.fields ->> 'url' is null or update_webhook_endpoint.fields ->> 'url' !~* '^https://' then
    raise exception 'A webhook endpoint URL must start with https://' using errcode = '22023', hint = 'WEBHOOK_ENDPOINT_URL';
  end if;
  end if;
  update "better_supabase"."webhook_endpoints" d set "name" = case when update_webhook_endpoint.fields ? 'name' then update_webhook_endpoint.fields ->> 'name' else d."name" end, "url" = case when update_webhook_endpoint.fields ? 'url' then update_webhook_endpoint.fields ->> 'url' else d."url" end, "enabled" = case when update_webhook_endpoint.fields ? 'enabled' then (update_webhook_endpoint.fields ->> 'enabled')::boolean else d."enabled" end, "event_types" = case when update_webhook_endpoint.fields ? 'eventTypes' then array(select jsonb_array_elements_text(update_webhook_endpoint.fields -> 'eventTypes')) else d."event_types" end, "permissions" = case when update_webhook_endpoint.fields ? 'permissions' then case when jsonb_typeof(update_webhook_endpoint.fields -> 'permissions') = 'null' then null else array(select jsonb_array_elements_text(update_webhook_endpoint.fields -> 'permissions')) end else d."permissions" end, "batch" = case when update_webhook_endpoint.fields ? 'batch' then (update_webhook_endpoint.fields ->> 'batch')::boolean else d."batch" end, "signing" = case when update_webhook_endpoint.fields ? 'signing' then update_webhook_endpoint.fields ->> 'signing' else d."signing" end, "format" = case when update_webhook_endpoint.fields ? 'format' then update_webhook_endpoint.fields ->> 'format' else d."format" end, "credential_ref" = case when update_webhook_endpoint.fields ? 'credentialRef' then nullif(update_webhook_endpoint.fields -> 'credentialRef', 'null'::jsonb) else d."credential_ref" end, "updated_at" = now()
  where d."id" = update_webhook_endpoint.endpoint;
  select jsonb_build_object('id', d."id", 'tenant', d."organization_id", 'name', d."name", 'url', d."url", 'enabled', d."enabled", 'eventTypes', d."event_types", 'permissions', d."permissions", 'batch', d."batch", 'signing', d."signing", 'format', d."format", 'credentialRef', d."credential_ref", 'failingSince', d."first_failed_at", 'disabledAt', d."disabled_at", 'disabledReason', d."disabled_reason", 'createdBy', d."created_by", 'createdAt', d."created_at", 'updatedAt', d."updated_at") into v_endpoint
  from "better_supabase"."webhook_endpoints" d where d."id" = update_webhook_endpoint.endpoint;
  return v_endpoint;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.variant_price (
  variant    uuid,
  currency   text,
  price_list uuid                     DEFAULT NULL::uuid,
  as_of      timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'id', x."id",
    'variantId', x."variant_id",
    'currency', x."currency",
    'amount', x."amount"::text,
    'compareAt', x."compare_at_amount"::text,
    'priceListId', x."price_list_id"
  )
  from "better_supabase"."product_prices" x
  where x."variant_id" = $1 and x."currency" = $2
    and (x."price_list_id" is null or x."price_list_id" = $3)
    and tstzrange(coalesce(x."starts_at", '-infinity'::timestamptz), coalesce(x."expires_at", 'infinity'::timestamptz), '[)') @> coalesce($4, now())
  order by (x."price_list_id" is null), x."updated_at" desc
  limit 1
$function$;

CREATE OR REPLACE FUNCTION better_supabase.verify_api_key (
  public_id   text,
  secret_hash text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  found "better_supabase"."api_keys";
  started timestamptz;
  hits integer;
begin
  select * into found from "better_supabase"."api_keys" k where k."public_id" = verify_api_key.public_id;
  if found."id" is null
    or found."secret_hash" <> verify_api_key.secret_hash
    or (found."expires_at" is not null and found."expires_at" <= now())
    or (found."revoked_at" is not null and found."revoked_at" <= now())
    or (found."user_id" is not null and better_supabase.user_disabled(found."user_id"))
    or (found."user_id" is not null and exists (
      select 1 from auth.users u
      where u.id = found."user_id" and (u.banned_until > now() or u.deleted_at is not null)
    ))
    or (found."organization_id" is not null and better_supabase.tenant_disabled(found."organization_id"))
    or (found."user_id" is not null and found."organization_id" is not null
      and better_supabase.organization_member_role(found."organization_id", found."user_id") is null)
  then
    return jsonb_build_object('status', 'invalid');
  end if;
  if found."rate_limit" is not null then
    -- One update counts the hit and, for an allowed request, touches last_used_at.
    update "better_supabase"."api_keys" k set
      "window_started_at" = case when (k."window_started_at" is null or k."window_started_at" + interval '1 minute' <= now()) then now() else k."window_started_at" end,
      "window_hits" = case when (k."window_started_at" is null or k."window_started_at" + interval '1 minute' <= now()) then 1 else k."window_hits" + 1 end,
      "last_used_at" = case when case when (k."window_started_at" is null or k."window_started_at" + interval '1 minute' <= now()) then 1 else k."window_hits" + 1 end <= k."rate_limit" and (k."last_used_at" is null or k."last_used_at" + interval '60 seconds' <= now()) then now() else k."last_used_at" end
    where k."id" = found."id"
    returning k."window_started_at", k."window_hits" into started, hits;
    if hits > found."rate_limit" then
      return jsonb_build_object(
        'status', 'rate_limited',
        'retry_after', greatest(1, ceil(extract(epoch from started + interval '1 minute' - now()))::integer)
      );
    end if;
  elsif (found."last_used_at" is null or found."last_used_at" + interval '60 seconds' <= now()) then
    update "better_supabase"."api_keys" k set "last_used_at" = now() where k."id" = found."id";
  end if;
  return jsonb_build_object('status', 'ok', 'key', jsonb_build_object(
    'id', found."id",
    'organization_id', found."organization_id",
    'user_id', found."user_id",
    'name', found."name",
    'prefix', found."prefix",
    'public_id', found."public_id",
    'scopes', to_jsonb(found."scopes"),
    'kind', found."kind",
    'rate_limit', found."rate_limit",
    'expires_at', found."expires_at",
    'last_used_at', found."last_used_at",
    'revoked_at', found."revoked_at",
    'rotated_from', found."rotated_from",
    'created_by', found."created_by",
    'created_at', found."created_at",
    'state', case
      when found."revoked_at" is not null and found."revoked_at" <= now() then 'revoked'
      when found."expires_at" is not null and found."expires_at" <= now() then 'expired'
      when found."revoked_at" is not null then 'grace'
      else 'active'
    end
  ));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.wake_snoozed_conversations()
  RETURNS integer
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_until timestamptz;
  v_count integer := 0;
  v_claims text;
begin
  for v_conv in
    select * from "better_supabase"."inbox_conversations"
    where "status" = 'snoozed' and "snooze_expires_at" <= now()
    order by "snooze_expires_at"
    for update skip locked
  loop
    v_until := v_conv."snooze_expires_at";
    update "better_supabase"."inbox_conversations" set "status" = 'open', "snooze_expires_at" = null
    where "id" = v_conv."id"
    returning * into v_conv;
    insert into "better_supabase"."inbox_conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
    values (v_conv."tenant_id", v_conv."id", 'unsnoozed', null, jsonb_build_object('snooze_expires_at', v_until));
    perform "better_supabase".emit_event('inbox_conversation.unsnoozed', jsonb_build_object('conversationId', v_conv."id", 'organizationId', v_conv."tenant_id"::text, 'inboxId', v_conv."inbox_id", 'contactId', v_conv."contact_id", 'assigneeId', v_conv."assignee_id", 'status', v_conv."status"), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id")::text, null, 'better-supabase/inbox');
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'inbox.snooze_ended',
      'tenant', v_conv."tenant_id",
      'subject_type', 'conversation',
      'subject_id', v_conv."id"::text,
      'summary', coalesce(v_conv."subject", v_conv."last_message_preview"),
      'recipients', case when v_conv."assignee_id" is not null then to_jsonb(array[v_conv."assignee_id"])
    else coalesce((select jsonb_agg(m."user_id") from "better_supabase"."inbox_members" m where m."inbox_id" = v_conv."inbox_id"), '[]'::jsonb) end,
      'key', 'inbox.snooze_ended:' || v_conv."id"::text || ':' || extract(epoch from v_until)::text,
      'data', jsonb_build_object('conversationId', v_conv."id")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.withdraw_consent (
  consent_id uuid,
  reason     text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."consents";
  v_purpose "better_supabase"."consent_purposes";
  v_reason text := nullif(trim(withdraw_consent.reason), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."consents" x where x."id" = withdraw_consent.consent_id for update;
  if not found then
    raise exception 'no such consent' using errcode = 'P0002', hint = 'CONSENT_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'consents.record'), false) and coalesce("better_supabase"."can_subject"(v_row."subject_type", v_row."subject_id", 'read'), false))
      or ((v_row."tenant_id")::text, (v_row."subject_type")::text, (v_row."subject_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g)
      or exists (select 1 from "better_supabase"."relations" r
      where r."kind" = 'represents' and r."source_type" = 'person'
        and r."tenant_id"::text = (v_row."tenant_id")::text
        and r."target_type" = v_row."subject_type" and r."target_id" = (v_row."subject_id")::text
        and r."data" ->> 'authority' = 'act'
        and (case when r."data" ->> 'valid_from' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_from', 'date') then (r."data" ->> 'valid_from')::date <= current_date
      else false end) and (case when r."data" ->> 'valid_until' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_until', 'date') then (r."data" ->> 'valid_until')::date >= current_date
      else false end)
        and ((v_row."tenant_id")::text, ('person')::text, (r."source_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g))) or coalesce(v_row."given_by_user_id" = auth.uid(), false)) then
    if (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'consents.read'), false) and coalesce("better_supabase"."can_subject"(v_row."subject_type", v_row."subject_id", 'read'), false))
      or ((v_row."tenant_id")::text, (v_row."subject_type")::text, (v_row."subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)
      or ((v_row."tenant_id")::text, (v_row."subject_type")::text, (v_row."subject_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g)
      or exists (select 1 from "better_supabase"."relations" r
      where r."kind" = 'represents' and r."source_type" = 'person'
        and r."tenant_id"::text = (v_row."tenant_id")::text
        and r."target_type" = v_row."subject_type" and r."target_id" = (v_row."subject_id")::text
        and r."data" ->> 'authority' in ('inform', 'act')
        and (case when r."data" ->> 'valid_from' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_from', 'date') then (r."data" ->> 'valid_from')::date <= current_date
      else false end) and (case when r."data" ->> 'valid_until' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_until', 'date') then (r."data" ->> 'valid_until')::date >= current_date
      else false end)
        and ((v_row."tenant_id")::text, ('person')::text, (r."source_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g))) then
      raise exception 'not allowed to withdraw this consent' using errcode = '42501', hint = 'CONSENT_FORBIDDEN';
    end if;
    raise exception 'no such consent' using errcode = 'P0002', hint = 'CONSENT_NOT_FOUND';
  end if;
  if v_row."status" = 'withdrawn' then
    raise exception 'the consent is already withdrawn' using errcode = '22023', hint = 'CONSENT_ALREADY_WITHDRAWN';
  end if;
  if v_row."status" <> 'granted' then
    raise exception 'only a granted consent can be withdrawn' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  if length(v_reason) > 1000 then
    raise exception 'a reason is at most 1000 characters' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_consent_withdraw"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  update "better_supabase"."consents" x set
    "status" = 'withdrawn',
    "withdrawn_at" = now(),
    "withdrawn_reason" = v_reason
  where x."id" = v_row."id"
  returning * into v_row;
  select * into v_purpose from "better_supabase"."consent_purposes" x where x."id" = v_row."purpose_id";
  perform "better_supabase".emit_event('consent.withdrawn', jsonb_build_object('organizationId', v_row."tenant_id", 'consentId', v_row."id", 'purposeId', v_row."purpose_id", 'purposeKey', v_purpose."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'givenBy', v_row."given_by"), 'consents/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/consents');
  perform better_supabase.audit_event(
    event_type => 'consent.withdrawn',
    category => 'data',
    target_type => 'consent',
    record_id => v_row."id"::text,
    target_label => v_purpose."title",
    summary => 'withdrew a consent',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'consentId', v_row."id", 'purposeId', v_row."purpose_id", 'purposeKey', v_purpose."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'givenBy', v_row."given_by")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_consent_withdraw"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'purposeId', v_row."purpose_id", 'purposeKey', v_purpose."key", 'purposeTitle', v_purpose."title", 'purposeVersion', v_purpose."version", 'legalBasis', v_purpose."legal_basis", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'givenBy', v_row."given_by", 'givenByContactId', v_row."given_by_contact_id", 'givenByUserId', v_row."given_by_user_id", 'status', v_row."status", 'scope', coalesce(v_row."scope", '{}'::jsonb), 'grantedAt', v_row."granted_at", 'validUntil', v_row."expires_at", 'withdrawnAt', v_row."withdrawn_at", 'withdrawnReason', v_row."withdrawn_reason", 'signatureId', v_row."signature_id", 'submissionId', v_row."submission_id", 'attachmentId', v_row."attachment_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'active', (v_row."status" = 'granted' and (v_row."expires_at" is null or v_row."expires_at" > now())));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_admission_active (
  key text
)
  RETURNS integer
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select count(*)::integer from "better_supabase"."workflow_start_requests" x
  where x."key" = workflow_admission_active.key
    and (
      (x."status" = 'pending' and x."claim_expires_at" >= now())
      or (x."status" = 'started' and not exists (
        select 1 from "better_supabase"."workflow_runs" y
        where y."external_id" = x."run_id" and y."status" in ('completed', 'failed', 'cancelled')
      ) and x."started_at" > now() - interval '1 day')
    );
$function$;

ALTER TABLE "better_supabase"."calendar_events"
  ADD CONSTRAINT "calendar_events_calendar_id_uid_original_starts_at_key" UNIQUE NULLS NOT DISTINCT (calendar_id, uid, original_starts_at);

REVOKE ALL ON FUNCTION "api"."cancel_calendar_occurrence"(uuid, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."cancel_calendar_occurrence"(uuid, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."issue_pass"(uuid, text, uuid, text, text, text, text, uuid, uuid, integer, timestamp WITH time zone, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "api"."issue_pass"(uuid, text, uuid, text, text, text, text, uuid, uuid, integer, timestamp WITH time zone, timestamp WITH time zone)
  TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."record_consent"(text, text, text, text, text, uuid, timestamp WITH time zone, jsonb, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_consent"(text, text, text, text, text, uuid, timestamp WITH time zone, jsonb, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."reschedule_inbox_message"(uuid, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."reschedule_inbox_message"(uuid, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."schedule_inbox_message"(uuid, jsonb, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."schedule_inbox_message"(uuid, jsonb, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_conversation_status"(uuid, text, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_conversation_status"(uuid, text, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_price"(uuid, text, text, text, uuid, timestamp WITH time zone, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_price"(uuid, text, text, text, uuid, timestamp WITH time zone, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."cancel_calendar_occurrence"(uuid, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."cancel_calendar_occurrence"(uuid, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."issue_pass"(uuid, text, uuid, text, text, text, text, uuid, uuid, integer, timestamp WITH time zone, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "better_supabase"."issue_pass"(uuid, text, uuid, text, text, text, text, uuid, uuid, integer, timestamp WITH time zone, timestamp WITH time zone)
  TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_schedules"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_schedules"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_consent"(text, text, text, text, text, uuid, timestamp WITH time zone, jsonb, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_consent"(text, text, text, text, text, uuid, timestamp WITH time zone, jsonb, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."reschedule_inbox_message"(uuid, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."reschedule_inbox_message"(uuid, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."schedule_inbox_message"(uuid, jsonb, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."schedule_inbox_message"(uuid, jsonb, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_conversation_status"(uuid, text, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_conversation_status"(uuid, text, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_price"(uuid, text, text, text, uuid, timestamp WITH time zone, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_price"(uuid, text, text, text, uuid, timestamp WITH time zone, timestamp WITH time zone) TO "authenticated", "service_role";
