import type { ActiveTenantSource } from "../../config/blocks.ts";
import type { BlockSqlContext } from "../context.ts";
import type { BlockSqlDefinition, BlockSqlLayout } from "../module-types.ts";

import { DEFAULT_ACTIVE_TENANT } from "../../config/blocks.ts";
import { fillTemplate } from "../../core/access-sql.ts";
import { isRecord } from "../../core/guards.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  activeMembership,
  columnRef,
  accessDefinesDisabledHelpers,
  disabledHelpers,
  disabledHelpersNeedLaterTables,
  jwtClaim,
  membershipDisabledAt,
  renameSql,
  schemaPreamble,
  updatedAt,
} from "../shared.ts";
import {
  holdsRole,
  manyRoles,
  memberRolesFunction,
  membershipRolesPolicy,
  membershipRolesSql,
  membershipRolesTable,
} from "./membership-roles.ts";
import {
  accessModel,
  providerPlatformRoles,
  roleNames,
} from "./permissions-model.ts";
import { sameTenantSql } from "./tenant-same.ts";

/**
 * `blocks.memberships.options.roleThrough`: the membership role column holds a
 * key of `table` (`id`), and the role name is that row's `column`.
 */
export interface RoleThrough {
  /** The quoted `schema.table`. */
  readonly table: string;
  readonly id: string;
  readonly column: string;
  /** The tenant column of tenant custom roles (null for shared roles), quoted. */
  readonly tenant?: string;
  /** A condition on the roles row `{row}` that holds for tenant roles only. */
  readonly where?: string;
}

/** The tenant module's `roleThrough` option, quoted; `undefined` when unset. */
export function roleThrough(tenant: BlockSqlContext): RoleThrough | undefined {
  const value = tenant.option("roleThrough");

  if (value === undefined) {
    return undefined;
  }

  const where = "blocks.memberships.options.roleThrough";

  if (
    !isRecord(value) ||
    typeof value["table"] !== "string" ||
    typeof value["id"] !== "string" ||
    typeof value["column"] !== "string" ||
    (value["tenant"] !== undefined && typeof value["tenant"] !== "string") ||
    (value["where"] !== undefined &&
      (typeof value["where"] !== "string" || !value["where"].includes("{row}")))
  ) {
    throw new TypeError(
      `${where} must be { table: "schema.table", id: "<key column>", column: "<role name column>", tenant?: "<tenant column>", where?: "<condition on {row}>" }`,
    );
  }

  if (tenant.owns("memberships")) {
    throw new TypeError(
      `${where} describes your own memberships table; the block's table stores role names. Declare the memberships table in your schema, or map it in blocks.memberships.tables.memberships.`,
    );
  }

  const ref = columnRef(`${where}.table`, `${value["table"]}.${value["id"]}`);
  const problem = sharedRolesProblem(tenant);

  if (problem) {
    throw new TypeError(problem);
  }

  return {
    table: ref.table,
    id: ref.column,
    column: columnRef(where, `${value["table"]}.${value["column"]}`).column,
    ...(typeof value["tenant"] === "string"
      ? {
          tenant: columnRef(where, `${value["table"]}.${value["tenant"]}`)
            .column,
        }
      : {}),
    ...(typeof value["where"] === "string" ? { where: value["where"] } : {}),
  };
}

/**
 * The quoted table of `blocks.memberships.options.roleThrough` and whether it
 * sets `where`; `undefined` when unset or malformed.
 */
export function roleThroughTable(
  tenant: BlockSqlContext,
): { readonly table: string; readonly where: boolean } | undefined {
  const value = tenant.option("roleThrough");

  if (
    !isRecord(value) ||
    typeof value["table"] !== "string" ||
    typeof value["id"] !== "string"
  ) {
    return undefined;
  }

  try {
    return {
      table: columnRef("roleThrough", `${value["table"]}.${value["id"]}`).table,
      where: value["where"] !== undefined,
    };
  } catch {
    return undefined;
  }
}

