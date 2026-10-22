-- better-supabase module: passes
-- @bsb-block passes@1 managed
-- Admission passes on QR codes and NFC tags, signed with the signing-keys block: a ticket for a booking or a pass with a number of uses for a resource, a log of every scan, class credits that pay for bookings and come back on an early cancellation, and drop-ins counted against the resource's capacity with its bookings.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Passes: QR and NFC admission signed with the signing-keys block, with a
-- log of every scan and capacity counted against bookings.

-- Admission passes: a ticket for one booking, or a pass for a resource (a gym,
-- a venue) with a number of uses. The nonce goes in the signed token on the
-- QR code or NFC tag; only the functions read it.
create table if not exists "better_supabase"."passes" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "kind" text not null default 'ticket' check ("kind" ~ '^[a-z][a-z0-9_-]{0,39}$'),
  "holder_user_id" uuid references auth.users (id) on delete set null,
  "holder_name" text check ("holder_name" is null or length("holder_name") >= 1 and length("holder_name") <= 200),
  "holder_email" text check ("holder_email" is null or (length("holder_email") >= 3 and length("holder_email") <= 320 and position('@' in "holder_email") > 1)),
  "subject_type" text check ("subject_type" is null or "subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "subject_id" text check ("subject_id" is null or length("subject_id") >= 1 and length("subject_id") <= 200),
  "booking_id" uuid,
  "resource_id" uuid,
  "uses_allowed" integer check ("uses_allowed" is null or "uses_allowed" > 0),
  "uses" integer not null default 0 check ("uses" >= 0),
  "valid_from" timestamptz not null default now(),
  "valid_until" timestamptz,
  "status" text not null default 'active' check ("status" in ('active', 'revoked')),
  "nonce" text not null unique,
  "issued_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "revoked_at" timestamptz,
  check (("subject_type" is null) = ("subject_id" is null)),
  check ("uses_allowed" is null or "uses" <= "uses_allowed"),
  check ("valid_until" is null or "valid_until" > "valid_from")
);
create index if not exists "passes_tenant_idx" on "better_supabase"."passes" ("tenant_id", "created_at" desc);
create index if not exists "passes_holder_idx" on "better_supabase"."passes" ("holder_user_id");
create index if not exists "passes_booking_idx" on "better_supabase"."passes" ("booking_id");
create index if not exists "passes_resource_idx" on "better_supabase"."passes" ("resource_id");
create index if not exists "passes_subject_idx" on "better_supabase"."passes" ("tenant_id", "subject_type", "subject_id");
alter table "better_supabase"."passes" enable row level security;
revoke all on "better_supabase"."passes" from anon, authenticated;
grant all on "better_supabase"."passes" to service_role;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."passes"'::regclass and conname = 'passes_booking_fkey'
  ) then
    alter table "better_supabase"."passes" add constraint "passes_booking_fkey"
      foreign key ("booking_id") references "better_supabase"."bookings" ("id") on delete cascade not valid;
    begin
      alter table "better_supabase"."passes" validate constraint "passes_booking_fkey";
    exception when foreign_key_violation then
      raise warning '% has rows without a match, so only new rows are checked. Delete them, then run: alter table % validate constraint %',
        '"better_supabase"."passes"', '"better_supabase"."passes"', 'passes_booking_fkey';
    end;
  end if;
end;
$$;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."passes"'::regclass and conname = 'passes_resource_fkey'
  ) then
    alter table "better_supabase"."passes" add constraint "passes_resource_fkey"
      foreign key ("resource_id") references "better_supabase"."booking_resources" ("id") on delete cascade not valid;
    begin
      alter table "better_supabase"."passes" validate constraint "passes_resource_fkey";
    exception when foreign_key_violation then
      raise warning '% has rows without a match, so only new rows are checked. Delete them, then run: alter table % validate constraint %',
        '"better_supabase"."passes"', '"better_supabase"."passes"', 'passes_resource_fkey';
    end;
  end if;
