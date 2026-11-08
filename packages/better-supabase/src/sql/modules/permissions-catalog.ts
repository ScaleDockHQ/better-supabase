import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { auditTrigger } from "../row-audit.ts";
import { addForeignKey } from "../shared.ts";

/**
 * Registers the catalog tables with the audit log, so role, permission,
 * override and platform-role writes are audited under `access`.
 */
export function catalogAudit(ctx: BlockSqlContext): string {
  if (!ctx.installedModules.includes("audit")) {
    return "";
  }

  const tables = (
    [
      "roles",
      "permissions",
      "rolePermissions",
      "overrides",
      "platformAssignments",
    ] as const
  ).filter((table) => ctx.hasTable(table));

  // A schema diff reads the trigger `audit()` would create, so a declarative
  // layout declares it. Only the migrations workflow calls `audit()` in file
  // order, and it also removes the trigger when the audit config is off.
  if (!ctx.rerunnable) {
    if (!ctx.config.audit) {
      return "";
    }

    return `
-- The catalog is written directly by the service role, so a row trigger
-- audits it.
${tables
  .map((table) => {
    const { schema, name } = ctx.tableName(table);

    return auditTrigger(
      `${schema}.${name}`,
      {
        category: "access",
        ...(table === "overrides"
          ? {
              tenant_column: ctx.col("overrides", "tenant").replaceAll('"', ""),
            }
          : {}),
      },
      false,
    );
  })
  .join("\n")}`;
  }

  const call = (table: string): string => {
    const target = sqlString(ctx.table(table));

    if (!ctx.config.audit) {
      return `  perform better_supabase.unaudit(${target}::regclass);`;
    }

    const tenant =
      table === "overrides"
        ? sqlString(ctx.col("overrides", "tenant").replaceAll('"', ""))
        : "null";

    return `  execute format('select better_supabase.audit(%s::regclass, category => %L, tenant_column => %L)', quote_literal(${target}), 'access', ${tenant});`;
  };

  return `
-- The catalog is written directly by the service role, so a row trigger
-- audits it.
do $$
begin
${tables.map(call).join("\n")}
end;
$$;`;
}

/** A catalog role can't be deleted while a membership still holds it. */
export function membershipRoleKey(ctx: BlockSqlContext): string {
  const tenant = ctx.of("memberships");

  if (!tenant.owns("memberships")) {
    return "";
  }

  return `
${addForeignKey({
  table: tenant.table("memberships"),
  name: "memberships_role_fkey",
  column: tenant.col("memberships", "role"),
  references: `${ctx.table("roles")} (${ctx.col("roles", "id")})`,
  onDelete: "restrict",
})}`;
}