/**
 * Why `blocks.memberships.options.roleThrough` needs `where`: its table also
 * holds the platform roles of
 * `blocks.invitations.options.platformRoles.through`. `undefined` when it
 * doesn't.
 */
export function sharedRolesProblem(
  tenant: BlockSqlContext,
): string | undefined {
  const own = roleThroughTable(tenant);

  if (!own || own.where) {
    return undefined;
  }

  if (providerPlatformRoles(tenant)?.through?.table !== own.table) {
    return undefined;
  }

  return `blocks.memberships.options.roleThrough.where: ${own.table} also holds the platform roles (blocks.invitations.options.platformRoles.through), so name the tenant roles with a condition such as "{row}.scope = 'organization'". A roleThrough from the authorization provider's roleSources has no where; set blocks.memberships.options.roleThrough in the config.`;
}

/**
 * The `bsb_role_scope` trigger on the memberships table: with
 * `roleThrough.where`, every write (the service role's too) stores a role that
 * the condition names. Removed when `where` is unset.
 */
function roleScope(ctx: BlockSqlContext): string {
  if (ctx.owns("memberships")) {
    return "";
  }

  const m = ctx.table("memberships");
  const role = ctx.col("memberships", "role");
  const through = roleThrough(ctx);
  const fn = ctx.fn("membership_role_scope");

  if (!through?.where) {
    return `
drop trigger if exists ${ctx.trigger("role_scope")} on ${m};
drop function if exists ${fn}();
`;
  }

  return `
-- blocks.memberships.options.roleThrough.where names the tenant roles. Every
-- write to ${m} stores one of them, whoever writes it: a client policy, the
-- service role or an admin connection.
create or replace function ${fn}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.${role} is not null and not exists (
    select 1 from ${through.table} r
    where r.${through.id}::text = new.${role}::text and (${through.where.replaceAll("{row}", "r")})
  ) then
    raise exception 'Role % is not a tenant role', new.${role}
      using errcode = '23514', hint = 'MEMBERSHIP_ROLE_SCOPE';
  end if;
  return new;
end;
$$;
revoke execute on function ${fn}() from public, anon, authenticated;
drop trigger if exists ${ctx.trigger("role_scope")} on ${m};
create trigger ${ctx.trigger("role_scope")} before insert or update of ${role} on ${m}
  for each row execute function ${fn}();
`;
}

/** A stored role value (a key or a role id) as the role name. */
export function roleNameFrom(tenant: BlockSqlContext, value: string): string {
  const through = roleThrough(tenant);

  if (through) {
    return `(select r.${through.column}::text from ${through.table} r where r.${through.id}::text = (${value})::text)`;
  }

  if (accessModel(tenant) !== "catalog") {
    return value;
  }

  const access = tenant.of("permissions");

  return `(select r.${access.col("roles", "key")} from ${access.table("roles")} r where r.${access.col("roles", "id")} = ${value})`;
}

/** Expression for a membership row's role name, whatever the role column holds. */
export function roleNameOf(ctx: BlockSqlContext, alias: string): string {
  return roleNameFrom(ctx, `${alias}.${ctx.col("memberships", "role")}`);
}

/**
 * The active tenant: `blocks.permissions.activeTenant` (claim, resolver or
 * profile column).
 */
