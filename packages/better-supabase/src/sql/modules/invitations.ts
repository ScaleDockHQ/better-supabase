import type { ModuleContext, ModuleNames } from "../context.ts";
import type { ModuleDefinition, ModuleLayout } from "../registry.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  organizationMissing,
  renameSql,
  schemaPreamble,
  SERVICE_CALLER,
  updatedAt,
} from "../shared.ts";
import {
  accessModel,
  hasPlatformRoles,
  MODULE_PERMISSIONS,
  permdockPlatformRoles,
  roleNames,
  roleScopeIs,
  tenantScope,
} from "./access-model.ts";
import { permdockForUser } from "./access.ts";
import { assignableRole, roleValue, TRUSTED_SETTING } from "./organizations.ts";
import { roleThrough } from "./tenant.ts";

const PLATFORM_COLUMNS = {
  id: "id",
  email: "email",
  role: "role",
  tokenHash: "token_hash",
  invitedBy: "invited_by",
  createdAt: "created_at",
  updatedAt: "updated_at",
  expiresAt: "expires_at",
  acceptedAt: "accepted_at",
  acceptedBy: "accepted_by",
  declinedAt: "declined_at",
  revokedAt: "revoked_at",
} as const;

const NAMES: ModuleNames = {
  options: [
    "maxValidFor",
    "platformRoles",
    "prefill",
    "previewColumns",
    "requireConfirmedEmail",
    "tokenBytes",
    "tokenStorage",
    "validFor",
  ],
  tables: {
    invitations: {
      name: "invitations",
      columns: {
        ...PLATFORM_COLUMNS,
        tenant: "organization_id",
        prefill: "prefill",
      },
      optional: [
        "invitedBy",
        "createdAt",
        "updatedAt",
        "acceptedBy",
        "declinedAt",
        "revokedAt",
        "prefill",
      ],
    },
    platformInvitations: {
      name: "platform_invitations",
      columns: PLATFORM_COLUMNS,
      optional: [
        "invitedBy",
        "createdAt",
        "updatedAt",
        "acceptedBy",
        "declinedAt",
        "revokedAt",
      ],
      optionalTable: true,
    },
  },
  hooks: [
    "before_invitation_create",
    "after_invitation_accept",
    "invitation_preview_extra",
  ],
};

/** Every error the module raises: its hint code and default SQLSTATE. */
const INVITATION_ERRORS = {
  INVITATION_FORBIDDEN: "42501",
  INVITATION_ROLE_FORBIDDEN: "42501",
  INVITATION_ROLE_UNKNOWN: "23514",
  INVITATION_ALREADY_MEMBER: "23505",
  INVITATION_INVALID: "P0002",
  INVITATION_VALIDITY: "22023",
  INVITATION_SIGN_IN: "42501",
  INVITATION_EMAIL_MISMATCH: "42501",
  INVITATION_EMAIL_UNCONFIRMED: "42501",
  INVITATION_SELF: "42501",
  INVITATION_INVITER_REVOKED: "42501",
  INVITATION_SCOPE_UNSUPPORTED: "0A000",
} as const;

type InvitationError = keyof typeof INVITATION_ERRORS;

/** `raise exception` for `code`, with its SQLSTATE from `INVITATION_ERRORS`. */
function raise(
  code: InvitationError,
  message: string,
  ...args: string[]
): string {
  return `raise exception ${sqlString(message)}${args.map((arg) => `, ${arg}`).join("")} using errcode = '${INVITATION_ERRORS[code]}', hint = '${code}';`;
}

/**
 * How tokens are stored (`sql.modules.invitations.options.tokenStorage`): `sha256`
 * (the default) keeps only the hash; `plain` keeps the token itself, for an
 * adopted table whose open invitations hold plain tokens.
 */
function tokenHash(ctx: ModuleContext, token: string): string {
  const storage = ctx.text("tokenStorage", "sha256");
  if (storage === "plain") return token;
  if (storage !== "sha256") {
    throw new TypeError(
      `sql.modules.invitations.options.tokenStorage must be "sha256" or "plain", got "${storage}"`,
    );
  }
  return `encode(extensions.digest(${token}, 'sha256'), 'hex')`;
}

/** A table of invitations: the tenant one, or the platform one. */
interface InviteTable {
  readonly table: string;
  col(logical: string): string;
  has(logical: string): boolean;
  /** ` and <alias>.<tenant> is [not] null` when both kinds share a table. */
  only(alias: string): string;
}

/** Whether platform invitations live in the tenant table, as rows without a tenant. */
function sharesTable(ctx: ModuleContext): boolean {
  return (
    !ctx.manages &&
    ctx.config.tables["platformInvitations"] != null &&
    ctx.table("platformInvitations") === ctx.table("invitations")
  );
}

function tenantTable(ctx: ModuleContext): InviteTable {
  const shared = sharesTable(ctx);
  // Managed tables add prefill only on request (`sql.modules.invitations.options.prefill`).
  const prefill =
    ctx.has("invitations", "prefill") &&
    (!ctx.manages || ctx.flag("prefill", false));
  return {
    table: ctx.table("invitations"),
    col: (logical) => ctx.col("invitations", logical),
    has: (logical) =>
      logical === "prefill" ? prefill : ctx.has("invitations", logical),
    only: (alias) =>
      shared
        ? ` and ${alias}.${ctx.col("invitations", "tenant")} is not null`
        : "",
  };
}

/**
 * Platform invitations, with the catalog model's platform roles. Managed:
 * their own table. Adopted: `sql.modules.invitations.tables.platformInvitations`,
 * which may name the tenant table.
 */