end;
$$;
-- Every scan, admitted or not, for the door log and the drop-in count.
create table if not exists "better_supabase"."pass_check_ins" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "pass_id" uuid not null references "better_supabase"."passes" ("id") on delete cascade,
  "resource_id" uuid,
  "booking_id" uuid,
  "gate" text check ("gate" is null or length("gate") >= 1 and length("gate") <= 100),
  "method" text not null check ("method" in ('qr', 'nfc', 'manual')),
  "admitted" boolean not null,
  "reason" text check ("reason" is null or "reason" in ('invalid', 'revoked', 'not_yet_valid', 'expired', 'used_up', 'booking_cancelled', 'booking_unconfirmed', 'outside_window', 'wrong_resource', 'full')),
  "checked_in_by" uuid,
  "created_at" timestamptz not null default now(),
  check ("admitted" = ("reason" is null))
);
create index if not exists "pass_check_ins_log_idx" on "better_supabase"."pass_check_ins" ("pass_id", "created_at" desc);
create index if not exists "pass_check_ins_drop_in_idx" on "better_supabase"."pass_check_ins" ("resource_id", "created_at") where "admitted" and "booking_id" is null;
alter table "better_supabase"."pass_check_ins" enable row level security;
revoke all on "better_supabase"."pass_check_ins" from anon, authenticated;
grant all on "better_supabase"."pass_check_ins" to service_role;

