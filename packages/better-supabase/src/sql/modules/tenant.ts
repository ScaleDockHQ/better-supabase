import type { ActiveTenantSource } from "../../config/blocks.ts";
import type { BlockModuleDefinition } from "../blocks.ts";
import type { BlockContext } from "../context.ts";

import { DEFAULT_ACTIVE_TENANT } from "../../config/blocks.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  columnRef,
  disabledHelpers,
  disabledHelpersNeedLaterTables,
  jwtClaim,
  renameSql,
  schemaPreamble,
  updatedAt,
} from "../shared.ts";
import { accessModel, roleNames } from "./access-model.ts";

/** Expression for a membership row's role name, whatever the role column holds. */
export function roleNameOf(ctx: BlockContext, alias: string): string {
  const role = `${alias}.${ctx.col("memberships", "role")}`;
  if (accessModel(ctx) !== "catalog") return role;
  const access = ctx.of("access");
  return `(select r.${access.col("roles", "key")} from ${access.table("roles")} r where r.${access.col("roles", "id")} = ${role})`;
}

/** The active tenant: `blocks.access.activeTenant` (claim, resolver or profile column). */
function currentTenant(ctx: BlockContext): string {
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
-- the x-bs-tenant header over the Data API), then the \`${ctx.claims.tenant}\` claim.
-- A tenant the caller isn't a member of counts as none.`;
    requested = `coalesce(
    ${member(`nullif(current_setting('better_supabase.tenant', true), '')`)},
    ${member(`nullif(current_setting('request.headers', true)::jsonb ->> 'x-bs-tenant', '')`)},
    ${member(claim)}
  )`;
  } else {
    const profile = columnRef(
      "blocks.access.activeTenant.profileColumn",
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

/** `blocks.access.activeTenant`, defaulting to the resolver (URL tenancy). */
export function activeTenantSource(ctx: BlockContext): ActiveTenantSource {
  return ctx.blocks.access?.activeTenant ?? DEFAULT_ACTIVE_TENANT;
}

/**
 * With the claim source, removing a membership also clears the claim that
 * points at it, so the next token carries no tenant.
 */
function clearClaim(ctx: BlockContext): string {
  if (ctx.mode === "custom") return "";
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

function tenantSql(ctx: BlockContext): string {
  const id = ctx.idType;
  const m = ctx.table("memberships");
  const tenant = ctx.col("memberships", "tenant");
  const user = ctx.col("memberships", "user");
  const roleCol = ctx.col("memberships", "role");
  const createdAt = ctx.col("memberships", "createdAt");
  const role = roleNameOf(ctx, "m");
  const model = accessModel(ctx);
  const claimJson =
    ctx.text("claimFormat", "array") === "map"
      ? `coalesce(jsonb_object_agg(m.${tenant}::text, ${role}), '{}'::jsonb)`
      : `coalesce(jsonb_agg(jsonb_build_object(
      'scope', ${sqlString(ctx.claims.scope)},
      'id', m.${tenant},
      'roles', jsonb_build_array(${role})
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
${model === "catalog" ? `create index if not exists memberships_role_idx on ${m} (${roleCol});\n` : ""}${ctx.has("memberships", "updatedAt") ? `${updatedAt(m, ctx.col("memberships", "updatedAt"))}\n` : ""}${ctx.has("memberships", "lastUsedAt") ? `alter table ${m} add column if not exists ${ctx.col("memberships", "lastUsedAt")} timestamptz;\n` : ""}${
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
-- Adopted: ${m} belongs to the app (blocks.tenant.tables.memberships).
`;
  const policy = ctx.manages
    ? `
drop policy if exists bs_memberships_read on ${m};
create policy bs_memberships_read on ${m}
  for select to authenticated
  using (${user} = (select auth.uid()) or ${tenant} in (select better_supabase.member_organization_ids()));
`
    : "";
  // The catalog's roles table and the managed organizations table are in
  // files that sort after this one; the bodies are checked when they first
  // run instead.
  const deferBodies =
    model === "catalog" || disabledHelpersNeedLaterTables(ctx);
  return `${schemaPreamble(ctx)}
grant usage on schema better_supabase to supabase_auth_admin;
${deferBodies ? "set check_function_bodies = off;\n" : ""}${table}${disabledHelpers(ctx)}
${currentTenant(ctx)}

-- Policies compare against the set once per statement:
--   using (organization_id in (select better_supabase.member_organization_ids('{owner,admin}')))
-- has_organization_role(organization) answers for one organization, in functions and checks.
-- Prefer the access contract (better_supabase.can, tenant_ids_with) for
-- permission checks; these answer by role name.
create or replace function better_supabase.member_organization_ids(roles text[] default null)
returns setof ${id}
language sql
stable
security definer
set search_path = ''
as $$
  select m.${tenant}
  from ${m} m
  where m.${user} = (select auth.uid())
    and (member_organization_ids.roles is null or ${role} = any (member_organization_ids.roles))
    and not better_supabase.user_disabled(m.${user})
    and not better_supabase.tenant_disabled(m.${tenant})
$$;

create or replace function better_supabase.has_organization_role(organization ${id}, roles text[] default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from ${m} m
    where m.${tenant} = has_organization_role.organization
      and m.${user} = auth.uid()
      and (has_organization_role.roles is null or ${role} = any (has_organization_role.roles))
      and not better_supabase.user_disabled(m.${user})
      and not better_supabase.tenant_disabled(m.${tenant})
  )
$$;

-- The role of a user in a tenant, or null when they aren't a member.
create or replace function better_supabase.organization_member_role(organization ${id}, member uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select ${role} from ${m} m where m.${tenant} = organization_member_role.organization and m.${user} = organization_member_role.member
$$;
${policy}
revoke execute on function better_supabase.member_organization_ids(text[]) from public, anon;
revoke execute on function better_supabase.has_organization_role(${id}, text[]) from public, anon;
revoke execute on function better_supabase.organization_member_role(${id}, uuid) from public, anon, authenticated;
grant execute on function better_supabase.member_organization_ids(text[]) to authenticated, service_role;
grant execute on function better_supabase.has_organization_role(${id}, text[]) to authenticated, service_role;
grant execute on function better_supabase.organization_member_role(${id}, uuid) to service_role;

-- The memberships claim. \`claimFormat: 'array'\` (the default) is PermDock's
-- shape, [{ scope, id, roles }]; \`'map'\` is { [tenant id]: role }. With
-- PermDock, \`permdock supabase hook generate\` writes the hook instead.
-- Otherwise call it from your custom access token hook:
--   return jsonb_set(event, '{claims,memberships}',
--     better_supabase.membership_claims((event ->> 'user_id')::uuid));
-- Disabled users and tenants (blocks.access.disabled) are left out.
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
    and not better_supabase.tenant_disabled(m.${tenant})
$$;

revoke execute on function better_supabase.membership_claims(uuid) from public, anon, authenticated;
grant execute on function better_supabase.membership_claims(uuid) to service_role, supabase_auth_admin;${deferBodies ? "\nreset check_function_bodies;" : ""}`;
}

export const TENANT: BlockModuleDefinition = {
  name: "tenant",
  title: "Tenant memberships and permission helper",
  description:
    "Memberships with roles, member_organization_ids() and has_organization_role() for RLS policies, and membership_claims() for the access token hook. Adopt an existing memberships table through blocks.tenant.",
  requires: ["updated-at"],
  target: "schema",
  version: 2,
  modes: ["managed", "adopt", "custom"],
  names: {
    options: ["claimFormat"],
    tables: {
      memberships: {
        name: "memberships",
        columns: {
          tenant: "organization_id",
          user: "user_id",
          role: "role",
          createdAt: "created_at",
          updatedAt: "updated_at",
          lastUsedAt: "last_used_at",
        },
        optional: ["lastUsedAt", "updatedAt"],
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
        "Renames memberships.org_id to organization_id, adds memberships.updated_at, memberships.last_used_at and organization_member_role(); the role check follows blocks.access.roles.",
      sql: (ctx) =>
        ctx.manages
          ? renameSql({
              schema: ctx.tableName("memberships").schema,
              table: ctx.tableName("memberships").name,
              columns: [["org_id", "organization_id"]],
            })
          : "",
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
      use: "the claims.tenant claim (tenant_id)",
      since: "0.2.0",
      removed: "0.2.0",
    },
  ],
  build: tenantSql,
};