function platformTable(ctx: ModuleContext): InviteTable | undefined {
  if (!hasPlatformRoles(ctx) || !ctx.hasTable("platformInvitations")) {
    return undefined;
  }
  if (!ctx.manages && ctx.config.tables["platformInvitations"] === undefined) {
    return undefined;
  }
  const logical = sharesTable(ctx) ? "invitations" : "platformInvitations";
  return {
    table: ctx.table(logical),
    col: (column) => ctx.col(logical, column),
    has: (column) => column in PLATFORM_COLUMNS && ctx.has(logical, column),
    only: (alias) =>
      logical === "invitations"
        ? ` and ${alias}.${ctx.col("invitations", "tenant")} is null`
        : "",
  };
}

/** A column of the invitation row `alias`, or `fallback` when the table lacks it. */
function optionalCol(
  t: InviteTable,
  alias: string,
  logical: string,
  fallback: string,
): string {
  return t.has(logical) ? `${alias}.${t.col(logical)}` : fallback;
}

/** `pending`, `accepted`, `declined`, `revoked` or `expired` for row `alias`. */
function statusOf(t: InviteTable, alias: string): string {
  const c = (logical: string) => `${alias}.${t.col(logical)}`;
  const declined = t.has("declinedAt")
    ? `\n    when ${c("declinedAt")} is not null then 'declined'`
    : "";
  const revoked = t.has("revokedAt")
    ? `\n    when ${c("revokedAt")} is not null then 'revoked'`
    : "";
  return `case
    when ${c("acceptedAt")} is not null then 'accepted'${declined}${revoked}
    when ${c("expiresAt")} < now() then 'expired'
    else 'pending'
  end`;
}

/** Open invitations: not accepted, declined or revoked (expired ones count). */
function openFilter(t: InviteTable, alias: string): string {
  return ["acceptedAt", "declinedAt", "revokedAt"]
    .filter((logical) => t.has(logical))
    .map((logical) => `${alias}.${t.col(logical)} is null`)
    .join(" and ");
}

/** The catalog role id for a key or id, in `scope`; `expr` itself in other models. */
function roleIn(
  ctx: ModuleContext,
  expr: string,
  scope: "tenant" | "platform",
): string {
  if (accessModel(ctx) !== "catalog") return roleValue(ctx, expr);
  const scoped = roleScopeIs(ctx, "r", scope);
  if (!scoped) return roleValue(ctx, expr);
  const access = ctx.of("access");
  const rid = access.col("roles", "id");
  const key = access.col("roles", "key");
  const text = `(${expr})::text`;
  return `(select r.${rid} from ${access.table("roles")} r where (r.${rid}::text = ${text} or r.${key} = ${text}) and ${scoped} order by (r.${rid}::text = ${text}) desc limit 1)`;
}

/** Where an accepted platform invitation assigns its role, and the checks around it. */
interface PlatformAssignment {
  /** The stored role for a role name or id; null when it is unknown. */
  value(expr: string): string;
  /** The assignment table's role value for an invitation's stored role. */
  assign(stored: string): string;
  /** Whether `member` may assign the stored role `stored`; `undefined` for no ceiling. */
  canAssign(member: string, stored: string): string | undefined;
  readonly table: string;
  readonly user: string;
  readonly role: string;
  /** Whether the inviter's authority can be checked again at accept. */
  readonly recheck: boolean;
}

function platformAssignment(ctx: ModuleContext): PlatformAssignment {
  const permdock = permdockPlatformRoles(ctx);
  if (permdock) {
    const through = permdock.through;
    const name = (stored: string) =>
      through
        ? `(select r.${through.column}::text from ${through.table} r where r.${through.id}::text = (${stored})::text)`
        : `(${stored})::text`;
    return {
      value: (expr) =>
        through
          ? `(select r.${through.id} from ${through.table} r where r.${through.id}::text = (${expr})::text or r.${through.column}::text = (${expr})::text order by (r.${through.id}::text = (${expr})::text) desc limit 1)`
          : expr,
      assign(stored) {
        return this.value(stored);
      },
      canAssign: (member, stored) =>
        permdock.canAssign === undefined
          ? undefined
          : `coalesce((${permdock.canAssign.replaceAll("{user}", member).replaceAll("{role}", name(stored))}), false)`,
      table: permdock.table,
      user: permdock.user,
      role: permdock.role,
      recheck: false,
    };
  }
  const access = ctx.of("access");
  return {
    value: (expr) => roleIn(ctx, expr, "platform"),
    assign: (stored) => roleValue(ctx, stored),
    canAssign: (member, stored) =>
      `better_supabase.platform_can_assign(${member}, ${stored}::text)`,
    table: access.table("platformAssignments"),
    user: access.col("platformAssignments", "user"),
    role: access.col("platformAssignments", "role"),
    recheck: true,
  };
}

