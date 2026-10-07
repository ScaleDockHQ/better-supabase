import type { ModuleContext } from "../context.ts";
import type { ModuleLayout, ModuleDefinition } from "../registry.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  addForeignKey,
  disabledHelpers,
  disabledHelpersNeedLaterTables,
  ensureCheck,
  schemaPreamble,
} from "../shared.ts";
import {
  accessModel,
  hasPlatformRoles,
  roleScopeIs,
  rolesOf,
  tenantScope,
} from "./access-model.ts";
import { roleNameOf } from "./tenant.ts";

const SERVICE = `coalesce(auth.jwt() ->> 'role', '') = 'service_role'`;

// A token with an `act` claim (a support session) acts as its subject, so it
// never carries the subject's platform permissions.
const NOT_ACTING = `(platform_can.member is distinct from auth.uid() or auth.jwt() -> 'act' is null)`;

/** Fills `{name}` placeholders of a `sql.modules.access.functions` template. */
function fill(
  template: string,
  values: Readonly<Record<string, string>>,
): string {
  return template.replaceAll(/\{(\w+)\}/g, (match, name: string) => {
    const value = values[name];
    if (value === undefined) {
      throw new TypeError(
        `sql.modules.access.functions: ${match} is not available here. Use ${Object.keys(
          values,
        )
          .map((key) => `{${key}}`)
          .join(", ")}`,
      );
    }
    return value;
  });
}

interface Names {
  readonly m: string;
  readonly tenant: string;
  readonly user: string;
  readonly role: string;
}

function membershipNames(ctx: ModuleContext): Names {
  const tenant = ctx.of("tenant");
  return {
    m: tenant.table("memberships"),
    tenant: tenant.col("memberships", "tenant"),
    user: tenant.col("memberships", "user"),
    role: tenant.col("memberships", "role"),
  };
}

/** Whether membership row `m` grants catalog permission row `p`: deny beats grant beats the role default. */
function catalogEffective(ctx: ModuleContext, n: Names): string {
  const rp = ctx.table("rolePermissions");
  const fallback = `exists (select 1 from ${rp} rp where rp.${ctx.col("rolePermissions", "role")} = m.${n.role} and rp.${ctx.col("rolePermissions", "permission")} = p.${ctx.col("permissions", "id")})`;
  if (!ctx.hasTable("overrides")) return fallback;
  const o = ctx.table("overrides");
  return `coalesce(
      (select bool_and(o.${ctx.col("overrides", "granted")}) from ${o} o
        where o.${ctx.col("overrides", "tenant")} = m.${n.tenant}
          and o.${ctx.col("overrides", "role")} = m.${n.role}
          and o.${ctx.col("overrides", "permission")} = p.${ctx.col("permissions", "id")}),
      ${fallback}
    )`;
}

/** Whether membership row `m` grants `permission` (an SQL expression). */
function grants(ctx: ModuleContext, n: Names, permission: string): string {
  if (accessModel(ctx) === "roles") {
    return `better_supabase.role_grants(${roleNameOf(ctx.of("tenant"), "m")}, ${permission})`;
  }
  return `exists (select 1 from ${ctx.table("permissions")} p where p.${ctx.col("permissions", "key")} = ${permission} and ${catalogEffective(ctx, n)})`;
}

function platformClaim(ctx: ModuleContext, member: string, permission: string) {
  const claim = sqlString(
    ctx.modules.access?.platformClaim ?? "platform_permissions",
  );
  return `(${member} = auth.uid() and exists (
    select 1
    from jsonb_array_elements_text(
      case when jsonb_typeof(coalesce(auth.jwt() -> ${claim}, auth.jwt() -> 'app_metadata' -> ${claim})) = 'array'
        then coalesce(auth.jwt() -> ${claim}, auth.jwt() -> 'app_metadata' -> ${claim})
        else '[]'::jsonb end
    ) g(key)
    where better_supabase.permission_matches(g.key, ${permission})
  ))`;
}

