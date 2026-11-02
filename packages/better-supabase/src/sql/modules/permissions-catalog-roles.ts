import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { accessModel } from "./permissions-model.ts";

/**
 * The tenant roles every catalog starts with. They are system rows: one set for
 * the whole database, shared by every organization, so they are not tenant
 * defaults (`seeds` insert one row set per organization) and live in the
 * module's data step instead.
 */
export const CATALOG_ROLES = ["owner", "admin", "member"] as const;

/**
 * `owner`, `admin` and `member` in the role catalog, added when missing. A role
 * the app already has keeps its row and id, so memberships that point at it
 * stay valid. Only the catalog model has the table.
 */
export function catalogRoles(ctx: BlockSqlContext): string {
  // An app's own role table may have no default id, so the module leaves it alone.
  if (accessModel(ctx) !== "catalog" || !ctx.owns("roles")) {
    return "";
  }

  const roles = ctx.table("roles");
  const key = ctx.col("roles", "key");

  const scope = ctx.has("roles", "scope")
    ? ctx.col("roles", "scope")
    : undefined;

  const columns = scope === undefined ? key : `${key}, ${scope}`;

  const values = CATALOG_ROLES.map(
    (role) => `(${sqlString(role)}${scope === undefined ? "" : ", 'tenant'"})`,
  ).join(", ");

  return `-- The roles every organization can assign: one row each for the database.
insert into ${roles} (${columns})
select ${scope === undefined ? "v.k" : "v.k, v.s"}
from (values ${values}) as v (${scope === undefined ? "k" : "k, s"})
where not exists (select 1 from ${roles} x where x.${key} = v.k);`;
}