function tenantTableSql(ctx: ModuleContext): string {
  const t = tenantTable(ctx);
  const c = (logical: string) => t.col(logical);
  if (!ctx.manages) {
    return `
-- Adopted: ${t.table} belongs to the app (modules.invitations.tables.invitations).
`;
  }
  const add = (logical: string, type: string) =>
    t.has(logical)
      ? `alter table ${t.table} add column if not exists ${c(logical)} ${type};\n`
      : "";
  const roleCheck =
    accessModel(ctx) === "roles" && !roleThrough(ctx.of("tenant"))
      ? `alter table ${t.table}
  add constraint invitations_role_check check (${c("role")} in (${roleNames(ctx).map(sqlString).join(", ")}));
`
      : "";
  const where = openFilter(t, t.table).replaceAll(`${t.table}.`, "");
  return `
create table if not exists ${t.table} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("email")} text not null,
  ${c("role")} text not null,
  ${c("tokenHash")} text not null unique,
  ${c("expiresAt")} timestamptz not null,
  ${c("acceptedAt")} timestamptz
);
alter table ${t.table} alter column ${c("tenant")} set not null;
alter table ${t.table} alter column ${c("role")} drop default;
${add("invitedBy", "uuid references auth.users (id) on delete set null")}${add("createdAt", "timestamptz not null default now()")}${add("acceptedBy", "uuid references auth.users (id) on delete set null")}${add("declinedAt", "timestamptz")}${add("revokedAt", "timestamptz")}${add("prefill", "jsonb not null default '{}'")}
drop index if exists ${sqlIdent(ctx.tableName("invitations").schema)}.invitations_open_idx;
create unique index if not exists invitations_open_email_idx
  on ${t.table} (${c("tenant")}, lower(${c("email")})) where ${where};
${t.has("createdAt") ? `create index if not exists invitations_tenant_created_idx on ${t.table} (${c("tenant")}, ${c("createdAt")});\n` : `create index if not exists invitations_tenant_idx on ${t.table} (${c("tenant")});\n`}${t.has("updatedAt") ? `${updatedAt(t.table, c("updatedAt"))}\n` : ""}${t.has("invitedBy") ? `create index if not exists invitations_invited_by_idx on ${t.table} (${c("invitedBy")});\n` : ""}${t.has("acceptedBy") ? `create index if not exists invitations_accepted_by_idx on ${t.table} (${c("acceptedBy")});\n` : ""}
alter table ${t.table} drop constraint if exists invitations_role_check;
${roleCheck}
alter table ${t.table} enable row level security;
revoke all on ${t.table} from anon, authenticated;
grant select on ${t.table} to authenticated;
grant all on ${t.table} to service_role;

-- PL/pgSQL resolves tenant_ids_with when it runs, so this file installs
-- before the access module's.
create or replace function ${ctx.fn("invitation_tenant_ids")}()
returns setof ${ctx.idType}
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query select better_supabase.tenant_ids_with(${ctx.permission("view", MODULE_PERMISSIONS.invitations.view)});
end;
$$;
revoke execute on function ${ctx.fn("invitation_tenant_ids")}() from public, anon;
grant execute on function ${ctx.fn("invitation_tenant_ids")}() to authenticated, service_role;
drop policy if exists bs_invitations_read on ${t.table};
create policy bs_invitations_read on ${t.table} for select to authenticated
  using (${c("tenant")} in (select ${ctx.fn("invitation_tenant_ids")}()));
`;
}

function platformTableSql(ctx: ModuleContext): string {
  const p = platformTable(ctx);
  if (!p || !ctx.manages) return "";
  const c = (logical: string) => p.col(logical);
  const add = (logical: string, type: string) =>
    p.has(logical)
      ? `alter table ${p.table} add column if not exists ${c(logical)} ${type};\n`
      : "";
  const where = openFilter(p, p.table).replaceAll(`${p.table}.`, "");
  return `
-- Invitations to a platform role (the catalog model's platform assignments).
create table if not exists ${p.table} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("email")} text not null,
  ${c("role")} text not null,
  ${c("tokenHash")} text not null unique,
  ${c("expiresAt")} timestamptz not null,
  ${c("acceptedAt")} timestamptz
);
${add("invitedBy", "uuid references auth.users (id) on delete set null")}${add("createdAt", "timestamptz not null default now()")}${add("acceptedBy", "uuid references auth.users (id) on delete set null")}${add("declinedAt", "timestamptz")}${add("revokedAt", "timestamptz")}
create unique index if not exists platform_invitations_open_email_idx
  on ${p.table} (lower(${c("email")})) where ${where};
${p.has("updatedAt") ? `${updatedAt(p.table, c("updatedAt"))}\n` : ""}${p.has("invitedBy") ? `create index if not exists platform_invitations_invited_by_idx on ${p.table} (${c("invitedBy")});\n` : ""}${p.has("acceptedBy") ? `create index if not exists platform_invitations_accepted_by_idx on ${p.table} (${c("acceptedBy")});\n` : ""}
alter table ${p.table} enable row level security;
revoke all on ${p.table} from anon, authenticated;
grant select on ${p.table} to authenticated;
grant all on ${p.table} to service_role;
create or replace function ${ctx.fn("platform_invitations_readable")}()
returns boolean
language plpgsql
stable
set search_path = ''
as $$
begin
  return better_supabase.is_platform(${invitePlatform(ctx)});
end;
$$;
revoke execute on function ${ctx.fn("platform_invitations_readable")}() from public, anon;
grant execute on function ${ctx.fn("platform_invitations_readable")}() to authenticated, service_role;
drop policy if exists bs_platform_invitations_read on ${p.table};
create policy bs_platform_invitations_read on ${p.table} for select to authenticated
  using ((select ${ctx.fn("platform_invitations_readable")}()));
`;
}

const invitePlatform = (ctx: ModuleContext): string =>
  ctx.permission(
    "invitePlatform",
    MODULE_PERMISSIONS.invitations.invitePlatform,
  );