function currentTenant(ctx: BlockSqlContext): string {
  const id = ctx.idType;
  const m = ctx.table("memberships");
  const tenant = ctx.col("memberships", "tenant");
  const user = ctx.col("memberships", "user");
  const claim = `nullif(${jwtClaim(ctx.claims.tenant)}, '')`;
  const source = activeTenantSource(ctx);

  const member = (value: string): string =>
    `(select m.${tenant}::text from ${m} m where m.${tenant}::text = ${value} and m.${user} = auth.uid() limit 1)`;

  let requested: string;
  let comment: string;

  if (source === "claim") {
    comment = `-- The top-level \`${ctx.claims.tenant}\` claim (custom access token hook) or
-- \`app_metadata.${ctx.claims.tenant}\` (switch_organization), while the caller is
-- still a member: a token issued before a removal grants nothing. Never
-- user_metadata: users can write it.`;
    requested = member(claim);
  } else if (source === "resolver") {
    comment = `-- The tenant the server resolved (the better_supabase.tenant setting over Postgres,
-- the x-bsb-tenant header over the Data API), then the \`${ctx.claims.tenant}\` claim.
-- A tenant the caller isn't a member of counts as none.`;
    requested = `coalesce(
    ${member(`nullif(current_setting('better_supabase.tenant', true), '')`)},
    ${member(`nullif(current_setting('request.headers', true)::jsonb ->> 'x-bsb-tenant', '')`)},
    ${member(claim)}
  )`;
  } else {
    const profile = columnRef(
      "blocks.permissions.activeTenant.profileColumn",
      source.profileColumn,
    );

    const key = sqlIdent(source.key ?? "id");
    comment = `-- The \`${ctx.claims.tenant}\` claim, then ${source.profileColumn}, while the
-- caller is still a member.`;
    requested = `coalesce(
    ${member(claim)},
    ${member(`(select p.${profile.column}::text from ${profile.table} p where p.${key} = auth.uid())`)}
  )`;
  }

  return `
${comment}
create or replace function better_supabase.current_tenant_id()
returns ${id}
language sql
stable
security definer
set search_path = ''
as $$
  select ${requested}::${id}
$$;
revoke execute on function better_supabase.current_tenant_id() from public;
grant execute on function better_supabase.current_tenant_id() to anon, authenticated, service_role, supabase_auth_admin;${source === "claim" ? clearClaim(ctx) : ""}`;
}

/** `blocks.permissions.activeTenant`, defaulting to the resolver (URL tenancy). */
export function activeTenantSource(ctx: BlockSqlContext): ActiveTenantSource {
  return ctx.modules.permissions?.activeTenant ?? DEFAULT_ACTIVE_TENANT;
}

/**
 * With the claim source, removing a membership also clears the claim that
 * points at it, so the next token carries no tenant.
 */
function clearClaim(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const m = ctx.table("memberships");
  const tenant = ctx.col("memberships", "tenant");
  const user = ctx.col("memberships", "user");
  const key = sqlString(ctx.claims.tenant);

  return `

create or replace function better_supabase.clear_tenant_claim()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update auth.users u
  set raw_app_meta_data = u.raw_app_meta_data - ${key}
  where u.id = old.${user}
    and u.raw_app_meta_data ->> ${key} = old.${tenant}::text;
  return null;
end;
$$;
revoke execute on function better_supabase.clear_tenant_claim() from public, anon, authenticated;
drop trigger if exists ${ctx.trigger("clear_tenant_claim")} on ${m};
create trigger ${ctx.trigger("clear_tenant_claim")} after delete on ${m}
  for each row execute function better_supabase.clear_tenant_claim();`;
}

/**
 * The provider's `memberIds` and `memberIdsFor` templates under the provider
 * access model: the role helpers then answer membership from the provider, and
 * the memberships table only names roles.
 */
export function providerMembers(
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
): { readonly ids?: string; readonly idsFor?: (user: string) => string } {
  const provider =
    accessModel(ctx) === "provider" ? layout.accessProvider : undefined;

  if (provider === undefined) {
    return {};
  }

  const { memberIds, memberIdsFor } = provider.functions;

  return {
    ...(memberIds === undefined
      ? {}
      : {
          ids: fillTemplate("authorization.functions.memberIds", memberIds, {
            scope: provider.scope,
          }),
        }),
    ...(memberIdsFor === undefined
      ? {}
      : {
          idsFor: (user: string) =>
            fillTemplate("authorization.functions.memberIdsFor", memberIdsFor, {
              scope: provider.scope,
              user,
            }),
        }),
  };
}