-- Issues a pass in tenant: a ticket for booking_id (valid until the booking
-- ends unless valid_until says otherwise), a pass for resource_id, or a pass
-- for a registered record. Returns the pass with its nonce for the token.
create or replace function "better_supabase"."issue_pass"(tenant uuid, kind text default 'ticket', holder_user uuid default null, holder_name text default null, holder_email text default null, subject_type text default null, subject_id text default null, booking_id uuid default null, resource_id uuid default null, uses_allowed integer default null, valid_from timestamptz default null, valid_until timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."lease_agreements" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'maintenance_request' then (select s."tenant_id"::text from "better_supabase"."maintenance_requests" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'policy' then (select s."tenant_id"::text from "better_supabase"."policies" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (issue_pass.subject_id)::uuid)
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
$$;
revoke execute on function "better_supabase"."issue_pass"(uuid, text, uuid, text, text, text, text, uuid, uuid, integer, timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."issue_pass"(uuid, text, uuid, text, text, text, text, uuid, uuid, integer, timestamptz, timestamptz) to authenticated, service_role;

-- Revokes a pass; its token stops admitting.
create or replace function "better_supabase"."revoke_pass"(pass_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."revoke_pass"(uuid) from public, anon;
grant execute on function "better_supabase"."revoke_pass"(uuid) to authenticated, service_role;

-- One pass with its nonce, for the holder or a manager signing its token.
create or replace function "better_supabase"."get_pass"(pass_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."passes"%rowtype;
begin
  select * into v_row from "better_supabase"."passes" x where x."id" = get_pass.pass_id;
  if not found or not (v_row."holder_user_id" = auth.uid() or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'passes.manage'), false))) then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'kind', v_row."kind", 'holderUserId', v_row."holder_user_id", 'holderName', v_row."holder_name", 'holderEmail', v_row."holder_email", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'bookingId', v_row."booking_id", 'resourceId', v_row."resource_id", 'usesAllowed', v_row."uses_allowed", 'uses', v_row."uses", 'validFrom', v_row."valid_from", 'validUntil', v_row."valid_until", 'status', v_row."status", 'issuedBy', v_row."issued_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'revokedAt', v_row."revoked_at") || jsonb_build_object('nonce', v_row."nonce");
end;
$$;
revoke execute on function "better_supabase"."get_pass"(uuid) from public, anon;
grant execute on function "better_supabase"."get_pass"(uuid) to authenticated, service_role;

-- Scans a pass at a door. nonce comes from the verified token; a manual
-- check-in by staff leaves it null. Every scan is logged; an admitted one
-- uses the pass once. A pass without a booking counts against the
-- resource's capacity with the bookings and drop-ins there now.
create or replace function "better_supabase"."check_in_pass"(pass_id uuid, nonce text default null, method text default 'qr', gate text default null, resource_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."check_in_pass"(uuid, text, text, text, uuid) from public, anon;
grant execute on function "better_supabase"."check_in_pass"(uuid, text, text, text, uuid) to authenticated, service_role;

-- A tenant's passes, newest first, filtered by holder, record or status.
create or replace function "better_supabase"."list_passes"(tenant uuid, holder_user uuid default null, subject_type text default null, subject_id text default null, status text default null, before timestamptz default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_passes.tenant, 'passes.read'), false)) then
    raise exception 'not allowed to read passes' using errcode = '42501', hint = 'PASS_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(z.item order by z.created desc, z.id desc), '[]'::jsonb)
    from (
      select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'kind', x."kind", 'holderUserId', x."holder_user_id", 'holderName', x."holder_name", 'holderEmail', x."holder_email", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'bookingId', x."booking_id", 'resourceId', x."resource_id", 'usesAllowed', x."uses_allowed", 'uses', x."uses", 'validFrom', x."valid_from", 'validUntil', x."valid_until", 'status', x."status", 'issuedBy', x."issued_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'revokedAt', x."revoked_at") as item, x."created_at" as created, x."id" as id
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
$$;
revoke execute on function "better_supabase"."list_passes"(uuid, uuid, text, text, text, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."list_passes"(uuid, uuid, text, text, text, timestamptz, integer) to authenticated, service_role;

-- The caller's own live passes with their nonces, for a wallet screen.
create or replace function "better_supabase"."my_passes"()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'kind', x."kind", 'holderUserId', x."holder_user_id", 'holderName', x."holder_name", 'holderEmail', x."holder_email", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'bookingId', x."booking_id", 'resourceId', x."resource_id", 'usesAllowed', x."uses_allowed", 'uses', x."uses", 'validFrom', x."valid_from", 'validUntil', x."valid_until", 'status', x."status", 'issuedBy', x."issued_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'revokedAt', x."revoked_at") || jsonb_build_object('nonce', x."nonce") order by x."valid_from", x."id"), '[]'::jsonb)
  from "better_supabase"."passes" x
  where x."holder_user_id" = auth.uid()
    and x."status" = 'active'
    and (x."valid_until" is null or x."valid_until" > now())
    and not better_supabase.tenant_disabled(x."tenant_id")
$$;
revoke execute on function "better_supabase"."my_passes"() from public, anon;
grant execute on function "better_supabase"."my_passes"() to authenticated, service_role;

-- A pass's scans, newest first.
create or replace function "better_supabase"."list_pass_check_ins"(pass_id uuid, before timestamptz default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_pass "better_supabase"."passes"%rowtype;
begin
  select * into v_pass from "better_supabase"."passes" x where x."id" = list_pass_check_ins.pass_id;
  if not found or not (v_pass."holder_user_id" = auth.uid() or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_pass."tenant_id", 'passes.read'), false))) then
    return '[]'::jsonb;
  end if;
  return (
    select coalesce(jsonb_agg(z.item order by z.created desc, z.id desc), '[]'::jsonb)
    from (
      select jsonb_build_object('id', y."id", 'organizationId', y."tenant_id"::text, 'passId', y."pass_id", 'resourceId', y."resource_id", 'bookingId', y."booking_id", 'gate', y."gate", 'method', y."method", 'admitted', y."admitted", 'reason', y."reason", 'checkedInBy', y."checked_in_by", 'createdAt', y."created_at") as item, y."created_at" as created, y."id" as id
      from "better_supabase"."pass_check_ins" y
      where y."pass_id" = v_pass."id"
        and (list_pass_check_ins.before is null or y."created_at" < list_pass_check_ins.before)
      order by y."created_at" desc, y."id" desc
      limit least(greatest(coalesce(list_pass_check_ins.page_size, 50), 1), 500)
    ) z
  );
end;
$$;
revoke execute on function "better_supabase"."list_pass_check_ins"(uuid, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."list_pass_check_ins"(uuid, timestamptz, integer) to authenticated, service_role;

-- How full a resource is now: seats taken by bookings and drop-ins admitted
-- within the drop-in length, for a door display.
create or replace function "better_supabase"."pass_occupancy"(resource_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_capacity integer;
  v_booked integer;
  v_drop_ins integer;
begin
  select rs."tenant_id", rs."capacity" into v_tenant, v_capacity
    from "better_supabase"."booking_resources" rs where rs."id" = pass_occupancy.resource_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'passes.check_in'), false)) then
    raise exception 'resource not found' using errcode = 'P0002', hint = 'PASS_RESOURCE_NOT_FOUND';
  end if;
  select count(*) into v_booked from "better_supabase"."bookings" bk
    where bk."resource_id" = pass_occupancy.resource_id and (bk."status" = 'confirmed' or (bk."status" = 'hold' and bk."hold_expires_at" > now())) and bk."during" @> now();
  select count(*) into v_drop_ins from "better_supabase"."pass_check_ins" y
    where y."resource_id" = pass_occupancy.resource_id and y."admitted" and y."booking_id" is null
      and y."created_at" > now() - '2 hours'::interval;
  return jsonb_build_object('resourceId', pass_occupancy.resource_id, 'capacity', v_capacity,
    'booked', v_booked, 'dropIns', v_drop_ins, 'free', greatest(v_capacity - v_booked - v_drop_ins, 0));
