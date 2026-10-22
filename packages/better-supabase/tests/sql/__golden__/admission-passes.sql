-- ==== alone: schema supabase/schemas/900_better_supabase_118_admission_passes.sql
-- better-supabase module: admission-passes
-- @bsb-block admission-passes@1 managed
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
    and null::text is distinct from issue_pass.tenant::text then
    raise exception 'the record does not exist in this organization' using errcode = 'P0002', hint = 'PASS_SUBJECT_NOT_FOUND';
  end if;
  if issue_pass.holder_user is not null and not exists (select 1 from auth.users u where u.id = issue_pass.holder_user) then
    raise exception 'the holder does not exist' using errcode = 'P0002', hint = 'PASS_HOLDER_NOT_FOUND';
  end if;
  if issue_pass.booking_id is not null or issue_pass.resource_id is not null then
    raise exception 'install the bookings block to tie passes to bookings or resources' using errcode = '22023', hint = 'PASS_BOOKINGS_MISSING';
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
  null;
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
    null;
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
  insert into "better_supabase"."pass_check_ins" ("tenant_id", "pass_id", "resource_id", "booking_id", "gate", "method", "admitted", "reason", "checked_in_by")
  values (v_pass."tenant_id", v_pass."id", v_resource, v_pass."booking_id", check_in_pass.gate, check_in_pass.method, v_reason is null, v_reason, auth.uid())
  returning * into v_row;
  if v_reason is null then
    update "better_supabase"."passes" x set "uses" = x."uses" + 1, "updated_at" = now()
      where x."id" = v_pass."id"
      returning * into v_pass;
    null;
  else
    null;
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

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_118_admission_passes.sql
-- better-supabase module: admission-passes
-- @bsb-block-data admission-passes
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('admission-passes', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_118_admission_passes.sql
-- better-supabase module: admission-passes
-- @bsb-block admission-passes@1 managed
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
    and null::text is distinct from issue_pass.tenant::text then
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
  perform "better_supabase".emit_event('pass.issued', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'kind', v_row."kind", 'holderUserId', v_row."holder_user_id", 'bookingId', v_row."booking_id"), 'passes/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/admission-passes');
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
    perform "better_supabase".emit_event('pass.revoked', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id"), 'passes/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/admission-passes');
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
    perform "better_supabase".emit_event('pass.admitted', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."pass_id", 'checkInId', v_row."id", 'resourceId', v_row."resource_id", 'bookingId', v_row."booking_id"), 'passes/' || v_row."pass_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/admission-passes');
  else
    perform "better_supabase".emit_event('pass.rejected', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."pass_id", 'checkInId', v_row."id", 'resourceId', v_row."resource_id", 'bookingId', v_row."booking_id", 'reason', v_row."reason"), 'passes/' || v_row."pass_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/admission-passes');
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

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_118_admission_passes.sql
-- better-supabase module: admission-passes
-- @bsb-block-data admission-passes
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('admission-passes', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_118_admission_passes.sql
-- better-supabase module: admission-passes
-- @bsb-block admission-passes@1 managed
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
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
-- Passes: QR and NFC admission signed with the signing-keys block, with a
-- log of every scan and capacity counted against bookings.

-- Admission passes: a ticket for one booking, or a pass for a resource (a gym,
-- a venue) with a number of uses. The nonce goes in the signed token on the
-- QR code or NFC tag; only the functions read it.
create table if not exists "app_private"."passes" (
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
create index if not exists "passes_tenant_idx" on "app_private"."passes" ("tenant_id", "created_at" desc);
create index if not exists "passes_holder_idx" on "app_private"."passes" ("holder_user_id");
create index if not exists "passes_booking_idx" on "app_private"."passes" ("booking_id");
create index if not exists "passes_resource_idx" on "app_private"."passes" ("resource_id");
create index if not exists "passes_subject_idx" on "app_private"."passes" ("tenant_id", "subject_type", "subject_id");
alter table "app_private"."passes" enable row level security;
revoke all on "app_private"."passes" from anon, authenticated;
grant all on "app_private"."passes" to service_role;

-- Every scan, admitted or not, for the door log and the drop-in count.
create table if not exists "app_private"."pass_check_ins" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "pass_id" uuid not null references "app_private"."passes" ("id") on delete cascade,
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
create index if not exists "pass_check_ins_log_idx" on "app_private"."pass_check_ins" ("pass_id", "created_at" desc);
create index if not exists "pass_check_ins_drop_in_idx" on "app_private"."pass_check_ins" ("resource_id", "created_at") where "admitted" and "booking_id" is null;
alter table "app_private"."pass_check_ins" enable row level security;
revoke all on "app_private"."pass_check_ins" from anon, authenticated;
grant all on "app_private"."pass_check_ins" to service_role;

-- Issues a pass in tenant: a ticket for booking_id (valid until the booking
-- ends unless valid_until says otherwise), a pass for resource_id, or a pass
-- for a registered record. Returns the pass with its nonce for the token.
create or replace function "app_private"."issue_pass"(tenant uuid, kind text default 'ticket', holder_user uuid default null, holder_name text default null, holder_email text default null, subject_type text default null, subject_id text default null, booking_id uuid default null, resource_id uuid default null, uses_allowed integer default null, valid_from timestamptz default null, valid_until timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."passes"%rowtype;
  v_resource uuid := issue_pass.resource_id;
  v_until timestamptz := issue_pass.valid_until;
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
    and null::text is distinct from issue_pass.tenant::text then
    raise exception 'the record does not exist in this organization' using errcode = 'P0002', hint = 'PASS_SUBJECT_NOT_FOUND';
  end if;
  if issue_pass.holder_user is not null and not exists (select 1 from auth.users u where u.id = issue_pass.holder_user) then
    raise exception 'the holder does not exist' using errcode = 'P0002', hint = 'PASS_HOLDER_NOT_FOUND';
  end if;
  if issue_pass.booking_id is not null or issue_pass.resource_id is not null then
    raise exception 'install the bookings block to tie passes to bookings or resources' using errcode = '22023', hint = 'PASS_BOOKINGS_MISSING';
  end if;
  if v_until is not null and v_until <= coalesce(issue_pass.valid_from, now()) then
    raise exception 'valid_until must be after valid_from and in the future' using errcode = '22023', hint = 'PASS_VALIDITY_INVALID';
  end if;
  insert into "app_private"."passes" ("tenant_id", "kind", "holder_user_id", "holder_name", "holder_email", "subject_type", "subject_id", "booking_id", "resource_id", "uses_allowed", "valid_from", "valid_until", "nonce", "issued_by")
  values (issue_pass.tenant, coalesce(issue_pass.kind, 'ticket'), issue_pass.holder_user, issue_pass.holder_name, lower(btrim(issue_pass.holder_email)),
    issue_pass.subject_type, issue_pass.subject_id, issue_pass.booking_id, v_resource,
    case when issue_pass.booking_id is not null then coalesce(issue_pass.uses_allowed, 1) else issue_pass.uses_allowed end,
    coalesce(issue_pass.valid_from, now()), v_until, encode(extensions.gen_random_bytes(16), 'hex'), auth.uid())
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'kind', v_row."kind", 'holderUserId', v_row."holder_user_id", 'holderName', v_row."holder_name", 'holderEmail', v_row."holder_email", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'bookingId', v_row."booking_id", 'resourceId', v_row."resource_id", 'usesAllowed', v_row."uses_allowed", 'uses', v_row."uses", 'validFrom', v_row."valid_from", 'validUntil', v_row."valid_until", 'status', v_row."status", 'issuedBy', v_row."issued_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'revokedAt', v_row."revoked_at") || jsonb_build_object('nonce', v_row."nonce");
end;
$$;
revoke execute on function "app_private"."issue_pass"(uuid, text, uuid, text, text, text, text, uuid, uuid, integer, timestamptz, timestamptz) from public, anon;
grant execute on function "app_private"."issue_pass"(uuid, text, uuid, text, text, text, text, uuid, uuid, integer, timestamptz, timestamptz) to authenticated, service_role;

-- Revokes a pass; its token stops admitting.
create or replace function "app_private"."revoke_pass"(pass_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."passes"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."passes" x where x."id" = revoke_pass.pass_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'passes.manage'), false)) then
    raise exception 'pass not found' using errcode = 'P0002', hint = 'PASS_NOT_FOUND';
  end if;
  if v_row."status" <> 'revoked' then
    update "app_private"."passes" x set "status" = 'revoked', "revoked_at" = now(), "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'kind', v_row."kind", 'holderUserId', v_row."holder_user_id", 'holderName', v_row."holder_name", 'holderEmail', v_row."holder_email", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'bookingId', v_row."booking_id", 'resourceId', v_row."resource_id", 'usesAllowed', v_row."uses_allowed", 'uses', v_row."uses", 'validFrom', v_row."valid_from", 'validUntil', v_row."valid_until", 'status', v_row."status", 'issuedBy', v_row."issued_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'revokedAt', v_row."revoked_at");
end;
$$;
revoke execute on function "app_private"."revoke_pass"(uuid) from public, anon;
grant execute on function "app_private"."revoke_pass"(uuid) to authenticated, service_role;

-- One pass with its nonce, for the holder or a manager signing its token.
create or replace function "app_private"."get_pass"(pass_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."passes"%rowtype;
begin
  select * into v_row from "app_private"."passes" x where x."id" = get_pass.pass_id;
  if not found or not (v_row."holder_user_id" = auth.uid() or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'passes.manage'), false))) then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'kind', v_row."kind", 'holderUserId', v_row."holder_user_id", 'holderName', v_row."holder_name", 'holderEmail', v_row."holder_email", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'bookingId', v_row."booking_id", 'resourceId', v_row."resource_id", 'usesAllowed', v_row."uses_allowed", 'uses', v_row."uses", 'validFrom', v_row."valid_from", 'validUntil', v_row."valid_until", 'status', v_row."status", 'issuedBy', v_row."issued_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'revokedAt', v_row."revoked_at") || jsonb_build_object('nonce', v_row."nonce");
