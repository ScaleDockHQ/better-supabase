import type { PassesEvents } from "../../blocks/passes/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  addForeignKey,
  fail,
  lockTable,
  pageSize,
  schemaPreamble,
  SERVICE_CALLER,
  userGrant,
} from "../shared.ts";
import { subjectTenant } from "../subject-check-sql.ts";
import { moveSubjectRows, subjectMergeHandler } from "../subject-merge-sql.ts";
import { registeredSubjects } from "../subject-registry.ts";
import { moduleOperations } from "./access-model.ts";
import {
  CREDIT_TABLES,
  creditsContract,
  creditsOn,
  creditsSql,
} from "./passes-credits.ts";

/** Why `check_in_pass` turned a pass away. */
const PASS_REJECTIONS = [
  "invalid",
  "revoked",
  "not_yet_valid",
  "expired",
  "used_up",
  "booking_cancelled",
  "booking_unconfirmed",
  "outside_window",
  "wrong_resource",
  "full",
] as const;

const PASS_METHODS = ["qr", "nfc", "manual"] as const;

const CHECK_IN_PAYLOAD = [
  "organizationId",
  "id",
  "checkInId",
  "resourceId",
  "bookingId",
] as const;

const CREDIT_PAYLOAD = [
  "organizationId",
  "id",
  "entryId",
  "bookingId",
] as const;

const EVENTS: BlockSqlEvents<PassesEvents> = {
  "pass.issued": {
    subject: "passes",
    payload: ["organizationId", "id", "kind", "holderUserId", "bookingId"],
  },
  "pass.revoked": { subject: "passes", payload: ["organizationId", "id"] },
  "pass.admitted": { subject: "passes", payload: CHECK_IN_PAYLOAD },
  "pass.rejected": {
    subject: "passes",
    payload: [...CHECK_IN_PAYLOAD, "reason"],
  },
  "pass.credit_used": { subject: "passes", payload: CREDIT_PAYLOAD },
  "pass.credit_refunded": { subject: "passes", payload: CREDIT_PAYLOAD },
};

const NAMES: BlockSqlNames = {
  entities: {
    pass: {
      table: "passes",
      singular: "pass",
      plural: "passes",
      primary: true,
    },
    pass_check_in: { table: "checkIns", singular: "pass_check_in" },
  },
  events: EVENTS,
  options: ["checkInOpens", "dropInLength", "credits", "creditRefundBefore"],
  tables: {
    passes: {
      name: "passes",
      lifecycle: { tenant: "tenant", user: "holderUser", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        kind: "kind",
        holderUser: "holder_user_id",
        holderName: "holder_name",
        holderEmail: "holder_email",
        subjectType: "subject_type",
        subjectId: "subject_id",
        booking: "booking_id",
        resource: "resource_id",
        usesAllowed: "uses_allowed",
        uses: "uses",
        validFrom: "valid_from",
        validUntil: "valid_until",
        status: "status",
        nonce: "nonce",
        issuedBy: "issued_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
        revokedAt: "revoked_at",
      },
    },
    checkIns: {
      name: "pass_check_ins",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        pass: "pass_id",
        resource: "resource_id",
        booking: "booking_id",
        gate: "gate",
        method: "method",
        admitted: "admitted",
        reason: "reason",
        checkedInBy: "checked_in_by",
        createdAt: "created_at",
      },
    },
    ...CREDIT_TABLES,
  },
};

const list = (values: readonly string[]): string =>
  values.map((value) => sqlString(value)).join(", ");

