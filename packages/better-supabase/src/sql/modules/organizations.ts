import type { ModuleContext, ModuleNames } from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  activeMembership,
  addForeignKey,
  columnRef,
  membershipDisabledAt,
  schemaPreamble,
  SERVICE_CALLER,
  updatedAt,
} from "../shared.ts";
import { accessModel, MODULE_PERMISSIONS, roleNames } from "./access-model.ts";
import { ORGANIZATION_EVENTS } from "./organizations-events.ts";
import { organizationReads } from "./organizations-reads.ts";
import { memberSuspension } from "./organizations-suspension.ts";
import {
  activeTenantSource,
  roleNameFrom,
  roleNameOf,
  roleThrough,
} from "./tenant.ts";

const NAMES: ModuleNames = {
  events: ORGANIZATION_EVENTS,
  options: [
    "assignmentGuard",
    "attributes",
    "auditCategory",
    "deleteMode",
    "formerOwnerRole",
    "ownerInvariant",
    "ownerRole",
    "reservedSlugs",
    "slugCitext",
    "slugMaxLength",
    "slugMinLength",
    "slugPattern",
  ],
  tables: {
    organizations: {
      name: "organizations",
      columns: {
        id: "id",
        name: "name",
        slug: "slug",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
        disabledAt: "disabled_at",
        deletedAt: "deleted_at",
      },
      optional: [
        "slug",
        "createdBy",
        "createdAt",
        "updatedAt",
        "disabledAt",
        "deletedAt",
      ],
    },
  },
  hooks: [
    "before_organization_create",
    "after_organization_create",
    "after_member_change",
  ],
};

/** The roles client writes run as; the guard checks only their writes. */
const CLIENT_WRITE = "current_user in ('anon', 'authenticated')";

const DEFAULT_SLUG_PATTERN = "^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$";

/** Names the module reads from `tenant` and `access`, resolved once. */
interface OrganizationNames {
  readonly organization: string;
  readonly id: string;
  readonly m: string;
  readonly tenant: string;
  readonly user: string;
  readonly role: string;
  /** The role name owners hold (`sql.modules.organizations.options.ownerRole`). */
  readonly ownerRole: string;
}

function namesOf(ctx: ModuleContext): OrganizationNames {
  const t = ctx.of("tenant");
  return {
    organization: ctx.table("organizations"),
    id: ctx.col("organizations", "id"),
    m: t.table("memberships"),
    tenant: t.col("memberships", "tenant"),
    user: t.col("memberships", "user"),
    role: t.col("memberships", "role"),
    ownerRole: ctx.text("ownerRole", "owner"),
  };
}

/**
 * The tenant column of a roles table with tenant custom roles: the
 * `roleThrough` table's `tenant`, or the catalog's mapped `roles.tenant`.
 */
function rolesTenantColumn(ctx: ModuleContext): string | undefined {
  const through = roleThrough(ctx.of("tenant"));
  if (through) return through.tenant;
  if (accessModel(ctx) !== "catalog") return undefined;
  const access = ctx.of("access");
  return !access.manages &&
    typeof access.config.columns["roles"]?.["tenant"] === "string"
    ? access.col("roles", "tenant")
    : undefined;
}

/**
 * Limits roles row `r` to `tenant`'s custom roles and the shared ones (no
 * tenant), its own first, so a key that several tenants use resolves to the
 * tenant's role. Nothing without a tenant or a tenant column.
 */
export function tenantRoleScope(
  ctx: ModuleContext,
  tenant: string | undefined,
): { readonly where: string; readonly order: string } {
  const column = rolesTenantColumn(ctx);
  if (column === undefined || tenant === undefined)
    return { where: "", order: "" };
  return {
    where: ` and (r.${column} = ${tenant} or r.${column} is null)`,
    order: `, (r.${column} is not null) desc`,
  };
}

/**
 * A role argument as the membership role column stores it: the name for the
 * roles model, the catalog role id (looked up by id or key) for `catalog`.
 * With `tenant`, a key resolves among that tenant's roles. A `roleThrough`
 * lookup keeps to the rows its `where` accepts unless `tenantRoles` is false.
 */
export function roleValue(
  ctx: ModuleContext,
  expr: string,
  tenant?: string,
  tenantRoles = true,
): string {
  const scope = tenantRoleScope(ctx, tenant);
  const through = roleThrough(ctx.of("tenant"));
  if (through) {
    const text = `(${expr})::text`;
    const only =
      tenantRoles && through.where
        ? ` and (${through.where.replaceAll("{row}", "r")})`
        : "";
    return `(select r.${through.id} from ${through.table} r where (r.${through.id}::text = ${text} or r.${through.column}::text = ${text})${only}${scope.where} order by (r.${through.id}::text = ${text}) desc${scope.order} limit 1)`;
  }
  if (accessModel(ctx) !== "catalog") return expr;
  const access = ctx.of("access");
  const rid = access.col("roles", "id");
  const key = access.col("roles", "key");
  const text = `(${expr})::text`;
  return `(select r.${rid} from ${access.table("roles")} r where (r.${rid}::text = ${text} or r.${key} = ${text})${scope.where} order by (r.${rid}::text = ${text}) desc${scope.order} limit 1)`;
}