end;
$$;
revoke execute on function "better_supabase"."pass_occupancy"(uuid) from public, anon;
grant execute on function "better_supabase"."pass_occupancy"(uuid) to authenticated, service_role;

-- Moves this module's rows from one subject record to another when
-- better_supabase.merge_subject_refs merges them.
create or replace function "better_supabase"."passes_subject_merge"(subject_table text, keep text, drop text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text;
  v_keep text := keep;
  v_drop text := drop;
begin
  for v_type in select unnest(case subject_table when 'better_supabase.messages' then array['message'] when 'better_supabase.conversations' then array['conversation'] when 'better_supabase.channels' then array['channel'] when 'better_supabase.companies' then array['company'] when 'better_supabase.people' then array['person'] when 'better_supabase.deals' then array['deal'] when 'better_supabase.courses' then array['course'] when 'better_supabase.posts' then array['post'] when 'better_supabase.engagements' then array['engagement'] when 'better_supabase.work_items' then array['work_item'] when 'better_supabase.employees' then array['employee'] when 'better_supabase.ledger_accounts' then array['ledger_account'] when 'better_supabase.products' then array['product'] when 'better_supabase.product_variants' then array['product_variant'] when 'better_supabase.calendar_events' then array['calendar_event'] when 'better_supabase.assets' then array['asset'] when 'better_supabase.asset_locations' then array['asset_location'] when 'better_supabase.lease_agreements' then array['lease'] when 'better_supabase.maintenance_requests' then array['maintenance_request'] when 'better_supabase.expense_reports' then array['expense_report'] when 'better_supabase.expense_lines' then array['expense_line'] when 'better_supabase.donation_funds' then array['donation_fund'] when 'better_supabase.work_orders' then array['work_order'] when 'better_supabase.shipments' then array['shipment'] when 'better_supabase.contracts' then array['contract'] when 'better_supabase.controls' then array['control'] when 'better_supabase.policies' then array['policy'] when 'better_supabase.incidents' then array['incident'] when 'better_supabase.documents' then array['document'] when 'public.customers' then array['customer'] when 'better_supabase.drive_nodes' then array['drive_node'] when 'better_supabase.applications' then array['application'] when 'public.projects' then array['project'] when 'public.tasks' then array['task'] else '{}'::text[] end) loop
    update "better_supabase"."passes" x set "subject_id" = v_keep where x."subject_type" = v_type and x."subject_id" = v_drop;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."passes_subject_merge"(text, text, text) from public, anon, authenticated;
comment on function "better_supabase"."passes_subject_merge"(text, text, text) is 'better-supabase:subject-merge';

-- The class-credit ledger: -1 when a pass pays for a booking, +1 when the
-- booking is cancelled before the refund window closes. One of each per
-- booking at most.
create table if not exists "better_supabase"."pass_credit_entries" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "pass_id" uuid not null references "better_supabase"."passes" ("id") on delete cascade,
  "booking_id" uuid references "better_supabase"."bookings" ("id") on delete set null,
  "delta" integer not null check ("delta" in (-1, 1)),
  "reason" text not null check ("reason" in ('booking', 'refund')),
  "created_by" uuid,
  "created_at" timestamptz not null default clock_timestamp(),
  check (("reason" = 'booking') = ("delta" = -1))
);
create index if not exists "pass_credit_entries_pass_idx" on "better_supabase"."pass_credit_entries" ("pass_id", "created_at" desc);
create index if not exists "pass_credit_entries_booking_idx" on "better_supabase"."pass_credit_entries" ("booking_id");
create unique index if not exists "pass_credit_entries_once_idx" on "better_supabase"."pass_credit_entries" ("booking_id", "reason");
alter table "better_supabase"."pass_credit_entries" enable row level security;
revoke all on "better_supabase"."pass_credit_entries" from anon, authenticated;
grant all on "better_supabase"."pass_credit_entries" to service_role;