function tables(ctx: BlockSqlContext): string {
  if (!ctx.manages) {
    return "";
  }

  const passes = ctx.table("passes");
  const checkIns = ctx.table("checkIns");
  const p = (column: string): string => ctx.col("passes", column);
  const k = (column: string): string => ctx.col("checkIns", column);

  const index = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const bookingKeys = ctx.installed("bookings")
    ? (() => {
        const bookings = ctx.of("bookings");

        return [
          addForeignKey({
            table: passes,
            name: `${ctx.tableName("passes").name}_booking_fkey`,
            column: p("booking"),
            references: `${bookings.table("bookings")} (${bookings.col("bookings", "id")})`,
            onDelete: "cascade",
          }),
          addForeignKey({
            table: passes,
            name: `${ctx.tableName("passes").name}_resource_fkey`,
            column: p("resource"),
            references: `${bookings.table("resources")} (${bookings.col("resources", "id")})`,
            onDelete: "cascade",
          }),
        ].join("\n");
      })()
    : "";

  return `
-- Admission passes: a ticket for one booking, or a pass for a resource (a gym,
-- a venue) with a number of uses. The nonce goes in the signed token on the
-- QR code or NFC tag; only the functions read it.
create table if not exists ${passes} (
  ${p("id")} uuid primary key default gen_random_uuid(),
  ${p("tenant")} ${ctx.idType} not null,
  ${p("kind")} text not null default 'ticket' check (${p("kind")} ~ '^[a-z][a-z0-9_-]{0,39}$'),
  ${p("holderUser")} uuid references auth.users (id) on delete set null,
  ${p("holderName")} text check (${p("holderName")} is null or length(${p("holderName")}) >= 1 and length(${p("holderName")}) <= 200),
  ${p("holderEmail")} text check (${p("holderEmail")} is null or (length(${p("holderEmail")}) >= 3 and length(${p("holderEmail")}) <= 320 and position('@' in ${p("holderEmail")}) > 1)),
  ${p("subjectType")} text check (${p("subjectType")} is null or ${p("subjectType")} ~ '^[a-z][a-z0-9_-]{0,62}$'),
  ${p("subjectId")} text check (${p("subjectId")} is null or length(${p("subjectId")}) >= 1 and length(${p("subjectId")}) <= 200),
  ${p("booking")} uuid,
  ${p("resource")} uuid,
  ${p("usesAllowed")} integer check (${p("usesAllowed")} is null or ${p("usesAllowed")} > 0),
  ${p("uses")} integer not null default 0 check (${p("uses")} >= 0),
  ${p("validFrom")} timestamptz not null default now(),
  ${p("validUntil")} timestamptz,
  ${p("status")} text not null default 'active' check (${p("status")} in ('active', 'revoked')),
  ${p("nonce")} text not null unique,
  ${p("issuedBy")} uuid,
  ${p("createdAt")} timestamptz not null default now(),
  ${p("updatedAt")} timestamptz not null default now(),
  ${p("revokedAt")} timestamptz,
  check ((${p("subjectType")} is null) = (${p("subjectId")} is null)),
  check (${p("usesAllowed")} is null or ${p("uses")} <= ${p("usesAllowed")}),
  check (${p("validUntil")} is null or ${p("validUntil")} > ${p("validFrom")})
);
create index if not exists ${index("passes", "tenant_idx")} on ${passes} (${p("tenant")}, ${p("createdAt")} desc);
create index if not exists ${index("passes", "holder_idx")} on ${passes} (${p("holderUser")});
create index if not exists ${index("passes", "booking_idx")} on ${passes} (${p("booking")});
create index if not exists ${index("passes", "resource_idx")} on ${passes} (${p("resource")});
create index if not exists ${index("passes", "subject_idx")} on ${passes} (${p("tenant")}, ${p("subjectType")}, ${p("subjectId")});
${lockTable(passes)}
${bookingKeys}
-- Every scan, admitted or not, for the door log and the drop-in count.
create table if not exists ${checkIns} (
  ${k("id")} uuid primary key default gen_random_uuid(),
  ${k("tenant")} ${ctx.idType} not null,
  ${k("pass")} uuid not null references ${passes} (${p("id")}) on delete cascade,
  ${k("resource")} uuid,
  ${k("booking")} uuid,
  ${k("gate")} text check (${k("gate")} is null or length(${k("gate")}) >= 1 and length(${k("gate")}) <= 100),
  ${k("method")} text not null check (${k("method")} in (${list(PASS_METHODS)})),
  ${k("admitted")} boolean not null,
  ${k("reason")} text check (${k("reason")} is null or ${k("reason")} in (${list(PASS_REJECTIONS)})),
  ${k("checkedInBy")} uuid,
  ${k("createdAt")} timestamptz not null default now(),
  check (${k("admitted")} = (${k("reason")} is null))
);
create index if not exists ${index("checkIns", "log_idx")} on ${checkIns} (${k("pass")}, ${k("createdAt")} desc);
create index if not exists ${index("checkIns", "drop_in_idx")} on ${checkIns} (${k("resource")}, ${k("createdAt")}) where ${k("admitted")} and ${k("booking")} is null;
${lockTable(checkIns)}
`;
}