function tenantSql(ctx: BlockSqlContext, layout: BlockSqlLayout): string {
  const id = ctx.idType;
  const m = ctx.table("memberships");
  const tenant = ctx.col("memberships", "tenant");
  const user = ctx.col("memberships", "user");
  const roleCol = ctx.col("memberships", "role");
  const createdAt = ctx.col("memberships", "createdAt");
  const role = roleNameOf(ctx, "m");
  const model = accessModel(ctx);
  const active = activeMembership(ctx, "m");
  const disabledAt = membershipDisabledAt(ctx);
  const members = providerMembers(ctx, layout);

  const inProvider = (column: string): string =>
    members.ids === undefined
      ? ""
      : `\n    and ${column} in (select p.id from ${members.ids} as p(id))`;

  const memberIdsBody =
    members.ids === undefined
      ? `  select m.${tenant}
  from ${m} m
  where m.${user} = (select auth.uid())
    and (member_organization_ids.roles is null or ${holdsRole(ctx, "m", "member_organization_ids.roles", role)})
    and not better_supabase.user_disabled(m.${user})
    and not better_supabase.tenant_disabled(m.${tenant})${active}`
      : `  select p.id
  from ${members.ids} as p(id)
  where member_organization_ids.roles is null
    and not better_supabase.user_disabled((select auth.uid()))
    and not better_supabase.tenant_disabled(p.id)
  union
  select m.${tenant}
  from ${m} m
  where member_organization_ids.roles is not null
    and m.${user} = (select auth.uid())
    and ${holdsRole(ctx, "m", "member_organization_ids.roles", role)}
    and not better_supabase.user_disabled(m.${user})
    and not better_supabase.tenant_disabled(m.${tenant})${active}${inProvider(`m.${tenant}`)}`;

  const hasRoleBody =
    members.ids === undefined
      ? `  select exists (
    select 1
    from ${m} m
    where m.${tenant} = has_organization_role.organization
      and m.${user} = auth.uid()
      and (has_organization_role.roles is null or ${holdsRole(ctx, "m", "has_organization_role.roles", role)})
      and not better_supabase.user_disabled(m.${user})
      and not better_supabase.tenant_disabled(m.${tenant})${active}
  )`
      : `  select has_organization_role.organization in (
    select ${ctx.fn("member_organization_ids")}(has_organization_role.roles)
  )`;

  const memberRoleFilter = `${active}${
    members.idsFor === undefined
      ? ""
      : ` and m.${tenant} in (select p.id from ${members.idsFor("organization_member_role.member")} as p(id))`
  }`;

  const many = manyRoles(ctx);

  const roleSet = many
    ? `(select coalesce(jsonb_agg(r."role" order by r."role"), '[]'::jsonb) from ${membershipRolesTable(ctx)} r where r.${tenant} = m.${tenant} and r.${user} = m.${user})`
    : `jsonb_build_array(${role})`;

  const claimJson =
    ctx.text("claimFormat", "array") === "map"
      ? `coalesce(jsonb_object_agg(m.${tenant}::text, ${many ? roleSet : role}), '{}'::jsonb)`
      : `coalesce(jsonb_agg(jsonb_build_object(
      'scope', ${sqlString(ctx.claims.scope)},
      'id', m.${tenant},
      'roles', ${roleSet}
    ) order by m.${createdAt}, m.${tenant}), '[]'::jsonb)`;

  const table = ctx.manages
    ? `
create table if not exists ${m} (
  ${tenant} ${id} not null,
  ${user} uuid not null references auth.users (id) on delete cascade,
  ${roleCol} ${model === "catalog" ? "uuid not null" : "text not null default 'member'"},
  ${createdAt} timestamptz not null default now(),
  primary key (${tenant}, ${user})
);
create index if not exists memberships_user_idx on ${m} (${user});
${model === "catalog" ? `create index if not exists memberships_role_idx on ${m} (${roleCol});\n` : ""}${ctx.has("memberships", "updatedAt") ? `${updatedAt(m, ctx.col("memberships", "updatedAt"))}\n` : ""}${ctx.has("memberships", "lastUsedAt") ? `alter table ${m} add column if not exists ${ctx.col("memberships", "lastUsedAt")} timestamptz;\n` : ""}${disabledAt === undefined ? "" : `alter table ${m} add column if not exists ${disabledAt} timestamptz;\n`}${
        model === "catalog"
          ? ""
          : `alter table ${m} drop constraint if exists memberships_role_check;
alter table ${m}
  add constraint memberships_role_check check (${roleCol} in (${roleNames(ctx).map(sqlString).join(", ")}));
`
      }
alter table ${m} enable row level security;
grant select on ${m} to authenticated;
grant all on ${m} to service_role;
`
    : `
-- Adopted: ${m} belongs to the app (blocks.memberships.tables.memberships).
`;

  const policy = ctx.manages
    ? `
drop policy if exists bsb_memberships_read on ${m};
create policy bsb_memberships_read on ${m}
  for select to authenticated
  using (${user} = (select auth.uid()) or ${tenant} in (select ${ctx.scope.members()}));
`
    : "";

  // The access module defines tenant_disabled and user_disabled when it is
  // installed. Its file, the catalog's roles table and the managed
  // organizations table sort after this one; the bodies are checked when
  // they first run instead.
  const accessHelpers = accessDefinesDisabledHelpers(ctx);

  const deferBodies =
    model === "catalog" || accessHelpers || disabledHelpersNeedLaterTables(ctx);

  return `${schemaPreamble(ctx)}
grant usage on schema better_supabase to supabase_auth_admin;
${deferBodies ? "set check_function_bodies = off;\n" : ""}${table}${membershipRolesSql(ctx)}${roleScope(ctx)}${sameTenantSql(ctx, layout)}${accessHelpers ? "" : disabledHelpers(ctx)}
${currentTenant(ctx)}

-- Policies compare against the set once per statement:
--   using (organization_id in (select better_supabase.member_organization_ids('{owner,admin}')))
-- has_organization_role(organization) answers for one organization, in functions and checks.
-- Prefer the access contract (better_supabase.can, tenant_ids_with) for
-- permission checks; these answer by role name.${
    members.ids === undefined
      ? ""
      : `
-- Under the authorization provider, membership comes from its memberIds;
-- the memberships table only names roles.`
  }
create or replace function ${ctx.fn("member_organization_ids")}(roles text[] default null)
returns setof ${id}
language sql
rows 1
stable
security definer
set search_path = ''
as $$
${memberIdsBody}
$$;

create or replace function ${ctx.fn("has_organization_role")}(organization ${id}, roles text[] default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
${hasRoleBody}
$$;

-- The role of a user in a tenant, or null when they aren't a member.
create or replace function ${ctx.fn("organization_member_role")}(organization ${id}, member uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select ${role} from ${m} m where m.${tenant} = organization_member_role.organization and m.${user} = organization_member_role.member${memberRoleFilter}
$$;
${memberRolesFunction(ctx, role, memberRoleFilter.replaceAll("organization_member_role.member", "organization_member_roles.member"))}${policy}${membershipRolesPolicy(ctx)}
revoke execute on function ${ctx.fn("member_organization_ids")}(text[]) from public, anon;
revoke execute on function ${ctx.fn("has_organization_role")}(${id}, text[]) from public, anon;
revoke execute on function ${ctx.fn("organization_member_role")}(${id}, uuid) from public, anon, authenticated;
grant execute on function ${ctx.fn("member_organization_ids")}(text[]) to authenticated, service_role;
grant execute on function ${ctx.fn("has_organization_role")}(${id}, text[]) to authenticated, service_role;
grant execute on function ${ctx.fn("organization_member_role")}(${id}, uuid) to service_role;

-- The memberships claim. \`claimFormat: 'array'\` (the default) is
-- [{ scope, id, roles }]; \`'map'\` is { [tenant id]: role }. When an
-- authorization provider's hook writes this claim, use its hook instead.
-- Otherwise call it from your custom access token hook:
--   return jsonb_set(event, '{claims,memberships}',
--     better_supabase.membership_claims((event ->> 'user_id')::uuid));
-- Disabled users and tenants (blocks.permissions.disabled) are left out.
create or replace function better_supabase.membership_claims(user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select ${claimJson}
  from ${m} m
  where m.${user} = membership_claims.user_id
    and not better_supabase.user_disabled(membership_claims.user_id)
    and not better_supabase.tenant_disabled(m.${tenant})${active}
$$;

revoke execute on function better_supabase.membership_claims(uuid) from public, anon, authenticated;
grant execute on function better_supabase.membership_claims(uuid) to service_role, supabase_auth_admin;${deferBodies ? "\nreset check_function_bodies;" : ""}`;
}

