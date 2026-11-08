/** `alter table <table> add column <definition>`: a column the table lacks. */
export function addColumn(table: string, definition: string): string {
  return `alter table ${table} add column ${definition};`;
}