-- Books a class with one credit of a pass: the holder, or a passes manager
-- for the holder. The pass must be active, valid when the class starts, for
-- that resource (or any) and have a use left. The booking is confirmed.
create or replace function "better_supabase"."book_with_credit"(pass_id uuid, service uuid, resource uuid, starts_at timestamptz, customer jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_pass "better_supabase"."passes"%rowtype;
  v_tenant uuid;
  v_booking jsonb;
  v_entry "better_supabase"."pass_credit_entries"%rowtype;
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
  insert into "better_supabase"."pass_credit_entries" ("tenant_id", "pass_id", "booking_id", "delta", "reason", "created_by")
  values (v_pass."tenant_id", v_pass."id", (v_booking ->> 'id')::uuid, -1, 'booking', auth.uid())
  returning * into v_entry;
  update "better_supabase"."passes" x set "uses" = x."uses" + 1, "updated_at" = now()
  where x."id" = v_pass."id";
  perform "better_supabase".emit_event('pass.credit_used', jsonb_build_object('organizationId', v_entry."tenant_id"::text, 'id', v_entry."pass_id", 'entryId', v_entry."id", 'bookingId', v_entry."booking_id"), 'passes/' || v_entry."pass_id"::text, (v_entry."tenant_id")::text, null, 'better-supabase/passes');
  perform better_supabase.audit_event(
    event_type => 'pass.credit_used',
    category => 'access',
    target_type => 'pass',
    record_id => v_entry."pass_id"::text,
    summary => 'booked with a credit of pass',
    tenant => (v_entry."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_entry."tenant_id"::text, 'id', v_entry."pass_id", 'entryId', v_entry."id", 'bookingId', v_entry."booking_id")
  );
  return (v_booking - 'accessToken') || jsonb_build_object('passId', v_pass."id", 'creditsLeft', v_pass."uses_allowed" - v_pass."uses" - 1);
end;
$$;
revoke execute on function "better_supabase"."book_with_credit"(uuid, uuid, uuid, timestamptz, jsonb) from public, anon;
grant execute on function "better_supabase"."book_with_credit"(uuid, uuid, uuid, timestamptz, jsonb) to authenticated, service_role;

-- Gives the credit back when a credit booking is cancelled at least
-- 12 hours before it starts; later, the credit is spent. A booking
-- that moves (cancel reason bs:moving) keeps its credit.
create or replace function "better_supabase"."refund_pass_credit"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_entry "better_supabase"."pass_credit_entries"%rowtype;
begin
  if new."status" <> 'cancelled' or old."status" = 'cancelled'
    or new."cancel_reason" is not distinct from 'bs:moving'
    or now() > lower(new."during") - '12 hours'::interval then
    return null;
  end if;
  for v_entry in
    insert into "better_supabase"."pass_credit_entries" ("tenant_id", "pass_id", "booking_id", "delta", "reason", "created_by")
    select spent."tenant_id", spent."pass_id", spent."booking_id", 1, 'refund', auth.uid()
    from "better_supabase"."pass_credit_entries" spent
    where spent."booking_id" = new."id" and spent."reason" = 'booking'
    on conflict ("booking_id", "reason") do nothing
    returning *
  loop
    update "better_supabase"."passes" x set "uses" = greatest(x."uses" - 1, 0), "updated_at" = now()
    where x."id" = v_entry."pass_id";
    perform "better_supabase".emit_event('pass.credit_refunded', jsonb_build_object('organizationId', v_entry."tenant_id"::text, 'id', v_entry."pass_id", 'entryId', v_entry."id", 'bookingId', v_entry."booking_id"), 'passes/' || v_entry."pass_id"::text, (v_entry."tenant_id")::text, null, 'better-supabase/passes');
  perform better_supabase.audit_event(
    event_type => 'pass.credit_refunded',
    category => 'access',
    target_type => 'pass',
    record_id => v_entry."pass_id"::text,
    summary => 'refunded a credit to pass',
    tenant => (v_entry."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_entry."tenant_id"::text, 'id', v_entry."pass_id", 'entryId', v_entry."id", 'bookingId', v_entry."booking_id")
  );
  end loop;
  return null;
end;
$$;
revoke all on function "better_supabase"."refund_pass_credit"() from public, anon, authenticated;
drop trigger if exists "pass_credit_entries_refund" on "better_supabase"."bookings";
create trigger "pass_credit_entries_refund"
after update of "status" on "better_supabase"."bookings"
for each row execute function "better_supabase"."refund_pass_credit"();

-- A pass's credit ledger, newest first: its holder, or a passes reader.
create or replace function "better_supabase"."list_pass_credits"(pass_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_pass "better_supabase"."passes"%rowtype;
begin
  select * into v_pass from "better_supabase"."passes" x where x."id" = list_pass_credits.pass_id;
  if not found or not (v_pass."holder_user_id" = auth.uid() or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_pass."tenant_id", 'passes.read'), false))) then
    raise exception 'pass not found' using errcode = 'P0002', hint = 'PASS_NOT_FOUND';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', e."id", 'organizationId', e."tenant_id"::text, 'passId', e."pass_id", 'bookingId', e."booking_id", 'delta', e."delta", 'reason', e."reason", 'createdBy', e."created_by", 'createdAt', e."created_at") order by e."created_at" desc, e."id")
    from "better_supabase"."pass_credit_entries" e where e."pass_id" = v_pass."id"
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_pass_credits"(uuid) from public, anon;
grant execute on function "better_supabase"."list_pass_credits"(uuid) to authenticated, service_role;

-- blocks.passes.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."actor_may_write"()
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."actor_may_write"() $$;
revoke execute on function "api"."actor_may_write"() from public;
grant execute on function "api"."actor_may_write"() to anon, authenticated, service_role;

create or replace function "api"."raise_actor_readonly"()
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."raise_actor_readonly"() $$;
revoke execute on function "api"."raise_actor_readonly"() from public;
grant execute on function "api"."raise_actor_readonly"() to anon, authenticated, service_role;

create or replace function "api"."issue_pass"(tenant uuid, kind text default 'ticket', holder_user uuid default null, holder_name text default null, holder_email text default null, subject_type text default null, subject_id text default null, booking_id uuid default null, resource_id uuid default null, uses_allowed integer default null, valid_from timestamptz default null, valid_until timestamptz default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."issue_pass"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12) $$;
revoke execute on function "api"."issue_pass"(uuid, text, uuid, text, text, text, text, uuid, uuid, integer, timestamptz, timestamptz) from public, anon;
grant execute on function "api"."issue_pass"(uuid, text, uuid, text, text, text, text, uuid, uuid, integer, timestamptz, timestamptz) to authenticated, service_role;

create or replace function "api"."revoke_pass"(pass_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."revoke_pass"($1) $$;
revoke execute on function "api"."revoke_pass"(uuid) from public, anon;
grant execute on function "api"."revoke_pass"(uuid) to authenticated, service_role;

create or replace function "api"."get_pass"(pass_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_pass"($1) $$;
revoke execute on function "api"."get_pass"(uuid) from public, anon;
grant execute on function "api"."get_pass"(uuid) to authenticated, service_role;

create or replace function "api"."check_in_pass"(pass_id uuid, nonce text default null, method text default 'qr', gate text default null, resource_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."check_in_pass"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."check_in_pass"(uuid, text, text, text, uuid) from public, anon;
grant execute on function "api"."check_in_pass"(uuid, text, text, text, uuid) to authenticated, service_role;

create or replace function "api"."list_passes"(tenant uuid, holder_user uuid default null, subject_type text default null, subject_id text default null, status text default null, before timestamptz default null, page_size integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_passes"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."list_passes"(uuid, uuid, text, text, text, timestamptz, integer) from public, anon;
grant execute on function "api"."list_passes"(uuid, uuid, text, text, text, timestamptz, integer) to authenticated, service_role;

create or replace function "api"."my_passes"()
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."my_passes"() $$;
revoke execute on function "api"."my_passes"() from public, anon;
grant execute on function "api"."my_passes"() to authenticated, service_role;

create or replace function "api"."list_pass_check_ins"(pass_id uuid, before timestamptz default null, page_size integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_pass_check_ins"($1, $2, $3) $$;
revoke execute on function "api"."list_pass_check_ins"(uuid, timestamptz, integer) from public, anon;
grant execute on function "api"."list_pass_check_ins"(uuid, timestamptz, integer) to authenticated, service_role;

create or replace function "api"."pass_occupancy"(resource_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."pass_occupancy"($1) $$;
revoke execute on function "api"."pass_occupancy"(uuid) from public, anon;
grant execute on function "api"."pass_occupancy"(uuid) to authenticated, service_role;

create or replace function "api"."book_with_credit"(pass_id uuid, service uuid, resource uuid, starts_at timestamptz, customer jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."book_with_credit"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."book_with_credit"(uuid, uuid, uuid, timestamptz, jsonb) from public, anon;
grant execute on function "api"."book_with_credit"(uuid, uuid, uuid, timestamptz, jsonb) to authenticated, service_role;

create or replace function "api"."list_pass_credits"(pass_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_pass_credits"($1) $$;
revoke execute on function "api"."list_pass_credits"(uuid) from public, anon;
grant execute on function "api"."list_pass_credits"(uuid) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;
