import type { KitContext, KitNames } from "../context.ts";
import type { KitModuleDefinition } from "../kit.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { schemaPreamble, SERVICE_CALLER } from "../shared.ts";
import {
  accessModel,
  KIT_PERMISSIONS,
  roleNames,
  tenantScope,
} from "./access-model.ts";
import { roleValue, TRUSTED_SETTING } from "./organizations.ts";

const NAMES: KitNames = {
  tables: {
    invitations: {
      name: "invitations",
      columns: {
        id: "id",
        tenant: "org_id",
        email: "email",
        role: "role",
        tokenHash: "token_hash",
        invitedBy: "invited_by",
        createdAt: "created_at",
        expiresAt: "expires_at",
        acceptedAt: "accepted_at",
        acceptedBy: "accepted_by",
        declinedAt: "declined_at",
        revokedAt: "revoked_at",
        prefill: "prefill",
      },
      optional: [
        "invitedBy",
        "createdAt",
        "acceptedBy",
        "declinedAt",
        "revokedAt",
        "prefill",
      ],
    },
  },
  hooks: ["before_invitation_create", "after_invitation_accept"],
};

/** Every error the module raises: its hint code and default SQLSTATE. */
export const INVITATION_ERRORS = {
  INVITATION_FORBIDDEN: "42501",
  INVITATION_ROLE_FORBIDDEN: "42501",
  INVITATION_ROLE_UNKNOWN: "23514",
  INVITATION_ALREADY_MEMBER: "23505",
  INVITATION_INVALID: "P0002",
  INVITATION_SIGN_IN: "42501",
  INVITATION_EMAIL_MISMATCH: "42501",
  INVITATION_EMAIL_UNCONFIRMED: "42501",
  INVITATION_SELF: "42501",
  INVITATION_INVITER_REVOKED: "42501",
  INVITATION_SCOPE_UNSUPPORTED: "0A000",
} as const;

type InvitationError = keyof typeof INVITATION_ERRORS;

const SQLSTATE = /^[0-9A-Z]{5}$/;

/** `raise exception` for `code`, with the SQLSTATE from `kits.invitations.options.errorCodes`. */
function raiser(
  ctx: KitContext,
): (code: InvitationError, message: string, ...args: string[]) => string {
  const configured = ctx.config.options["errorCodes"] ?? {};
  if (typeof configured !== "object" || Array.isArray(configured)) {
    throw new TypeError(
      "kits.invitations.options.errorCodes must map error codes to SQLSTATEs",
    );
  }
  const states = new Map<string, string>(Object.entries(INVITATION_ERRORS));
  for (const [code, state] of Object.entries(configured)) {
    if (!states.has(code)) {
      throw new TypeError(
        `kits.invitations.options.errorCodes: unknown code "${code}". Codes: ${[...states.keys()].join(", ")}`,
      );
    }
    if (typeof state !== "string" || !SQLSTATE.test(state)) {
      throw new TypeError(
        `kits.invitations.options.errorCodes.${code} must be a five-character SQLSTATE`,
      );
    }
    states.set(code, state);
  }
  return (code, message, ...args) =>
    `raise exception ${sqlString(message)}${args.map((arg) => `, ${arg}`).join("")} using errcode = '${states.get(code)!}', hint = '${code}';`;
}

/**
 * How tokens are stored (`kits.invitations.options.tokenStorage`): `sha256`
 * (the default) keeps only the hash; `plain` keeps the token itself, for an
 * adopted table whose open invitations hold plain tokens.
 */
function tokenHash(ctx: KitContext, token: string): string {
  const storage = ctx.text("tokenStorage", "sha256");
  if (storage === "plain") return token;
  if (storage !== "sha256") {
    throw new TypeError(
      `kits.invitations.options.tokenStorage must be "sha256" or "plain", got "${storage}"`,
    );
  }
  return `encode(extensions.digest(${token}, 'sha256'), 'hex')`;
}