/**
 * A stored membership role as `can_assign` takes it: the role name with
 * `sql.modules.tenant.options.roleThrough`, the stored value otherwise.
 */
export function assignableRole(ctx: ModuleContext, stored: string): string {
  const tenant = ctx.of("tenant");
  return roleThrough(tenant) ? roleNameFrom(tenant, stored) : `${stored}::text`;
}

/** Raises `ORGANIZATION_ROLE_UNKNOWN` for a role the access model doesn't know. */
function checkRole(ctx: ModuleContext, expr: string, tenant: string): string {
  const model = accessModel(ctx);
  const through = roleThrough(ctx.of("tenant")) !== undefined;
  if (!through && (model === "provider" || model === "custom")) return "";
  const known =
    model === "roles" && !through
      ? `${expr} = any (array[${roleNames(ctx).map(sqlString).join(", ")}]::text[])`
      : `${roleValue(ctx, expr, tenant)} is not null`;
  return `
  if not (${known}) then
    raise exception 'Unknown role %', ${expr} using errcode = '22023', hint = 'ORGANIZATION_ROLE_UNKNOWN';
  end if;`;
}

const isOwner = (
  ctx: ModuleContext,
  n: OrganizationNames,
  alias: string,
): string =>
  `${roleNameOf(ctx.of("tenant"), alias)} = ${sqlString(n.ownerRole)}`;

/** True while the organization exists and is neither deleted nor disabled. */
function activeOrganization(
  ctx: ModuleContext,
  n: OrganizationNames,
  organization: string,
): string {
  const c = (logical: string) => `o.${ctx.col("organizations", logical)}`;
  const flags = (["deletedAt", "disabledAt"] as const)
    .filter((logical) => ctx.has("organizations", logical))
    .map((logical) => ` and ${c(logical)} is null`)
    .join("");
  return `exists (select 1 from ${n.organization} o where o.${n.id} = ${organization}${flags}) and not better_supabase.tenant_disabled(${organization})`;
}

function idColumn(ctx: ModuleContext, column: string): string {
  switch (ctx.idType) {
    case "uuid":
      return `${column} uuid primary key default gen_random_uuid()`;
    case "text":
      return `${column} text primary key default gen_random_uuid()::text`;
    case "bigint":
    case "integer":
      return `${column} ${ctx.idType} generated by default as identity primary key`;
    default: {
      const unreachable: never = ctx.idType;
      return unreachable;
    }
  }
}

function table(ctx: ModuleContext, n: OrganizationNames): string {
  if (!ctx.manages) {
    return `
-- Adopted: ${n.organization} belongs to the app (modules.organizations.tables.organizations).
`;
  }
  const c = (logical: string) => ctx.col("organizations", logical);
  const optional = (logical: string, type: string) =>
    ctx.has("organizations", logical) ? `,\n  ${c(logical)} ${type}` : "";
  const slugType = ctx.flag("slugCitext", false) ? "extensions.citext" : "text";
  const slugIndex = ctx.has("organizations", "slug")
    ? `create unique index if not exists organizations_slug_idx on ${n.organization} (lower(${c("slug")}::text))${ctx.has("organizations", "deletedAt") ? ` where ${c("deletedAt")} is null` : ""};\n`
    : "";
  return `${slugType === "text" ? "" : "\ncreate extension if not exists citext with schema extensions;"}
create table if not exists ${n.organization} (
  ${idColumn(ctx, n.id)},
  ${c("name")} text not null check (length(btrim(${c("name")})) > 0)${optional("slug", `${slugType} not null`)}${optional("createdBy", "uuid references auth.users (id) on delete set null")}${optional("createdAt", "timestamptz not null default now()")}${optional("disabledAt", "timestamptz")}${optional("deletedAt", "timestamptz")}
);
${slugIndex}${ctx.has("organizations", "createdBy") ? `create index if not exists organizations_created_by_idx on ${n.organization} (${c("createdBy")});\n` : ""}${ctx.has("organizations", "updatedAt") ? `${updatedAt(n.organization, c("updatedAt"))}\n` : ""}${
    ctx.installed("entitlements")
      ? `-- The Stripe customer the entitlements module reads (config.entitlements.customer).
alter table ${n.organization} add column if not exists stripe_customer_id text unique;
`
      : ""
  }alter table ${n.organization} enable row level security;
revoke all on ${n.organization} from anon, authenticated;
grant select on ${n.organization} to authenticated;
grant all on ${n.organization} to service_role;
drop policy if exists bs_organizations_read on ${n.organization};
create policy bs_organizations_read on ${n.organization} for select to authenticated
  using (${n.id} in (select better_supabase.member_organization_ids()));
`;
}

