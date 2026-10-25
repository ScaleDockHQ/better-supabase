const DEFAULT_TENANT_COLUMN = "tenant_id";

export function blockColumnName(
  where: { readonly module: string; readonly table: string },
  columns: Readonly<Record<string, string>>,
  name: string,
  tenantColumn: string | undefined,
  rename: (name: string) => string,
): string {
  if (name !== DEFAULT_TENANT_COLUMN || tenantColumn === undefined) {
    return rename(name);
  }

  const clash = Object.entries(columns).find(
    ([, other]) => rename(other) === tenantColumn,
  );

  if (clash !== undefined) {
    throw new TypeError(
      `sql.tenantColumn: "${tenantColumn}" is the name of ${where.table}.${clash[0]} in the ${where.module} module. Choose another name, or map blocks.${where.module}.columns.${where.table}.tenant.`,
    );
  }

  return tenantColumn;
}