/** A column of the invitation row `alias`, or `fallback` when it's mapped to `null`. */
function optionalCol(
  ctx: KitContext,
  alias: string,
  logical: string,
  fallback: string,
): string {
  return ctx.has("invitations", logical)
    ? `${alias}.${ctx.col("invitations", logical)}`
    : fallback;
}

/** `pending`, `accepted`, `declined`, `revoked` or `expired` for row `i`. */
function statusOf(ctx: KitContext): string {
  const c = (logical: string) => `i.${ctx.col("invitations", logical)}`;
  const declined = ctx.has("invitations", "declinedAt")
    ? `\n    when ${c("declinedAt")} is not null then 'declined'`
    : "";
  const revoked = ctx.has("invitations", "revokedAt")
    ? `\n    when ${c("revokedAt")} is not null then 'revoked'`
    : "";
  return `case
    when ${c("acceptedAt")} is not null then 'accepted'${declined}${revoked}
    when ${c("expiresAt")} < now() then 'expired'
    else 'pending'
  end`;
}

/** Open invitations: not accepted, declined or revoked (expired ones count). */
function openFilter(ctx: KitContext, alias: string): string {
  return ["acceptedAt", "declinedAt", "revokedAt"]
    .filter((logical) => ctx.has("invitations", logical))
    .map((logical) => `${alias}.${ctx.col("invitations", logical)} is null`)
    .join(" and ");
}

function table(ctx: KitContext): string {
  const t = ctx.table("invitations");
  const c = (logical: string) => ctx.col("invitations", logical);
  if (!ctx.manages) {
    return `
-- Adopted: ${t} belongs to the app (kits.invitations.tables.invitations).
`;
  }
  const add = (logical: string, type: string) =>
    ctx.has("invitations", logical)
      ? `alter table ${t} add column if not exists ${c(logical)} ${type};\n`
      : "";
  const roleCheck =
    accessModel(ctx) === "roles"
      ? `alter table ${t}
  add constraint invitations_role_check check (${c("role")} in (${roleNames(ctx).map(sqlString).join(", ")}));
`
      : "";
  const where = openFilter(ctx, t).replaceAll(`${t}.`, "");
  return `
create table if not exists ${t} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType},
  ${c("email")} text not null,
  ${c("role")} text not null,
  ${c("tokenHash")} text not null unique,
  ${c("expiresAt")} timestamptz not null,
  ${c("acceptedAt")} timestamptz
);
-- A null tenant is a platform invitation (a platform role on accept).
alter table ${t} alter column ${c("tenant")} drop not null;
alter table ${t} alter column ${c("role")} drop default;
${add("invitedBy", "uuid references auth.users (id) on delete set null")}${add("createdAt", "timestamptz not null default now()")}${add("acceptedBy", "uuid references auth.users (id) on delete set null")}${add("declinedAt", "timestamptz")}${add("revokedAt", "timestamptz")}${add("prefill", "jsonb not null default '{}'")}
drop index if exists ${sqlIdent(ctx.tableName("invitations").schema)}.invitations_open_idx;
create unique index if not exists invitations_open_email_idx
  on ${t} (${c("tenant")}, lower(${c("email")})) nulls not distinct where ${where};
${ctx.has("invitations", "invitedBy") ? `create index if not exists invitations_invited_by_idx on ${t} (${c("invitedBy")});\n` : ""}${ctx.has("invitations", "acceptedBy") ? `create index if not exists invitations_accepted_by_idx on ${t} (${c("acceptedBy")});\n` : ""}
alter table ${t} drop constraint if exists invitations_role_check;
${roleCheck}
alter table ${t} enable row level security;
revoke all on ${t} from anon, authenticated;
grant select on ${t} to authenticated;
grant all on ${t} to service_role;

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
  return query select better_supabase.tenant_ids_with(${ctx.permission("view", KIT_PERMISSIONS.invitations.view)});
end;
$$;
revoke execute on function ${ctx.fn("invitation_tenant_ids")}() from public, anon;
grant execute on function ${ctx.fn("invitation_tenant_ids")}() to authenticated, service_role;
drop policy if exists bs_invitations_read on ${t};
create policy bs_invitations_read on ${t} for select to authenticated
  using (${c("tenant")} in (select ${ctx.fn("invitation_tenant_ids")}()));
`;
}

