/** `create table` with its columns and table constraints, one item per line. */
export function createTable(
  name: string,
  items: readonly string[],
  suffix = "",
): string {
  return `create table ${name} (\n${items.map((item) => `  ${item}`).join(",\n")}\n)${suffix};`;
}

/** `alter table <table> enable row level security`. */
export const enableRowSecurity = (table: string): string =>
  `alter table ${table} enable row level security;`;