function functions(ctx: BlockSqlContext): string {
  const passes = ctx.table("passes");
  const checkIns = ctx.table("checkIns");
  const p = (column: string): string => ctx.col("passes", column);
  const k = (column: string): string => ctx.col("checkIns", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const keys = moduleOperations("passes");
  const read = ctx.permission("read", keys.read);
  const manage = ctx.permission("manage", keys.manage);
  const checkIn = ctx.permission("checkIn", keys.checkIn);
  const opens = ctx.text("checkInOpens", "1 hour");
  const dropIn = ctx.text("dropInLength", "2 hours");
  const bookings = ctx.installed("bookings") ? ctx.of("bookings") : undefined;

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`;

  const passJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${p("id")}, 'organizationId', ${row}.${p("tenant")}::text, 'kind', ${row}.${p("kind")}, 'holderUserId', ${row}.${p("holderUser")}, 'holderName', ${row}.${p("holderName")}, 'holderEmail', ${row}.${p("holderEmail")}, 'subjectType', ${row}.${p("subjectType")}, 'subjectId', ${row}.${p("subjectId")}, 'bookingId', ${row}.${p("booking")}, 'resourceId', ${row}.${p("resource")}, 'usesAllowed', ${row}.${p("usesAllowed")}, 'uses', ${row}.${p("uses")}, 'validFrom', ${row}.${p("validFrom")}, 'validUntil', ${row}.${p("validUntil")}, 'status', ${row}.${p("status")}, 'issuedBy', ${row}.${p("issuedBy")}, 'createdAt', ${row}.${p("createdAt")}, 'updatedAt', ${row}.${p("updatedAt")}, 'revokedAt', ${row}.${p("revokedAt")})`;

  const withNonce = (row: string): string =>
    `${passJson(row)} || jsonb_build_object('nonce', ${row}.${p("nonce")})`;

  const checkInJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${k("id")}, 'organizationId', ${row}.${k("tenant")}::text, 'passId', ${row}.${k("pass")}, 'resourceId', ${row}.${k("resource")}, 'bookingId', ${row}.${k("booking")}, 'gate', ${row}.${k("gate")}, 'method', ${row}.${k("method")}, 'admitted', ${row}.${k("admitted")}, 'reason', ${row}.${k("reason")}, 'checkedInBy', ${row}.${k("checkedInBy")}, 'createdAt', ${row}.${k("createdAt")})`;

  const passRecord = (
    type: "pass.issued" | "pass.revoked",
    row: string,
    summary: string,
  ): string => {
    const base = `'organizationId', ${row}.${p("tenant")}::text, 'id', ${row}.${p("id")}`;

    return ctx.record({
      type,
      payload:
        type === "pass.issued"
          ? `jsonb_build_object(${base}, 'kind', ${row}.${p("kind")}, 'holderUserId', ${row}.${p("holderUser")}, 'bookingId', ${row}.${p("booking")})`
          : `jsonb_build_object(${base})`,
      subject: `'passes/' || ${row}.${p("id")}::text`,
      tenant: `${row}.${p("tenant")}`,
      audit: {
        category: "access",
        targetType: "pass",
        recordId: `${row}.${p("id")}::text`,
        summary: `'${summary} ' || ${row}.${p("kind")}`,
      },
    });
  };

  const checkInRecord = (type: "pass.admitted" | "pass.rejected"): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', v_row.${k("tenant")}::text, 'id', v_row.${k("pass")}, 'checkInId', v_row.${k("id")}, 'resourceId', v_row.${k("resource")}, 'bookingId', v_row.${k("booking")}${type === "pass.rejected" ? `, 'reason', v_row.${k("reason")}` : ""})`,
      subject: `'passes/' || v_row.${k("pass")}::text`,
      tenant: `v_row.${k("tenant")}`,
      audit: false,
    });

  const b = (column: string): string =>
    bookings === undefined ? column : bookings.col("bookings", column);

  const r = (column: string): string =>
    bookings === undefined ? column : bookings.col("resources", column);

  const seated = (row: string): string =>
    `(${row}.${b("status")} = 'confirmed' or (${row}.${b("status")} = 'hold' and ${row}.${b("holdExpiresAt")} > now()))`;

  const issueChecks =
    bookings === undefined
      ? `  if issue_pass.booking_id is not null or issue_pass.resource_id is not null then
    ${fail("PASS_BOOKINGS_MISSING", "install the bookings block to tie passes to bookings or resources", "22023")}
  end if;`
      : `  if issue_pass.booking_id is not null then
    select * into v_booking from ${bookings.table("bookings")} bk
      where bk.${b("id")} = issue_pass.booking_id and bk.${b("tenant")} = issue_pass.tenant;
    if not found then
      ${fail("PASS_BOOKING_NOT_FOUND", "the booking does not exist in this organization", "P0002")}
    end if;
    if v_booking.${b("status")} = 'cancelled' then
      ${fail("PASS_BOOKING_CANCELLED", "the booking is cancelled", "55000")}
    end if;
    if issue_pass.resource_id is not null and issue_pass.resource_id <> v_booking.${b("resource")} then
      ${fail("PASS_RESOURCE_MISMATCH", "the booking is for another resource", "22023")}
    end if;
    v_resource := v_booking.${b("resource")};
    v_until := coalesce(v_until, upper(v_booking.${b("during")}));
  elsif issue_pass.resource_id is not null then
    if not exists (
      select 1 from ${bookings.table("resources")} rs
      where rs.${r("id")} = issue_pass.resource_id and rs.${r("tenant")} = issue_pass.tenant
    ) then
      ${fail("PASS_RESOURCE_NOT_FOUND", "the resource does not exist in this organization", "P0002")}
    end if;
  end if;`;

  const bookingDeclare =
    bookings === undefined
      ? ""
      : `\n  v_booking ${bookings.table("bookings")}%rowtype;`;

  const capacity =
    bookings === undefined
      ? ""
      : `
  if v_reason is null and v_pass.${p("booking")} is not null then
    select * into v_booking from ${bookings.table("bookings")} bk where bk.${b("id")} = v_pass.${p("booking")};
    if not found or v_booking.${b("status")} = 'cancelled'
      or (v_booking.${b("status")} = 'hold' and v_booking.${b("holdExpiresAt")} <= now()) then
      v_reason := 'booking_cancelled';
    elsif v_booking.${b("status")} = 'hold' then
      v_reason := 'booking_unconfirmed';
    elsif now() < lower(v_booking.${b("during")}) - ${sqlString(opens)}::interval
      or now() >= upper(v_booking.${b("during")}) then
      v_reason := 'outside_window';
    end if;
  end if;
  if v_reason is null and v_pass.${p("booking")} is null and v_resource is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bsb:passes:' || v_resource::text, 0));
    select rs.${r("capacity")} into v_capacity from ${bookings.table("resources")} rs
      where rs.${r("id")} = v_resource and rs.${r("tenant")} = v_pass.${p("tenant")};
    if v_capacity is null then
      v_reason := 'wrong_resource';
    elsif ${occupied("v_resource")} >= v_capacity then
      v_reason := 'full';
    end if;
  end if;`;

  function occupied(resource: string): string {
    if (bookings === undefined) {
      return "0";
    }

    return `((select count(*) from ${bookings.table("bookings")} bk
      where bk.${b("resource")} = ${resource} and ${seated("bk")} and bk.${b("during")} @> now())
      + (select count(*) from ${checkIns} y
      where y.${k("resource")} = ${resource} and y.${k("admitted")} and y.${k("booking")} is null
        and y.${k("createdAt")} > now() - ${sqlString(dropIn)}::interval))`;
  }

  const occupancy =
    bookings === undefined
      ? ""
      : `
-- How full a resource is now: seats taken by bookings and drop-ins admitted
-- within the drop-in length, for a door display.
create or replace function ${fn("pass_occupancy")}(resource_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${idType};
  v_capacity integer;
  v_booked integer;
  v_drop_ins integer;
begin
  select rs.${r("tenant")}, rs.${r("capacity")} into v_tenant, v_capacity
    from ${bookings.table("resources")} rs where rs.${r("id")} = pass_occupancy.resource_id;
  if not found or not ${allowed("v_tenant", checkIn)} then
    ${fail("PASS_RESOURCE_NOT_FOUND", "resource not found", "P0002")}
  end if;
  select count(*) into v_booked from ${bookings.table("bookings")} bk
    where bk.${b("resource")} = pass_occupancy.resource_id and ${seated("bk")} and bk.${b("during")} @> now();
  select count(*) into v_drop_ins from ${checkIns} y
    where y.${k("resource")} = pass_occupancy.resource_id and y.${k("admitted")} and y.${k("booking")} is null
      and y.${k("createdAt")} > now() - ${sqlString(dropIn)}::interval;
  return jsonb_build_object('resourceId', pass_occupancy.resource_id, 'capacity', v_capacity,
    'booked', v_booked, 'dropIns', v_drop_ins, 'free', greatest(v_capacity - v_booked - v_drop_ins, 0));
end;
$$;
${userGrant(`${fn("pass_occupancy")}(uuid)`)}
`;

  return `
-- Issues a pass in tenant: a ticket for booking_id (valid until the booking
-- ends unless valid_until says otherwise), a pass for resource_id, or a pass
-- for a registered record. Returns the pass with its nonce for the token.
create or replace function ${fn("issue_pass")}(tenant ${idType}, kind text default 'ticket', holder_user uuid default null, holder_name text default null, holder_email text default null, subject_type text default null, subject_id text default null, booking_id uuid default null, resource_id uuid default null, uses_allowed integer default null, valid_from timestamptz default null, valid_until timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${passes}%rowtype;
  v_resource uuid := issue_pass.resource_id;
  v_until timestamptz := issue_pass.valid_until;${bookingDeclare}
begin
  if not ${allowed("issue_pass.tenant", manage)} then
    ${fail("PASS_FORBIDDEN", "not allowed to issue passes")}
  end if;
  if (issue_pass.subject_type is null) <> (issue_pass.subject_id is null) then
    ${fail("PASS_SUBJECT_INVALID", "pass both subject_type and subject_id, or neither", "22023")}
  end if;
  if issue_pass.subject_type is not null
    and ${subjectTenant(ctx, "issue_pass.subject_type", "issue_pass.subject_id")} is distinct from issue_pass.tenant::text then
    ${fail("PASS_SUBJECT_NOT_FOUND", "the record does not exist in this organization", "P0002")}
  end if;
  if issue_pass.holder_user is not null and not exists (select 1 from auth.users u where u.id = issue_pass.holder_user) then
    ${fail("PASS_HOLDER_NOT_FOUND", "the holder does not exist", "P0002")}
  end if;
${issueChecks}
  if v_until is not null and v_until <= coalesce(issue_pass.valid_from, now()) then
    ${fail("PASS_VALIDITY_INVALID", "valid_until must be after valid_from and in the future", "22023")}
  end if;
  insert into ${passes} (${p("tenant")}, ${p("kind")}, ${p("holderUser")}, ${p("holderName")}, ${p("holderEmail")}, ${p("subjectType")}, ${p("subjectId")}, ${p("booking")}, ${p("resource")}, ${p("usesAllowed")}, ${p("validFrom")}, ${p("validUntil")}, ${p("nonce")}, ${p("issuedBy")})
  values (issue_pass.tenant, coalesce(issue_pass.kind, 'ticket'), issue_pass.holder_user, issue_pass.holder_name, lower(btrim(issue_pass.holder_email)),
    issue_pass.subject_type, issue_pass.subject_id, issue_pass.booking_id, v_resource,
    case when issue_pass.booking_id is not null then coalesce(issue_pass.uses_allowed, 1) else issue_pass.uses_allowed end,
    coalesce(issue_pass.valid_from, now()), v_until, encode(extensions.gen_random_bytes(16), 'hex'), auth.uid())
  returning * into v_row;
  ${passRecord("pass.issued", "v_row", "issued pass")}
  return ${withNonce("v_row")};
end;
$$;
${userGrant(`${fn("issue_pass")}(${idType}, text, uuid, text, text, text, text, uuid, uuid, integer, timestamptz, timestamptz)`)}

-- Revokes a pass; its token stops admitting.
create or replace function ${fn("revoke_pass")}(pass_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${passes}%rowtype;
begin
  select * into v_row from ${passes} x where x.${p("id")} = revoke_pass.pass_id for update;
  if not found or not ${allowed(`v_row.${p("tenant")}`, manage)} then
    ${fail("PASS_NOT_FOUND", "pass not found", "P0002")}
  end if;
  if v_row.${p("status")} <> 'revoked' then
    update ${passes} x set ${p("status")} = 'revoked', ${p("revokedAt")} = now(), ${p("updatedAt")} = now()
      where x.${p("id")} = v_row.${p("id")}
      returning * into v_row;
    ${passRecord("pass.revoked", "v_row", "revoked pass")}
  end if;
  return ${passJson("v_row")};
end;
$$;
${userGrant(`${fn("revoke_pass")}(uuid)`)}

-- One pass with its nonce, for the holder or a manager signing its token.
create or replace function ${fn("get_pass")}(pass_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${passes}%rowtype;
begin
  select * into v_row from ${passes} x where x.${p("id")} = get_pass.pass_id;
  if not found or not (v_row.${p("holderUser")} = auth.uid() or ${allowed(`v_row.${p("tenant")}`, manage)}) then
    return null;
  end if;
  return ${withNonce("v_row")};
end;
$$;
${userGrant(`${fn("get_pass")}(uuid)`)}

-- Scans a pass at a door. nonce comes from the verified token; a manual
-- check-in by staff leaves it null. Every scan is logged; an admitted one
-- uses the pass once. A pass without a booking counts against the
-- resource's capacity with the bookings and drop-ins there now.
create or replace function ${fn("check_in_pass")}(pass_id uuid, nonce text default null, method text default 'qr', gate text default null, resource_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_pass ${passes}%rowtype;
  v_row ${checkIns}%rowtype;
  v_reason text;
  v_resource uuid;
  v_capacity integer;${bookingDeclare}
begin
  if check_in_pass.method is null or check_in_pass.method not in (${list(PASS_METHODS)}) then
    ${fail("PASS_METHOD_INVALID", "method is qr, nfc or manual", "22023")}
  end if;
  select * into v_pass from ${passes} x where x.${p("id")} = check_in_pass.pass_id for update;
  if not found or not ${allowed(`v_pass.${p("tenant")}`, checkIn)} then
    ${fail("PASS_NOT_FOUND", "pass not found", "P0002")}
  end if;
  v_resource := coalesce(check_in_pass.resource_id, v_pass.${p("resource")});
  v_reason := case
    when check_in_pass.method <> 'manual' and check_in_pass.nonce is distinct from v_pass.${p("nonce")} then 'invalid'
    when v_pass.${p("status")} = 'revoked' then 'revoked'
    when now() < v_pass.${p("validFrom")} then 'not_yet_valid'
    when v_pass.${p("validUntil")} is not null and now() >= v_pass.${p("validUntil")} then 'expired'
    when v_pass.${p("usesAllowed")} is not null and v_pass.${p("uses")} >= v_pass.${p("usesAllowed")} then 'used_up'
    when check_in_pass.resource_id is not null and v_pass.${p("resource")} is not null
      and check_in_pass.resource_id <> v_pass.${p("resource")} then 'wrong_resource'
  end;${capacity}
  insert into ${checkIns} (${k("tenant")}, ${k("pass")}, ${k("resource")}, ${k("booking")}, ${k("gate")}, ${k("method")}, ${k("admitted")}, ${k("reason")}, ${k("checkedInBy")})
  values (v_pass.${p("tenant")}, v_pass.${p("id")}, v_resource, v_pass.${p("booking")}, check_in_pass.gate, check_in_pass.method, v_reason is null, v_reason, auth.uid())
  returning * into v_row;
  if v_reason is null then
    update ${passes} x set ${p("uses")} = x.${p("uses")} + 1, ${p("updatedAt")} = now()
      where x.${p("id")} = v_pass.${p("id")}
      returning * into v_pass;
    ${checkInRecord("pass.admitted")}
  else
    ${checkInRecord("pass.rejected")}
  end if;
  return ${checkInJson("v_row")} || jsonb_build_object('pass', ${passJson("v_pass")});
end;
$$;
${userGrant(`${fn("check_in_pass")}(uuid, text, text, text, uuid)`)}

-- A tenant's passes, newest first, filtered by holder, record or status.
create or replace function ${fn("list_passes")}(tenant ${idType}, holder_user uuid default null, subject_type text default null, subject_id text default null, status text default null, before timestamptz default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not ${allowed("list_passes.tenant", read)} then
    ${fail("PASS_FORBIDDEN", "not allowed to read passes")}
  end if;
  return (
    select coalesce(jsonb_agg(z.item order by z.created desc, z.id desc), '[]'::jsonb)
    from (
      select ${passJson("x")} as item, x.${p("createdAt")} as created, x.${p("id")} as id
      from ${passes} x
      where x.${p("tenant")} = list_passes.tenant
        and (list_passes.holder_user is null or x.${p("holderUser")} = list_passes.holder_user)
        and (list_passes.subject_type is null or (x.${p("subjectType")} = list_passes.subject_type and x.${p("subjectId")} = list_passes.subject_id))
        and (list_passes.status is null or x.${p("status")} = list_passes.status)
        and (list_passes.before is null or x.${p("createdAt")} < list_passes.before)
      order by x.${p("createdAt")} desc, x.${p("id")} desc
      limit ${pageSize("list_passes.page_size", 50, 500)}
    ) z
  );
end;
$$;
${userGrant(`${fn("list_passes")}(${idType}, uuid, text, text, text, timestamptz, integer)`)}

-- The caller's own live passes with their nonces, for a wallet screen.
create or replace function ${fn("my_passes")}()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(${withNonce("x")} order by x.${p("validFrom")}, x.${p("id")}), '[]'::jsonb)
  from ${passes} x
  where x.${p("holderUser")} = auth.uid()
    and x.${p("status")} = 'active'
    and (x.${p("validUntil")} is null or x.${p("validUntil")} > now())
    and not better_supabase.tenant_disabled(x.${p("tenant")})
$$;
${userGrant(`${fn("my_passes")}()`)}

-- A pass's scans, newest first.
create or replace function ${fn("list_pass_check_ins")}(pass_id uuid, before timestamptz default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_pass ${passes}%rowtype;
begin
  select * into v_pass from ${passes} x where x.${p("id")} = list_pass_check_ins.pass_id;
  if not found or not (v_pass.${p("holderUser")} = auth.uid() or ${allowed(`v_pass.${p("tenant")}`, read)}) then
    return '[]'::jsonb;
  end if;
  return (
    select coalesce(jsonb_agg(z.item order by z.created desc, z.id desc), '[]'::jsonb)
    from (
      select ${checkInJson("y")} as item, y.${k("createdAt")} as created, y.${k("id")} as id
      from ${checkIns} y
      where y.${k("pass")} = v_pass.${p("id")}
        and (list_pass_check_ins.before is null or y.${k("createdAt")} < list_pass_check_ins.before)
      order by y.${k("createdAt")} desc, y.${k("id")} desc
      limit ${pageSize("list_pass_check_ins.page_size", 50, 500)}
    ) z
  );
end;
$$;
${userGrant(`${fn("list_pass_check_ins")}(uuid, timestamptz, integer)`)}
${occupancy}`;
}