function rolesFunctions(ctx: ModuleContext): string {
  const roles = Object.entries(rolesOf(ctx));
  const cases =
    roles.length === 0
      ? "'{}'::text[]"
      : `case role
    ${roles.map(([role, keys]) => `when ${sqlString(role)} then array[${keys.map(sqlString).join(", ")}]::text[]`).join("\n    ")}
    else '{}'::text[]
  end`;
  return `
-- The roles model (modules.access.roles): each role's permission keys.
create or replace function better_supabase.role_permissions(role text)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select ${cases}
$$;

create or replace function better_supabase.role_grants(role text, permission text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select exists (
    select 1 from unnest(better_supabase.role_permissions(role)) g(key)
    where better_supabase.permission_matches(g.key, permission)
  )
$$;
revoke execute on function better_supabase.role_permissions(text) from public, anon, authenticated;
revoke execute on function better_supabase.role_grants(text, text) from public, anon, authenticated;
grant execute on function better_supabase.role_permissions(text) to service_role, supabase_auth_admin;
grant execute on function better_supabase.role_grants(text, text) to service_role, supabase_auth_admin;`;
}

function catalogTables(ctx: ModuleContext): string {
  if (!ctx.manages) {
    return `
-- Adopted catalog: ${[
      "roles",
      "permissions",
      "rolePermissions",
      "overrides",
      "platformAssignments",
    ]
      .filter((table) => ctx.hasTable(table))
      .map((table) => ctx.table(table))
      .join(", ")}.`;
  }
  const id = ctx.idType;
  return `
create table if not exists ${ctx.table("roles")} (
  ${ctx.col("roles", "id")} uuid primary key default gen_random_uuid(),
  ${ctx.col("roles", "key")} text not null unique
);
-- A tenant role goes in memberships, a platform role in platform assignments.
alter table ${ctx.table("roles")} add column if not exists ${ctx.col("roles", "scope")} text not null default 'tenant';
${ensureCheck(ctx.table("roles"), "roles_scope_check", `${ctx.col("roles", "scope")} in ('tenant', 'platform')`)}
create table if not exists ${ctx.table("permissions")} (
  ${ctx.col("permissions", "id")} uuid primary key default gen_random_uuid(),
  ${ctx.col("permissions", "key")} text not null unique
);
create table if not exists ${ctx.table("rolePermissions")} (
  ${ctx.col("rolePermissions", "role")} uuid not null references ${ctx.table("roles")} on delete cascade,
  ${ctx.col("rolePermissions", "permission")} uuid not null references ${ctx.table("permissions")} on delete cascade,
  primary key (${ctx.col("rolePermissions", "role")}, ${ctx.col("rolePermissions", "permission")})
);
create index if not exists role_permissions_permission_idx on ${ctx.table("rolePermissions")} (${ctx.col("rolePermissions", "permission")});
${
  ctx.hasTable("overrides")
    ? `create table if not exists ${ctx.table("overrides")} (
  ${ctx.col("overrides", "tenant")} ${id} not null,
  ${ctx.col("overrides", "role")} uuid not null references ${ctx.table("roles")} on delete cascade,
  ${ctx.col("overrides", "permission")} uuid not null references ${ctx.table("permissions")} on delete cascade,
  ${ctx.col("overrides", "granted")} boolean not null,
  primary key (${ctx.col("overrides", "tenant")}, ${ctx.col("overrides", "role")}, ${ctx.col("overrides", "permission")})
);
create index if not exists permission_overrides_role_idx on ${ctx.table("overrides")} (${ctx.col("overrides", "role")});
create index if not exists permission_overrides_permission_idx on ${ctx.table("overrides")} (${ctx.col("overrides", "permission")});`
    : ""
}
${
  ctx.hasTable("platformAssignments")
    ? `create table if not exists ${ctx.table("platformAssignments")} (
  ${ctx.col("platformAssignments", "user")} uuid not null references auth.users (id) on delete cascade,
  ${ctx.col("platformAssignments", "role")} uuid not null references ${ctx.table("roles")} on delete cascade,
  primary key (${ctx.col("platformAssignments", "user")}, ${ctx.col("platformAssignments", "role")})
);
create index if not exists platform_roles_role_idx on ${ctx.table("platformAssignments")} (${ctx.col("platformAssignments", "role")});`
    : ""
}
do $$
declare
  t text;
begin
  foreach t in array array[${[
    "roles",
    "permissions",
    "rolePermissions",
    "overrides",
    "platformAssignments",
  ]
    .filter((table) => ctx.hasTable(table))
    .map((table) => sqlString(ctx.table(table)))
    .join(", ")}] loop
    execute format('alter table %s enable row level security', t);
    execute format('revoke all on %s from anon, authenticated', t);
    execute format('grant all on %s to service_role', t);
  end loop;
end;
$$;${membershipRoleKey(ctx)}`;
}