/** The invitation as returned to the inviter; the token only right after creating it. */
function inviteJson(
  t: InviteTable,
  row: string,
  token: string,
  tenant: string,
): string {
  const c = (logical: string) => `${row}.${t.col(logical)}`;
  return `jsonb_build_object(
    'id', ${c("id")},
    'tenant', ${tenant},
    'email', ${c("email")},
    'role', ${c("role")},
    'expires_at', ${c("expiresAt")},
    'invited_by', ${optionalCol(t, row, "invitedBy", "null")},
    'prefill', ${optionalCol(t, row, "prefill", "'{}'::jsonb")},
    'token', ${token}
  )`;
}

/** Raises unless `valid_for` is positive and at most `sql.modules.invitations.options.maxValidFor`. */
function validity(ctx: ModuleContext): string {
  const max = sqlString(ctx.text("maxValidFor", "30 days"));
  return `if valid_for is null or valid_for <= interval '0' or valid_for > ${max}::interval then
    ${raise("INVITATION_VALIDITY", "An invitation is valid for at most %", max)}
  end if;`;
}

function platformInvite(
  ctx: ModuleContext,
  p: InviteTable | undefined,
): string {
  const fail = raise;
  if (!p) {
    return fail(
      "INVITATION_SCOPE_UNSUPPORTED",
      "Platform invitations need platform roles: sql.modules.access.model 'catalog' with platform assignments, or sql.modules.invitations.options.platformRoles under 'permdock'",
    );
  }
  const c = (logical: string) => p.col(logical);
  const assignment = platformAssignment(ctx);
  const role = assignment.value("invitee_role");
  const ceiling = assignment.canAssign("auth.uid()", `(${role})`);
  const columns: (readonly [string, string])[] = [
    ["email", "lower(btrim(invitee_email))"],
    ["role", `(${role})::text`],
    ["tokenHash", tokenHash(ctx, "token")],
    ["invitedBy", "auth.uid()"],
    ["expiresAt", "now() + valid_for"],
  ];
  const present = columns.filter(([logical]) => p.has(logical));
  const open = openFilter(p, "i");
  return `if not service and not better_supabase.is_platform(${invitePlatform(ctx)}) then
      ${fail("INVITATION_FORBIDDEN", "Not allowed to invite platform users")}
    end if;
    if ${role} is null then
      ${fail("INVITATION_ROLE_UNKNOWN", "Unknown platform role %", "invitee_role")}
    end if;
    ${
      ceiling
        ? `if not service and not ${ceiling} then
      ${fail("INVITATION_ROLE_FORBIDDEN", "That role is above your own")}
    end if;`
        : "-- No platform role ceiling: holding the invite permission is enough."
    }
    ${ctx.hook("before_invitation_create", [
      [ctx.idType, "tenant"],
      ["text", "invitee_email"],
      ["text", "invitee_role"],
    ])}
    delete from ${p.table} i
    where lower(i.${c("email")}) = lower(btrim(invitee_email))${open ? ` and ${open}` : ""}${p.only("i")};
    insert into ${p.table} (${present.map(([logical]) => c(logical)).join(", ")})
    values (${present.map(([, value]) => value).join(", ")})
    returning * into platform_created;
    ${ctx.emit({ type: "invitation.created", payload: `jsonb_build_object('invitationId', platform_created.${c("id")}, 'organizationId', null, 'email', platform_created.${c("email")}, 'role', platform_created.${c("role")})`, subject: `'invitations/' || platform_created.${c("id")}::text` })}
    return ${inviteJson(p, "platform_created", "token", "null")};`;
}