end;
$$;
revoke execute on function "app_private"."get_pass"(uuid) from public, anon;
grant execute on function "app_private"."get_pass"(uuid) to authenticated, service_role;

-- Scans a pass at a door. nonce comes from the verified token; a manual
-- check-in by staff leaves it null. Every scan is logged; an admitted one
-- uses the pass once. A pass without a booking counts against the
-- resource's capacity with the bookings and drop-ins there now.
create or replace function "app_private"."check_in_pass"(pass_id uuid, nonce text default null, method text default 'qr', gate text default null, resource_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_pass "app_private"."passes"%rowtype;
  v_row "app_private"."pass_check_ins"%rowtype;
  v_reason text;
  v_resource uuid;
  v_capacity integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if check_in_pass.method is null or check_in_pass.method not in ('qr', 'nfc', 'manual') then
    raise exception 'method is qr, nfc or manual' using errcode = '22023', hint = 'PASS_METHOD_INVALID';
  end if;
  select * into v_pass from "app_private"."passes" x where x."id" = check_in_pass.pass_id for update;
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
  insert into "app_private"."pass_check_ins" ("tenant_id", "pass_id", "resource_id", "booking_id", "gate", "method", "admitted", "reason", "checked_in_by")
  values (v_pass."tenant_id", v_pass."id", v_resource, v_pass."booking_id", check_in_pass.gate, check_in_pass.method, v_reason is null, v_reason, auth.uid())
  returning * into v_row;
  if v_reason is null then
    update "app_private"."passes" x set "uses" = x."uses" + 1, "updated_at" = now()
      where x."id" = v_pass."id"
      returning * into v_pass;
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'passId', v_row."pass_id", 'resourceId', v_row."resource_id", 'bookingId', v_row."booking_id", 'gate', v_row."gate", 'method', v_row."method", 'admitted', v_row."admitted", 'reason', v_row."reason", 'checkedInBy', v_row."checked_in_by", 'createdAt', v_row."created_at") || jsonb_build_object('pass', jsonb_build_object('id', v_pass."id", 'organizationId', v_pass."tenant_id"::text, 'kind', v_pass."kind", 'holderUserId', v_pass."holder_user_id", 'holderName', v_pass."holder_name", 'holderEmail', v_pass."holder_email", 'subjectType', v_pass."subject_type", 'subjectId', v_pass."subject_id", 'bookingId', v_pass."booking_id", 'resourceId', v_pass."resource_id", 'usesAllowed', v_pass."uses_allowed", 'uses', v_pass."uses", 'validFrom', v_pass."valid_from", 'validUntil', v_pass."valid_until", 'status', v_pass."status", 'issuedBy', v_pass."issued_by", 'createdAt', v_pass."created_at", 'updatedAt', v_pass."updated_at", 'revokedAt', v_pass."revoked_at"));
end;
$$;
revoke execute on function "app_private"."check_in_pass"(uuid, text, text, text, uuid) from public, anon;
grant execute on function "app_private"."check_in_pass"(uuid, text, text, text, uuid) to authenticated, service_role;