/** A catalog role can't be deleted while a membership still holds it. */
function membershipRoleKey(ctx: ModuleContext): string {
  const tenant = ctx.of("tenant");
  if (!tenant.manages) return "";
  return `
${addForeignKey({
  table: tenant.table("memberships"),
  name: "memberships_role_fkey",
  column: tenant.col("memberships", "role"),
  references: `${ctx.table("roles")} (${ctx.col("roles", "id")})`,
  onDelete: "restrict",
})}`;
}

/** `member_can`, `member_permissions` and `platform_can` for the roles and catalog models. */
function membershipFunctions(ctx: ModuleContext): string {
  const id = ctx.idType;
  const n = membershipNames(ctx);
  const model = accessModel(ctx);
  const permissions =
    model === "roles"
      ? `select coalesce((
      select better_supabase.role_permissions(${roleNameOf(ctx.of("tenant"), "m")}) from ${n.m} m
      where m.${n.tenant} = member_permissions.tenant and m.${n.user} = member_permissions.member
    ), '{}'::text[])`
      : `select coalesce(array_agg(p.${ctx.col("permissions", "key")} order by p.${ctx.col("permissions", "key")}), '{}'::text[])
    from ${ctx.table("permissions")} p
    where exists (
      select 1 from ${n.m} m
      where m.${n.tenant} = member_permissions.tenant and m.${n.user} = member_permissions.member
        and ${catalogEffective(ctx, n)}
    )`;
  // The catalog role's keys in this tenant, overrides included: the same
  // rule member_can applies to a member holding the role.
  const roleKeys =
    model === "roles"
      ? "select 1 from unnest(better_supabase.role_permissions(can_assign_as.role)) k(key) where true"
      : `select 1
        from (
          select r.${ctx.col("roles", "id")} as ${n.role}, can_assign_as.tenant as ${n.tenant}
          from ${ctx.table("roles")} r
          where r.${ctx.col("roles", "id")}::text = can_assign_as.role
        ) m
        cross join ${ctx.table("permissions")} p
        cross join lateral (select p.${ctx.col("permissions", "key")} as key) k
        where ${catalogEffective(ctx, n)}`;
  const tenantRole = roleScopeIs(ctx, "r", "tenant");
  const scoped = tenantRole
    ? `
      and exists (
        select 1 from ${ctx.table("roles")} r
        where r.${ctx.col("roles", "id")}::text = can_assign_as.role and ${tenantRole}
      )`
    : "";
  let platform = platformClaim(
    ctx,
    "platform_can.member",
    "platform_can.permission",
  );
  if (model === "catalog" && ctx.hasTable("platformAssignments")) {
    platform = `exists (
    select 1
    from ${ctx.table("platformAssignments")} a
    join ${ctx.table("rolePermissions")} rp on rp.${ctx.col("rolePermissions", "role")} = a.${ctx.col("platformAssignments", "role")}
    join ${ctx.table("permissions")} p on p.${ctx.col("permissions", "id")} = rp.${ctx.col("rolePermissions", "permission")}
    where a.${ctx.col("platformAssignments", "user")} = platform_can.member
      and p.${ctx.col("permissions", "key")} = platform_can.permission
  ) or ${platform}`;
  }
  return `
create or replace function better_supabase.member_can(member uuid, tenant ${id}, permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select member is not null
    and not better_supabase.user_disabled(member)
    and not better_supabase.tenant_disabled(tenant)
    and exists (
      select 1 from ${n.m} m
      where m.${n.tenant} = member_can.tenant and m.${n.user} = member_can.member
        and ${grants(ctx, n, "member_can.permission")}
    )
$$;

-- The permission keys a member holds in a tenant${model === "roles" ? " (wildcards as configured)" : ""}.
create or replace function better_supabase.member_permissions(member uuid, tenant ${id})
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  ${permissions}
$$;

create or replace function better_supabase.platform_can(member uuid, permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select member is not null
    and ${NOT_ACTING}
    and not better_supabase.user_disabled(member)
    and (${platform})
$$;

create or replace function better_supabase.tenant_ids_with(permission text)
returns setof ${id}
language sql
rows 1
stable
security definer
set search_path = ''
as $$
  select m.${n.tenant}
  from ${n.m} m
  where m.${n.user} = (select auth.uid())
    and not better_supabase.user_disabled(auth.uid())
    and not better_supabase.tenant_disabled(m.${n.tenant})
    and ${grants(ctx, n, "tenant_ids_with.permission")}
$$;

-- Members assign roles up to their own permissions: every key the role
-- grants must be one the member holds in the tenant.
create or replace function better_supabase.can_assign_as(member uuid, tenant ${id}, role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select member is not null
    and exists (
      select 1 from ${n.m} m
      where m.${n.tenant} = can_assign_as.tenant and m.${n.user} = can_assign_as.member
    )${scoped}
    and not exists (
      ${roleKeys}
        and not coalesce(better_supabase.member_can(can_assign_as.member, can_assign_as.tenant, k.key), false)
    )
$$;

create or replace function better_supabase.can_assign(tenant ${id}, role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select ${SERVICE} or better_supabase.can_assign_as(auth.uid(), can_assign.tenant, can_assign.role)
$$;
${platformCanAssign(ctx)}

create or replace function better_supabase.permission_claims(user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(m.${n.tenant}::text, to_jsonb(better_supabase.member_permissions(m.${n.user}, m.${n.tenant}))), '{}'::jsonb)
  from ${n.m} m
  where m.${n.user} = permission_claims.user_id
    and not better_supabase.user_disabled(permission_claims.user_id)
    and not better_supabase.tenant_disabled(m.${n.tenant})
$$;`;
}