function invite(ctx: ModuleContext): string {
  const t = tenantTable(ctx);
  const p = platformTable(ctx);
  const c = (logical: string) => t.col(logical);
  const id = ctx.idType;
  const fail = raise;
  const tenantMembers = ctx.of("tenant");
  const m = tenantMembers.table("memberships");
  const mt = tenantMembers.col("memberships", "tenant");
  const mu = tenantMembers.col("memberships", "user");
  const bytes = ctx.number("tokenBytes", 24);
  const validFor = sqlString(ctx.text("validFor", "7 days"));
  const model = accessModel(ctx);
  const stored = roleIn(ctx, "invitee_role", "tenant");
  const through = roleThrough(ctx.of("tenant")) !== undefined;
  const unknownRole =
    model === "catalog" || through
      ? `${stored} is null`
      : model === "roles"
        ? `not (invitee_role = any (array[${roleNames(ctx).map(sqlString).join(", ")}]::text[]))`
        : "false";
  const columns: (readonly [string, string])[] = [
    ["tenant", "tenant"],
    ["email", "lower(btrim(invitee_email))"],
    ["role", stored],
    ["tokenHash", tokenHash(ctx, "token")],
    ["invitedBy", "auth.uid()"],
    ["expiresAt", "now() + valid_for"],
    ["prefill", "coalesce(prefill, '{}')"],
  ];
  const present = columns.filter(([logical]) => t.has(logical));
  const open = openFilter(t, "i");
  const pOpen = p ? openFilter(p, "i") : "";
  const pc = (logical: string) => p!.col(logical);
  const platformResend = p
    ? `
    update ${p.table} i
    set ${pc("tokenHash")} = ${tokenHash(ctx, "token")},
      ${pc("expiresAt")} = now() + valid_for
    where i.${pc("id")} = invitation_id${pOpen ? ` and ${pOpen}` : ""}${p.only("i")}
      and (${SERVICE_CALLER} or better_supabase.is_platform(${invitePlatform(ctx)}))
    returning * into platform_updated;
    if platform_updated.${pc("id")} is not null then
      ${ctx.emit({ type: "invitation.resent", payload: `jsonb_build_object('invitationId', platform_updated.${pc("id")}, 'organizationId', null, 'email', platform_updated.${pc("email")})`, subject: `'invitations/' || platform_updated.${pc("id")}::text` })}
      return ${inviteJson(p, "platform_updated", "token", "null")};
    end if;`
    : "";
  return `
-- Invites email to tenant (null: a platform invitation) with role, a catalog
-- role id or key under sql.modules.access.model 'catalog'. Returns the invitation
-- and its token; only the token's hash is stored. An open invitation for
-- the same email is replaced.
create or replace function ${ctx.fn("invite_member")}(
  tenant ${id},
  invitee_email text,
  invitee_role text,
  valid_for interval default ${validFor},
  prefill jsonb default '{}'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  service boolean := ${SERVICE_CALLER};
  token text := encode(extensions.gen_random_bytes(${String(bytes)}), 'hex');
  created ${t.table};${p ? `\n  platform_created ${p.table};` : ""}
begin
  ${validity(ctx)}
  if tenant is null then
    ${platformInvite(ctx, p)}
  end if;
  if not service and not coalesce(better_supabase.member_can(auth.uid(), tenant, ${ctx.permission("invite", MODULE_PERMISSIONS.invitations.invite)}), false) then
    ${fail("INVITATION_FORBIDDEN", "Not allowed to invite members")}
  end if;
  if better_supabase.tenant_disabled(tenant) or ${organizationMissing(ctx, "tenant")} then
    ${fail("INVITATION_INVALID", "The organization is not active")}
  end if;
  if ${unknownRole} then
    ${fail("INVITATION_ROLE_UNKNOWN", "Unknown role %", "invitee_role")}
  end if;
  if not service and not better_supabase.can_assign(tenant, ${assignableRole(ctx, `(${stored})`)}) then
    ${fail("INVITATION_ROLE_FORBIDDEN", "That role is above your own")}
  end if;
  if exists (
    select 1 from ${m} m join auth.users u on u.id = m.${mu}
    where m.${mt} = tenant and lower(u.email) = lower(btrim(invitee_email))
  ) then
    ${fail("INVITATION_ALREADY_MEMBER", "% is already a member", "invitee_email")}
  end if;
  ${ctx.hook("before_invitation_create", [
    [id, "tenant"],
    ["text", "invitee_email"],
    ["text", "invitee_role"],
  ])}
  delete from ${t.table} i
  where i.${c("tenant")} = tenant
    and lower(i.${c("email")}) = lower(btrim(invitee_email))${open ? `\n    and ${open}` : ""};
  insert into ${t.table} (${present.map(([logical]) => c(logical)).join(", ")})
  values (${present.map(([, value]) => value).join(", ")})
  returning * into created;
  ${ctx.emit({ type: "invitation.created", payload: `jsonb_build_object('invitationId', created.${c("id")}, 'organizationId', tenant::text, 'email', created.${c("email")}, 'role', created.${c("role")})`, subject: `'invitations/' || created.${c("id")}::text`, tenant: "tenant" })}
  return ${inviteJson(t, "created", "token", `created.${c("tenant")}`)};
end;
$$;

-- The 0.4 signature: returns the token only.
drop function if exists ${ctx.fn("create_invitation")}(${id}, text, text, interval);
create or replace function ${ctx.fn("create_invitation")}(
  organization ${id},
  invitee_email text,
  invitee_role text default 'member',
  valid_for interval default ${validFor}
)
returns text
language sql
security invoker
set search_path = ''
as $$
  select ${ctx.fn("invite_member")}($1, $2, $3, $4) ->> 'token'
$$;

-- A new token and expiry for an open invitation; the old token stops working.
create or replace function ${ctx.fn("resend_invitation")}(invitation_id uuid, valid_for interval default ${validFor})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  token text := encode(extensions.gen_random_bytes(${String(bytes)}), 'hex');
  updated ${t.table};${p ? `\n  platform_updated ${p.table};` : ""}
begin
  ${validity(ctx)}
  update ${t.table} i
  set ${c("tokenHash")} = ${tokenHash(ctx, "token")},
    ${c("expiresAt")} = now() + valid_for
  where i.${c("id")} = invitation_id${open ? ` and ${open}` : ""}${t.only("i")}
    and (${SERVICE_CALLER} or ${canManage(ctx, "i")})
  returning * into updated;
  if updated.${c("id")} is null then${platformResend}
    ${fail("INVITATION_INVALID", "No open invitation %", "invitation_id")}
  end if;
  ${ctx.emit({ type: "invitation.resent", payload: `jsonb_build_object('invitationId', updated.${c("id")}, 'organizationId', updated.${c("tenant")}::text, 'email', updated.${c("email")})`, subject: `'invitations/' || updated.${c("id")}::text`, tenant: `updated.${c("tenant")}` })}
  return ${inviteJson(t, "updated", "token", `updated.${c("tenant")}`)};
end;
$$;
`;
}

/** Whether the caller may manage tenant invitation row `alias` (revoke and resend). */
function canManage(ctx: ModuleContext, alias: string): string {
  const tenant = `${alias}.${ctx.col("invitations", "tenant")}`;
  return `coalesce(better_supabase.member_can(auth.uid(), ${tenant}, ${ctx.permission("revoke", MODULE_PERMISSIONS.invitations.revoke)}), false)`;
}

