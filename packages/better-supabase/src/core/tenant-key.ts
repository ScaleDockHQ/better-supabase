/**
 * The tenant of a block result row. The SQL names it `organization_id`, and the
 * block-names middleware reads a configured tenant column back as `tenant_id`,
 * so a row from an app with `sql.tenantColumn` carries the second key. A parser
 * reads both.
 */
export function tenantOf(row: Readonly<Record<string, unknown>>): unknown {
  return row["organization_id"] ?? row["tenant_id"];
}
