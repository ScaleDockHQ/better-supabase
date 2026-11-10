import type { ExtraColumn } from "./context.ts";

import { sqlIdent } from "../core/template.ts";

/**
 * The columns the app's files make fields of a block's table: those not in
 * `skip`, marked `app` so the block doesn't add them. They are the columns an
 * app file adds to a block's table, and the ones a table the app creates lists
 * in its `@bsb fields` comment.
 */
function appExtraColumns(
  source: {
    readonly appColumns?: Readonly<
      Record<
        string,
        readonly { readonly name: string; readonly type: string }[]
      >
    >;
  },
  table: () => { readonly schema: string; readonly name: string },
  skip: ReadonlySet<string>,
): readonly ExtraColumn[] {
  const { schema, name } = table();
  const key = `${schema}.${name}`;

  return (source.appColumns?.[key] ?? [])
    .filter((column) => !skip.has(column.name))
    .map((column): ExtraColumn => ({
      name: column.name,
      ident: sqlIdent(column.name),
      type: column.type,
      app: true,
    }));
}

/** What `resolveExtraColumns` reads from a module's context. */
interface ExtraColumnsInput {
  readonly known:
    | {
        readonly columns: Readonly<Record<string, unknown>>;
        readonly yieldsToExtra?: readonly string[];
      }
    | undefined;
  readonly table: string;
  readonly reserved: readonly string[];
  readonly column: (table: string, logical: string) => string | null;
  readonly tableName: (table: string) => {
    readonly schema: string;
    readonly name: string;
  };
  readonly source: Parameters<typeof appExtraColumns>[0];
}

/**
 * The extra columns of one table: the ones an app file adds to it, as fields,
 * except those that shadow a column the block returns or a reserved key.
 */
export function resolveExtraColumns(
  input: ExtraColumnsInput,
): readonly ExtraColumn[] {
  const { known, table } = input;

  if (known === undefined) {
    return [];
  }

  // Look up this table's own entry before anything else: a read of the map's
  // keys would make every module with extra columns depend on which other
  // tables the app's files alter (ADR 0638).
  const { schema, name } = input.tableName(table);

  if ((input.source.appColumns?.[`${schema}.${name}`] ?? []).length === 0) {
    return [];
  }

  const taken = new Set([
    ...input.reserved,
    ...Object.keys(known.columns)
      .filter((logical) => !known.yieldsToExtra?.includes(logical))
      .flatMap((logical) => input.column(table, logical) ?? []),
  ]);

  return appExtraColumns(input.source, () => input.tableName(table), taken);
}
