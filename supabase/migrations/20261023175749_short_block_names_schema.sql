SET local check_function_bodies = off;

DROP FUNCTION "better_supabase"."admission_passes_subject_merge"(text, text, text);

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
  if not found or not (v_pass."holder_user_id" = auth.uid() or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_pass."tenant_id", 'passes.manage'), false))) then
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
  if book_with_credit.starts_at < v_pass."valid_from" or (v_pass."valid_until" is not null and book_with_credit.starts_at >= v_pass."valid_until") then
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

CREATE OR REPLACE FUNCTION better_supabase.bulk_step (
  run_id uuid,
  size   integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_run "better_supabase"."bulk_runs"%rowtype;
  v_role text := current_user;
  v_claims text := current_setting('request.jwt.claims', true);
  v_size integer := least(greatest(coalesce(bulk_step.size, 200), 1), 500);
  v_chunk text[];
  v_id text;
  v_ok integer := 0;
  v_failed integer := 0;
  v_results jsonb := '[]'::jsonb;
  v_message text;
  v_hint text;
  v_state text;
  v_allowed boolean;
  v_status text;
  v_done boolean;
begin
  select * into v_run from "better_supabase"."bulk_runs" r where r."id" = bulk_step.run_id for update;
  if not found then
    raise exception 'bulk run not found' using errcode = 'P0002', hint = 'BULK_RUN_NOT_FOUND';
  end if;
  if v_run."status" in ('completed', 'failed') then
    return jsonb_build_object('id', v_run."id", 'status', v_run."status", 'done', true);
  end if;
  v_chunk := v_run."ids"[v_run."position" + 1 : v_run."position" + v_size];
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_run."created_by", 'role', 'authenticated', 'aud', 'authenticated')::text, true);
  set local role authenticated;
  v_allowed := coalesce(better_supabase.can('tenant', v_run."tenant_id", 'bulk.run'), false);
  if v_allowed then
    foreach v_id in array v_chunk loop
    begin
      perform "better_supabase"."bulk_row"(v_run."tenant_id", v_run."subject_type", v_id, v_run."action", v_run."args");
      v_ok := v_ok + 1;
      v_results := v_results || jsonb_build_array(jsonb_build_object('id', v_id, 'ok', true));
    exception when others then
      get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint, v_state = returned_sqlstate;
      if false then
        raise exception using message = v_message, hint = coalesce(v_hint, ''), errcode = v_state;
      end if;
      v_failed := v_failed + 1;
      v_results := v_results || jsonb_build_array(jsonb_build_object('id', v_id, 'ok', false, 'error', jsonb_build_object('code', nullif(v_hint, ''), 'message', v_message, 'sqlstate', v_state)));
    end;
  end loop;
  end if;
  execute format('set local role %I', v_role);
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  v_done := not v_allowed or v_run."position" + cardinality(coalesce(v_chunk, array[]::text[])) >= cardinality(v_run."ids");
  v_status := case when not v_allowed then 'failed' when v_done then 'completed' else 'running' end;
  update "better_supabase"."bulk_runs" set
    "position" = case when v_allowed then "position" + cardinality(coalesce(v_chunk, array[]::text[])) else "position" end,
    "succeeded" = "succeeded" + v_ok,
    "failed" = "failed" + v_failed,
    "results" = "results" || v_results,
    "status" = v_status,
    "finished_at" = case when v_done then now() else null end
  where "id" = v_run."id"
  returning * into v_run;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('id', v_run."id", 'status', v_status, 'position', v_run."position", 'total', cardinality(v_run."ids"), 'succeeded', v_run."succeeded", 'failed', v_run."failed"), 'progress', 'bulk:' || v_run."id"::text, true);
  end if;
  if v_done then
    perform "better_supabase".emit_event('bulk_run.completed', jsonb_build_object('organizationId', v_run."tenant_id", 'id', v_run."id", 'kind', v_run."action", 'status', v_status, 'count', cardinality(v_run."ids"), 'failed', v_run."failed"), 'bulk-runs/' || v_run."id"::text, (v_run."tenant_id")::text, null, 'better-supabase/bulk');
  end if;
  return jsonb_build_object('id', v_run."id", 'status', v_status, 'position', v_run."position", 'total', cardinality(v_run."ids"), 'succeeded', v_run."succeeded", 'failed', v_run."failed", 'done', v_done);
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
    when now() < v_pass."valid_from" then 'not_yet_valid'
    when v_pass."valid_until" is not null and now() >= v_pass."valid_until" then 'expired'
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'passId', v_row."pass_id", 'resourceId', v_row."resource_id", 'bookingId', v_row."booking_id", 'gate', v_row."gate", 'method', v_row."method", 'admitted', v_row."admitted", 'reason', v_row."reason", 'checkedInBy', v_row."checked_in_by", 'createdAt', v_row."created_at") || jsonb_build_object('pass', jsonb_build_object('id', v_pass."id", 'organizationId', v_pass."tenant_id"::text, 'kind', v_pass."kind", 'holderUserId', v_pass."holder_user_id", 'holderName', v_pass."holder_name", 'holderEmail', v_pass."holder_email", 'subjectType', v_pass."subject_type", 'subjectId', v_pass."subject_id", 'bookingId', v_pass."booking_id", 'resourceId', v_pass."resource_id", 'usesAllowed', v_pass."uses_allowed", 'uses', v_pass."uses", 'validFrom', v_pass."valid_from", 'validUntil', v_pass."valid_until", 'status', v_pass."status", 'issuedBy', v_pass."issued_by", 'createdAt', v_pass."created_at", 'updatedAt', v_pass."updated_at", 'revokedAt', v_pass."revoked_at"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_flag (
  key text
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
  delete from "better_supabase"."flags" x where x."key" = delete_flag.key;
  if not found then
    return false;
  end if;
  perform "better_supabase".emit_event('flag.deleted', jsonb_build_object('key', delete_flag.key), 'flags/' || delete_flag.key, null, null, 'better-supabase/flags');
  perform better_supabase.audit_event(
    event_type => 'flag.deleted',
    category => 'configuration',
    target_type => 'flag',
    record_id => delete_flag.key,
    metadata => jsonb_build_object('key', delete_flag.key)
  );
  return true;
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
  valid_from   timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  valid_until  timestamp with time zone DEFAULT NULL::timestamp WITH time zone
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
  v_until timestamptz := issue_pass.valid_until;
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
      when 'engagement' then (select s."tenant_id"::text from "better_supabase"."engagements" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'quote' then (select s."tenant_id"::text from "better_supabase"."quotes" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'invoice' then (select s."tenant_id"::text from "better_supabase"."invoices" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'order' then (select s."tenant_id"::text from "better_supabase"."orders" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'booking' then (select s."tenant_id"::text from "better_supabase"."bookings" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."lease_agreements" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'policy' then (select s."tenant_id"::text from "better_supabase"."policies" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'content_entry' then (select s."tenant_id"::text from "better_supabase"."content_entries" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'form' then (select s."tenant_id"::text from "better_supabase"."forms" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (issue_pass.subject_id)::uuid)
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
  if v_until is not null and v_until <= coalesce(issue_pass.valid_from, now()) then
    raise exception 'valid_until must be after valid_from and in the future' using errcode = '22023', hint = 'PASS_VALIDITY_INVALID';
  end if;
  insert into "better_supabase"."passes" ("tenant_id", "kind", "holder_user_id", "holder_name", "holder_email", "subject_type", "subject_id", "booking_id", "resource_id", "uses_allowed", "valid_from", "valid_until", "nonce", "issued_by")
  values (issue_pass.tenant, coalesce(issue_pass.kind, 'ticket'), issue_pass.holder_user, issue_pass.holder_name, lower(btrim(issue_pass.holder_email)),
    issue_pass.subject_type, issue_pass.subject_id, issue_pass.booking_id, v_resource,
    case when issue_pass.booking_id is not null then coalesce(issue_pass.uses_allowed, 1) else issue_pass.uses_allowed end,
    coalesce(issue_pass.valid_from, now()), v_until, encode(extensions.gen_random_bytes(16), 'hex'), auth.uid())
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'kind', v_row."kind", 'holderUserId', v_row."holder_user_id", 'holderName', v_row."holder_name", 'holderEmail', v_row."holder_email", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'bookingId', v_row."booking_id", 'resourceId', v_row."resource_id", 'usesAllowed', v_row."uses_allowed", 'uses', v_row."uses", 'validFrom', v_row."valid_from", 'validUntil', v_row."valid_until", 'status', v_row."status", 'issuedBy', v_row."issued_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'revokedAt', v_row."revoked_at") || jsonb_build_object('nonce', v_row."nonce");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.passes_subject_merge (
  subject_table text,
  keep          text,
  drop          text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text;
  v_keep text := keep;
  v_drop text := drop;
begin
  for v_type in select unnest(case subject_table when 'better_supabase.messages' then array['message'] when 'better_supabase.conversations' then array['conversation'] when 'better_supabase.channels' then array['channel'] when 'better_supabase.companies' then array['company'] when 'better_supabase.people' then array['person'] when 'better_supabase.deals' then array['deal'] when 'better_supabase.courses' then array['course'] when 'better_supabase.posts' then array['post'] when 'better_supabase.engagements' then array['engagement'] when 'better_supabase.quotes' then array['quote'] when 'better_supabase.work_items' then array['work_item'] when 'better_supabase.employees' then array['employee'] when 'better_supabase.invoices' then array['invoice'] when 'better_supabase.ledger_accounts' then array['ledger_account'] when 'better_supabase.products' then array['product'] when 'better_supabase.product_variants' then array['product_variant'] when 'better_supabase.orders' then array['order'] when 'better_supabase.calendar_events' then array['calendar_event'] when 'better_supabase.bookings' then array['booking'] when 'better_supabase.assets' then array['asset'] when 'better_supabase.asset_locations' then array['asset_location'] when 'better_supabase.lease_agreements' then array['lease'] when 'better_supabase.expense_reports' then array['expense_report'] when 'better_supabase.expense_lines' then array['expense_line'] when 'better_supabase.donation_funds' then array['donation_fund'] when 'better_supabase.work_orders' then array['work_order'] when 'better_supabase.shipments' then array['shipment'] when 'better_supabase.contracts' then array['contract'] when 'better_supabase.controls' then array['control'] when 'better_supabase.policies' then array['policy'] when 'better_supabase.incidents' then array['incident'] when 'better_supabase.content_entries' then array['content_entry'] when 'better_supabase.forms' then array['form'] when 'better_supabase.documents' then array['document'] when 'public.customers' then array['customer'] when 'better_supabase.drive_nodes' then array['drive_node'] when 'better_supabase.applications' then array['application'] when 'public.projects' then array['project'] when 'public.tasks' then array['task'] else '{}'::text[] end) loop
    update "better_supabase"."passes" x set "subject_id" = v_keep where x."subject_type" = v_type and x."subject_id" = v_drop;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.refund_pass_credit()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_spent record;
  v_entry uuid;
begin
  if new."status" <> 'cancelled' or old."status" = 'cancelled'
    or new."cancel_reason" is not distinct from 'bs:moving'
    or now() > lower(new."during") - '12 hours'::interval then
    return null;
  end if;
  for v_spent in
    select r."tenant_id" as tenant, (r."metadata" ->> 'passId')::uuid as pass, x."holder_user_id" as holder
    from "better_supabase"."ledger_transactions" r
    join "better_supabase"."passes" x on x."id" = (r."metadata" ->> 'passId')::uuid
    where r."tenant_id" = new."tenant_id" and r."idempotency_key" = 'pass-credit:' || new."id"::text || ':booking'
      and not exists (select 1 from "better_supabase"."ledger_transactions" d where d."tenant_id" = r."tenant_id" and d."idempotency_key" = 'pass-credit:' || new."id"::text || ':refund')
  loop
    v_entry := "better_supabase"."ledger_post"(v_spent.tenant, 'pass.credit_refunded',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_spent.tenant, 'pass_credits', 'pass:' || v_spent.pass::text, 'Pass credits', 'credit', 0::smallint,
    'passes', v_spent.pass::text, v_spent.holder, true, 'passes.read', 'passes', jsonb_build_object('passId', v_spent.pass)), 'amount', 1),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_spent.tenant, 'pass_credits_pool', 'pass-credits:pool', 'Pass credits pool', 'credit', 0::smallint,
    null, null, null, true, 'passes.read', 'passes', null), 'amount', -1)),
      'bookings', new."id"::text, null, 'pass-credit:' || new."id"::text || ':refund', clock_timestamp(),
      jsonb_build_object('passId', v_spent.pass, 'reason', 'refund'));
    update "better_supabase"."passes" x set "uses" = greatest(x."uses" - 1, 0), "updated_at" = now()
    where x."id" = v_spent.pass;
    perform "better_supabase".emit_event('pass.credit_refunded', jsonb_build_object('organizationId', v_spent.tenant::text, 'id', v_spent.pass, 'entryId', v_entry, 'bookingId', new."id"), 'passes/' || v_spent.pass::text, (v_spent.tenant)::text, null, 'better-supabase/passes');
  perform better_supabase.audit_event(
    event_type => 'pass.credit_refunded',
    category => 'access',
    target_type => 'pass',
    record_id => v_spent.pass::text,
    summary => 'refunded a credit to pass',
    tenant => (v_spent.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_spent.tenant::text, 'id', v_spent.pass, 'entryId', v_entry, 'bookingId', new."id")
  );
  end loop;
  return null;
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'kind', v_row."kind", 'holderUserId', v_row."holder_user_id", 'holderName', v_row."holder_name", 'holderEmail', v_row."holder_email", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'bookingId', v_row."booking_id", 'resourceId', v_row."resource_id", 'usesAllowed', v_row."uses_allowed", 'uses', v_row."uses", 'validFrom', v_row."valid_from", 'validUntil', v_row."valid_until", 'status', v_row."status", 'issuedBy', v_row."issued_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'revokedAt', v_row."revoked_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_flag (
  key        text,
  definition jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  d jsonb := coalesce(definition, '{}');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('flags.manage'), false))) then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  insert into "better_supabase"."flags" as x ("key", "type", "description", "variants", "default_variant", "enabled", "archived", "rules", "rollout_percentage", "rollout_variant")
  values (
    save_flag.key,
    coalesce(d ->> 'type', 'boolean'),
    d ->> 'description',
    coalesce(d -> 'variants', '{"on": true, "off": false}'::jsonb),
    coalesce(d ->> 'default_variant', 'off'),
    coalesce((d ->> 'enabled')::boolean, true),
    coalesce((d ->> 'archived')::boolean, false),
    coalesce(d -> 'rules', '[]'::jsonb),
    coalesce((d ->> 'rollout_percentage')::numeric, 0),
    d ->> 'rollout_variant'
  )
  on conflict ("key") do update set
    "type" = case when d ? 'type' then excluded."type" else x."type" end,
    "description" = case when d ? 'description' then excluded."description" else x."description" end,
    "variants" = case when d ? 'variants' then excluded."variants" else x."variants" end,
    "default_variant" = case when d ? 'default_variant' then excluded."default_variant" else x."default_variant" end,
    "enabled" = case when d ? 'enabled' then excluded."enabled" else x."enabled" end,
    "archived" = case when d ? 'archived' then excluded."archived" else x."archived" end,
    "rules" = case when d ? 'rules' then excluded."rules" else x."rules" end,
    "rollout_percentage" = case when d ? 'rollout_percentage' then excluded."rollout_percentage" else x."rollout_percentage" end,
    "rollout_variant" = case when d ? 'rollout_variant' then excluded."rollout_variant" else x."rollout_variant" end,
    "updated_at" = now();
  perform "better_supabase".emit_event('flag.saved', jsonb_build_object('key', save_flag.key), 'flags/' || save_flag.key, null, null, 'better-supabase/flags');
  perform better_supabase.audit_event(
    event_type => 'flag.saved',
    category => 'configuration',
    target_type => 'flag',
    record_id => save_flag.key,
    metadata => jsonb_build_object('key', save_flag.key)
  );
  return (select v from jsonb_array_elements("better_supabase"."flag_definitions"()) v where v ->> 'key' = save_flag.key);
end;
$function$;

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
    perform "better_supabase".emit_event('flag.override_set', jsonb_build_object('key', set_flag_override.key, 'variant', set_flag_override.variant, 'organizationId', set_flag_override.tenant::text, 'userId', set_flag_override.member, 'context', set_flag_override.context, 'contextKey', set_flag_override.context_key), 'flags/' || set_flag_override.key, (set_flag_override.tenant)::text, null, 'better-supabase/flags');
  perform better_supabase.audit_event(
    event_type => 'flag.override_set',
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
  on conflict on constraint flag_overrides_unique do update set "variant" = excluded."variant";
  perform "better_supabase".emit_event('flag.override_set', jsonb_build_object('key', set_flag_override.key, 'variant', set_flag_override.variant, 'organizationId', set_flag_override.tenant::text, 'userId', set_flag_override.member, 'context', set_flag_override.context, 'contextKey', set_flag_override.context_key), 'flags/' || set_flag_override.key, (set_flag_override.tenant)::text, null, 'better-supabase/flags');
  perform better_supabase.audit_event(
    event_type => 'flag.override_set',
    category => 'configuration',
    target_type => 'flag',
    record_id => set_flag_override.key,
    tenant => (set_flag_override.tenant)::uuid,
    metadata => jsonb_build_object('key', set_flag_override.key, 'variant', set_flag_override.variant, 'organizationId', set_flag_override.tenant::text, 'userId', set_flag_override.member, 'context', set_flag_override.context, 'contextKey', set_flag_override.context_key)
  );
  return true;
end;
$function$;

COMMENT ON FUNCTION "better_supabase"."passes_subject_merge"(text, text, text) IS 'better-supabase:subject-merge';

REVOKE ALL ON FUNCTION "better_supabase"."passes_subject_merge"(text, text, text) FROM PUBLIC;