/** Moves the passes on a merged registered subject to the record it merged into. */
function passMerges(ctx: BlockSqlContext): string {
  const subjects = registeredSubjects(ctx.subjects, ctx.naming).map(
    (subject) =>
      [
        subject.type,
        { table: `${subject.schema}.${subject.table}`, extra: {} },
      ] as const,
  );

  return subjectMergeHandler(
    ctx,
    subjects,
    moveSubjectRows(
      {
        table: ctx.table("passes"),
        type: ctx.col("passes", "subjectType"),
        id: ctx.col("passes", "subjectId"),
      },
      "v_type",
    ),
  );
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  return `${schemaPreamble(ctx)}
-- Passes: QR and NFC admission signed with the signing-keys block, with a
-- log of every scan and capacity counted against bookings.
${tables(ctx)}${functions(ctx)}${passMerges(ctx)}${creditsOn(ctx) ? creditsSql(ctx) : ""}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "issue_pass",
      args: [
        "{id}",
        "text",
        "uuid",
        "text",
        "text",
        "text",
        "text",
        "uuid",
        "uuid",
        "integer",
        "timestamptz",
        "timestamptz",
      ],
      returns: "jsonb",
    },
    { name: "revoke_pass", args: ["uuid"], returns: "jsonb" },
    { name: "get_pass", args: ["uuid"], returns: "jsonb" },
    {
      name: "check_in_pass",
      args: ["uuid", "text", "text", "text", "uuid"],
      returns: "jsonb",
    },
    {
      name: "list_passes",
      args: ["{id}", "uuid", "text", "text", "text", "timestamptz", "integer"],
      returns: "jsonb",
    },
    { name: "my_passes", args: [], returns: "jsonb" },
    {
      name: "list_pass_check_ins",
      args: ["uuid", "timestamptz", "integer"],
      returns: "jsonb",
    },
    ...(ctx.installed("bookings")
      ? [{ name: "pass_occupancy", args: ["uuid"], returns: "jsonb" }]
      : []),
    ...(creditsOn(ctx) ? creditsContract() : []),
  ];
}

export const PASSES: BlockSqlDefinition = {
  name: "passes",
  scopes: ["tenant"],
  title: "Passes",
  description:
    "Admission passes on QR codes and NFC tags, signed with the signing-keys block: a ticket for a booking or a pass with a number of uses for a resource, a log of every scan, class credits that pay for bookings and come back on an early cancellation, and drop-ins counted against the resource's capacity with its bookings.",
  requires: ["tenant", "access"],
  integrates: ["outbox", "audit", "bookings", "signing-keys"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
