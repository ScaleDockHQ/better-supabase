import type { ModuleContext } from "../context.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { organizationMissing, SERVICE_CALLER } from "../shared.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";
import {
  invitePlatform,
  platformAssignment,
  tenantRole,
} from "./invitations-roles.ts";
import {
  openFilter,
  optionalCol,
  platformTable,
  raise,
  tenantTable,
  type InviteTable,
} from "./invitations-tables.ts";
import { assignableRole } from "./organizations.ts";

/**
 * The invitation's organization: its id plus
 * `sql.modules.invitations.options.previewColumns` when the organizations
 * module is installed.
 */
export function organizationJson(ctx: ModuleContext, tenant: string): string {
  if (!ctx.installed("organizations")) {
    return `jsonb_build_object('id', ${tenant})`;
  }
  const organizations = ctx.of("organizations");
  const id = organizations.col("organizations", "id");
  const columns = ctx.list("previewColumns", ["name"]).map((column) => {
    if (!/^[A-Za-z_][A-Za-z0-9_$]*$/.test(column)) {
      throw new TypeError(
        `sql.modules.invitations.options.previewColumns: "${column}" is not a valid column`,
      );
    }
    return `, ${sqlString(column)}, o.${sqlIdent(column)}`;
  });
  return `(select jsonb_build_object('id', o.${id}${columns.join("")})
      from ${organizations.table("organizations")} o where o.${id} = ${tenant})`;
}

/**
 * The inviter's id and public profile fields (as in `notification_actors`)
 * when the profiles module is installed and the table has `invitedBy`;
 * `undefined` otherwise.
 */
function inviterJson(
  ctx: ModuleContext,
  t: InviteTable,
  row: string,
): string | undefined {
  if (!ctx.installed("profiles") || !t.has("invitedBy")) return undefined;
  const profiles = ctx.of("profiles");
  const p = (logical: string) => profiles.col("profiles", logical);
  const fields = (
    ["username", "fullName", "firstName", "lastName", "avatar"] as const
  )
    .filter((logical) => profiles.has("profiles", logical))
    .map((logical) => `, '${logical}', pr.${p(logical)}`)
    .join("");
  return `(select jsonb_build_object('id', pr.${p("key")}${fields})
      from ${profiles.table("profiles")} pr where pr.${p("key")} = ${row}.${t.col("invitedBy")})`;
}

/** The `invitation_preview_extra(uuid)` hook's signature, for `to_regprocedure`. */
const extraHook = (ctx: ModuleContext): string =>
  sqlString(`${ctx.hookTarget("invitation_preview_extra")}(uuid)`);

/**
 * `invitation_extra(invitation)`: the keys the app's
 * `invitation_preview_extra` hook returns, or `{}` without the hook.
 */
export function invitationExtra(ctx: ModuleContext): string {
  return `
-- The keys an invitation_preview_extra(invitation uuid) hook returns for an
-- invitation, such as a role's display name; {} without the hook. The
-- module's functions merge them into every invitation they return.
create or replace function ${ctx.fn("invitation_extra")}(invitation uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  hook regprocedure := to_regprocedure(${extraHook(ctx)});
  extra jsonb;
begin
  if hook is null or invitation is null then
    return '{}'::jsonb;
  end if;
  -- Not a literal name, so plpgsql_check passes without the hook.
  execute format('select %s($1)', hook::oid::regproc) into extra using invitation;
  return coalesce(extra, '{}'::jsonb);
end;
$$;
revoke execute on function ${ctx.fn("invitation_extra")}(uuid) from public, anon, authenticated;
`;
}

/**
 * The invitation as returned to the inviter and the invitee, with the
 * inviter's profile fields and the `invitation_preview_extra` keys; the
 * token only right after creating it.
 */
export function inviteJson(
  ctx: ModuleContext,
  t: InviteTable,
  row: string,
  token: string,
  tenant: string | null,
): string {
  const c = (logical: string) => `${row}.${t.col(logical)}`;
  const inviter = inviterJson(ctx, t, row);
  return `(jsonb_build_object(
    'id', ${c("id")},
    'tenant', ${tenant ?? "null"},
    'email', ${c("email")},
    'role', ${c("role")},
    'expires_at', ${c("expiresAt")},
    'created_at', ${optionalCol(t, row, "createdAt", "null")},
    'invited_by', ${optionalCol(t, row, "invitedBy", "null")},
    'organization', ${tenant === null ? "null" : organizationJson(ctx, tenant)},
    'prefill', ${optionalCol(t, row, "prefill", "'{}'::jsonb")},${
      inviter
        ? `
    'inviter', ${inviter},`
        : ""
    }
    'token', ${token}
  ) || ${ctx.fn("invitation_extra")}(${c("id")}))`;
}

