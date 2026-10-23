SET local check_function_bodies = off;

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
    'passes', v_pass."id"::text, v_pass."holder_user_id", true, 'passes.read', 'admission-passes', jsonb_build_object('passId', v_pass."id")), 'amount', -1),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_pass."tenant_id", 'pass_credits_pool', 'pass-credits:pool', 'Pass credits pool', 'credit', 0::smallint,
    null, null, null, true, 'passes.read', 'admission-passes', null), 'amount', 1)),
      'bookings', (v_booking ->> 'id')::uuid::text, null, 'pass-credit:' || (v_booking ->> 'id')::uuid::text || ':booking', clock_timestamp(),
      jsonb_build_object('passId', v_pass."id", 'reason', 'booking'));
  update "better_supabase"."passes" x set "uses" = x."uses" + 1, "updated_at" = now()
  where x."id" = v_pass."id";
  perform "better_supabase".emit_event('pass.credit_used', jsonb_build_object('organizationId', v_pass."tenant_id"::text, 'id', v_pass."id", 'entryId', v_entry, 'bookingId', (v_booking ->> 'id')::uuid), 'passes/' || v_pass."id"::text, (v_pass."tenant_id")::text, null, 'better-supabase/admission-passes');
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

CREATE OR REPLACE FUNCTION better_supabase.list_pass_credits (
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
  v_pass "better_supabase"."passes"%rowtype;
begin
  select * into v_pass from "better_supabase"."passes" x where x."id" = list_pass_credits.pass_id;
  if not found or not (v_pass."holder_user_id" = auth.uid() or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_pass."tenant_id", 'passes.read'), false))) then
    raise exception 'pass not found' using errcode = 'P0002', hint = 'PASS_NOT_FOUND';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', r."id", 'organizationId', r."tenant_id"::text, 'passId', (x."metadata" ->> 'passId')::uuid,
      'bookingId', r."reference_id"::uuid, 'delta', y."amount",
      'reason', case when r."kind" = 'pass.credit_used' then 'booking' else 'refund' end,
      'createdBy', r."actor_id", 'createdAt', r."created_at") order by r."effective_at" desc, r."created_at" desc, r."id")
    from "better_supabase"."ledger_accounts" x
    join "better_supabase"."ledger_entries" y on y."account_id" = x."id"
    join "better_supabase"."ledger_transactions" r on r."id" = y."transaction_id"
    where x."tenant_id" = v_pass."tenant_id" and x."code" = 'pass:' || v_pass."id"::text
  ), '[]'::jsonb);
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
    'passes', v_spent.pass::text, v_spent.holder, true, 'passes.read', 'admission-passes', jsonb_build_object('passId', v_spent.pass)), 'amount', 1),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_spent.tenant, 'pass_credits_pool', 'pass-credits:pool', 'Pass credits pool', 'credit', 0::smallint,
    null, null, null, true, 'passes.read', 'admission-passes', null), 'amount', -1)),
      'bookings', new."id"::text, null, 'pass-credit:' || new."id"::text || ':refund', clock_timestamp(),
      jsonb_build_object('passId', v_spent.pass, 'reason', 'refund'));
    update "better_supabase"."passes" x set "uses" = greatest(x."uses" - 1, 0), "updated_at" = now()
    where x."id" = v_spent.pass;
    perform "better_supabase".emit_event('pass.credit_refunded', jsonb_build_object('organizationId', v_spent.tenant::text, 'id', v_spent.pass, 'entryId', v_entry, 'bookingId', new."id"), 'passes/' || v_spent.pass::text, (v_spent.tenant)::text, null, 'better-supabase/admission-passes');
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