function close(ctx: ModuleContext): string {
  const t = tenantTable(ctx);
  const p = platformTable(ctx);
  /** Ends open invitations of `table` matching `where`: sets `logical`, or deletes when the table lacks it. */
  const end = (table: InviteTable, logical: string, where: string) => {
    const open = openFilter(table, "i");
    const filter = `${where}${open ? ` and ${open}` : ""}${table.only("i")}`;
    return table.has(logical)
      ? `update ${table.table} i set ${table.col(logical)} = now() where ${filter}`
      : `delete from ${table.table} i where ${filter}`;
  };
  const hash = (table: InviteTable) =>
    `i.${table.col("tokenHash")} = ${tokenHash(ctx, "token")}`;
  const platformRevoke = p
    ? `
  ${end(p, "revokedAt", `i.${p.col("id")} = invitation_id and (${SERVICE_CALLER} or better_supabase.is_platform(${invitePlatform(ctx)}))`)};
  if found then
    ${ctx.emit({ type: "invitation.revoked", payload: "jsonb_build_object('invitationId', invitation_id, 'organizationId', null)", subject: "'invitations/' || invitation_id::text" })}
    return true;
  end if;`
    : "";
  const platformDecline = p
    ? `
  ${end(p, "declinedAt", `${hash(p)} and i.${p.col("expiresAt")} >= now()`)}
  returning i.${p.col("id")} into declined_id;
  if declined_id is not null then
    ${ctx.emit({ type: "invitation.declined", payload: "jsonb_build_object('invitationId', declined_id, 'organizationId', null)", subject: "'invitations/' || declined_id::text" })}
    return true;
  end if;`
    : "";
  return `
-- Revokes an open invitation (deletes it when revokedAt is mapped to null).
create or replace function ${ctx.fn("revoke_invitation")}(invitation_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  tenant text;
begin
  ${end(t, "revokedAt", `i.${t.col("id")} = invitation_id and (${SERVICE_CALLER} or ${canManage(ctx, "i")})`)}
  returning i.${t.col("tenant")}::text into tenant;
  if found then
    ${ctx.emit({ type: "invitation.revoked", payload: "jsonb_build_object('invitationId', invitation_id, 'organizationId', tenant)", subject: "'invitations/' || invitation_id::text", tenant: "tenant" })}
    return true;
  end if;${platformRevoke}
  return false;
end;
$$;

-- The invitee declines with the token, signed in or not.
create or replace function ${ctx.fn("decline_invitation")}(token text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  declined_id uuid;
  tenant text;
begin
  ${end(t, "declinedAt", `${hash(t)} and i.${t.col("expiresAt")} >= now()`)}
  returning i.${t.col("id")}, i.${t.col("tenant")}::text into declined_id, tenant;
  if declined_id is not null then
    ${ctx.emit({ type: "invitation.declined", payload: "jsonb_build_object('invitationId', declined_id, 'organizationId', tenant)", subject: "'invitations/' || declined_id::text", tenant: "tenant" })}
    return true;
  end if;${platformDecline}
  return false;
end;
$$;
`;
}

/** `invitation_preview(token)`: what the accept page shows before sign-in. */
function preview(ctx: ModuleContext): string {
  const t = tenantTable(ctx);
  const p = platformTable(ctx);
  const c = (logical: string) => `i.${t.col(logical)}`;
  let organization = `jsonb_build_object('id', ${c("tenant")})`;
  if (ctx.installed("organizations")) {
    const organizations = ctx.of("organizations");
    const columns = ctx.list("previewColumns", ["name"]).map((column) => {
      if (!/^[A-Za-z_][A-Za-z0-9_$]*$/.test(column)) {
        throw new TypeError(
          `sql.modules.invitations.options.previewColumns: "${column}" is not a valid column`,
        );
      }
      return `, ${sqlString(column)}, o.${sqlIdent(column)}`;
    });
    organization = `(select jsonb_build_object('id', o.${organizations.col("organizations", "id")}${columns.join("")})
      from ${organizations.table("organizations")} o where o.${organizations.col("organizations", "id")} = ${c("tenant")})`;
  }
  const json = (table: InviteTable, tenant: string, organization: string) =>
    `jsonb_build_object(
    'status', ${statusOf(table, "i")},
    'email', i.${table.col("email")},
    'role', i.${table.col("role")},
    'tenant', ${tenant},
    'expires_at', i.${table.col("expiresAt")},
    'organization', ${organization},
    'prefill', ${optionalCol(table, "i", "prefill", "'{}'::jsonb")}
  )`;
  const platform = p
    ? `
  if preview is null then
    select ${json(p, "null", "null")}, i.${p.col("id")}
    into preview, invitation
    from ${p.table} i
    where i.${p.col("tokenHash")} = ${tokenHash(ctx, "invitation_preview.token")}${p.only("i")};
  end if;`
    : "";
  const extra = sqlString(
    `${ctx.hookTarget("invitation_preview_extra")}(uuid)`,
  );
  return `
-- What an invitation link shows before sign-in: status (pending, accepted,
-- declined, revoked or expired), email, role, organization (id plus
-- sql.modules.invitations.options.previewColumns) and prefill. Null for an unknown token.
-- An invitation_preview_extra(invitation uuid) returns jsonb hook adds its
-- keys, such as a role's display name or branding from another table.
create or replace function ${ctx.fn("invitation_preview")}(token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  preview jsonb;
  invitation uuid;
  extra jsonb;
begin
  select ${json(t, c("tenant"), organization)}, ${c("id")}
  into preview, invitation
  from ${t.table} i
  where ${c("tokenHash")} = ${tokenHash(ctx, "invitation_preview.token")}${t.only("i")};${platform}
  if preview is not null and to_regprocedure(${extra}) is not null then
    -- Not a literal name, so plpgsql_check passes without the hook.
    execute format('select %s($1)', to_regprocedure(${extra})::oid::regproc)
      into extra using invitation;
    preview := preview || coalesce(extra, '{}');
  end if;
  return preview;
end;
$$;
`;
}