/** `platform_can_assign(member, role)`: the platform role ceiling. */
function platformCanAssign(ctx: ModuleContext): string {
  if (!hasPlatformRoles(ctx)) return "";
  const platformRole = roleScopeIs(ctx, "r", "platform");
  return `
-- A platform role is assignable by a member who holds every key it grants.
create or replace function better_supabase.platform_can_assign(member uuid, role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select member is not null
    and exists (
      select 1 from ${ctx.table("roles")} r
      where r.${ctx.col("roles", "id")}::text = platform_can_assign.role${platformRole ? ` and ${platformRole}` : ""}
    )
    and not exists (
      select 1
      from ${ctx.table("rolePermissions")} rp
      join ${ctx.table("permissions")} p on p.${ctx.col("permissions", "id")} = rp.${ctx.col("rolePermissions", "permission")}
      where rp.${ctx.col("rolePermissions", "role")}::text = platform_can_assign.role
        and not coalesce(better_supabase.platform_can(platform_can_assign.member, p.${ctx.col("permissions", "key")}), false)
    )
$$;
revoke execute on function better_supabase.platform_can_assign(uuid, text) from public, anon, authenticated;
grant execute on function better_supabase.platform_can_assign(uuid, text) to service_role;`;
}

function permdockCanAssign(ctx: ModuleContext): string {
  const template = ctx.modules.access?.functions?.canAssign;
  if (template) {
    return fill(template, {
      tenant: "can_assign.tenant",
      role: "can_assign.role",
    });
  }
  if (!ctx.installed("tenant")) return "false";
  const owner = sqlString(ctx.of("organizations").text("ownerRole", "owner"));
  return `can_assign.role <> ${owner} or better_supabase.has_organization_role(can_assign.tenant, array[${owner}])`;
}

/**
 * PermDock's schema and scope for the `permdock` model: from the manifest
 * (`layout.accessPermdock`, which `sql add` reads), else both set in
 * `sql.modules.access.permdock`. Never a default, so a project whose helpers live
 * elsewhere never gets functions that call helpers that don't exist.
 */
/**
 * PermDock's helpers for a named user: those the manifest lists, or all of
 * them with `sql.modules.access.permdock.forUser`.
 */