/** `organization_slug_problem(slug)`: `invalid`, `reserved`, `taken` or null. */
function slugCheck(ctx: ModuleContext, n: OrganizationNames): string {
  if (!ctx.has("organizations", "slug")) return "";
  const slug = ctx.col("organizations", "slug");
  const pattern = sqlString(ctx.text("slugPattern", DEFAULT_SLUG_PATTERN));
  const min = ctx.number("slugMinLength", 2);
  const max = ctx.number("slugMaxLength", 48);
  const reservedList = ctx.list("reservedSlugs", []);
  const reserved = [
    ...(ctx.installed("reserved-slugs")
      ? [
          "exists (select 1 from better_supabase.reserved_slugs r where r.slug = lower(value))",
        ]
      : []),
    ...(reservedList.length > 0
      ? [
          `lower(value) = any (array[${reservedList.map((s) => sqlString(s.toLowerCase())).join(", ")}]::text[])`,
        ]
      : []),
  ];
  const deleted = ctx.has("organizations", "deletedAt")
    ? ` and o.${ctx.col("organizations", "deletedAt")} is null`
    : "";
  return `
-- Why a slug can't be used, or null: 'invalid' (length and pattern from
-- sql.modules.organizations.options), 'reserved' or 'taken'. except_organization skips the
-- organization being renamed.
create or replace function ${ctx.fn("organization_slug_problem")}(value text, except_organization ${ctx.idType} default null)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when value is null then null
    when length(value) < ${String(min)} or length(value) > ${String(max)} or value !~ ${pattern} then 'invalid'
    when ${reserved.length > 0 ? reserved.join(" or ") : "false"} then 'reserved'
    when exists (
      select 1 from ${n.organization} o
      where lower(o.${slug}::text) = lower(value)${deleted}
        and o.${n.id} is distinct from except_organization
    ) then 'taken'
  end
$$;
revoke execute on function ${ctx.fn("organization_slug_problem")}(text, ${ctx.idType}) from public, anon;
grant execute on function ${ctx.fn("organization_slug_problem")}(text, ${ctx.idType}) to authenticated, service_role;
`;
}

const raiseSlug = (
  ctx: ModuleContext,
  value: string,
  except: string,
): string =>
  ctx.has("organizations", "slug")
    ? `
  case ${ctx.fn("organization_slug_problem")}(${ctx.manages ? `coalesce(${value}, '')` : value}, ${except})
    when 'invalid' then raise exception 'Invalid slug "%"', ${value} using errcode = '23514', hint = 'ORGANIZATION_SLUG_INVALID';
    when 'reserved' then raise exception 'The slug "%" is reserved', ${value} using errcode = '23514', hint = 'ORGANIZATION_SLUG_RESERVED';
    when 'taken' then raise exception 'The slug "%" is taken', ${value} using errcode = '23505', hint = 'ORGANIZATION_SLUG_TAKEN';
    else null;
  end case;`
    : "";

/** The columns `create_organization` and `update_organization` copy from `attrs`. */
function attributeColumns(ctx: ModuleContext): readonly string[] {
  const extra = ctx.list("attributes", []).map((column) => {
    if (!/^[A-Za-z_][A-Za-z0-9_$]*$/.test(column)) {
      throw new TypeError(
        `sql.modules.organizations.options.attributes: "${column}" is not a valid column`,
      );
    }
    return sqlIdent(column);
  });
  return [
    ctx.col("organizations", "name"),
    ...(ctx.has("organizations", "slug")
      ? [ctx.col("organizations", "slug")]
      : []),
    ...extra,
  ];
}

/** A quoted identifier's name, as `jsonb_populate_record` keys it. */
const unquoted = (ident: string): string =>
  ident.slice(1, -1).replaceAll('""', '"');

const event = (organization: string, user: string, extra = ""): string =>
  `jsonb_build_object('organizationId', ${organization}::text, 'userId', ${user}${extra})`;

