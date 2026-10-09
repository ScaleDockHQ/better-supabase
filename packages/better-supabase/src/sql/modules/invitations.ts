import type { ModuleContext, ModuleEvents, ModuleNames } from "../context.ts";
import type { ModuleDefinition, ModuleLayout } from "../registry.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  memberAddedRecord,
  organizationMissing,
  renameSql,
  schemaPreamble,
  SERVICE_CALLER,
  updatedAt,
} from "../shared.ts";
import {
  accessModel,
  MODULE_PERMISSIONS,
  modulePermission,
  roleNames,
  tenantScope,
} from "./access-model.ts";
import { hasCanAssignAs, providerForUser } from "./access.ts";
import {
  invitePlatform,
  platformAssignment,
  platformRoleScope,
  tenantRole,
} from "./invitations-roles.ts";
import {
  invitationExtra,
  inviteJson,
  myInvitations,
  organizationJson,
  updateInvitation,
} from "./invitations-rows.ts";
import {
  PLATFORM_COLUMNS,
  openFilter,
  optionalCol,
  platformTable,
  raise,
  statusOf,
  tenantTable,
  tokenHash,
  type InviteTable,
} from "./invitations-tables.ts";
import { assignableRole, roleValue } from "./organizations.ts";
import { roleThrough } from "./tenant.ts";

const EVENTS: ModuleEvents = {
  "invitation.created": {
    subject: "invitations",
    payload: ["invitationId", "organizationId", "email", "role"],
  },
  "invitation.resent": {
    subject: "invitations",
    payload: ["invitationId", "organizationId", "email"],
  },
  "invitation.updated": {
    subject: "invitations",
    payload: ["invitationId", "organizationId", "email", "role"],
  },
  "invitation.revoked": {
    subject: "invitations",
    payload: ["invitationId", "organizationId"],
  },
  "invitation.declined": {
    subject: "invitations",
    payload: ["invitationId", "organizationId"],
  },
  "invitation.accepted": {
    subject: "invitations",
    payload: ["invitationId", "organizationId", "email", "role"],
  },
  "organization.member_added": {
    subject: "organizations",
    payload: ["organizationId", "userId", "role"],
  },
};

const NAMES: ModuleNames = {
  events: EVENTS,
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
      lifecycle: { tenant: "tenant", omit: ["tokenHash"] },
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
  return query select better_supabase.tenant_ids_with(${modulePermission(ctx, "view", MODULE_PERMISSIONS.invitations.view)});
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
      "Platform invitations need platform roles: sql.modules.access.model 'catalog' with platform assignments, or sql.modules.invitations.options.platformRoles under 'provider'",
    );
  }
  const c = (logical: string) => p.col(logical);
  const assignment = platformAssignment(ctx);
  const role = assignment.value("invitee_role");
  const ceiling = assignment.canAssign("auth.uid()", `(${role})`);
  const columns: (readonly [string, string])[] = [
    ["email", "lower(btrim(invitee_email))"],
    ["role", role],
    ["tokenHash", tokenHash(ctx, "token")],
    ["invitedBy", "auth.uid()"],
    ["expiresAt", "now() + valid_for"],
    ["prefill", "coalesce(prefill, '{}')"],
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
    ${ctx.record({ type: "invitation.created", payload: `jsonb_build_object('invitationId', platform_created.${c("id")}, 'organizationId', null, 'email', platform_created.${c("email")}, 'role', platform_created.${c("role")})`, subject: `'invitations/' || platform_created.${c("id")}::text`, audit: { category: "membership", targetType: "invitation", recordId: `platform_created.${c("id")}::text` } })}
    return ${inviteJson(ctx, p, "platform_created", "token", null)};`;
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
  const { stored, unknownRole } = tenantRole(ctx);
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
      ${ctx.record({ type: "invitation.resent", payload: `jsonb_build_object('invitationId', platform_updated.${pc("id")}, 'organizationId', null, 'email', platform_updated.${pc("email")})`, subject: `'invitations/' || platform_updated.${pc("id")}::text`, audit: { category: "membership", targetType: "invitation", recordId: `platform_updated.${pc("id")}::text` } })}
      return ${inviteJson(ctx, p, "platform_updated", "token", null)};
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
  ${ctx.record({ type: "invitation.created", payload: `jsonb_build_object('invitationId', created.${c("id")}, 'organizationId', tenant::text, 'email', created.${c("email")}, 'role', created.${c("role")})`, subject: `'invitations/' || created.${c("id")}::text`, tenant: "tenant", audit: { category: "membership", targetType: "invitation", recordId: `created.${c("id")}::text` } })}
  return ${inviteJson(ctx, t, "created", "token", `created.${c("tenant")}`)};
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
  ${ctx.record({ type: "invitation.resent", payload: `jsonb_build_object('invitationId', updated.${c("id")}, 'organizationId', updated.${c("tenant")}::text, 'email', updated.${c("email")})`, subject: `'invitations/' || updated.${c("id")}::text`, tenant: `updated.${c("tenant")}`, audit: { category: "membership", targetType: "invitation", recordId: `updated.${c("id")}::text` } })}
  return ${inviteJson(ctx, t, "updated", "token", `updated.${c("tenant")}`)};
end;
$$;
`;
}

