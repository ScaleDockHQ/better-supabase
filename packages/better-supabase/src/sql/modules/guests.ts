import type { GuestsEvents } from "../../blocks/guests/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition, BlockSqlLayout } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { guestFunctions, providerGuestSource } from "../guest-sql.ts";
import { GUEST_ACTIONS } from "../scope.ts";
import {
  fail,
  pageSize,
  schemaPreamble,
  SERVICE_CALLER,
  sha256Hex,
  userGrant,
} from "../shared.ts";
import { subjectTenant } from "../subject-check-sql.ts";
import { moveSubjectRows, subjectMergeHandler } from "../subject-merge-sql.ts";
import { registeredSubjects } from "../subject-registry.ts";
import { asText, lockModuleTable } from "./over-app.ts";
import { moduleOperations } from "./permissions-model.ts";

const ACCESS_PAYLOAD = [
  "organizationId",
  "id",
  "guestId",
  "subjectType",
  "subjectId",
  "actions",
] as const;

const EVENTS: BlockSqlEvents<GuestsEvents> = {
  "guest.invited": {
    subject: "guests",
    payload: ["organizationId", "id", "email", "partyType", "partyId"],
  },
  "guest.accepted": {
    subject: "guests",
    payload: ["organizationId", "id", "userId"],
  },
  "guest.revoked": { subject: "guests", payload: ["organizationId", "id"] },
  "guest_grant.created": { subject: "guest-grants", payload: ACCESS_PAYLOAD },
  "guest_grant.revoked": { subject: "guest-grants", payload: ACCESS_PAYLOAD },
};

const NAMES: BlockSqlNames = {
  entities: {
    guest: { table: "guests", singular: "guest", primary: true },
    guest_grant: { table: "grants", singular: "guest_grant" },
  },
  events: EVENTS,
  tables: {
    guests: {
      name: "guests",
      app: {},
      lifecycle: { tenant: "tenant", user: "user", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        email: "email",
        name: "name",
        user: "user_id",
        partyType: "party_type",
        partyId: "party_id",
        status: "status",
        tokenHash: "token_hash",
        invitedBy: "invited_by",
        expiresAt: "expires_at",
        acceptedAt: "accepted_at",
        revokedAt: "revoked_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: [
        "name",
        "partyType",
        "partyId",
        "invitedBy",
        "expiresAt",
        "acceptedAt",
        "revokedAt",
        "updatedAt",
      ],
      typed: ["status"],
    },
    grants: {
      name: "guest_grants",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        guest: "guest_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        actions: "actions",
        grantedBy: "granted_by",
        expiresAt: "expires_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["grantedBy", "expiresAt", "updatedAt"],
    },
  },
};

const ACTIONS = `array[${GUEST_ACTIONS.map((action) => sqlString(action)).join(", ")}]::text[]`;

/**
 * The tenant (as text) of the record a grant names: the records other blocks
 * own that guests commonly reach (an invoice, a booking), then every registered
 * subject. Null for an unknown record.
 */
function grantSubjectTenant(
  ctx: BlockSqlContext,
  type: string,
  id: string,
): string {
  const owned: string[] = [];

  const row = (module: string, table: string): string => {
    const other = ctx.of(module);
    const c = (column: string): string => `s.${other.col(table, column)}`;

    return `(select ${c("tenant")}::text from ${other.table(table)} s where ${c("id")}::text = ${id})`;
  };

  if (ctx.installed("invoices")) {
    owned.push(`when 'invoice' then ${row("invoices", "invoices")}`);
  }

  if (ctx.installed("bookings")) {
    owned.push(`when 'booking' then ${row("bookings", "bookings")}`);
  }

  const registered = subjectTenant(ctx, type, id);

  return owned.length === 0
    ? registered
    : `(case ${type}\n      ${owned.join("\n      ")}\n      else ${registered}\n    end)`;
}