function create(ctx: ModuleContext, n: OrganizationNames): string {
  const id = ctx.idType;
  const columns = attributeColumns(ctx);
  const fixed = ctx.has("organizations", "slug") ? 2 : 1;
  const createdBy = ctx.has("organizations", "createdBy");
  const required = [
    ...columns.slice(0, fixed),
    ...(createdBy ? [ctx.col("organizations", "createdBy")] : []),
  ].join(", ");
  const values = (owner: string) =>
    [
      ...columns.slice(0, fixed).map((column) => `r.${column}`),
      ...(createdBy ? [owner] : []),
    ].join(", ");
  const optional = columns
    .slice(fixed)
    .map((column) => sqlString(unquoted(column)));
  const literal = (sql: string) => sql.replaceAll("'", "''");
  // Attributes missing from attrs keep their column default.
  const insert =
    optional.length === 0
      ? `insert into ${n.organization} (${required})
  select ${values("owner")}
  from jsonb_populate_record(null::${n.organization}, attrs) r
  returning ${n.id} into organization;`
      : `select coalesce(string_agg(format(', %I', c), ''), ''), coalesce(string_agg(format(', r.%I', c), ''), '')
  into extra_columns, extra_values
  from unnest(array[${optional.join(", ")}]) c
  where attrs ? c;
  execute format(
    'insert into ${literal(n.organization)} (${literal(required)}%s) select ${literal(values("$2"))}%s from jsonb_populate_record(null::${literal(n.organization)}, $1) r returning ${literal(n.id)}',
    extra_columns,
    extra_values
  ) into organization using attrs, owner;`;
  const permission = ctx.permissionKey("create", "");
  const createCheck =
    permission === ""
      ? ""
      : `
  if not service and not better_supabase.is_platform(${sqlString(permission)}) then
    raise exception 'Not allowed to create an organization' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;`;
  const slug = ctx.has("organizations", "slug")
    ? sqlString(unquoted(ctx.col("organizations", "slug")))
    : undefined;
  return `
-- Creates an organization from attrs (its name${slug ? ", slug" : ""} and the columns in
-- sql.modules.organizations.options.attributes) and makes the caller its owner. The
-- service role passes the owner as attrs.owner_id.
create or replace function ${ctx.fn("create_organization")}(attrs jsonb)
returns ${id}
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  service boolean := ${SERVICE_CALLER};
  owner uuid := case when service then nullif(attrs ->> 'owner_id', '')::uuid else auth.uid() end;
  organization ${id};${optional.length === 0 ? "" : "\n  extra_columns text;\n  extra_values text;"}
begin
  if owner is null then
    raise exception 'An organization needs an owner' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if better_supabase.user_disabled(owner) then
    raise exception 'The user is disabled' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;${createCheck}${slug ? raiseSlug(ctx, `attrs ->> ${slug}`, "null") : ""}
  ${ctx.hook("before_organization_create", [
    ["jsonb", "attrs"],
    ["uuid", "owner"],
  ])}
  ${insert}
  insert into ${n.m} (${n.tenant}, ${n.user}, ${n.role})
  values (organization, owner, ${roleValue(ctx, sqlString(n.ownerRole), "organization")});
  ${ctx.hook("after_organization_create", [
    [id, "organization"],
    ["uuid", "owner"],
  ])}
  ${ctx.record({ type: "organization.created", payload: event("organization", "owner", `, 'role', ${sqlString(n.ownerRole)}`), subject: "'organizations/' || organization::text", tenant: "organization", audit: { category: "configuration", targetType: "organization", recordId: "organization::text" } })}
  return organization;
end;
$$;

-- Updates the name${slug ? ", slug" : ""} and attribute columns present in attrs.
create or replace function ${ctx.fn("update_organization")}(organization ${id}, attrs jsonb)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (${SERVICE_CALLER}) and not coalesce(better_supabase.member_can(auth.uid(), organization, ${ctx.permission("update", MODULE_PERMISSIONS.organizations.update)}), false)${platformOverride(ctx, "updatePlatform")} then
    raise exception 'Not allowed to update the organization' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;${slug ? `\n  if attrs ? ${slug} then${raiseSlug(ctx, `attrs ->> ${slug}`, "organization").replaceAll("\n", "\n  ")}\n  end if;` : ""}
  update ${n.organization} o
  set ${columns.map((column) => `${column} = case when attrs ? ${sqlString(unquoted(column))} then r.${column} else o.${column} end`).join(",\n    ")}
  from jsonb_populate_record(null::${n.organization}, attrs) r
  where o.${n.id} = organization;
  if not found then
    raise exception 'No organization %', organization using errcode = 'P0002', hint = 'ORGANIZATION_NOT_FOUND';
  end if;
  ${ctx.record({ type: "organization.updated", payload: event("organization", "auth.uid()"), subject: "'organizations/' || organization::text", tenant: "organization", audit: { category: "configuration", targetType: "organization", recordId: "organization::text" } })}
  return true;
end;
$$;
`;
}

/**
 * `permissions.updatePlatform`, `deletePlatform`, `updateRolePlatform` and
 * `removeMemberPlatform`: a platform key (`is_platform`) that lets platform
 * staff edit or delete any tenant, or manage its members, without the
 * service role. Nothing when unset.
 */
function platformOverride(
  ctx: ModuleContext,
  action:
    | "updatePlatform"
    | "deletePlatform"
    | "updateRolePlatform"
    | "removeMemberPlatform",
): string {
  const key = ctx.permissionKey(action, "");
  return key === ""
    ? ""
    : `\n    and not coalesce(better_supabase.is_platform(${sqlString(key)}), false)`;
}

type DeleteMode = "hard" | "soft" | "lifecycle" | "none";

/** `sql.modules.organizations.options.deleteMode`. */
function deleteMode(ctx: ModuleContext): DeleteMode {
  const mode = ctx.text("deleteMode", "hard");
  if (
    mode !== "hard" &&
    mode !== "soft" &&
    mode !== "lifecycle" &&
    mode !== "none"
  ) {
    throw new TypeError(
      `sql.modules.organizations.options.deleteMode must be "hard", "soft", "lifecycle" or "none", not "${mode}"`,
    );
  }
  if (mode === "lifecycle" && !ctx.installed("data-lifecycle")) {
    throw new TypeError(
      'sql.modules.organizations.options.deleteMode "lifecycle" schedules the deletion with request_organization_deletion, so it needs the data-lifecycle module in sql.modules',
    );
  }
  return mode;
}