/** The invitation as returned to the inviter; the token only right after creating it. */
function inviteJson(ctx: KitContext, row: string, token: string): string {
  const c = (logical: string) => `${row}.${ctx.col("invitations", logical)}`;
  return `jsonb_build_object(
    'id', ${c("id")},
    'tenant', ${c("tenant")},
    'email', ${c("email")},
    'role', ${c("role")},
    'expires_at', ${c("expiresAt")},
    'invited_by', ${optionalCol(ctx, row, "invitedBy", "null")},
    'prefill', ${optionalCol(ctx, row, "prefill", "'{}'::jsonb")},
    'token', ${token}
  )`;
}

function invite(ctx: KitContext): string {
  const t = ctx.table("invitations");
  const c = (logical: string) => ctx.col("invitations", logical);
  const id = ctx.idType;
  const fail = raiser(ctx);
  const tenantMembers = ctx.of("tenant");
  const m = tenantMembers.table("memberships");
  const mt = tenantMembers.col("memberships", "tenant");
  const mu = tenantMembers.col("memberships", "user");
  const bytes = ctx.number("tokenBytes", 24);
  const validFor = sqlString(ctx.text("validFor", "7 days"));
  const model = accessModel(ctx);
  const unknownRole =
    model === "roles"
      ? `not (invitee_role = any (array[${roleNames(ctx).map(sqlString).join(", ")}]::text[]))`
      : model === "catalog"
        ? `${roleValue(ctx, "invitee_role")} is null`
        : "false";
  const stored =
    model === "catalog" ? roleValue(ctx, "invitee_role") : "invitee_role";
  const columns: (readonly [string, string])[] = [
    ["tenant", "tenant"],
    ["email", "lower(btrim(invitee_email))"],
    ["role", stored],
    ["tokenHash", tokenHash(ctx, "token")],
    ["invitedBy", "auth.uid()"],
    ["expiresAt", "now() + valid_for"],
    ["prefill", "coalesce(prefill, '{}')"],
  ];
  const present = columns.filter(([logical]) =>
    ctx.has("invitations", logical),
  );
  const open = openFilter(ctx, "i");
  return `
-- Invites email to tenant (null: a platform invitation) with role, a catalog
-- role id or key under kits.access.model 'catalog'. Returns the invitation
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
  created ${t};
begin
  if not service then
    if tenant is null then
      if not better_supabase.is_platform(${ctx.permission("invitePlatform", "platform.invite")}) then
        ${fail("INVITATION_FORBIDDEN", "Not allowed to invite platform users")}
      end if;
    elsif not coalesce(better_supabase.member_can(auth.uid(), tenant, ${ctx.permission("invite", KIT_PERMISSIONS.invitations.invite)}), false) then
      ${fail("INVITATION_FORBIDDEN", "Not allowed to invite members")}
    end if;
  end if;
  if ${unknownRole} then
    ${fail("INVITATION_ROLE_UNKNOWN", "Unknown role %", "invitee_role")}
  end if;
  if tenant is not null and not service and not better_supabase.can_assign(tenant, (${stored})::text) then
    ${fail("INVITATION_ROLE_FORBIDDEN", "That role is above your own")}
  end if;
  if tenant is not null and exists (
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
  delete from ${t} i
  where i.${c("tenant")} is not distinct from tenant
    and lower(i.${c("email")}) = lower(btrim(invitee_email))${open ? `\n    and ${open}` : ""};
  insert into ${t} (${present.map(([logical]) => c(logical)).join(", ")})
  values (${present.map(([, value]) => value).join(", ")})
  returning * into created;
  ${ctx.emit({ type: "invitation.created", payload: `jsonb_build_object('invitationId', created.${c("id")}, 'organizationId', tenant::text, 'email', created.${c("email")}, 'role', created.${c("role")})`, subject: `'invitations/' || created.${c("id")}::text`, tenant: "tenant" })}
  return ${inviteJson(ctx, "created", "token")};
end;
$$;

-- The 0.4 signature: returns the token only.
drop function if exists ${ctx.fn("create_invitation")}(${id}, text, text, interval);
create or replace function ${ctx.fn("create_invitation")}(
  org ${id},
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
  updated ${t};
begin
  update ${t} i
  set ${c("tokenHash")} = ${tokenHash(ctx, "token")},
    ${c("expiresAt")} = now() + valid_for
  where i.${c("id")} = invitation_id${open ? ` and ${open}` : ""}
    and (${SERVICE_CALLER} or ${canManage(ctx, "i")})
  returning * into updated;
  if updated.${c("id")} is null then
    ${fail("INVITATION_INVALID", "No open invitation %", "invitation_id")}
  end if;
  ${ctx.emit({ type: "invitation.resent", payload: `jsonb_build_object('invitationId', updated.${c("id")}, 'organizationId', updated.${c("tenant")}::text, 'email', updated.${c("email")})`, subject: `'invitations/' || updated.${c("id")}::text`, tenant: `updated.${c("tenant")}` })}
  return ${inviteJson(ctx, "updated", "token")};
end;
$$;
`;
}