function tables(ctx: BlockSqlContext): string {
  if (!ctx.manages) {
    return "";
  }

  const guests = ctx.table("guests");
  const grants = ctx.table("grants");
  const g = (column: string): string => ctx.col("guests", column);
  const r = (column: string): string => ctx.col("grants", column);
  const read = ctx.permission("read", moduleOperations("guests").read);

  const index = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  // A column definition, left out when the app maps the column to null.
  const column = (
    table: string,
    logical: string,
    definition: (name: string) => string,
  ): string =>
    ctx.has(table, logical)
      ? `\n  ${ctx.col(table, logical)} ${definition(ctx.col(table, logical))},`
      : "";

  const party = ctx.has("guests", "partyType") && ctx.has("guests", "partyId");

  return `
create table if not exists ${guests} (
  ${g("id")} uuid primary key default gen_random_uuid(),
  ${g("tenant")} ${ctx.idType} not null,
  ${g("email")} text not null check (length(${g("email")}) >= 3 and length(${g("email")}) <= 320 and position('@' in ${g("email")}) > 1),${column("guests", "name", (name) => `text check (${name} is null or length(${name}) between 1 and 200)`)}
  ${g("user")} uuid references auth.users (id) on delete set null,${column("guests", "partyType", () => "text")}${column("guests", "partyId", () => "text")}
  ${g("status")} text not null default 'invited' check (${g("status")} in ('invited', 'active', 'revoked')),
  ${g("tokenHash")} text unique,${column("guests", "invitedBy", () => "uuid")}${column("guests", "expiresAt", () => "timestamptz")}${column("guests", "acceptedAt", () => "timestamptz")}${column("guests", "revokedAt", () => "timestamptz")}
  ${g("createdAt")} timestamptz not null default now(),${column("guests", "updatedAt", () => "timestamptz not null default now()")}${party ? `\n  check ((${g("partyType")} is null) = (${g("partyId")} is null)),` : ""}
  check (${g("status")} <> 'active' or ${g("user")} is not null)
);
create unique index if not exists ${index("guests", "email_idx")} on ${guests} (${g("tenant")}, lower(${g("email")}));
create unique index if not exists ${index("guests", "user_idx")} on ${guests} (${g("tenant")}, ${g("user")}) where ${g("user")} is not null;
create index if not exists ${index("guests", "user_id_idx")} on ${guests} (${g("user")});
${lockModuleTable(ctx, "guests", { read: true })}
drop policy if exists ${index("guests", "read")} on ${guests};
create policy ${index("guests", "read")} on ${guests} for select to authenticated
  using (${ctx.scope.check(g("tenant"), read)} or ${g("user")} = (select auth.uid()));

create table if not exists ${grants} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("guest")} uuid not null references ${guests} (${g("id")}) on delete cascade,
  ${r("subjectType")} text not null check (${r("subjectType")} ~ '^[a-z][a-z0-9_-]{0,62}$'),
  ${r("subjectId")} text not null check (length(${r("subjectId")}) between 1 and 200),
  ${r("actions")} text[] not null check (cardinality(${r("actions")}) > 0 and ${r("actions")} <@ ${ACTIONS} and 'read' = any(${r("actions")})),${column("grants", "grantedBy", () => "uuid")}${column("grants", "expiresAt", () => "timestamptz")}
  ${r("createdAt")} timestamptz not null default now(),${column("grants", "updatedAt", () => "timestamptz not null default now()")}
  unique (${r("guest")}, ${r("subjectType")}, ${r("subjectId")})
);${ctx.owns("grants") ? "" : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName("grants").name}_subject_key`)} on ${grants} (${r("guest")}, ${r("subjectType")}, ${r("subjectId")});`}
create index if not exists ${index("grants", "subject_idx")} on ${grants} (${r("tenant")}, ${r("subjectType")}, ${r("subjectId")});
${lockModuleTable(ctx, "grants", { read: true })}
drop policy if exists ${index("grants", "read")} on ${grants};
create policy ${index("grants", "read")} on ${grants} for select to authenticated
  using (${ctx.scope.check(r("tenant"), read)}
    or ${r("guest")} in (select x.${g("id")} from ${guests} x where x.${g("user")} = (select auth.uid())));
`;
}