/** `delete_organization(organization)`: requests the purge through data-lifecycle. */
function requestDeletion(ctx: ModuleContext): string {
  return `
-- Deletes an organization through data-lifecycle (modules.organizations.options.deleteMode
-- "lifecycle"): schedules the purge after the grace period and disables it.
create or replace function ${ctx.fn("delete_organization")}(organization ${ctx.idType})
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (${SERVICE_CALLER}) and not coalesce(better_supabase.member_can(auth.uid(), organization, ${ctx.permission("delete", MODULE_PERMISSIONS.organizations.delete)}), false)${platformOverride(ctx, "deletePlatform")} then
    raise exception 'Not allowed to delete the organization' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  perform ${ctx.of("data-lifecycle").fn("request_organization_deletion")}(organization);
  return true;
end;
$$;
`;
}

function remove(ctx: ModuleContext, n: OrganizationNames): string {
  const id = ctx.idType;
  const mode = deleteMode(ctx);
  if (mode === "none") {
    return `
-- modules.organizations.options.deleteMode is "none": no delete function.
drop function if exists ${ctx.fn("delete_organization")}(${id});
`;
  }
  if (mode === "lifecycle") return requestDeletion(ctx);
  const soft = mode === "soft";
  if (soft && !ctx.has("organizations", "deletedAt")) {
    throw new TypeError(
      "sql.modules.organizations.options.deleteMode 'soft' needs the deletedAt column",
    );
  }
  const action = soft
    ? `update ${n.organization} set ${ctx.col("organizations", "deletedAt")} = now() where ${n.id} = organization and ${ctx.col("organizations", "deletedAt")} is null;`
    : `delete from ${n.organization} where ${n.id} = organization;`;
  return `
-- Deletes an organization (modules.organizations.options.deleteMode: ${soft ? "soft, setting deleted_at" : "hard, with its memberships"}).
create or replace function ${ctx.fn("delete_organization")}(organization ${id})
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (${SERVICE_CALLER}) and not coalesce(better_supabase.member_can(auth.uid(), organization, ${ctx.permission("delete", MODULE_PERMISSIONS.organizations.delete)}), false)${platformOverride(ctx, "deletePlatform")} then
    raise exception 'Not allowed to delete the organization' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  ${action}
  if not found then
    return false;
  end if;${soft ? "" : `\n  delete from ${n.m} where ${n.tenant} = organization;`}
  ${ctx.record({
    type: "organization.deleted",
    payload: event("organization", "auth.uid()"),
    subject: "'organizations/' || organization::text",
    tenant: "organization",
    audit: {
      category: "configuration",
      targetType: "organization",
      recordId: "organization::text",
      metadata: `jsonb_build_object('mode', ${sqlString(soft ? "soft" : "hard")})`,
    },
  })}
  return true;
end;
$$;
`;
}

/**
 * When the module owns the organizations table, the tenant rows of memberships,
 * invitations and permission overrides go with their organization.
 */
function tenantKeys(ctx: ModuleContext, n: OrganizationNames): string {
  if (!ctx.manages) return "";
  const references = `${n.organization} (${n.id})`;
  const keys: string[] = [];
  const add = (
    module: string,
    logical: string,
    name: string,
    available: boolean,
  ): void => {
    if (!available) return;
    const other = ctx.of(module);
    if (!other.manages || !other.hasTable(logical)) return;
    keys.push(
      addForeignKey({
        table: other.table(logical),
        name,
        column: other.col(logical, "tenant"),
        references,
        onDelete: "cascade",
      }),
    );
  };
  add("tenant", "memberships", "memberships_organization_fkey", true);
  add(
    "access",
    "overrides",
    "permission_overrides_organization_fkey",
    accessModel(ctx) === "catalog",
  );
  add(
    "invitations",
    "invitations",
    "invitations_organization_fkey",
    ctx.installed("invitations"),
  );
  return keys.length === 0
    ? ""
    : `
${keys.join("\n")}
`;
}

