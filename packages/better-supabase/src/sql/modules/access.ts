import type { KitContext } from "../context.ts";
import type { KitLayout, KitModuleDefinition } from "../kit.ts";

import { PERMDOCK_SCHEMA } from "../../core/permdock-sql.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  disabledHelpers,
  disabledHelpersNeedLaterTables,
  schemaPreamble,
} from "../shared.ts";
import {
  accessModel,
  hasPlatformRoles,
  roleScopeIs,
  rolesOf,
  tenantScope,
} from "./access-model.ts";

const SERVICE = `coalesce(auth.jwt() ->> 'role', '') = 'service_role'`;

// A token with an `act` claim (a support session) acts as its subject, so it
// never carries the subject's platform permissions.
const NOT_ACTING = `(platform_can.member is distinct from auth.uid() or auth.jwt() -> 'act' is null)`;

/** Fills `{name}` placeholders of a `kits.access.functions` template. */
function fill(
  template: string,
  values: Readonly<Record<string, string>>,
): string {
  return template.replaceAll(/\{(\w+)\}/g, (match, name: string) => {
    const value = values[name];
    if (value === undefined) {
      throw new TypeError(
        `kits.access.functions: ${match} is not available here. Use ${Object.keys(
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

function membershipNames(ctx: KitContext): Names {
  const tenant = ctx.of("tenant");
  return {
    m: tenant.table("memberships"),
    tenant: tenant.col("memberships", "tenant"),
    user: tenant.col("memberships", "user"),
    role: tenant.col("memberships", "role"),
  };
}

/** Whether membership row `m` grants catalog permission row `p`: deny beats grant beats the role default. */
function catalogEffective(ctx: KitContext, n: Names): string {
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
function grants(ctx: KitContext, n: Names, permission: string): string {
  if (accessModel(ctx) === "roles") {
    return `better_supabase.role_grants(m.${n.role}, ${permission})`;
  }
  return `exists (select 1 from ${ctx.table("permissions")} p where p.${ctx.col("permissions", "key")} = ${permission} and ${catalogEffective(ctx, n)})`;
}

function platformClaim(ctx: KitContext, member: string, permission: string) {
  const claim = sqlString(
    ctx.kits.access?.platformClaim ?? "platform_permissions",
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

function rolesFunctions(ctx: KitContext): string {
  const roles = Object.entries(rolesOf(ctx));
  const cases =
    roles.length === 0
      ? "'{}'::text[]"
      : `case role
    ${roles.map(([role, keys]) => `when ${sqlString(role)} then array[${keys.map(sqlString).join(", ")}]::text[]`).join("\n    ")}
    else '{}'::text[]
  end`;
  return `
-- The roles model (kits.access.roles): each role's permission keys.
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

function catalogTables(ctx: KitContext): string {
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
alter table ${ctx.table("roles")} drop constraint if exists roles_scope_check;
alter table ${ctx.table("roles")} add constraint roles_scope_check check (${ctx.col("roles", "scope")} in ('tenant', 'platform'));
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
$$;`;
}

/** `member_can`, `member_permissions` and `platform_can` for the roles and catalog models. */
function membershipFunctions(ctx: KitContext): string {
  const id = ctx.idType;
  const n = membershipNames(ctx);
  const model = accessModel(ctx);
  const permissions =
    model === "roles"
      ? `select coalesce((
      select better_supabase.role_permissions(m.${n.role}) from ${n.m} m
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
function platformCanAssign(ctx: KitContext): string {
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

function permdockCanAssign(ctx: KitContext): string {
  const template = ctx.kits.access?.functions?.canAssign;
  if (template) {
    return fill(template, {
      tenant: "can_assign.tenant",
      role: "can_assign.role",
    });
  }
  if (!ctx.installed("tenant")) return "false";
  const owner = sqlString(ctx.of("organizations").text("ownerRole", "owner"));
  return `can_assign.role <> ${owner} or better_supabase.has_org_role(can_assign.tenant, array[${owner}])`;
}

function permdockFunctions(ctx: KitContext, layout: KitLayout): string {
  const id = ctx.idType;
  const permdock = ctx.kits.access?.permdock ?? {};
  const schema = sqlIdent(
    permdock.schema ?? layout.permdock?.schema ?? PERMDOCK_SCHEMA,
  );
  const scope = permdock.scope ?? layout.permdock?.scope ?? "organization";
  const permitted = `${schema}.${sqlIdent(`permitted_${scope}_ids`)}`;
  return `
-- The permdock model: PermDock's ${permitted}() and ${schema}.permdock_has(),
-- from \`permdock rls generate\`. They answer for the caller only.
create or replace function better_supabase.member_can(member uuid, tenant ${id}, permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case when member is distinct from auth.uid() then null::boolean
    else not better_supabase.user_disabled(member)
      and not better_supabase.tenant_disabled(tenant)
      and tenant::text in (select t.id::text from ${permitted}(permission) as t(id))
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
  select member = auth.uid() and ${NOT_ACTING} and not better_supabase.user_disabled(member) and ${schema}.permdock_has(permission)
$$;

create or replace function better_supabase.tenant_ids_with(permission text)
returns setof ${id}
language sql
stable
security definer
set search_path = ''
as $$
  select t.id::${id} from ${permitted}(tenant_ids_with.permission) as t(id)
  where not better_supabase.user_disabled(auth.uid())
    and not better_supabase.tenant_disabled(t.id::${id})
$$;

-- kits.access.functions.canAssign decides who assigns which role. Without
-- it, only owners assign the owner role, and only with the tenant module.
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

function customFunctions(ctx: KitContext): string {
  const id = ctx.idType;
  const functions = ctx.kits.access?.functions ?? {};
  const missing = (
    ["can", "tenantIdsWith", "isPlatform", "canAssign"] as const
  ).filter((name) => !functions[name]);
  if (missing.length > 0) {
    throw new TypeError(
      `kits.access.model 'custom' needs kits.access.functions.${missing.join(", ")}`,
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
-- The custom model: the app's own functions, from kits.access.functions.
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

function accessSql(ctx: KitContext, layout: KitLayout): string {
  const id = ctx.idType;
  const model = accessModel(ctx);
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
      body = customFunctions(ctx);
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

-- The access contract. Policies and kit modules call these, never a model's
-- tables, so the model can change without touching them:
--   using ((select better_supabase.can('${tenantScope(ctx)}', organization_id, 'invoices.read')))
--   using (organization_id in (select better_supabase.tenant_ids_with('invoices.read')))
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
-- authority at accept time. Null when the model can't answer for others.
create or replace function better_supabase.can_user(member uuid, scope text, scope_id ${id}, permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when can_user.scope = 'platform' then better_supabase.platform_can(can_user.member, can_user.permission)
    when can_user.scope in (${scope}, 'tenant') then better_supabase.member_can(can_user.member, can_user.scope_id, can_user.permission)
    else false
  end
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

do $$
declare
  fn text;
begin
  foreach fn in array array[
    'permission_matches(text, text)',
    'can(text, ${id}, text)',
    'tenant_ids_with(text)',
    'is_platform(text)',
    'can_assign(${id}, text)'
  ] loop
    execute format('revoke execute on function better_supabase.%s from public', fn);
    execute format('grant execute on function better_supabase.%s to anon, authenticated, service_role', fn);
  end loop;
  foreach fn in array array[
    'member_can(uuid, ${id}, text)',
    'member_permissions(uuid, ${id})',
    'platform_can(uuid, text)',
    'can_user(uuid, text, ${id}, text)',
    'permission_claims(uuid)'${model === "roles" || model === "catalog" ? `,\n    'can_assign_as(uuid, ${id}, text)'` : ""}
  ] loop
    execute format('revoke execute on function better_supabase.%s from public, anon, authenticated', fn);
    execute format('grant execute on function better_supabase.%s to service_role, supabase_auth_admin', fn);
  end loop;
end;
$$;

-- The permission claim: { [tenant id]: permission keys }, for the access
-- token hook when the app checks permissions from the token:
--   return jsonb_set(event, '{claims,permissions}',
--     better_supabase.permission_claims((event ->> 'user_id')::uuid));`;
}

export const ACCESS: KitModuleDefinition = {
  name: "access",
  title: "Access contract",
  description:
    "can(), tenant_ids_with() and is_platform(): one permission contract for policies and kit modules, over a roles list, a role and permission catalog, PermDock or the app's own functions (kits.access.model).",
  requires: ["tenant"],
  dependencies: (layout) => {
    const model = layout.kits?.access?.model ?? "roles";
    return model === "roles" || model === "catalog" ? ["tenant"] : [];
  },
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  names: {
    tables: {
      roles: {
        name: "roles",
        columns: { id: "id", key: "key", scope: "scope" },
        optional: ["scope"],
      },
      permissions: { name: "permissions", columns: { id: "id", key: "key" } },
      rolePermissions: {
        name: "role_permissions",
        columns: { role: "role_id", permission: "permission_id" },
      },
      overrides: {
        name: "permission_overrides",
        columns: {
          tenant: "org_id",
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
    { name: "permission_claims", args: ["uuid"], returns: "jsonb" },
  ],
  build: accessSql,
};