/** Whether the caller may manage tenant invitation row `alias` (revoke and resend). */
function canManage(ctx: ModuleContext, alias: string): string {
  const tenant = `${alias}.${ctx.col("invitations", "tenant")}`;
  return `coalesce(better_supabase.member_can(auth.uid(), ${tenant}, ${modulePermission(ctx, "revoke", MODULE_PERMISSIONS.invitations.revoke)}), false)`;
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
    ${ctx.record({ type: "invitation.revoked", payload: "jsonb_build_object('invitationId', invitation_id, 'organizationId', null)", subject: "'invitations/' || invitation_id::text", audit: { category: "membership", targetType: "invitation", recordId: `invitation_id::text` } })}
    return true;
  end if;`
    : "";
  const platformDecline = (match: (table: InviteTable) => string) =>
    p
      ? `
  ${end(p, "declinedAt", `${match(p)} and i.${p.col("expiresAt")} >= now()`)}
  returning i.${p.col("id")} into declined_id;
  if declined_id is not null then
    ${ctx.record({ type: "invitation.declined", payload: "jsonb_build_object('invitationId', declined_id, 'organizationId', null)", subject: "'invitations/' || declined_id::text", audit: { category: "membership", targetType: "invitation", recordId: `declined_id::text` } })}
    return true;
  end if;`
      : "";
  const mine = (table: InviteTable) =>
    `i.${table.col("id")} = invitation_id and lower(i.${table.col("email")}) = invitee_email`;
  const confirmed = ctx.flag("requireConfirmedEmail", true)
    ? " and u.email_confirmed_at is not null"
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
    ${ctx.record({ type: "invitation.revoked", payload: "jsonb_build_object('invitationId', invitation_id, 'organizationId', tenant)", subject: "'invitations/' || invitation_id::text", tenant: "tenant", audit: { category: "membership", targetType: "invitation", recordId: `invitation_id::text` } })}
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
    ${ctx.record({ type: "invitation.declined", payload: "jsonb_build_object('invitationId', declined_id, 'organizationId', tenant)", subject: "'invitations/' || declined_id::text", tenant: "tenant", audit: { category: "membership", targetType: "invitation", recordId: `declined_id::text` } })}
    return true;
  end if;${platformDecline(hash)}
  return false;
end;
$$;

create or replace function ${ctx.fn("decline_invitation_by_id")}(invitation_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  declined_id uuid;
  tenant text;
  invitee_email text;
begin
  select lower(u.email) into invitee_email
  from auth.users u
  where u.id = auth.uid()${confirmed};
  if invitee_email is null then
    return false;
  end if;
  ${end(t, "declinedAt", `${mine(t)} and i.${t.col("expiresAt")} >= now()`)}
  returning i.${t.col("id")}, i.${t.col("tenant")}::text into declined_id, tenant;
  if declined_id is not null then
    ${ctx.record({ type: "invitation.declined", payload: "jsonb_build_object('invitationId', declined_id, 'organizationId', tenant)", subject: "'invitations/' || declined_id::text", tenant: "tenant", audit: { category: "membership", targetType: "invitation", recordId: `declined_id::text` } })}
    return true;
  end if;${platformDecline(mine)}
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
  const organization = organizationJson(ctx, c("tenant"));
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
begin
  select ${json(t, c("tenant"), organization)}, ${c("id")}
  into preview, invitation
  from ${t.table} i
  where ${c("tokenHash")} = ${tokenHash(ctx, "invitation_preview.token")}${t.only("i")};${platform}
  if preview is not null then
    preview := preview || ${ctx.fn("invitation_extra")}(invitation);
  end if;
  return preview;
end;
$$;
`;
}