function functions(ctx: BlockSqlContext, layout: BlockSqlLayout): string {
  const guests = ctx.table("guests");
  const grants = ctx.table("grants");
  const g = (column: string): string => ctx.col("guests", column);
  const r = (column: string): string => ctx.col("grants", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const keys = moduleOperations("guests");
  const read = ctx.permission("read", keys.read);
  const manage = ctx.permission("manage", keys.manage);

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`;

  const forbidden = (message: string): string =>
    fail("GUEST_FORBIDDEN", message);

  const hasGuest = (column: string): boolean => ctx.has("guests", column);
  const hasGrant = (column: string): boolean => ctx.has("grants", column);
  const party = hasGuest("partyType") && hasGuest("partyId");
  const status = (value: string): string => ctx.cast("guests", "status", value);

  // Column `column` of row `row`, or `missing` when the app's table lacks it.
  const guest = (row: string, column: string, missing = "null"): string =>
    hasGuest(column) ? `${row}.${g(column)}` : missing;

  const grant = (row: string, column: string, missing = "null"): string =>
    hasGrant(column) ? `${row}.${r(column)}` : missing;

  // `column = value` assignments for the columns the app's guests table has.
  const assign = (
    pairs: readonly (readonly [column: string, value: string])[],
  ): string[] =>
    pairs
      .filter(([column]) => hasGuest(column))
      .map(([column, value]) => `${g(column)} = ${value}`);

  const unexpiredGrant = (row: string): string =>
    hasGrant("expiresAt")
      ? ` and (${row}.${r("expiresAt")} is null or ${row}.${r("expiresAt")} > now())`
      : "";

  const live = (alias: string): string =>
    `${asText(ctx, "guests", `${alias}.${g("status")}`)} = 'active' and ${alias}.${g("user")} = auth.uid() and not better_supabase.tenant_disabled(${alias}.${g("tenant")}) and not better_supabase.user_disabled(auth.uid())`;

  const guestJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${g("id")}, 'organizationId', ${row}.${g("tenant")}::text, 'email', ${row}.${g("email")}, 'name', ${guest(row, "name")}, 'userId', ${row}.${g("user")}, 'partyType', ${guest(row, "partyType")}, 'partyId', ${guest(row, "partyId")}, 'status', ${row}.${g("status")}, 'invitedBy', ${guest(row, "invitedBy")}, 'expiresAt', ${guest(row, "expiresAt")}, 'acceptedAt', ${guest(row, "acceptedAt")}, 'revokedAt', ${guest(row, "revokedAt")}, 'createdAt', ${row}.${g("createdAt")}, 'updatedAt', ${guest(row, "updatedAt", `${row}.${g("createdAt")}`)})`;

  const grantJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${r("id")}, 'organizationId', ${row}.${r("tenant")}::text, 'guestId', ${row}.${r("guest")}, 'subjectType', ${row}.${r("subjectType")}, 'subjectId', ${row}.${r("subjectId")}, 'actions', to_jsonb(${row}.${r("actions")}), 'grantedBy', ${grant(row, "grantedBy")}, 'expiresAt', ${grant(row, "expiresAt")}, 'createdAt', ${row}.${r("createdAt")}, 'updatedAt', ${grant(row, "updatedAt", `${row}.${r("createdAt")}`)})`;

  const guestRecord = (
    type: "guest.invited" | "guest.accepted" | "guest.revoked",
    row: string,
    summary: string,
  ): string => {
    const base = `'organizationId', ${row}.${g("tenant")}::text, 'id', ${row}.${g("id")}`;

    const payload =
      type === "guest.invited"
        ? `jsonb_build_object(${base}, 'email', ${row}.${g("email")}, 'partyType', ${guest(row, "partyType")}, 'partyId', ${guest(row, "partyId")})`
        : type === "guest.accepted"
          ? `jsonb_build_object(${base}, 'userId', ${row}.${g("user")})`
          : `jsonb_build_object(${base})`;

    return ctx.record({
      type,
      payload,
      subject: `'guests/' || ${row}.${g("id")}::text`,
      tenant: `${row}.${g("tenant")}`,
      audit: {
        category: "access",
        targetType: "guest",
        recordId: `${row}.${g("id")}::text`,
        targetLabel: `${row}.${g("email")}`,
        summary: `'${summary} ' || ${row}.${g("email")}`,
      },
    });
  };

  const grantRecord = (
    type: "guest_grant.created" | "guest_grant.revoked",
    row: string,
    summary: string,
  ): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${r("tenant")}::text, 'id', ${row}.${r("id")}, 'guestId', ${row}.${r("guest")}, 'subjectType', ${row}.${r("subjectType")}, 'subjectId', ${row}.${r("subjectId")}, 'actions', to_jsonb(${row}.${r("actions")}))`,
      subject: `'guest-grants/' || ${row}.${r("id")}::text`,
      tenant: `${row}.${r("tenant")}`,
      audit: {
        category: "access",
        targetType: "guest_grant",
        recordId: `${row}.${r("id")}::text`,
        summary: `'${summary} ' || ${row}.${r("subjectType")} || '/' || ${row}.${r("subjectId")}`,
      },
    });

  const own = {
    subjects: `select x.${g("tenant")}::text, y.${r("subjectType")}, y.${r("subjectId")}
  from ${grants} y
  join ${guests} x on x.${g("id")} = y.${r("guest")}
  where ${live("x")}
    and portal_subjects.action = any(y.${r("actions")})${unexpiredGrant("y") === "" ? "" : `\n   ${unexpiredGrant("y")}`}`,
    ...(party
      ? {
          parties: `select x.${g("tenant")}::text, x.${g("partyType")}, x.${g("partyId")}
  from ${guests} x
  where ${live("x")} and x.${g("partyType")} is not null`,
        }
      : {}),
  };

  const refreshed = assign([
    ["name", `coalesce(invite_guest.name, ${guest("x", "name")})`],
    [
      "partyType",
      `coalesce(invite_guest.party_type, ${guest("x", "partyType")})`,
    ],
    ["partyId", `coalesce(invite_guest.party_id, ${guest("x", "partyId")})`],
    ["updatedAt", "now()"],
  ]);

  const reinvited = [
    ...assign([
      ["name", `coalesce(invite_guest.name, ${guest("x", "name")})`],
      [
        "partyType",
        `coalesce(invite_guest.party_type, ${guest("x", "partyType")})`,
      ],
      ["partyId", `coalesce(invite_guest.party_id, ${guest("x", "partyId")})`],
    ]),
    `${g("status")} = ${status("'invited'")}`,
    `${g("user")} = null`,
    `${g("tokenHash")} = ${sha256Hex("convert_to(v_token, 'utf8')")}`,
    ...assign([
      ["invitedBy", "auth.uid()"],
      ["expiresAt", "invite_guest.expires_at"],
      ["revokedAt", "null"],
      ["updatedAt", "now()"],
    ]),
  ];

  const invited = (
    [
      ["tenant", "invite_guest.tenant"],
      ["email", "v_email"],
      ["name", "invite_guest.name"],
      ["partyType", "invite_guest.party_type"],
      ["partyId", "invite_guest.party_id"],
      ["tokenHash", sha256Hex("convert_to(v_token, 'utf8')")],
      ["invitedBy", "auth.uid()"],
      ["expiresAt", "invite_guest.expires_at"],
    ] as const
  ).filter(([column]) => hasGuest(column));

  const accepted = [
    `${g("user")} = auth.uid()`,
    `${g("status")} = ${status("'active'")}`,
    `${g("tokenHash")} = null`,
    ...assign([
      ["acceptedAt", "now()"],
      ["updatedAt", "now()"],
    ]),
  ];

  const revoked = [
    `${g("status")} = ${status("'revoked'")}`,
    `${g("tokenHash")} = null`,
    ...assign([
      ["revokedAt", "now()"],
      ["updatedAt", "now()"],
    ]),
  ];

  const granted = (
    [
      ["tenant", `v_guest.${g("tenant")}`],
      ["guest", `v_guest.${g("id")}`],
      ["subjectType", "grant_guest_access.subject_type"],
      ["subjectId", "grant_guest_access.subject_id"],
      ["actions", "v_actions"],
      ["grantedBy", "auth.uid()"],
      ["expiresAt", "grant_guest_access.expires_at"],
    ] as const
  ).filter(([column]) => hasGrant(column));

  const regranted = [
    `${r("actions")} = excluded.${r("actions")}`,
    ...(["grantedBy", "expiresAt"] as const)
      .filter((column) => hasGrant(column))
      .map((column) => `${r(column)} = excluded.${r(column)}`),
    ...(hasGrant("updatedAt") ? [`${r("updatedAt")} = now()`] : []),
  ];

  // Rejects an argument the app's table has no column to keep.
  const unsupported = (
    argument: string,
    supported: boolean,
    code: string,
    message: string,
  ): string =>
    supported
      ? ""
      : `
  if ${argument} is not null then
    ${fail(code, message, "0A000")}
  end if;`;

  const token = "encode(extensions.gen_random_bytes(32), 'hex')";

  const hash = (value: string): string =>
    sha256Hex(`convert_to(${value}, 'utf8')`);

  return `${guestFunctions([own, providerGuestSource(layout)])}
-- Whether the caller reaches subject_type/subject_id as a guest for action.
create or replace function ${fn("guest_can")}(subject_type text, subject_id text, action text default 'read')
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from better_supabase.portal_subjects(guest_can.action) s
    where s.subject_type = guest_can.subject_type and s.subject_id = guest_can.subject_id
  )
$$;
${userGrant(`${fn("guest_can")}(text, text, text)`)}

-- Invites email as a guest of tenant, acting for party_type/party_id (a
-- customer company or person) when set. Returns the guest with a one-time
-- token for the invite link. Inviting an email again issues a new token,
-- unless the guest has already accepted.
create or replace function ${fn("invite_guest")}(tenant ${idType}, email text, name text default null, party_type text default null, party_id text default null, expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${guests}%rowtype;
  v_token text;
  v_email text := lower(btrim(invite_guest.email));
begin
  if not ${allowed("invite_guest.tenant", manage)} then
    ${forbidden("not allowed to manage guests")}
  end if;
  if (invite_guest.party_type is null) <> (invite_guest.party_id is null) then
    ${fail("GUEST_PARTY_INVALID", "pass party_type and party_id together", "22023")}
  end if;${unsupported("invite_guest.party_type", party, "GUEST_PARTY_UNSUPPORTED", "this guests table keeps no party")}${unsupported("invite_guest.expires_at", hasGuest("expiresAt"), "GUEST_EXPIRY_UNSUPPORTED", "this guests table keeps no expiry")}
  if invite_guest.party_type is not null
    and ${subjectTenant(ctx, "invite_guest.party_type", "invite_guest.party_id")} is distinct from invite_guest.tenant::text then
    ${fail("GUEST_PARTY_NOT_FOUND", "the party does not exist in this organization", "P0002")}
  end if;
  if invite_guest.expires_at is not null and invite_guest.expires_at <= now() then
    ${fail("GUEST_EXPIRES_IN_PAST", "expires_at must be in the future", "22023")}
  end if;
  select * into v_row from ${guests} x
    where x.${g("tenant")} = invite_guest.tenant and lower(x.${g("email")}) = v_email
    for update;
  if found and ${asText(ctx, "guests", `v_row.${g("status")}`)} = 'active' then${
    refreshed.length === 0
      ? ""
      : `
    update ${guests} x set
      ${refreshed.join(",\n      ")}
      where x.${g("id")} = v_row.${g("id")}
      returning * into v_row;`
  }
    return ${guestJson("v_row")} || jsonb_build_object('token', null);
  end if;
  v_token := ${token};
  if found then
    update ${guests} x set
      ${reinvited.join(",\n      ")}
      where x.${g("id")} = v_row.${g("id")}
      returning * into v_row;
  else
    insert into ${guests} (${invited.map(([column]) => g(column)).join(", ")})
    values (${invited.map(([, value]) => value).join(", ")})
    returning * into v_row;
  end if;
  ${guestRecord("guest.invited", "v_row", "invited guest")}
  return ${guestJson("v_row")} || jsonb_build_object('token', v_token);
end;
$$;
${userGrant(`${fn("invite_guest")}(${idType}, text, text, text, text, timestamptz)`)}

-- The signed-in invitee accepts with the token. Their confirmed email must
-- match the invite, so a forwarded link doesn't let someone else in.
create or replace function ${fn("accept_guest_invite")}(token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${guests}%rowtype;
  v_email text;
begin
  if auth.uid() is null then
    ${fail("GUEST_SIGN_IN_REQUIRED", "sign in to accept the invite", "42501")}
  end if;
  select * into v_row from ${guests} x
    where x.${g("tokenHash")} = ${hash("accept_guest_invite.token")}
      and ${asText(ctx, "guests", `x.${g("status")}`)} = 'invited'${
        hasGuest("expiresAt")
          ? `
      and (x.${g("expiresAt")} is null or x.${g("expiresAt")} > now())`
          : ""
      }
    for update;
  if not found then
    ${fail("GUEST_INVITE_INVALID", "this invite is not valid or has expired", "P0002")}
  end if;
  select lower(u.email) into v_email from auth.users u
    where u.id = auth.uid() and u.email_confirmed_at is not null;
  if v_email is distinct from lower(v_row.${g("email")}) then
    ${fail("GUEST_EMAIL_MISMATCH", "this invite was sent to another email", "42501")}
  end if;
  if exists (
    select 1 from ${guests} x
    where x.${g("tenant")} = v_row.${g("tenant")} and x.${g("user")} = auth.uid() and x.${g("id")} <> v_row.${g("id")}
  ) then
    ${fail("GUEST_ALREADY_GUEST", "you are already a guest of this organization", "23505")}
  end if;
  update ${guests} x set
    ${accepted.join(",\n    ")}
    where x.${g("id")} = v_row.${g("id")}
    returning * into v_row;
  ${guestRecord("guest.accepted", "v_row", "guest accepted")}
  return ${guestJson("v_row")};
end;
$$;
${userGrant(`${fn("accept_guest_invite")}(text)`)}

-- Revokes a guest: their grants stop counting and the invite token is
-- dropped. Inviting the email again restores them.
create or replace function ${fn("revoke_guest")}(guest_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${guests}%rowtype;
begin
  select * into v_row from ${guests} x where x.${g("id")} = revoke_guest.guest_id for update;
  if not found or not ${allowed(`v_row.${g("tenant")}`, manage)} then
    ${fail("GUEST_NOT_FOUND", "guest not found", "P0002")}
  end if;
  if ${asText(ctx, "guests", `v_row.${g("status")}`)} <> 'revoked' then
    update ${guests} x set
      ${revoked.join(",\n      ")}
      where x.${g("id")} = v_row.${g("id")}
      returning * into v_row;
    ${guestRecord("guest.revoked", "v_row", "revoked guest")}
  end if;
  return ${guestJson("v_row")};
end;
$$;
${userGrant(`${fn("revoke_guest")}(uuid)`)}

-- Lets a guest reach one record: read always, and comment or upload when
-- actions names them. Granting the same record again replaces the actions
-- and the expiry.
create or replace function ${fn("grant_guest_access")}(guest_id uuid, subject_type text, subject_id text, actions text[] default array['read'], expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_guest ${guests}%rowtype;
  v_row ${grants}%rowtype;
  v_actions text[];
begin
  select * into v_guest from ${guests} x where x.${g("id")} = grant_guest_access.guest_id;
  if not found or not ${allowed(`v_guest.${g("tenant")}`, manage)} then
    ${fail("GUEST_NOT_FOUND", "guest not found", "P0002")}
  end if;
  if ${asText(ctx, "guests", `v_guest.${g("status")}`)} = 'revoked' then
    ${fail("GUEST_REVOKED", "invite the guest again before granting access", "55000")}
  end if;
  if not (coalesce(grant_guest_access.actions, '{}') <@ ${ACTIONS}) then
    ${fail("GUEST_ACTION_INVALID", "actions are read, comment and upload", "22023")}
  end if;${unsupported("grant_guest_access.expires_at", hasGrant("expiresAt"), "GUEST_EXPIRY_UNSUPPORTED", "this guest grants table keeps no expiry")}
  select array_agg(a order by array_position(${ACTIONS}, a)) into v_actions
    from (select distinct a from unnest(array_append(coalesce(grant_guest_access.actions, '{}'), 'read')) a) z;
  if grant_guest_access.expires_at is not null and grant_guest_access.expires_at <= now() then
    ${fail("GUEST_EXPIRES_IN_PAST", "expires_at must be in the future", "22023")}
  end if;
  if ${grantSubjectTenant(ctx, "grant_guest_access.subject_type", "grant_guest_access.subject_id")} is distinct from v_guest.${g("tenant")}::text then
    ${fail("GUEST_SUBJECT_NOT_FOUND", "the record does not exist in this organization", "P0002")}
  end if;
  insert into ${grants} as y (${granted.map(([column]) => r(column)).join(", ")})
  values (${granted.map(([, value]) => value).join(", ")})
  on conflict (${r("guest")}, ${r("subjectType")}, ${r("subjectId")}) do update set
    ${regranted.join(",\n    ")}
  returning * into v_row;
  ${grantRecord("guest_grant.created", "v_row", "granted guest access to")}
  return ${grantJson("v_row")};
end;
$$;
${userGrant(`${fn("grant_guest_access")}(uuid, text, text, text[], timestamptz)`)}

create or replace function ${fn("revoke_guest_access")}(grant_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${grants}%rowtype;
begin
  select * into v_row from ${grants} y where y.${r("id")} = revoke_guest_access.grant_id for update;
  if not found or not ${allowed(`v_row.${r("tenant")}`, manage)} then
    return false;
  end if;
  delete from ${grants} y where y.${r("id")} = v_row.${r("id")};
  ${grantRecord("guest_grant.revoked", "v_row", "revoked guest access to")}
  return true;
end;
$$;
${userGrant(`${fn("revoke_guest_access")}(uuid)`)}

-- A tenant's guests, newest first. status filters; before pages back from a
-- guest's created_at.
create or replace function ${fn("list_guests")}(tenant ${idType}, status text default null, before timestamptz default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not ${allowed("list_guests.tenant", read)} then
    ${forbidden("not allowed to read guests")}
  end if;
  return (
    select coalesce(jsonb_agg(z.item order by z.created desc, z.id desc), '[]'::jsonb)
    from (
      select ${guestJson("x")} as item, x.${g("createdAt")} as created, x.${g("id")} as id
      from ${guests} x
      where x.${g("tenant")} = list_guests.tenant
        and (list_guests.status is null or ${asText(ctx, "guests", `x.${g("status")}`)} = list_guests.status)
        and (list_guests.before is null or x.${g("createdAt")} < list_guests.before)
      order by x.${g("createdAt")} desc, x.${g("id")} desc
      limit ${pageSize("list_guests.page_size", 50, 500)}
    ) z
  );
end;
$$;
${userGrant(`${fn("list_guests")}(${idType}, text, timestamptz, integer)`)}

-- The guests who reach one record, with their grant, for the record's
-- sharing panel.
create or replace function ${fn("list_guest_grants")}(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant text := ${grantSubjectTenant(ctx, "list_guest_grants.subject_type", "list_guest_grants.subject_id")};
begin
  if v_tenant is null or not ${allowed(`v_tenant::${idType}`, read)} then
    return '[]'::jsonb;
  end if;
  return (
    select coalesce(jsonb_agg(${grantJson("y")} || jsonb_build_object('guest', ${guestJson("x")}) order by y.${r("createdAt")}, y.${r("id")}), '[]'::jsonb)
    from ${grants} y
    join ${guests} x on x.${g("id")} = y.${r("guest")}
    where y.${r("tenant")}::text = v_tenant
      and y.${r("subjectType")} = list_guest_grants.subject_type
      and y.${r("subjectId")} = list_guest_grants.subject_id
  );
end;
$$;
${userGrant(`${fn("list_guest_grants")}(text, text)`)}

-- What the caller reaches as a guest, per organization, for a portal's home
-- page: the party they act for and their live grants.
create or replace function ${fn("my_guest_access")}()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(${guestJson("x")} || jsonb_build_object('grants', (
    select coalesce(jsonb_agg(${grantJson("y")} order by y.${r("createdAt")}, y.${r("id")}), '[]'::jsonb)
    from ${grants} y
    where y.${r("guest")} = x.${g("id")}${unexpiredGrant("y")}
  )) order by x.${g("createdAt")}), '[]'::jsonb)
  from ${guests} x
  where ${live("x")}
$$;
${userGrant(`${fn("my_guest_access")}()`)}
`;
}