function accept(ctx: ModuleContext, layout: ModuleLayout): string {
  const t = tenantTable(ctx);
  const p = platformTable(ctx);
  const c = (logical: string) => t.col(logical);
  const id = ctx.idType;
  const fail = raise;
  const tenantCtx = ctx.of("tenant");
  const m = tenantCtx.table("memberships");
  const mt = tenantCtx.col("memberships", "tenant");
  const mu = tenantCtx.col("memberships", "user");
  const mr = tenantCtx.col("memberships", "role");
  const model = accessModel(ctx);
  const invitePermission = ctx.permission(
    "invite",
    MODULE_PERMISSIONS.invitations.invite,
  );
  const roleOf = (expr: string) => roleValue(ctx, expr);
  /** Checks shared by both kinds of invitation in row `row`. */
  const invitee = (table: InviteTable, row: string) => {
    const col = (logical: string) => `${row}.${table.col(logical)}`;
    const open = openFilter(table, row);
    const confirmed = ctx.flag("requireConfirmedEmail", true)
      ? `
  -- The email claim alone does not prove the address: an unconfirmed sign-up carries it too.
  if not exists (
    select 1 from auth.users u
    where u.id = me and u.email_confirmed_at is not null and lower(u.email) = lower(${col("email")})
  ) then
    ${fail("INVITATION_EMAIL_UNCONFIRMED", "Confirm your email address before accepting the invitation")}
  end if;`
      : "";
    const self = table.has("invitedBy")
      ? `
  if ${col("invitedBy")} = me then
    ${fail("INVITATION_SELF", "You cannot accept your own invitation")}
  end if;`
      : "";
    return `if not (${open || "true"}) or ${col("expiresAt")} < now() then
    ${fail("INVITATION_INVALID", "The invitation is invalid or has expired")}
  end if;
  if lower(${col("email")}) <> lower(coalesce(auth.jwt() ->> 'email', '')) then
    ${fail("INVITATION_EMAIL_MISMATCH", "The invitation is for another email address")}
  end if;${confirmed}${self}`;
  };
  // The inviter's authority is checked again: a role or permission they
  // lost after inviting must not reach the invitee.
  const inviter = t.has("invitedBy") ? `invite.${c("invitedBy")}` : undefined;
  const forUser =
    model === "permdock" ? permdockForUser(ctx, layout) : undefined;
  const assignAs =
    model === "roles" || model === "catalog" || forUser?.canAssign
      ? `
    if ${inviter} is not null
      and not better_supabase.can_assign_as(${inviter}, invite.${c("tenant")}, ${assignableRole(ctx, `invite.${c("role")}`)}) then
      ${fail("INVITATION_INVITER_REVOKED", "The person who invited you can no longer assign that role")}
    end if;`
      : "";
  const recheck =
    inviter && model === "permdock" && !(forUser?.permitted && forUser.has)
      ? `
    -- The permdock model answers for the caller only, so the inviter's
    -- authority was checked when they invited, not here.`
      : inviter
        ? `
    if ${inviter} is not null
      and better_supabase.can_user(${inviter}, ${sqlString(tenantScope(ctx))}, invite.${c("tenant")}, ${invitePermission}) is false then
      ${fail("INVITATION_INVITER_REVOKED", "The person who invited you can no longer invite members")}
    end if;${assignAs}`
        : "";
  let platformAccept = "";
  if (p) {
    const pc = (logical: string) => p.col(logical);
    const assignment = platformAssignment(ctx);
    const inviterCeiling = assignment.canAssign(
      `pinvite.${pc("invitedBy")}`,
      `pinvite.${pc("role")}`,
    );
    const platformInviter =
      p.has("invitedBy") && (assignment.recheck || forUser?.has)
        ? `
  if pinvite.${pc("invitedBy")} is not null and not (
    coalesce(better_supabase.platform_can(pinvite.${pc("invitedBy")}, ${invitePlatform(ctx)}), false)${inviterCeiling ? `\n    and ${inviterCeiling}` : ""}
  ) then
    ${fail("INVITATION_INVITER_REVOKED", "The person who invited you can no longer assign that role")}
  end if;`
        : "";
    platformAccept = `
  select * into pinvite
  from ${p.table} i
  where i.${pc("tokenHash")} = ${tokenHash(ctx, "token")}${p.only("i")}
  for update;
  if pinvite.${pc("id")} is not null then
  ${invitee(p, "pinvite")}${platformInviter}
  insert into ${assignment.table} (${assignment.user}, ${assignment.role})
  values (me, ${assignment.assign(`pinvite.${pc("role")}`)})
  on conflict do nothing;
  update ${p.table}
  set ${pc("acceptedAt")} = now()${p.has("acceptedBy") ? `, ${pc("acceptedBy")} = me` : ""}
  where ${pc("id")} = pinvite.${pc("id")};
  ${ctx.hook("after_invitation_accept", [
    ["uuid", `pinvite.${pc("id")}`],
    ["uuid", "me"],
  ])}
  ${ctx.emit({ type: "invitation.accepted", payload: `jsonb_build_object('invitationId', pinvite.${pc("id")}, 'organizationId', null, 'email', pinvite.${pc("email")}, 'role', pinvite.${pc("role")})`, subject: `'invitations/' || pinvite.${pc("id")}::text` })}
  return null;
  end if;`;
  }
  return `
-- Accepts with the token for the signed-in user, whose confirmed email must
-- match, and returns the tenant (null for a platform invitation).
create or replace function ${ctx.fn("accept_invitation")}(token text)
returns ${id}
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
  invite ${t.table};${p ? `\n  pinvite ${p.table};` : ""}
begin
  if me is null then
    ${fail("INVITATION_SIGN_IN", "Sign in to accept an invitation")}
  end if;
  select * into invite
  from ${t.table} i
  where i.${c("tokenHash")} = ${tokenHash(ctx, "token")}${t.only("i")}
  for update;
  if invite.${c("id")} is null then${platformAccept}
    ${fail("INVITATION_INVALID", "The invitation is invalid or has expired")}
  end if;
  ${invitee(t, "invite")}
  if better_supabase.tenant_disabled(invite.${c("tenant")}) or ${organizationMissing(ctx, `invite.${c("tenant")}`)} then
    ${fail("INVITATION_INVALID", "The invitation is invalid or has expired")}
  end if;
  if exists (select 1 from ${m} m where m.${mt} = invite.${c("tenant")} and m.${mu} = me) then
    ${fail("INVITATION_ALREADY_MEMBER", "You are already a member")}
  end if;${recheck}
  perform set_config('${TRUSTED_SETTING}', 'on', true);
  insert into ${m} (${mt}, ${mu}, ${mr})
  values (invite.${c("tenant")}, me, ${roleOf(`invite.${c("role")}`)});
  perform set_config('${TRUSTED_SETTING}', '', true);
  update ${t.table}
  set ${c("acceptedAt")} = now()${t.has("acceptedBy") ? `, ${c("acceptedBy")} = me` : ""}
  where ${c("id")} = invite.${c("id")};
  ${ctx.hook("after_invitation_accept", [
    ["uuid", `invite.${c("id")}`],
    ["uuid", "me"],
  ])}
  ${ctx.emit({ type: "invitation.accepted", payload: `jsonb_build_object('invitationId', invite.${c("id")}, 'organizationId', invite.${c("tenant")}::text, 'email', invite.${c("email")}, 'role', invite.${c("role")})`, subject: `'invitations/' || invite.${c("id")}::text`, tenant: `invite.${c("tenant")}` })}
  ${ctx.emit({ type: "organization.member_added", payload: `jsonb_build_object('organizationId', invite.${c("tenant")}::text, 'userId', me, 'role', invite.${c("role")})`, subject: `'organizations/' || invite.${c("tenant")}::text`, tenant: `invite.${c("tenant")}` })}
  return invite.${c("tenant")};
end;
$$;
`;
}