function accept(
  ctx: ModuleContext,
  layout: ModuleLayout,
  by: "token" | "id" = "token",
): string {
  const t = tenantTable(ctx);
  const match = (table: InviteTable) =>
    by === "token"
      ? `i.${table.col("tokenHash")} = ${tokenHash(ctx, "token")}`
      : `i.${table.col("id")} = invitation_id`;
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
  const storedRole = `invite.${t.col("role")}`;
  const role = roleValue(ctx, storedRole, `invite.${t.col("tenant")}`);
  const roleKnown = roleThrough(tenantCtx)
    ? `
  if ${role} is null then
    ${fail("INVITATION_ROLE_UNKNOWN", "Unknown role %", storedRole)}
  end if;`
    : "";
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
    return `if not (${open || "true"}) then
    ${fail("INVITATION_INVALID", "The invitation is invalid or has expired")}
  end if;
  if ${col("expiresAt")} < now() then
    ${fail("INVITATION_EXPIRED", "The invitation has expired; ask for a new one")}
  end if;
  if lower(${col("email")}) <> lower(coalesce(auth.jwt() ->> 'email', '')) then
    ${fail("INVITATION_EMAIL_MISMATCH", "The invitation is for another email address")}
  end if;${confirmed}${self}`;
  };
  // The inviter's authority is checked again: a role or permission they
  // lost after inviting must not reach the invitee.
  const inviter = t.has("invitedBy") ? `invite.${c("invitedBy")}` : undefined;
  const forUser = model === "provider" ? providerForUser(layout) : undefined;
  const assignAs = hasCanAssignAs(ctx, layout)
    ? `
    if ${inviter} is not null
      and not better_supabase.can_assign_as(${inviter}, invite.${c("tenant")}, ${assignableRole(ctx, `invite.${c("role")}`)}) then
      ${fail("INVITATION_INVITER_REVOKED", "The person who invited you can no longer assign that role")}
    end if;`
    : "";
  const recheck =
    inviter && model === "provider" && !(forUser?.permitted && forUser.has)
      ? `
    -- The provider model answers for the caller only, so the inviter's
    -- invite permission was checked when they invited, not here.${assignAs}`
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
    const inviterCeiling = assignment.inviterCanAssign(
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
  where ${match(p)}${p.only("i")}
  for update;
  if pinvite.${pc("id")} is not null then
  ${invitee(p, "pinvite")}${platformInviter}
  if ${assignment.assign(`pinvite.${pc("role")}`)} is null then
    ${fail("INVITATION_ROLE_UNKNOWN", "Unknown platform role %", `pinvite.${pc("role")}`)}
  end if;
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
  ${ctx.record({ type: "invitation.accepted", payload: `jsonb_build_object('invitationId', pinvite.${pc("id")}, 'organizationId', null, 'email', pinvite.${pc("email")}, 'role', pinvite.${pc("role")})`, subject: `'invitations/' || pinvite.${pc("id")}::text`, audit: { category: "membership", targetType: "invitation", recordId: `pinvite.${pc("id")}::text` } })}
  return null;
  end if;`;
  }
  return `${
    by === "token"
      ? `
-- Accepts with the token for the signed-in user, whose confirmed email must
-- match, and returns the tenant (null for a platform invitation).
create or replace function ${ctx.fn("accept_invitation")}(token text)`
      : `
create or replace function ${ctx.fn("accept_invitation_by_id")}(invitation_id uuid)`
  }
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
  where ${match(t)}${t.only("i")}
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
  end if;${recheck}${roleKnown}
  insert into ${m} (${mt}, ${mu}, ${mr})
  values (invite.${c("tenant")}, me, ${role});
  update ${t.table}
  set ${c("acceptedAt")} = now()${t.has("acceptedBy") ? `, ${c("acceptedBy")} = me` : ""}
  where ${c("id")} = invite.${c("id")};
  ${ctx.hook("after_invitation_accept", [
    ["uuid", `invite.${c("id")}`],
    ["uuid", "me"],
  ])}
  ${ctx.record({ type: "invitation.accepted", payload: `jsonb_build_object('invitationId', invite.${c("id")}, 'organizationId', invite.${c("tenant")}::text, 'email', invite.${c("email")}, 'role', invite.${c("role")})`, subject: `'invitations/' || invite.${c("id")}::text`, tenant: `invite.${c("tenant")}`, audit: { category: "membership", targetType: "invitation", recordId: `invite.${c("id")}::text` } })}
  ${memberAddedRecord(ctx, { tenant: `invite.${c("tenant")}`, user: "me", role: `invite.${c("role")}` })}
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
${tenantTableSql(ctx)}${platformTableSql(ctx)}${platformRoleScope(ctx)}${invitationExtra(ctx)}${invite(ctx)}${updateInvitation(ctx)}${close(ctx)}${preview(ctx)}${accept(ctx, layout)}${accept(ctx, layout, "id")}${myInvitations(ctx)}
${grant("invite_member", `${id}, text, text, interval, jsonb`, "authenticated, service_role")}
${grant("create_invitation", `${id}, text, text, interval`, "authenticated, service_role")}
${grant("resend_invitation", "uuid, interval", "authenticated, service_role")}
${grant("update_invitation", "uuid, text, text, jsonb", "authenticated, service_role")}
${grant("revoke_invitation", "uuid", "authenticated, service_role")}
${grant("decline_invitation", "text", "anon, authenticated, service_role", "public")}
${grant("invitation_preview", "text", "anon, authenticated, service_role", "public")}
${grant("accept_invitation", "text", "authenticated")}
${grant("accept_invitation_by_id", "uuid", "authenticated")}
${grant("decline_invitation_by_id", "uuid", "authenticated")}
${grant("my_invitations", "", "authenticated")}`;
}

export const INVITATIONS: ModuleDefinition = {
  internal: ["invitation_tenant_ids", "platform_invitations_readable"],
  name: "invitations",
  title: "Invitations",
  description:
    "invite_member(tenant, email, role) returns a single-use token whose hash is stored; accept_invitation(token) checks the signed-in user's confirmed email and, again, the inviter's authority. Roles follow the access model; a null tenant invites to a platform role, stored in platform_invitations.",
  requires: ["tenant", "access", "updated-at"],
  integrates: ["organizations", "profiles"],
  providerFunctions: ["idsWithFor", "isPlatformFor", "canAssignFor"],
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
    { name: "accept_invitation_by_id", args: ["uuid"], returns: "{id}" },
    { name: "decline_invitation_by_id", args: ["uuid"], returns: "boolean" },
    { name: "my_invitations", args: [], returns: "jsonb" },
    { name: "revoke_invitation", args: ["uuid"], returns: "boolean" },
    { name: "resend_invitation", args: ["uuid", "interval"], returns: "jsonb" },
    {
      name: "update_invitation",
      args: ["uuid", "text", "text", "jsonb"],
      returns: "jsonb",
    },
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
