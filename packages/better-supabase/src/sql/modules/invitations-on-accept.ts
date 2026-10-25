import type { BlockSqlContext } from "../context.ts";
import type { InviteTable } from "./invitations-tables.ts";

import { isRecord } from "../../core/guards.ts";
import { sqlString } from "../../core/template.ts";
import { raise } from "./invitations-tables.ts";
import { manyRoles, membershipRolesTable } from "./membership-roles.ts";
import { accessModel, roleNames } from "./permissions-model.ts";
import { teamIdType } from "./teams.ts";

const WHERE = "blocks.invitations.options";

/** What `options.onAccept` grants next to the invitation's role. */
export interface OnAccept {
  readonly roles: boolean;
  readonly teams: boolean;
}

/**
 * `options.defaultRole`: the role `create_invitation` invites with when the
 * caller names none. Defaults to `member`; under the roles model it must be a
 * declared role.
 */
export function defaultRole(ctx: BlockSqlContext): string {
  const role = ctx.text("defaultRole", "member");
  const tenant = ctx.of("memberships");

  if (
    accessModel(ctx) === "roles" &&
    tenant.option("roleThrough") === undefined &&
    !roleNames(ctx).includes(role)
  ) {
    throw new TypeError(
      `${WHERE}.defaultRole: "${role}" is not one of blocks.permissions.roles (${roleNames(ctx).join(", ")})`,
    );
  }

  return role;
}

/** `options.onAccept`, validated against the installed modules. */
export function onAcceptOf(ctx: BlockSqlContext): OnAccept {
  const value = ctx.option("onAccept");

  if (value === undefined) {
    return { roles: false, teams: false };
  }

  if (
    !isRecord(value) ||
    Object.keys(value).some((key) => key !== "roles" && key !== "teams") ||
    Object.values(value).some((flag) => typeof flag !== "boolean")
  ) {
    throw new TypeError(
      `${WHERE}.onAccept must be { roles?: boolean, teams?: boolean }`,
    );
  }

  const roles = value["roles"] === true;
  const teams = value["teams"] === true;

  if (roles && !manyRoles(ctx.of("memberships"))) {
    throw new TypeError(
      `${WHERE}.onAccept.roles adds roles next to the invitation's role; turn on blocks.memberships.options.roles.many`,
    );
  }

  if (teams && !ctx.installed("teams")) {
    throw new TypeError(
      `${WHERE}.onAccept.teams adds the invitee to teams; install the teams block`,
    );
  }

  if ((roles || teams) && !ctx.manages) {
    throw new TypeError(
      `${WHERE}.onAccept stores its roles and teams on the block's invitations table; it can't run over an app's own table`,
    );
  }

  return { roles, teams };
}

const teamType = (ctx: BlockSqlContext): string => teamIdType(ctx.of("teams"));

/** The columns `onAccept` stores on the managed invitations table. */
export function onAcceptColumns(ctx: BlockSqlContext, t: InviteTable): string {
  const on = onAcceptOf(ctx);

  return `${on.roles ? `alter table ${t.table} add column if not exists "extra_roles" text[] not null default '{}';\n` : ""}${on.teams ? `alter table ${t.table} add column if not exists "team_ids" ${teamType(ctx)}[] not null default '{}';\n` : ""}`;
}

/** `invite_member`'s `on_accept` argument, present when `onAccept` is set. */
export function onAcceptParam(ctx: BlockSqlContext): {
  readonly param: string;
  readonly type: string;
} {
  const on = onAcceptOf(ctx);

  return on.roles || on.teams
    ? { param: ", on_accept jsonb default null", type: ", jsonb" }
    : { param: "", type: "" };
}

/**
 * Checks `on_accept` in `invite_member` and stores it on row `created`: every
 * role must be declared and within the caller's ceiling, every team in the
 * tenant.
 */
export function onAcceptInvite(ctx: BlockSqlContext, t: InviteTable): string {
  const on = onAcceptOf(ctx);

  if (!on.roles && !on.teams) {
    return "";
  }

  const keys = [...(on.roles ? ["roles"] : []), ...(on.teams ? ["teams"] : [])];
  const id = `created.${t.col("id")}`;

  const roles = on.roles
    ? `
      accept_roles := array(select jsonb_array_elements_text(coalesce(on_accept -> 'roles', '[]')));
      if exists (select 1 from unnest(accept_roles) r(role) where not (r.role = any (array[${roleNames(ctx).map(sqlString).join(", ")}]::text[]))) then
        ${raise("INVITATION_ROLE_UNKNOWN", "Unknown role in on_accept.roles")}
      end if;
      if not service and exists (select 1 from unnest(accept_roles) r(role) where not better_supabase.can_assign(tenant, r.role)) then
        ${raise("INVITATION_ROLE_FORBIDDEN", "A role in on_accept.roles is above your own")}
      end if;
      update ${t.table} set "extra_roles" = accept_roles where ${t.col("id")} = ${id};`
    : "";

  const teams = on.teams
    ? (() => {
        const teamsCtx = ctx.of("teams");
        const teamsTable = teamsCtx.table("teams");
        const teamId = teamsCtx.col("teams", "id");
        const teamTenant = teamsCtx.col("teams", "tenant");

        return `
      accept_teams := array(select (jsonb_array_elements_text(coalesce(on_accept -> 'teams', '[]')))::${teamType(ctx)});
      if exists (
        select 1 from unnest(accept_teams) x(id)
        where not exists (select 1 from ${teamsTable} tm where tm.${teamId} = x.id and tm.${teamTenant} = tenant)
      ) then
        ${raise("INVITATION_TEAM_UNKNOWN", "A team in on_accept.teams is not in this organization")}
      end if;
      update ${t.table} set "team_ids" = accept_teams where ${t.col("id")} = ${id};`;
      })()
    : "";

  return `
  if on_accept is not null then
    declare
      accept_roles text[];
      accept_teams ${on.teams ? `${teamType(ctx)}[]` : "text[]"};
    begin
      if jsonb_typeof(on_accept) <> 'object' or exists (
        select 1 from jsonb_object_keys(on_accept) k where k not in (${keys.map(sqlString).join(", ")})
      ) then
        ${raise("INVITATION_ON_ACCEPT_INVALID", `on_accept takes ${keys.join(" and ")}`)}
      end if;${roles}${teams}
    end;
  end if;`;
}

/**
 * Grants what `onAccept` stored on row `invite` once the member row for `me`
 * exists. A team deleted or moved since the invitation is skipped.
 */
export function onAcceptGrant(ctx: BlockSqlContext, t: InviteTable): string {
  const on = onAcceptOf(ctx);
  const tenant = `invite.${t.col("tenant")}`;
  let sql = "";

  if (on.roles) {
    const members = ctx.of("memberships");
    const mt = members.col("memberships", "tenant");
    const mu = members.col("memberships", "user");

    sql += `
  insert into ${membershipRolesTable(members)} (${mt}, ${mu}, "role")
  select ${tenant}, me, r.role from unnest(invite."extra_roles") r(role)
  on conflict do nothing;`;
  }

  if (on.teams) {
    const teams = ctx.of("teams");
    const tm = teams.table("members");

    sql += `
  insert into ${tm} (${teams.col("members", "team")}, ${teams.col("members", "user")}, ${teams.col("members", "tenant")})
  select x.id, me, ${tenant} from unnest(invite."team_ids") x(id)
  where exists (
    select 1 from ${teams.table("teams")} tt
    where tt.${teams.col("teams", "id")} = x.id and tt.${teams.col("teams", "tenant")} = ${tenant}
  )
  on conflict do nothing;`;
  }

  return sql;
}