function invitationsSql(ctx: ModuleContext, layout: ModuleLayout): string {
  const id = ctx.idType;
  const grant = (
    fn: string,
    args: string,
    roles: string,
    revokeFrom = "public, anon",
  ) =>
    `revoke execute on function ${ctx.fn(fn)}(${args}) from ${revokeFrom};
grant execute on function ${ctx.fn(fn)}(${args}) to ${roles};`;
  return `${schemaPreamble(ctx)}
${tenantTableSql(ctx)}${platformTableSql(ctx)}${invite(ctx)}${close(ctx)}${preview(ctx)}${accept(ctx, layout)}
${grant("invite_member", `${id}, text, text, interval, jsonb`, "authenticated, service_role")}
${grant("create_invitation", `${id}, text, text, interval`, "authenticated, service_role")}
${grant("resend_invitation", "uuid, interval", "authenticated, service_role")}
${grant("revoke_invitation", "uuid", "authenticated, service_role")}
${grant("decline_invitation", "text", "anon, authenticated, service_role", "public")}
${grant("invitation_preview", "text", "anon, authenticated, service_role", "public")}
${grant("accept_invitation", "text", "authenticated")}`;
}

export const INVITATIONS: ModuleDefinition = {
  name: "invitations",
  title: "Invitations",
  description:
    "invite_member(tenant, email, role) returns a single-use token whose hash is stored; accept_invitation(token) checks the signed-in user's confirmed email and, again, the inviter's authority. Roles follow the access model; a null tenant invites to a platform role, stored in platform_invitations.",
  requires: ["tenant", "access", "updated-at"],
  target: "schema",
  version: 2,
  modes: ["managed", "adopt", "custom"],
  names: NAMES,
  contract: () => [
    {
      name: "invite_member",
      args: ["{id}", "text", "text", "interval", "jsonb"],
      returns: "jsonb",
    },
    { name: "accept_invitation", args: ["text"], returns: "{id}" },
    { name: "invitation_preview", args: ["text"], returns: "jsonb" },
    { name: "decline_invitation", args: ["text"], returns: "boolean" },
    { name: "revoke_invitation", args: ["uuid"], returns: "boolean" },
    { name: "resend_invitation", args: ["uuid", "interval"], returns: "jsonb" },
  ],
  upgrades: [
    {
      from: 1,
      description:
        "Renames invitations.org_id to organization_id, adds updated_at, declined_at and revoked_at (and prefill on request), a platform_invitations table for platform roles, takes roles from sql.modules.access, and adds invite_member, resend, revoke, decline and invitation_preview. create_invitation keeps its 0.4 signature.",
      sql: (ctx) =>
        ctx.manages
          ? renameSql({
              schema: ctx.tableName("invitations").schema,
              table: ctx.tableName("invitations").name,
              columns: [["org_id", "organization_id"]],
            })
          : "",
    },
  ],
  deprecated: [
    {
      kind: "column",
      symbol: "invitations.org_id",
      use: "invitations.organization_id",
      since: "0.5.0",
      removed: "0.5.0",
    },
  ],
  build: invitationsSql,
};