export function permdockForUser(
  ctx: ModuleContext,
  layout: ModuleLayout,
): {
  readonly has: boolean;
  readonly permitted: boolean;
  readonly canAssign: boolean;
  readonly canAssignAny: boolean;
} {
  if (ctx.modules.access?.permdock?.forUser) {
    return { has: true, permitted: true, canAssign: true, canAssignAny: false };
  }
  const manifest = layout.accessPermdock?.forUser;
  return {
    has: manifest?.has ?? false,
    permitted: manifest?.permitted ?? false,
    canAssign: manifest?.canAssign ?? false,
    canAssignAny: manifest?.canAssignAny ?? false,
  };
}

/**
 * The body of `can_assign_as(member, tenant, role)` under the permdock and
 * custom models: `sql.modules.access.functions.canAssignFor`, else
 * PermDock's `permdock_can_assign_any_for` (declared and custom roles) or
 * `permdock_can_assign_for` when the manifest lists them. Undefined when
 * there is none, so nothing can check a stored user's authority.
 */
function assignAsCheck(
  ctx: ModuleContext,
  layout: ModuleLayout,
): string | undefined {
  const template = ctx.modules.access?.functions?.canAssignFor;
  if (template) {
    return fill(template, {
      user: "can_assign_as.member",
      tenant: "can_assign_as.tenant",
      role: "can_assign_as.role",
    });
  }
  if (accessModel(ctx) !== "permdock") return undefined;
  const forUser = permdockForUser(ctx, layout);
  const schema = sqlIdent(permdockTarget(ctx, layout).schema);
  if (forUser.canAssignAny) {
    return `${schema}.permdock_can_assign_any_for(can_assign_as.member, can_assign_as.role, can_assign_as.tenant, ${sqlString(permdockTarget(ctx, layout).scope)}, can_assign_as.tenant::text)`;
  }
  return forUser.canAssign
    ? `${schema}.permdock_can_assign_for(can_assign_as.member, can_assign_as.role, can_assign_as.tenant::text)`
    : undefined;
}

/** Whether `can_assign_as` exists for this access model and layout. */
export function hasCanAssignAs(
  ctx: ModuleContext,
  layout: ModuleLayout,
): boolean {
  const model = accessModel(ctx);
  return (
    model === "roles" ||
    model === "catalog" ||
    assignAsCheck(ctx.of("access"), layout) !== undefined
  );
}

/** `can_assign_as` for the permdock and custom models, when it has a body. */
function assignAsFunction(ctx: ModuleContext, layout: ModuleLayout): string {
  const check = assignAsCheck(ctx, layout);
  if (check === undefined) return "";
  return `

-- Whether member may assign role in tenant, for trusted SQL that acts later
-- for a stored user, such as accepting an invitation the inviter sent.
create or replace function better_supabase.can_assign_as(member uuid, tenant ${ctx.idType}, role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select member is not null
    and not better_supabase.user_disabled(member)
    and coalesce((${check}), false)
$$;
revoke execute on function better_supabase.can_assign_as(uuid, ${ctx.idType}, text) from public, anon, authenticated;`;
}

function permdockTarget(
  ctx: ModuleContext,
  layout: ModuleLayout,
): { readonly schema: string; readonly scope: string } {
  const configured = ctx.modules.access?.permdock;
  const manifest = layout.accessPermdock;
  if (manifest) {
    if (manifest.idType !== ctx.idType) {
      throw new TypeError(
        `sql.modules.access: PermDock's manifest gives scope "${manifest.scope}" the type ${manifest.idType}, but the access module renders ${ctx.idType} ids. Set sql.modules.access.idType to "${manifest.idType}".`,
      );
    }
    return { schema: manifest.schema, scope: manifest.scope };
  }
  if (configured?.schema === undefined || configured.scope === undefined) {
    throw new TypeError(
      "sql.modules.access.model 'permdock' needs PermDock's manifest (`permdock supabase inspect --out`), which `better-supabase sql add` reads, or both sql.modules.access.permdock.schema and sql.modules.access.permdock.scope.",
    );
  }
  return { schema: configured.schema, scope: configured.scope };
}