-- A tenant's passes, newest first, filtered by holder, record or status.
create or replace function "app_private"."list_passes"(tenant uuid, holder_user uuid default null, subject_type text default null, subject_id text default null, status text default null, before timestamptz default null, page_size integer default 50)
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
      from "app_private"."passes" x
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
revoke execute on function "app_private"."list_passes"(uuid, uuid, text, text, text, timestamptz, integer) from public, anon;
grant execute on function "app_private"."list_passes"(uuid, uuid, text, text, text, timestamptz, integer) to authenticated, service_role;

-- The caller's own live passes with their nonces, for a wallet screen.
create or replace function "app_private"."my_passes"()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'kind', x."kind", 'holderUserId', x."holder_user_id", 'holderName', x."holder_name", 'holderEmail', x."holder_email", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'bookingId', x."booking_id", 'resourceId', x."resource_id", 'usesAllowed', x."uses_allowed", 'uses', x."uses", 'validFrom', x."valid_from", 'validUntil', x."valid_until", 'status', x."status", 'issuedBy', x."issued_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'revokedAt', x."revoked_at") || jsonb_build_object('nonce', x."nonce") order by x."valid_from", x."id"), '[]'::jsonb)
  from "app_private"."passes" x
  where x."holder_user_id" = auth.uid()
    and x."status" = 'active'
    and (x."valid_until" is null or x."valid_until" > now())
    and not better_supabase.tenant_disabled(x."tenant_id")