function build(ctx: BlockSqlContext, layout: BlockSqlLayout): string {
  if (ctx.mode === "custom") {
    return "";
  }

  return `${schemaPreamble(ctx)}
-- Guests: people outside the organization (a client, a contractor) who reach
-- the records they are granted, and portal access for the party they act for.
-- A guest is never a member; policies add them through ctx.scope.guest.
${tables(ctx)}${functions(ctx, layout)}${grantMerges(ctx)}`;
}

/** Moves the grants on a merged registered subject to the record it merged into. */
function grantMerges(ctx: BlockSqlContext): string {
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
        table: ctx.table("grants"),
        type: ctx.col("grants", "subjectType"),
        id: ctx.col("grants", "subjectId"),
        unique: [ctx.col("grants", "guest")],
      },
      "v_type",
    ),
  );
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "invite_guest",
      args: ["{id}", "text", "text", "text", "text", "timestamptz"],
      returns: "jsonb",
    },
    { name: "accept_guest_invite", args: ["text"], returns: "jsonb" },
    { name: "revoke_guest", args: ["uuid"], returns: "jsonb" },
    {
      name: "grant_guest_access",
      args: ["uuid", "text", "text", "text[]", "timestamptz"],
      returns: "jsonb",
    },
    { name: "revoke_guest_access", args: ["uuid"], returns: "boolean" },
    {
      name: "list_guests",
      args: ["{id}", "text", "timestamptz", "integer"],
      returns: "jsonb",
    },
    { name: "list_guest_grants", args: ["text", "text"], returns: "jsonb" },
    { name: "my_guest_access", args: [], returns: "jsonb" },
    { name: "guest_can", args: ["text", "text", "text"], returns: "boolean" },
  ];
}

export const GUESTS: BlockSqlDefinition = {
  name: "guests",
  scopes: ["tenant"],
  title: "Guests",
  description:
    "People outside the organization (clients, contractors) invited by email who read, comment on and upload to the records they are granted, and see the invoices and bookings of the party they act for. Never members, never through an authorization library.",
  requires: ["memberships", "permissions"],
  integrates: ["outbox", "audit", "invoices", "bookings", "contacts"],
  before: "comments",
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
