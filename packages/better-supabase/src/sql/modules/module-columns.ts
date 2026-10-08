import type { ModuleContext } from "../context.ts";

export type Columns<T> = { readonly [K in keyof T]: string };

/** The quoted column names of a module table, keyed like its spec. */
export function columnsOf<T extends Readonly<Record<string, string>>>(
  ctx: ModuleContext,
  table: string,
  spec: T,
): Columns<T> {
  // SAFETY: the keys are spec's own keys, each mapped to its quoted name.
  return Object.fromEntries(
    Object.keys(spec).map((key) => [key, ctx.col(table, key)]),
  ) as Columns<T>;
}

/** `jsonb_build_object` over every column of a spec, keyed by column name. */
export function rowJson<T extends Readonly<Record<string, string>>>(
  spec: T,
  columns: Columns<T>,
  row: string,
): string {
  const quoted: Readonly<Record<string, string>> = columns;
  const pairs = Object.entries(spec).map(
    ([key, name]) => `'${name}', ${row}.${quoted[key]!}`,
  );
  return `jsonb_build_object(${pairs.join(", ")})`;
}
