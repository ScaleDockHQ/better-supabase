import type { ExtraColumn } from "./context.ts";

import { isSqlType } from "../config/sql-type.ts";
import { sqlIdent } from "../core/template.ts";

const EXTRA_COLUMN = /^[a-z_][a-z0-9_]*$/;

function checkedExtraColumns(
  at: string,
  value: object,
  taken: ReadonlySet<string>,
): readonly ExtraColumn[] {
  return Object.entries(value).map(([name, type]: [string, unknown]) => {
    if (!EXTRA_COLUMN.test(name) || name.length > 63) {
      throw new TypeError(`${at}: "${name}" is not a valid column name`);
    }

    if (taken.has(name)) {
      throw new TypeError(
        `${at}.${name} shadows a column the module already returns`,
      );
    }

    if (typeof type !== "string" || !isSqlType(type)) {
      throw new TypeError(
        `${at}.${name} must be a SQL type such as "text not null default 'en'"`,
      );
    }

    return { name, ident: sqlIdent(name), type };
  });
}

/** Whether the app's files add a column to any table. */
function hasAppColumns(source: {
  readonly appColumns?: Readonly<Record<string, readonly unknown[]>>;
}): boolean {
  return Object.keys(source.appColumns ?? {}).length > 0;
}

/**
 * The columns an app file adds to a block's table, as fields: those not in
 * `skip`, marked `app` so the block doesn't add them. A table the app creates
 * has its own columns, so only a block's table takes them.
 */
function appExtraColumns(
  source: {
    readonly appColumns?: Readonly<
      Record<
        string,
        readonly { readonly name: string; readonly type: string }[]
      >
    >;
    readonly ownTables?: Readonly<Record<string, string>>;
  },
  table: () => { readonly schema: string; readonly name: string },
  skip: ReadonlySet<string>,
): readonly ExtraColumn[] {
  if (!hasAppColumns(source)) {
    return [];
  }

  const { schema, name } = table();
  const key = `${schema}.${name}`;

  if (source.ownTables?.[key] !== undefined) {
    return [];
  }

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
  readonly module: string;
  /** `blocks.<name>.options.<key>`, for messages. */
  readonly at: string;
  readonly value: unknown;
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
 * The extra columns of one table: the ones `options.extraColumns` names,
 * checked against the columns the block returns, then the ones an app file
 * adds.
 */
export function resolveExtraColumns(
  input: ExtraColumnsInput,
): readonly ExtraColumn[] {
  const { value, known, table } = input;

  if (
    value !== undefined &&
    (typeof value !== "object" || value === null || Array.isArray(value))
  ) {
    throw new TypeError(`${input.at} must be an object`);
  }

  if (known === undefined) {
    if (value === undefined) {
      return [];
    }

    throw new TypeError(`Module "${input.module}" has no table "${table}"`);
  }

  if (value === undefined && !hasAppColumns(input.source)) {
    return [];
  }

  const taken = new Set([
    ...input.reserved,
    ...Object.keys(known.columns)
      .filter((logical) => !known.yieldsToExtra?.includes(logical))
      .flatMap((logical) => input.column(table, logical) ?? []),
  ]);

  const own =
    value === undefined ? [] : checkedExtraColumns(input.at, value, taken);

  return [
    ...own,
    ...appExtraColumns(
      input.source,
      () => input.tableName(table),
      new Set([...taken, ...own.map((extra) => extra.name)]),
    ),
  ];
}