function permdockFunctions(ctx: ModuleContext, layout: ModuleLayout): string {
  const id = ctx.idType;
  const target = permdockTarget(ctx, layout);
  const schema = sqlIdent(target.schema);
  const permitted = `${schema}.${sqlIdent(`permitted_${target.scope}_ids`)}`;
  const forUser = permdockForUser(ctx, layout);
  const permittedFor = `${schema}.${sqlIdent(`permitted_${target.scope}_ids_for`)}`;
  const callerOnly = `raise exception 'The permdock access model answers for the caller only (modules.access.model)'
      using errcode = '0A000', hint = 'ACCESS_CALLER_ONLY';`;
  const otherMember = forUser.permitted
    ? `return not better_supabase.user_disabled(member)
      and not better_supabase.tenant_disabled(tenant)
      and tenant::text in (select t.id::text from ${permittedFor}(member, permission) as t(id));`
    : callerOnly;
  const platformOther = forUser.has
    ? `when member is not null then ${NOT_ACTING} and not better_supabase.user_disabled(member) and ${schema}.permdock_has_for(member, permission)`
    : "";
  const assignFor = assignAsFunction(ctx, layout);
  return `
-- The permdock model: PermDock's ${permitted}() and ${schema}.permdock_has(),
-- from \`permdock rls generate\`. They read auth.uid(), so member_can() and
-- can_user() answer for ${forUser.permitted || forUser.has ? "another user through PermDock's _for helpers" : "the caller only and raise 0A000 for anyone else"}.
create or replace function better_supabase.member_can(member uuid, tenant ${id}, permission text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if member is distinct from auth.uid() then
    ${otherMember}
  end if;
  return not better_supabase.user_disabled(member)
    and not better_supabase.tenant_disabled(tenant)
    and tenant::text in (select t.id::text from ${permitted}(permission) as t(id));
end;
$$;

create or replace function better_supabase.member_permissions(member uuid, tenant ${id})
returns text[]
language sql
stable
set search_path = ''
as $$
  select '{}'::text[]
$$;

create or replace function better_supabase.platform_can(member uuid, permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when member = auth.uid() then ${NOT_ACTING} and not better_supabase.user_disabled(member) and ${schema}.permdock_has(permission)
    ${platformOther}
    else false
  end
$$;${assignFor}

create or replace function better_supabase.tenant_ids_with(permission text)
returns setof ${id}
language sql
rows 1
stable
security definer
set search_path = ''
as $$
  select t.id::${id} from ${permitted}(tenant_ids_with.permission) as t(id)
  where not better_supabase.user_disabled(auth.uid())
    and not better_supabase.tenant_disabled(t.id::${id})
$$;

-- sql.modules.access.functions.canAssign decides who assigns which role, usually
-- ${schema}.permdock_can_assign({role}, {tenant}::text). Without it, only the
-- service role assigns roles, unless the tenant module is installed: then
-- only owners assign the owner role and this check passes other roles.
create or replace function better_supabase.can_assign(tenant ${id}, role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select ${SERVICE} or coalesce((${permdockCanAssign(ctx)}), false)
$$;

create or replace function better_supabase.permission_claims(user_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select '{}'::jsonb
$$;`;
}

