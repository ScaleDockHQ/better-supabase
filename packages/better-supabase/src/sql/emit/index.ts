/** `create index`, `unique` and partial (`where`) as the caller asks. */
export function createIndex(options: {
  readonly name: string;
  readonly table: string;
  readonly columns: readonly string[];
  readonly unique?: boolean;
  readonly where?: string;
  readonly using?: string;
}): string {
  const method = options.using === undefined ? "" : ` using ${options.using}`;
  const where = options.where === undefined ? "" : ` where ${options.where}`;

  return `create ${options.unique === true ? "unique " : ""}index ${options.name} on ${options.table}${method} (${options.columns.join(", ")})${where};`;
}