/**
 * `my_invitations()`: the caller's open invitations without their tokens,
 * with the organization and the `invitation_preview_extra` keys.
 */
export function myInvitations(ctx: ModuleContext): string {
  const t = tenantTable(ctx);
  const p = platformTable(ctx);
  const confirmed = ctx.flag("requireConfirmedEmail", true)
    ? " and u.email_confirmed_at is not null"
    : "";
  const rows = (table: InviteTable, tenant: string | null) => {
    const open = openFilter(table, "i");
    return `select ${inviteJson(ctx, table, "i", "null", tenant)} - 'token' as invitation, i.${table.col("id")} as id, i.${table.col("expiresAt")} as expires_at
    from ${table.table} i
    where lower(i.${table.col("email")}) = invitee_email
      and i.${table.col("expiresAt")} >= now()${open ? ` and ${open}` : ""}${table.only("i")}`;
  };
  return `
-- The caller's open invitations, for an in-app inbox: the invitation without
-- its token, its organization (id plus previewColumns) and the keys an
-- invitation_preview_extra(invitation uuid) hook adds.
create or replace function ${ctx.fn("my_invitations")}()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  invitee_email text;
  result jsonb := '[]'::jsonb;
begin
  select lower(u.email) into invitee_email
  from auth.users u
  where u.id = auth.uid()${confirmed};
  if invitee_email is null then
    return result;
  end if;
  select coalesce(jsonb_agg(x.invitation order by x.expires_at), '[]'::jsonb)
  into result
  from (
    ${rows(t, `i.${t.col("tenant")}`)}${
      p
        ? `
    union all
    ${rows(p, null)}`
        : ""
    }
  ) x;
  return result;
end;
$$;
`;
}

/**
 * `update_invitation`: a new email, role or prefill for an open invitation
 * that has not expired, with the checks `invite_member` makes. The token and
 * expiry stay.
 */