function customFunctions(ctx: ModuleContext): string {
  const id = ctx.idType;
  const functions = ctx.modules.access?.functions ?? {};
  const missing = (
    ["can", "tenantIdsWith", "isPlatform", "canAssign"] as const
  ).filter((name) => !functions[name]);
  if (missing.length > 0) {
    throw new TypeError(
      `sql.modules.access.model 'custom' needs sql.modules.access.functions.${missing.join(", ")}`,
    );
  }
  const can = (member: string, tenant: string, permission: string) =>
    fill(functions.can!, {
      scope: sqlString(tenantScope(ctx)),
      id: tenant,
      permission,
      user: member,
    });
  return `
-- The custom model: the app's own functions, from sql.modules.access.functions.
create or replace function better_supabase.member_can(member uuid, tenant ${id}, permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when member is distinct from auth.uid() then ${functions.canUser ? `coalesce((${fill(functions.canUser, { user: "member", scope: sqlString(tenantScope(ctx)), id: "tenant", permission: "permission" })}), false)` : "null::boolean"}
    else not better_supabase.user_disabled(member)
      and not better_supabase.tenant_disabled(tenant)
      and coalesce((${can("member", "tenant", "permission")}), false)
  end
$$;

create or replace function better_supabase.member_permissions(member uuid, tenant ${id})
returns text[]
language sql
stable
set search_path = ''
as $$
  select '{}'::text[]
$$;

create or replace function better_supabase.platform_can(member uuid, permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select member = auth.uid() and ${NOT_ACTING} and not better_supabase.user_disabled(member)
    and coalesce((${fill(functions.isPlatform!, { permission: "permission", user: "member" })}), false)
$$;

create or replace function better_supabase.tenant_ids_with(permission text)
returns setof ${id}
language sql
rows 1
stable
security definer
set search_path = ''
as $$
  select t.id::${id} from ${fill(functions.tenantIdsWith!, { permission: "tenant_ids_with.permission" })} as t(id)
  where not better_supabase.user_disabled(auth.uid())
    and not better_supabase.tenant_disabled(t.id::${id})
$$;

create or replace function better_supabase.can_assign(tenant ${id}, role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select ${SERVICE} or coalesce((${fill(functions.canAssign!, { tenant: "can_assign.tenant", role: "can_assign.role" })}), false)
$$;

create or replace function better_supabase.permission_claims(user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((${functions.permissionClaims ? fill(functions.permissionClaims, { user: "user_id" }) : "'{}'::jsonb"}), '{}'::jsonb)
$$;`;
}

function accessSql(ctx: ModuleContext, layout: ModuleLayout): string {
  const id = ctx.idType;
  const model = accessModel(ctx);
  const forUser =
    model === "permdock" ? permdockForUser(ctx, layout) : undefined;
  const answersForOthers = forUser ? forUser.permitted && forUser.has : false;
  const scope = sqlString(tenantScope(ctx));
  let body: string;
  switch (model) {
    case "roles":
      body = `${rolesFunctions(ctx)}\n${membershipFunctions(ctx)}`;
      break;
    case "catalog":
      body = `${catalogTables(ctx)}\n${membershipFunctions(ctx)}`;
      break;
    case "permdock":
      body = permdockFunctions(ctx, layout);
      break;
    case "custom":
      body = `${customFunctions(ctx)}${assignAsFunction(ctx, layout)}`;
      break;
    default: {
      const unreachable: never = model;
      return unreachable;
    }
  }
  const defer = disabledHelpersNeedLaterTables(ctx);
  return `${schemaPreamble(ctx)}
grant usage on schema better_supabase to supabase_auth_admin;
${defer ? "set check_function_bodies = off;" : ""}${disabledHelpers(ctx)}${defer ? "\nreset check_function_bodies;" : ""}

-- \`*\` grants every key and \`prefix.*\` every key under prefix.
create or replace function better_supabase.permission_matches(granted text, wanted text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select granted = '*' or granted = wanted
    or (right(granted, 2) = '.*' and starts_with(wanted, left(granted, -1)))
$$;
${body}

-- The access contract. Policies and SQL modules call these, never a model's
-- tables, so the model can change without touching them. In a policy, use
-- the set, which runs once per statement and can use the tenant index:
--   using (organization_id in (select better_supabase.tenant_ids_with('invoices.read')))
-- can() with a column argument runs once per row, even inside (select ...);
-- keep it for checks on one row and inside functions.
create or replace function better_supabase.can(scope text, scope_id ${id}, permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when can.scope = 'platform' then coalesce(better_supabase.platform_can(auth.uid(), can.permission), false)
    when can.scope in (${scope}, 'tenant') then coalesce(better_supabase.member_can(auth.uid(), can.scope_id, can.permission), false)
    else false
  end
$$;

-- The same question for another user, for checks such as an inviter's
-- authority at accept time. ${model === "permdock" ? (answersForOthers ? "The permdock model answers through PermDock's _for helpers." : "The permdock model can't answer for others.") : "Null when the model can't answer for others."}
create or replace function better_supabase.can_user(member uuid, scope text, scope_id ${id}, permission text)
returns boolean
language ${model === "permdock" ? "plpgsql" : "sql"}
stable
security definer
set search_path = ''
as $$${
    model === "permdock" && !answersForOthers
      ? `
begin
  if member is distinct from auth.uid() then
    raise exception 'The permdock access model answers for the caller only (modules.access.model)'
      using errcode = '0A000', hint = 'ACCESS_CALLER_ONLY';
  end if;
  return case`
      : model === "permdock"
        ? `
begin
  return case`
        : `
  select case`
  }
    when can_user.scope = 'platform' then better_supabase.platform_can(can_user.member, can_user.permission)
    when can_user.scope in (${scope}, 'tenant') then better_supabase.member_can(can_user.member, can_user.scope_id, can_user.permission)
    else false
  end${model === "permdock" ? ";\nend;" : ""}
$$;

create or replace function better_supabase.is_platform(permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(better_supabase.platform_can(auth.uid(), is_platform.permission), false)
$$;

${[
  "permission_matches(text, text)",
  `can(text, ${id}, text)`,
  "tenant_ids_with(text)",
  "is_platform(text)",
  `can_assign(${id}, text)`,
]
  .flatMap((fn) => [
    `revoke execute on function better_supabase.${fn} from public;`,
    `grant execute on function better_supabase.${fn} to anon, authenticated, service_role;`,
  ])
  .join("\n")}
${[
  `member_can(uuid, ${id}, text)`,
  `member_permissions(uuid, ${id})`,
  "platform_can(uuid, text)",
  `can_user(uuid, text, ${id}, text)`,
  "permission_claims(uuid)",
  ...(model === "roles" || model === "catalog"
    ? [`can_assign_as(uuid, ${id}, text)`]
    : []),
]
  .flatMap((fn) => [
    `revoke execute on function better_supabase.${fn} from public, anon, authenticated;`,
    `grant execute on function better_supabase.${fn} to service_role, supabase_auth_admin;`,
  ])
  .join("\n")}

-- The permission claim: { [tenant id]: permission keys }, for the access
-- token hook when the app checks permissions from the token:
--   return jsonb_set(event, '{claims,permissions}',
--     better_supabase.permission_claims((event ->> 'user_id')::uuid));`;
}