export const TENANT: BlockSqlDefinition = {
  name: "memberships",
  title: "Tenant memberships and permission helper",
  description:
    "Memberships with roles, member_organization_ids() and has_organization_role() for RLS policies, and membership_claims() for the access token hook. Adopt an existing memberships table through blocks.memberships.",
  requires: ["updated-at"],
  integrates: ["permissions", "invitations", "organizations"],
  target: "schema",
  version: 3,
  modes: ["managed", "custom"],
  names: {
    options: ["claimFormat", "roleThrough", "sameTenant", "roles"],
    entities: { organization: { singular: "organization", global: true } },
    tables: {
      memberships: {
        name: "memberships",
        app: {
          unused: (ctx) =>
            membershipDisabledAt(ctx) === undefined ? ["disabledAt"] : [],
        },
        lifecycle: { user: "user", tenant: "tenant" },
        columns: {
          tenant: "organization_id",
          user: "user_id",
          role: "role",
          createdAt: "created_at",
          updatedAt: "updated_at",
          lastUsedAt: "last_used_at",
          disabledAt: "disabled_at",
        },
        optional: ["lastUsedAt", "updatedAt", "disabledAt"],
      },
    },
  },
  contract: () => [
    { name: "current_tenant_id", args: [], returns: "{id}" },
    { name: "member_organization_ids", args: ["text[]"], returns: "{id}" },
    {
      name: "has_organization_role",
      args: ["{id}", "text[]"],
      returns: "boolean",
    },
    {
      name: "organization_member_role",
      args: ["{id}", "uuid"],
      returns: "text",
    },
    { name: "membership_claims", args: ["uuid"], returns: "jsonb" },
  ],
  upgrades: [
    {
      from: 1,
      description:
        "Renames memberships.org_id to organization_id, adds memberships.updated_at, memberships.last_used_at and organization_member_role(); the role check follows blocks.permissions.roles.",
      sql: (ctx) =>
        ctx.owns("memberships")
          ? renameSql({
              schema: ctx.tableName("memberships").schema,
              table: ctx.tableName("memberships").name,
              columns: [["org_id", "organization_id"]],
            })
          : "",
    },
    {
      from: 2,
      description:
        "Adds organization_member_roles(), and with blocks.memberships.options.roles.many the membership_roles table, filled from each membership's role.",
      sql: () => "",
    },
  ],
  deprecated: [
    {
      kind: "column",
      symbol: "memberships.org_id",
      use: "memberships.organization_id",
      since: "0.5.0",
      removed: "0.5.0",
    },
    {
      kind: "function",
      symbol: "better_supabase.current_org_id",
      use: "better_supabase.current_tenant_id()",
      since: "0.2.0",
      removed: "0.2.0",
    },
    {
      kind: "claim",
      symbol: "org_id",
      use: "the auth.organization.claim claim (tenant_id)",
      since: "0.2.0",
      removed: "0.2.0",
    },
  ],
  build: tenantSql,
};