/** Whether the caller may manage invitation row `alias` (revoke and resend). */
function canManage(ctx: KitContext, alias: string): string {
  const tenant = `${alias}.${ctx.col("invitations", "tenant")}`;
  return `case when ${tenant} is null
      then better_supabase.is_platform(${ctx.permission("invitePlatform", "platform.invite")})
      else coalesce(better_supabase.member_can(auth.uid(), ${tenant}, ${ctx.permission("revoke", KIT_PERMISSIONS.invitations.revoke)}), false)
    end`;
}

function close(ctx: KitContext): string {
  const t = ctx.table("invitations");
  const c = (logical: string) => ctx.col("invitations", logical);
  const open = openFilter(ctx, "i");
  const hash = `i.${c("tokenHash")} = ${tokenHash(ctx, "token")}`;
  const end = (logical: string, where: string, alias = "i") =>
    ctx.has("invitations", logical)
      ? `update ${t} ${alias} set ${c(logical)} = now() where ${where}${open ? ` and ${open}` : ""}`
      : `delete from ${t} ${alias} where ${where}${open ? ` and ${open}` : ""}`;
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
  ${end("revokedAt", `i.${c("id")} = invitation_id and (${SERVICE_CALLER} or ${canManage(ctx, "i")})`)}
  returning i.${c("tenant")}::text into tenant;
  if not found then
    return false;
  end if;
  ${ctx.emit({ type: "invitation.revoked", payload: "jsonb_build_object('invitationId', invitation_id, 'organizationId', tenant)", subject: "'invitations/' || invitation_id::text", tenant: "tenant" })}
  return true;
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
  ${end("declinedAt", `${hash} and i.${c("expiresAt")} >= now()`)}
  returning i.${c("id")}, i.${c("tenant")}::text into declined_id, tenant;
  if declined_id is null then
    return false;
  end if;
  ${ctx.emit({ type: "invitation.declined", payload: "jsonb_build_object('invitationId', declined_id, 'organizationId', tenant)", subject: "'invitations/' || declined_id::text", tenant: "tenant" })}
  return true;
end;
$$;
`;
}

/** `invitation_preview(token)`: what the accept page shows before sign-in. */
function preview(ctx: KitContext): string {
  const t = ctx.table("invitations");
  const c = (logical: string) => `i.${ctx.col("invitations", logical)}`;
  let organization = `jsonb_build_object('id', ${c("tenant")})`;
  if (ctx.installed("organizations")) {
    const orgs = ctx.of("organizations");
    const columns = ctx.list("previewColumns", ["name"]).map((column) => {
      if (!/^[A-Za-z_][A-Za-z0-9_$]*$/.test(column)) {
        throw new TypeError(
          `kits.invitations.options.previewColumns: "${column}" is not a valid column`,
        );
      }
      return `, ${sqlString(column)}, o.${sqlIdent(column)}`;
    });
    organization = `(select jsonb_build_object('id', o.${orgs.col("organizations", "id")}${columns.join("")})
      from ${orgs.table("organizations")} o where o.${orgs.col("organizations", "id")} = ${c("tenant")})`;
  }
  return `
-- What an invitation link shows before sign-in: status (pending, accepted,
-- declined, revoked or expired), email, role, organization (id plus
-- kits.invitations.options.previewColumns) and prefill. Null for an unknown token.
create or replace function ${ctx.fn("invitation_preview")}(token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return (select jsonb_build_object(
    'status', ${statusOf(ctx)},
    'email', ${c("email")},
    'role', ${c("role")},
    'tenant', ${c("tenant")},
    'expires_at', ${c("expiresAt")},
    'organization', case when ${c("tenant")} is null then null else ${organization} end,
    'prefill', ${optionalCol(ctx, "i", "prefill", "'{}'::jsonb")}
  )
  from ${t} i
  where ${c("tokenHash")} = ${tokenHash(ctx, "invitation_preview.token")});
end;
$$;
`;
}

function accept(ctx: KitContext): string {
  const t = ctx.table("invitations");
  const c = (logical: string) => ctx.col("invitations", logical);
  const id = ctx.idType;
  const fail = raiser(ctx);
  const tenantCtx = ctx.of("tenant");
  const m = tenantCtx.table("memberships");
  const mt = tenantCtx.col("memberships", "tenant");
  const mu = tenantCtx.col("memberships", "user");
  const mr = tenantCtx.col("memberships", "role");
  const access = ctx.of("access");
  const invitePermission = ctx.permission(
    "invite",
    KIT_PERMISSIONS.invitations.invite,
  );
  const roleOf = (expr: string) =>
    accessModel(ctx) === "catalog" ? roleValue(ctx, expr) : expr;
  const platform =
    accessModel(ctx) === "catalog" && access.hasTable("platformAssignments")
      ? `insert into ${access.table("platformAssignments")} (${access.col("platformAssignments", "user")}, ${access.col("platformAssignments", "role")})
    values (me, ${roleValue(ctx, `invite.${c("role")}`)})
    on conflict do nothing;`
      : fail(
          "INVITATION_SCOPE_UNSUPPORTED",
          "Platform invitations need kits.access.model 'catalog' with a platformAssignments table",
        );
  const selfCheck = ctx.has("invitations", "invitedBy")
    ? `
  if invite.${c("invitedBy")} = me then
    ${fail("INVITATION_SELF", "You cannot accept your own invitation")}
  end if;`
    : "";
  const recheck =
    ctx.flag("recheckInviter", true) && ctx.has("invitations", "invitedBy")
      ? `
    if invite.${c("invitedBy")} is not null
      and better_supabase.can_user(invite.${c("invitedBy")}, ${sqlString(tenantScope(ctx))}, invite.${c("tenant")}, ${invitePermission}) is false then
      ${fail("INVITATION_INVITER_REVOKED", "The person who invited you can no longer invite members")}
    end if;`
      : "";
  const confirmed = ctx.flag("requireConfirmedEmail", true)
    ? `
  -- The email claim alone does not prove the address: an unconfirmed sign-up carries it too.
  if not exists (
    select 1 from auth.users u
    where u.id = me and u.email_confirmed_at is not null and lower(u.email) = lower(invite.${c("email")})
  ) then
    ${fail("INVITATION_EMAIL_UNCONFIRMED", "Confirm your email address before accepting the invitation")}
  end if;`
    : "";
  const open = openFilter(ctx, "invite");
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
  invite ${t};
begin
  if me is null then
    ${fail("INVITATION_SIGN_IN", "Sign in to accept an invitation")}
  end if;
  select * into invite
  from ${t} i
  where i.${c("tokenHash")} = ${tokenHash(ctx, "token")}
  for update;
  if invite.${c("id")} is null or not (${open || "true"}) or invite.${c("expiresAt")} < now() then
    ${fail("INVITATION_INVALID", "The invitation is invalid or has expired")}
  end if;
  if lower(invite.${c("email")}) <> lower(coalesce(auth.jwt() ->> 'email', '')) then
    ${fail("INVITATION_EMAIL_MISMATCH", "The invitation is for another email address")}
  end if;${confirmed}${selfCheck}
  perform set_config('${TRUSTED_SETTING}', 'on', true);
  if invite.${c("tenant")} is null then
    ${platform}
  else
    if better_supabase.tenant_disabled(invite.${c("tenant")}) then
      ${fail("INVITATION_INVALID", "The invitation is invalid or has expired")}
    end if;
    if exists (select 1 from ${m} m where m.${mt} = invite.${c("tenant")} and m.${mu} = me) then
      ${fail("INVITATION_ALREADY_MEMBER", "You are already a member")}
    end if;${recheck}
    insert into ${m} (${mt}, ${mu}, ${mr})
    values (invite.${c("tenant")}, me, ${roleOf(`invite.${c("role")}`)});
  end if;
  perform set_config('${TRUSTED_SETTING}', '', true);
  update ${t}
  set ${c("acceptedAt")} = now()${ctx.has("invitations", "acceptedBy") ? `, ${c("acceptedBy")} = me` : ""}
  where ${c("id")} = invite.${c("id")};
  ${ctx.hook("after_invitation_accept", [
    ["uuid", `invite.${c("id")}`],
    ["uuid", "me"],
  ])}
  ${ctx.emit({ type: "invitation.accepted", payload: `jsonb_build_object('invitationId', invite.${c("id")}, 'organizationId', invite.${c("tenant")}::text, 'email', invite.${c("email")}, 'role', invite.${c("role")})`, subject: `'invitations/' || invite.${c("id")}::text`, tenant: `invite.${c("tenant")}` })}
  ${ctx.emit({ type: "org.member_added", payload: `jsonb_build_object('organizationId', invite.${c("tenant")}::text, 'userId', me, 'role', invite.${c("role")})`, subject: `'organizations/' || invite.${c("tenant")}::text`, tenant: `invite.${c("tenant")}` })}
  return invite.${c("tenant")};
end;
$$;
`;
}

function invitationsSql(ctx: KitContext): string {
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
${table(ctx)}${invite(ctx)}${close(ctx)}${preview(ctx)}${accept(ctx)}
${grant("invite_member", `${id}, text, text, interval, jsonb`, "authenticated, service_role")}
${grant("create_invitation", `${id}, text, text, interval`, "authenticated, service_role")}
${grant("resend_invitation", "uuid, interval", "authenticated, service_role")}
${grant("revoke_invitation", "uuid", "authenticated, service_role")}
${grant("decline_invitation", "text", "anon, authenticated, service_role", "public")}
${grant("invitation_preview", "text", "anon, authenticated, service_role", "public")}
${grant("accept_invitation", "text", "authenticated")}`;
}

export const INVITATIONS: KitModuleDefinition = {
  name: "invitations",
  title: "Invitations",
  description:
    "invite_member(tenant, email, role) returns a single-use token whose hash is stored; accept_invitation(token) checks the signed-in user's confirmed email and the inviter's authority. Roles follow the access model; a null tenant invites to a platform role.",
  requires: ["tenant", "access"],
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
        "Adds declined_at, revoked_at and prefill, makes org_id nullable for platform invitations, takes roles from kits.access, and adds invite_member, resend, revoke, decline and invitation_preview. create_invitation keeps its 0.4 signature.",
      sql: () => "",
    },
  ],
  build: invitationsSql,
};