/** The deferred owner check and the role guard on the memberships table. */
function guards(ctx: ModuleContext, n: OrganizationNames): string {
  const disabledAt = membershipDisabledAt(ctx);
  const invariant = ctx.flag("ownerInvariant", true)
    ? `
-- Checked at commit, so one transaction can promote one owner and demote
-- another. An organization may have several owners.
create or replace function ${ctx.fn("ensure_organization_owner")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- The row lock serializes concurrent demotions and leaves, so two
  -- transactions can't each remove a different last owner.
  perform 1 from ${n.organization} o where o.${n.id} = old.${n.tenant} for update;
  if found and not exists (
      select 1 from ${n.m} m where m.${n.tenant} = old.${n.tenant} and ${isOwner(ctx, n, "m")}${activeMembership(ctx, "m")}
    ) then
    raise exception 'An organization needs an owner' using errcode = '23514', hint = 'ORGANIZATION_OWNER_REQUIRED';
  end if;
  return null;
end;
$$;
drop trigger if exists ${ctx.trigger("organization_owner")} on ${n.m};
create constraint trigger ${ctx.trigger("organization_owner")} after update of ${n.role}, ${n.tenant}${disabledAt === undefined ? "" : `, ${disabledAt}`} or delete on ${n.m}
  deferrable initially deferred
  for each row execute function ${ctx.fn("ensure_organization_owner")}();
`
    : "";
  const guard = ctx.text("assignmentGuard", "module");
  if (guard !== "module" && guard !== "external") {
    throw new TypeError(
      `sql.modules.organizations.options.assignmentGuard must be "module" or "external", not "${guard}"`,
    );
  }
  if (guard === "external") {
    if (ctx.of("tenant").manages) {
      throw new TypeError(
        'sql.modules.organizations.options.assignmentGuard "external" leaves the role checks on the memberships table to another trigger, such as an authorization provider\'s assignment rules, so it needs an adopted table (sql.modules.tenant.mode "adopt").',
      );
    }
    return `${invariant}
-- sql.modules.organizations.options.assignmentGuard is "external": another
-- trigger on ${n.m} (such as an authorization provider's assignment rules) checks role
-- changes, so the module's guard is removed. Its functions still check
-- can_assign and the own-role rule before they write.
drop trigger if exists ${ctx.trigger("organization_role_guard")} on ${n.m};
drop function if exists ${ctx.fn("guard_membership")}();
drop function if exists ${ctx.fn("guard_membership_role")}(${ctx.idType}, uuid, text, ${ctx.idType}, text);
`;
  }
  const ceiling = `
-- No client grants a role above their own permissions (can_assign), demotes
-- someone above them, or changes their own role. Only writes made as anon or
-- authenticated are checked: the service role, direct admin connections and
-- security definer functions (the module's own and the app's, which check
-- their own ceilings) pass.
-- The checks, as the module's owner, so the client needs no rights on the
-- roles tables. It only raises, so a direct call reveals nothing.
create or replace function ${ctx.fn("guard_membership_role")}(target_tenant ${ctx.idType}, target_member uuid, target_role text, previous_tenant ${ctx.idType}, previous_role text)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if target_member = auth.uid() then
    raise exception 'You cannot change your own role' using errcode = '42501', hint = 'ORGANIZATION_SELF_ROLE';
  end if;
  if not better_supabase.can_assign(target_tenant, ${assignableRole(ctx, "target_role")})
    or (previous_tenant is not null and not better_supabase.can_assign(previous_tenant, ${assignableRole(ctx, "previous_role")})) then
    raise exception 'That role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
end;
$$;
revoke execute on function ${ctx.fn("guard_membership_role")}(${ctx.idType}, uuid, text, ${ctx.idType}, text) from public, anon;
grant execute on function ${ctx.fn("guard_membership_role")}(${ctx.idType}, uuid, text, ${ctx.idType}, text) to authenticated, service_role;

-- Security invoker, so current_user is the role that wrote the row.
create or replace function ${ctx.fn("guard_membership")}()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not (${CLIENT_WRITE}) then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.${n.role} is not distinct from old.${n.role}${disabledAt === undefined ? "" : ` and new.${disabledAt} is not distinct from old.${disabledAt}`} then
    return new;
  end if;
  perform ${ctx.fn("guard_membership_role")}(
    new.${n.tenant}, new.${n.user}, new.${n.role}::text,
    case when tg_op = 'UPDATE' then old.${n.tenant} end,
    case when tg_op = 'UPDATE' then old.${n.role}::text end
  );
  return new;
end;
$$;
drop trigger if exists ${ctx.trigger("organization_role_guard")} on ${n.m};
create trigger ${ctx.trigger("organization_role_guard")} before insert or update on ${n.m}
  for each row execute function ${ctx.fn("guard_membership")}();
revoke execute on function ${ctx.fn("guard_membership")}() from public, anon, authenticated;
`;
  return `${invariant}${ceiling}`;
}