export function updateInvitation(ctx: ModuleContext): string {
  const t = tenantTable(ctx);
  const p = platformTable(ctx);
  const c = (logical: string) => t.col(logical);
  const fail = raise;
  const tenantMembers = ctx.of("tenant");
  const m = tenantMembers.table("memberships");
  const mt = tenantMembers.col("memberships", "tenant");
  const mu = tenantMembers.col("memberships", "user");
  const { stored, unknownRole } = tenantRole(ctx);
  const open = openFilter(t, "i");
  /**
   * Writes the changes into row variable `next`, a copy of the current row,
   * so each value takes the column's own type, then updates the row from it.
   */
  const write = (
    table: InviteTable,
    current: string,
    next: string,
    role: string,
  ) => {
    const col = (logical: string) => table.col(logical);
    const prefill = table.has("prefill")
      ? `
    if prefill is not null then
      ${next}.${col("prefill")} := prefill;
    end if;`
      : "";
    return `${next} := ${current};
    if invitee_email is not null then
      ${next}.${col("email")} := lower(btrim(invitee_email));
    end if;
    if invitee_role is not null then
      ${next}.${col("role")} := ${role};
    end if;${prefill}
    update ${table.table} i
    set ${col("email")} = ${next}.${col("email")},
      ${col("role")} = ${next}.${col("role")}${
        table.has("prefill")
          ? `,
      ${col("prefill")} = ${next}.${col("prefill")}`
          : ""
      }
    where i.${col("id")} = invitation_id
    returning * into ${next};`;
  };
  let platformEdit = "";
  if (p) {
    const pc = (logical: string) => p.col(logical);
    const pOpen = openFilter(p, "i");
    const assignment = platformAssignment(ctx);
    const role = assignment.value("invitee_role");
    const ceiling = (stored: string) =>
      assignment.canAssign("auth.uid()", `(${stored})`);
    const newCeiling = ceiling(role);
    const oldCeiling = ceiling(`platform_current.${pc("role")}`);
    platformEdit = `
    select * into platform_current from ${p.table} i
    where i.${pc("id")} = invitation_id${pOpen ? ` and ${pOpen}` : ""}${p.only("i")}
    for update;
    if platform_current.${pc("id")} is not null then
      if platform_current.${pc("expiresAt")} < now() then
        ${fail("INVITATION_INVALID", "The invitation has expired; resend it to renew it")}
      end if;
      if not service and not better_supabase.is_platform(${invitePlatform(ctx)}) then
        ${fail("INVITATION_FORBIDDEN", "Not allowed to invite platform users")}
      end if;
      if invitee_role is not null and ${role} is null then
        ${fail("INVITATION_ROLE_UNKNOWN", "Unknown platform role %", "invitee_role")}
      end if;
      ${
        newCeiling && oldCeiling
          ? `if not service and (not ${oldCeiling} or (invitee_role is not null and not ${newCeiling})) then
        ${fail("INVITATION_ROLE_FORBIDDEN", "That role is above your own")}
      end if;`
          : "-- No platform role ceiling: holding the invite permission is enough."
      }
      if invitee_email is not null then
        delete from ${p.table} i
        where lower(i.${pc("email")}) = lower(btrim(invitee_email))
          and i.${pc("id")} <> invitation_id${pOpen ? ` and ${pOpen}` : ""}${p.only("i")};
      end if;
      ${write(p, "platform_current", "platform_updated", role)}
      ${ctx.emit({ type: "invitation.updated", payload: `jsonb_build_object('invitationId', platform_updated.${pc("id")}, 'organizationId', null, 'email', platform_updated.${pc("email")}, 'role', platform_updated.${pc("role")})`, subject: `'invitations/' || platform_updated.${pc("id")}::text` })}
      return ${inviteJson(ctx, p, "platform_updated", "null", null)} - 'token';
    end if;`;
  }
  return `
-- A new email, role or prefill for an open invitation that has not expired;
-- null keeps the current value. The caller needs what invite_member needs, and may assign
-- both the current and the new role. The token and expiry stay, and another
-- open invitation for the new email is replaced. Returns the invitation
-- without its token.
create or replace function ${ctx.fn("update_invitation")}(
  invitation_id uuid,
  invitee_email text default null,
  invitee_role text default null,
  prefill jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  service boolean := ${SERVICE_CALLER};
  current_invite ${t.table};
  updated ${t.table};
  tenant ${ctx.idType};${p ? `\n  platform_current ${p.table};\n  platform_updated ${p.table};` : ""}
begin
  if invitee_email is not null and btrim(invitee_email) = '' then
    ${fail("INVITATION_INVALID", "The email address is empty")}
  end if;
  select * into current_invite from ${t.table} i
  where i.${c("id")} = invitation_id${open ? ` and ${open}` : ""}${t.only("i")}
  for update;
  if current_invite.${c("id")} is null then${platformEdit}
    ${fail("INVITATION_INVALID", "No open invitation %", "invitation_id")}
  end if;
  if current_invite.${c("expiresAt")} < now() then
    ${fail("INVITATION_INVALID", "The invitation has expired; resend it to renew it")}
  end if;
  tenant := current_invite.${c("tenant")};
  if not service and not coalesce(better_supabase.member_can(auth.uid(), tenant, ${ctx.permission("invite", MODULE_PERMISSIONS.invitations.invite)}), false) then
    ${fail("INVITATION_FORBIDDEN", "Not allowed to invite members")}
  end if;
  if better_supabase.tenant_disabled(tenant) or ${organizationMissing(ctx, "tenant")} then
    ${fail("INVITATION_INVALID", "The organization is not active")}
  end if;
  if invitee_role is not null and ${unknownRole} then
    ${fail("INVITATION_ROLE_UNKNOWN", "Unknown role %", "invitee_role")}
  end if;
  if not service and (
    not better_supabase.can_assign(tenant, ${assignableRole(ctx, `current_invite.${c("role")}`)})
    or (invitee_role is not null and not better_supabase.can_assign(tenant, ${assignableRole(ctx, `(${stored})`)}))
  ) then
    ${fail("INVITATION_ROLE_FORBIDDEN", "That role is above your own")}
  end if;
  if invitee_email is not null and exists (
    select 1 from ${m} m join auth.users u on u.id = m.${mu}
    where m.${mt} = tenant and lower(u.email) = lower(btrim(invitee_email))
  ) then
    ${fail("INVITATION_ALREADY_MEMBER", "% is already a member", "invitee_email")}
  end if;
  if invitee_email is not null then
    delete from ${t.table} i
    where i.${c("tenant")} = tenant
      and lower(i.${c("email")}) = lower(btrim(invitee_email))
      and i.${c("id")} <> invitation_id${open ? `\n      and ${open}` : ""};
  end if;
  ${write(t, "current_invite", "updated", stored)}
  ${ctx.emit({ type: "invitation.updated", payload: `jsonb_build_object('invitationId', updated.${c("id")}, 'organizationId', tenant::text, 'email', updated.${c("email")}, 'role', updated.${c("role")})`, subject: `'invitations/' || updated.${c("id")}::text`, tenant: "tenant" })}
  return ${inviteJson(ctx, t, "updated", "null", `updated.${c("tenant")}`)} - 'token';
end;
$$;
`;
}
