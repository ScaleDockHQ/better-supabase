import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { raise } from "../shared.ts";
import { roleNameFrom, roleThrough } from "./memberships.ts";
import { accessModel, roleNames } from "./permissions-model.ts";

/**
 * The tenant column of a roles table with tenant custom roles: the
 * `roleThrough` table's `tenant`, or the catalog's mapped `roles.tenant`.
 */
function rolesTenantColumn(ctx: BlockSqlContext): string | undefined {
  const through = roleThrough(ctx.of("memberships"));

  if (through) {
    return through.tenant;
  }

  if (accessModel(ctx) !== "catalog") {
    return undefined;
  }

  const access = ctx.of("permissions");

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
  ctx: BlockSqlContext,
  tenant: string | undefined,
): { readonly where: string; readonly order: string } {
  const column = rolesTenantColumn(ctx);

  if (column === undefined || tenant === undefined) {
    return { where: "", order: "" };
  }

  return {
    where: ` and (r.${column} = ${tenant} or r.${column} is null)`,
    order: `, (r.${column} is not null) desc`,
  };
}

/**
 * A role argument as the membership role column stores it: the name for the
 * roles model, the catalog role id (looked up by id or key) for `catalog`. With
 * `tenant`, a key resolves among that tenant's roles. A `roleThrough` lookup
 * keeps to the rows its `where` accepts unless `tenantRoles` is false.
 */
export function roleValue(
  ctx: BlockSqlContext,
  expr: string,
  tenant?: string,
  tenantRoles = true,
): string {
  const scope = tenantRoleScope(ctx, tenant);
  const through = roleThrough(ctx.of("memberships"));

  if (through) {
    const text = `(${expr})::text`;

    const only =
      tenantRoles && through.where
        ? ` and (${through.where.replaceAll("{row}", "r")})`
        : "";

    return `(select r.${through.id} from ${through.table} r where (r.${through.id}::text = ${text} or r.${through.column}::text = ${text})${only}${scope.where} order by (r.${through.id}::text = ${text}) desc${scope.order} limit 1)`;
  }

  if (accessModel(ctx) !== "catalog") {
    return expr;
  }

  const access = ctx.of("permissions");
  const rid = access.col("roles", "id");
  const key = access.col("roles", "key");
  const text = `(${expr})::text`;

  return `(select r.${rid} from ${access.table("roles")} r where (r.${rid}::text = ${text} or r.${key} = ${text})${scope.where} order by (r.${rid}::text = ${text}) desc${scope.order} limit 1)`;
}

/**
 * A stored membership role as `can_assign` takes it: the role name with
 * `blocks.memberships.options.roleThrough`, the stored value otherwise.
 */
export function assignableRole(ctx: BlockSqlContext, stored: string): string {
  const tenant = ctx.of("memberships");

  return roleThrough(tenant) ? roleNameFrom(tenant, stored) : `${stored}::text`;
}

/** Raises `ORGANIZATION_ROLE_UNKNOWN` for a role the access model doesn't know. */
export function checkRole(
  ctx: BlockSqlContext,
  expr: string,
  tenant: string,
): string {
  const model = accessModel(ctx);
  const through = roleThrough(ctx.of("memberships")) !== undefined;

  if (!through && (model === "provider" || model === "custom")) {
    return "";
  }

  const known =
    model === "roles" && !through
      ? `${expr} = any (array[${roleNames(ctx).map(sqlString).join(", ")}]::text[])`
      : `${roleValue(ctx, expr, tenant)} is not null`;

  return `
  if not (${known}) then
    ${raise("Unknown role %", "22023", "ORGANIZATION_ROLE_UNKNOWN", expr)}
  end if;`;
}