function members(ctx: ModuleContext, n: OrganizationNames): string {
  const id = ctx.idType;
  const p = MODULE_PERMISSIONS.organizations;
  const can = (action: keyof typeof p) =>
    `(${SERVICE_CALLER} or coalesce(better_supabase.member_can(auth.uid(), organization, ${ctx.permission(action, p[action])}), false))`;
  const active = `
  if not (${activeOrganization(ctx, n, "organization")}) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;`;
  const change = (user: string, kind: string) =>
    ctx.hook("after_member_change", [
      [id, "organization"],
      ["uuid", user],
      ["text", sqlString(kind)],
    ]);
  const subject = "'organizations/' || organization::text";
  const lastUsed = ctx.of("tenant").has("memberships", "lastUsedAt")
    ? `update ${n.m} set ${ctx.of("tenant").col("memberships", "lastUsedAt")} = now()
  where ${n.tenant} = organization and ${n.user} = auth.uid();
  return found;`
    : "return false;";
  const former = sqlString(ctx.text("formerOwnerRole", "admin"));
  const disabledAt = membershipDisabledAt(ctx);
  const suspendedOwner =
    disabledAt === undefined
      ? ""
      : `
  if exists (select 1 from ${n.m} m where m.${n.tenant} = organization and m.${n.user} = new_owner and m.${disabledAt} is not null) then
    raise exception 'The new owner is suspended' using errcode = '42501', hint = 'ORGANIZATION_MEMBER_SUSPENDED';
  end if;`;
  return `
-- Errors carry a code in the hint: ORGANIZATION_FORBIDDEN, ORGANIZATION_DISABLED, ORGANIZATION_NOT_MEMBER,
-- ORGANIZATION_SELF, ORGANIZATION_SELF_ROLE, ORGANIZATION_ROLE_CEILING, ORGANIZATION_ROLE_UNKNOWN, ORGANIZATION_OWNER_REQUIRED.
create or replace function ${ctx.fn("update_member_role")}(organization ${id}, member uuid, role text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  previous text;
  previous_assignable text;
begin
  if not ${can("updateRole")}${platformOverride(ctx, "updateRolePlatform")} then
    raise exception 'Not allowed to change roles' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;${active}${checkRole(ctx, "role", "organization")}
  select ${roleNameOf(ctx.of("tenant"), "m")}, ${assignableRole(ctx, `m.${n.role}`)} into previous, previous_assignable
  from ${n.m} m where m.${n.tenant} = organization and m.${n.user} = member;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  -- Checked here whatever sql.modules.organizations.options.assignmentGuard
  -- says: a guard that checks only client writes never sees this function's.
  if not (${SERVICE_CALLER}) and member = auth.uid() then
    raise exception 'You cannot change your own role' using errcode = '42501', hint = 'ORGANIZATION_SELF_ROLE';
  end if;
  if not better_supabase.can_assign(organization, previous_assignable)
    or not better_supabase.can_assign(organization, ${assignableRole(ctx, `(${roleValue(ctx, "role", "organization")})`)}) then
    raise exception 'That role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
  update ${n.m} set ${n.role} = ${roleValue(ctx, "role", "organization")}
  where ${n.tenant} = organization and ${n.user} = member;
  ${change("member", "role")}
  ${ctx.record({ type: "organization.role_changed", payload: event("organization", "member", ", 'role', role, 'previousRole', previous"), subject, tenant: "organization", audit: { category: "membership", targetType: "user", recordId: "member::text" } })}
  return true;
end;
$$;

create or replace function ${ctx.fn("remove_member")}(organization ${id}, member uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  current_role_value text;
begin
  if member = auth.uid() then
    raise exception 'Leave the organization instead' using errcode = '22023', hint = 'ORGANIZATION_SELF';
  end if;
  if not ${can("removeMember")}${platformOverride(ctx, "removeMemberPlatform")} then
    raise exception 'Not allowed to remove members' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  select ${assignableRole(ctx, `m.${n.role}`)} into current_role_value from ${n.m} m where m.${n.tenant} = organization and m.${n.user} = member;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if not better_supabase.can_assign(organization, current_role_value) then
    raise exception 'That member''s role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
  delete from ${n.m} where ${n.tenant} = organization and ${n.user} = member;
  ${change("member", "removed")}
  ${ctx.record({ type: "organization.member_removed", payload: event("organization", "member"), subject, tenant: "organization", audit: { category: "membership", targetType: "user", recordId: "member::text" } })}
  return true;
end;
$$;

create or replace function ${ctx.fn("leave_organization")}(organization ${id})
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
begin
  delete from ${n.m} where ${n.tenant} = organization and ${n.user} = me;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  ${change("me", "left")}
  ${ctx.record({ type: "organization.member_left", payload: event("organization", "me"), subject, tenant: "organization", audit: { category: "membership", targetType: "user", recordId: "me::text" } })}
  return true;
end;
$$;

-- Makes new_owner an owner in one transaction; a calling owner becomes
-- former_role (modules.organizations.options.formerOwnerRole).
create or replace function ${ctx.fn("transfer_ownership")}(organization ${id}, new_owner uuid, former_role text default ${former})
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
begin
  if not ${can("transferOwnership")} then
    raise exception 'Not allowed to transfer ownership' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  -- Only an owner hands ownership on, so the permission alone can't make its
  -- holder an owner.
  if not (${SERVICE_CALLER}) and not exists (
    select 1 from ${n.m} m where m.${n.tenant} = organization and m.${n.user} = me and ${isOwner(ctx, n, "m")}
  ) then
    raise exception 'Only an owner can transfer ownership' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;${active}${checkRole(ctx, "former_role", "organization")}
  if not exists (select 1 from ${n.m} m where m.${n.tenant} = organization and m.${n.user} = new_owner) then
    raise exception 'The new owner must be a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if better_supabase.user_disabled(new_owner) then
    raise exception 'The new owner is disabled' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;${suspendedOwner}
  -- One statement for both rows, so a statement-level guard on the number of
  -- owners sees the transfer as a whole.
  update ${n.m} m set ${n.role} = case
      when m.${n.user} = new_owner then ${roleValue(ctx, sqlString(n.ownerRole), "organization")}
      else ${roleValue(ctx, "former_role", "organization")}
    end
  where m.${n.tenant} = organization
    and (m.${n.user} = new_owner
      or (me is not null and me <> new_owner and m.${n.user} = me and ${isOwner(ctx, n, "m")}));
  ${change("new_owner", "owner")}
  ${ctx.record({ type: "organization.ownership_transferred", payload: event("organization", "new_owner", `, 'role', ${sqlString(n.ownerRole)}`), subject, tenant: "organization", audit: { category: "membership", targetType: "user", recordId: "new_owner::text" } })}
  return true;
end;
$$;

-- Records that the caller opened the organization (the last_used_at column of
-- memberships, when it has one), for "recent organizations" lists.
create or replace function ${ctx.fn("mark_used")}(organization ${id})
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  ${lastUsed}
end;
$$;
`;
}