export const ACCESS: ModuleDefinition = {
  name: "access",
  title: "Access contract",
  description:
    "can(), tenant_ids_with() and is_platform(): one permission contract for policies and SQL modules, over a roles list, a role and permission catalog, PermDock or the app's own functions (modules.access.model).",
  requires: ["tenant"],
  dependencies: (layout) => {
    const model = layout.modules?.access?.model ?? "roles";
    return model === "roles" || model === "catalog" ? ["tenant"] : [];
  },
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  names: {
    options: ["platformRoleScope", "scope", "tenantRoleScope"],
    tables: {
      roles: {
        name: "roles",
        columns: { id: "id", key: "key", scope: "scope", tenant: "tenant_id" },
        optional: ["scope", "tenant"],
      },
      permissions: { name: "permissions", columns: { id: "id", key: "key" } },
      rolePermissions: {
        name: "role_permissions",
        columns: { role: "role_id", permission: "permission_id" },
      },
      overrides: {
        name: "permission_overrides",
        lifecycle: { tenant: "tenant" },
        columns: {
          tenant: "organization_id",
          role: "role_id",
          permission: "permission_id",
          granted: "granted",
        },
        optionalTable: true,
      },
      platformAssignments: {
        name: "platform_roles",
        columns: { user: "user_id", role: "role_id" },
        optionalTable: true,
      },
    },
  },
  contract: () => [
    { name: "can", args: ["text", "{id}", "text"], returns: "boolean" },
    { name: "tenant_ids_with", args: ["text"], returns: "{id}" },
    { name: "is_platform", args: ["text"], returns: "boolean" },
    {
      name: "can_user",
      args: ["uuid", "text", "{id}", "text"],
      returns: "boolean",
    },
    { name: "can_assign", args: ["{id}", "text"], returns: "boolean" },
    {
      name: "member_can",
      args: ["uuid", "{id}", "text"],
      returns: "boolean",
    },
    {
      name: "can_assign_as",
      args: ["uuid", "{id}", "text"],
      returns: "boolean",
    },
    { name: "permission_claims", args: ["uuid"], returns: "jsonb" },
  ],
  build: accessSql,
};