$$;
revoke execute on function "app_private"."my_passes"() from public, anon;
grant execute on function "app_private"."my_passes"() to authenticated, service_role;

-- A pass's scans, newest first.
create or replace function "app_private"."list_pass_check_ins"(pass_id uuid, before timestamptz default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_pass "app_private"."passes"%rowtype;
begin
  select * into v_pass from "app_private"."passes" x where x."id" = list_pass_check_ins.pass_id;
  if not found or not (v_pass."holder_user_id" = auth.uid() or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_pass."tenant_id", 'passes.read'), false))) then
    return '[]'::jsonb;
  end if;
  return (
    select coalesce(jsonb_agg(z.item order by z.created desc, z.id desc), '[]'::jsonb)
    from (
      select jsonb_build_object('id', y."id", 'organizationId', y."tenant_id"::text, 'passId', y."pass_id", 'resourceId', y."resource_id", 'bookingId', y."booking_id", 'gate', y."gate", 'method', y."method", 'admitted', y."admitted", 'reason', y."reason", 'checkedInBy', y."checked_in_by", 'createdAt', y."created_at") as item, y."created_at" as created, y."id" as id
      from "app_private"."pass_check_ins" y
      where y."pass_id" = v_pass."id"
        and (list_pass_check_ins.before is null or y."created_at" < list_pass_check_ins.before)
      order by y."created_at" desc, y."id" desc
      limit least(greatest(coalesce(list_pass_check_ins.page_size, 50), 1), 500)
    ) z
  );
end;
$$;
revoke execute on function "app_private"."list_pass_check_ins"(uuid, timestamptz, integer) from public, anon;
grant execute on function "app_private"."list_pass_check_ins"(uuid, timestamptz, integer) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_118_admission_passes.sql
-- better-supabase module: admission-passes
-- @bsb-block-data admission-passes
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('admission-passes', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_118_admission_passes.sql
-- better-supabase module: admission-passes
-- @bsb-block admission-passes@1 managed
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
    and null::text is distinct from issue_pass.tenant::text then
    raise exception 'the record does not exist in this organization' using errcode = 'P0002', hint = 'PASS_SUBJECT_NOT_FOUND';
  end if;
  if issue_pass.holder_user is not null and not exists (select 1 from auth.users u where u.id = issue_pass.holder_user) then
    raise exception 'the holder does not exist' using errcode = 'P0002', hint = 'PASS_HOLDER_NOT_FOUND';
  end if;
  if issue_pass.booking_id is not null or issue_pass.resource_id is not null then
    raise exception 'install the bookings block to tie passes to bookings or resources' using errcode = '22023', hint = 'PASS_BOOKINGS_MISSING';
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
  null;
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
    null;
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
  insert into "better_supabase"."pass_check_ins" ("tenant_id", "pass_id", "resource_id", "booking_id", "gate", "method", "admitted", "reason", "checked_in_by")
  values (v_pass."tenant_id", v_pass."id", v_resource, v_pass."booking_id", check_in_pass.gate, check_in_pass.method, v_reason is null, v_reason, auth.uid())
  returning * into v_row;
  if v_reason is null then
    update "better_supabase"."passes" x set "uses" = x."uses" + 1, "updated_at" = now()
      where x."id" = v_pass."id"
      returning * into v_pass;
    null;
  else
    null;
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

-- blocks.admission-passes.api: entry points for the Data API.
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

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_118_admission_passes.sql
-- better-supabase module: admission-passes
-- @bsb-block-data admission-passes
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('admission-passes', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