/**
 * `switch_organization(organization)`: makes organization the caller's active tenant through
 * `sql.modules.access.activeTenant`. A claim source writes \`app_metadata\` and
 * returns refresh = true, so the client refreshes its session.
 */
function switcher(ctx: ModuleContext, n: OrganizationNames): string {
  const source = activeTenantSource(ctx);
  let write: string;
  let refresh = "false";
  if (source === "claim") {
    write = `update auth.users
  set raw_app_meta_data = coalesce(raw_app_meta_data, '{}') || jsonb_build_object(${sqlString(ctx.claims.tenant)}, organization::text)
  where id = me;`;
    refresh = "true";
  } else if (source === "resolver") {
    write = "-- The server's tenant resolver picks the tenant per request.";
  } else {
    const profile = columnRef(
      "sql.modules.access.activeTenant.profileColumn",
      source.profileColumn,
    );
    write = `update ${profile.table} set ${profile.column} = organization where ${sqlIdent(source.key ?? "id")} = me;`;
  }
  const tenantModule = ctx.of("tenant");
  const lastUsed = tenantModule.has("memberships", "lastUsedAt")
    ? `
  update ${n.m} set ${tenantModule.col("memberships", "lastUsedAt")} = now() where ${n.tenant} = organization and ${n.user} = me;`
    : "";
  return `
-- Makes organization the caller's active organization (modules.access.activeTenant).
create or replace function ${ctx.fn("switch_organization")}(organization ${ctx.idType})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
begin
  if me is null or not exists (select 1 from ${n.m} m where m.${n.tenant} = organization and m.${n.user} = me) then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if not (${activeOrganization(ctx, n, "organization")}) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  ${write}${lastUsed}
  ${ctx.record({ type: "organization.switched", payload: event("organization", "me"), subject: "'organizations/' || organization::text", tenant: "organization", audit: false })}
  return jsonb_build_object('organization_id', organization, 'refresh', ${refresh});
end;
$$;
`;
}

const FUNCTIONS = (id: string): readonly (readonly [string, string])[] => [
  ["create_organization", "jsonb"],
  ["update_organization", `${id}, jsonb`],
  ["delete_organization", id],
  ["update_member_role", `${id}, uuid, text`],
  ["remove_member", `${id}, uuid`],
  ["leave_organization", id],
  ["transfer_ownership", `${id}, uuid, text`],
  ["mark_used", id],
  ["switch_organization", id],
  ["list_my_organizations", ""],
  ["list_members", id],
];

/** The module's functions, without delete_organization under deleteMode "none". */
const functionsOf = (
  ctx: ModuleContext,
  id: string,
): readonly (readonly [string, string])[] => [
  ...FUNCTIONS(id).filter(
    ([name]) => name !== "delete_organization" || deleteMode(ctx) !== "none",
  ),
  ...(ctx.installed("invitations")
    ? ([["list_organization_invitations", id]] as const)
    : []),
  ...(membershipDisabledAt(ctx) === undefined
    ? []
    : ([
        ["suspend_member", `${id}, uuid`],
        ["resume_member", `${id}, uuid`],
      ] as const)),
];

function organizationsSql(ctx: ModuleContext): string {
  const n = namesOf(ctx);
  const grants = functionsOf(ctx, ctx.idType)
    .map(
      ([
        name,
        args,
      ]) => `revoke execute on function ${ctx.fn(name)}(${args}) from public, anon;
grant execute on function ${ctx.fn(name)}(${args}) to authenticated, service_role;`,
    )
    .join("\n");
  return `${schemaPreamble(ctx)}
${table(ctx, n)}${tenantKeys(ctx, n)}${slugCheck(ctx, n)}${create(ctx, n)}${remove(ctx, n)}${guards(ctx, n)}${members(ctx, n)}${memberSuspension(
    ctx,
    n,
    {
      isOwner: (alias) => isOwner(ctx, n, alias),
      activeOrganization: (organization) =>
        activeOrganization(ctx, n, organization),
      platformOverride: platformOverride(ctx, "removeMemberPlatform"),
      assignableRole: (stored) => assignableRole(ctx, stored),
      event,
    },
  )}${switcher(ctx, n)}${organizationReads(ctx, n)}
${grants}`;
}

export const ORGANIZATIONS: ModuleDefinition = {
  internal: ["guard_membership_role"],
  name: "organizations",
  title: "Organizations",
  description:
    "create_organization(attrs) with slug rules and an after-create hook, a deferred owner check, an assignment ceiling, and member functions (role change, remove, leave, transfer ownership) on the access contract.",
  requires: ["tenant", "access", "updated-at"],
  integrates: [
    "audit",
    "data-lifecycle",
    "entitlements",
    "invitations",
    "reserved-slugs",
  ],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  names: NAMES,
  contract: (ctx) =>
    functionsOf(ctx, "{id}").map(([name, args]) => ({
      name,
      args: args === "" ? [] : args.split(", "),
      returns:
        name === "create_organization"
          ? "{id}"
          : name === "switch_organization"
            ? "jsonb"
            : name.startsWith("list_")
              ? "record"
              : "boolean",
    })),
  build: organizationsSql,
};
