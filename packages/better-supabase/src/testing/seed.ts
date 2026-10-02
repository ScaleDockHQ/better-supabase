import type { BetterSupabase } from "../core/define.ts";
import type { SqlClient } from "../postgres/executor.ts";
import type {
  AnyFunctions,
  AnyModels,
  ColumnMeta,
  SchemaMeta,
  TableMeta,
} from "../schema/types.ts";

/** Named rows per table, in app casing: `{ customers: { acme: { ... } } }`. */
export type SeedFixtures<M extends AnyModels> = {
  readonly [K in keyof M]?: Readonly<Record<string, M[K]["Insert"]>>;
};

/** Rejects columns that are not in the table's Insert type. */
export type ExactSeed<M extends AnyModels, S> = {
  readonly [K in keyof S]: K extends keyof M
    ? {
        readonly [N in keyof S[K]]: {
          readonly [C in keyof S[K][N]]: C extends keyof M[K]["Insert"]
            ? S[K][N][C]
            : never;
        };
      }
    : never;
};

// SAFETY: the symbol is only read through this constant, so typing it as unique
// symbol is sound.
const SEED: unique symbol = Symbol.for("better-supabase.seed") as never;

export interface Seed<S> {
  readonly [SEED]: true;
  /** The fixtures as given, so tests can reference `seed.rows.customers.acme.id`. */
  readonly rows: S;
  /** One `insert ... on conflict do nothing` per table, parents before children. */
  statements(): string[];
  sql(): string;
  /** Inserts the fixtures, e.g. in a test's `beforeAll`. Needs a service-role client. */
  insert(sql: SqlClient): Promise<void>;
}

export function isSeed(value: unknown): value is Seed<unknown> {
  return typeof value === "object" && value !== null && SEED in value;
}

const quote = (text: string): string => `'${text.replaceAll("'", "''")}'`;

function arrayLiteral(values: readonly unknown[]): string {
  const items = values.map((value) => {
    if (value === null) return "NULL";
    if (Array.isArray(value)) return arrayLiteral(value);
    const text = value instanceof Date ? value.toISOString() : String(value);
    return `"${text.replaceAll(/[\\"]/g, "\\$&")}"`;
  });
  return `{${items.join(",")}}`;
}

function literal(value: unknown, column: ColumnMeta, where: string): string {
  if (value === null) return "null";
  if (column.json) return quote(JSON.stringify(value));
  if (Array.isArray(value)) return quote(arrayLiteral(value));
  if (value instanceof Date) return quote(value.toISOString());
  const kind = typeof value;
  switch (kind) {
    case "string":
      // SAFETY: kind is typeof value, so this case only runs for strings.
      return quote(value as string);
    case "boolean":
    case "bigint":
      return String(value);
    case "number":
      if (!Number.isFinite(value))
        throw new TypeError(
          `${where}: ${String(value)} is not a finite number`,
        );
      return String(value);
    case "object":
    case "function":
    case "symbol":
    case "undefined":
      throw new TypeError(`${where}: unsupported value of type ${kind}`);
    default: {
      const unreachable: never = kind;
      throw new TypeError(
        `${where}: unsupported value of type ${String(unreachable)}`,
      );
    }
  }
}

const ident = (name: string): string => `"${name.replaceAll('"', '""')}"`;

/** Parents first (by forward relations), otherwise in the order given. */
function order(meta: SchemaMeta, keys: readonly string[]): string[] {
  const sorted: string[] = [];
  const visiting = new Set<string>();
  const visit = (key: string): void => {
    if (sorted.includes(key) || visiting.has(key)) return;
    visiting.add(key);
    for (const relation of Object.values(meta.tables[key]?.relations ?? {})) {
      if (
        relation.direction === "forward" &&
        relation.table !== key &&
        keys.includes(relation.table)
      ) {
        visit(relation.table);
      }
    }
    visiting.delete(key);
    sorted.push(key);
  };
  for (const key of keys) visit(key);
  return sorted;
}

function statement(
  table: TableMeta,
  rows: Readonly<Record<string, Record<string, unknown>>>,
): string | undefined {
  const entries = Object.entries(rows);
  if (entries.length === 0) return undefined;
  const columns: string[] = [];
  for (const [, row] of entries) {
    for (const [key, value] of Object.entries(row)) {
      if (value === undefined || columns.includes(key)) continue;
      const column = table.columns[key];
      if (!column)
        throw new TypeError(`seed ${table.key}: unknown column "${key}"`);
      if (column.generated)
        throw new TypeError(
          `seed ${table.key}: "${key}" is a generated column`,
        );
      columns.push(key);
    }
  }
  const values = entries.map(([name, row]) => {
    const cells = columns.map((key) =>
      row[key] === undefined
        ? "default"
        : literal(
            row[key],
            table.columns[key]!,
            `seed ${table.key}.${name}.${key}`,
          ),
    );
    return `  (${cells.join(", ")})`;
  });
  const target = `${ident(table.schema)}.${ident(table.name)}`;
  const list = columns.map((key) => ident(table.columns[key]!.db)).join(", ");
  return `insert into ${target} (${list}) values\n${values.join(",\n")}\non conflict do nothing;`;
}

/**
 * Typed fixtures shared by `supabase/seeds` and your tests. Rows use app
 * casing and Insert types; `better-supabase seed` renders them to SQL.
 *
 * ```ts
 * export const seed = defineSeed(sb, {
 *   organizations: { acme: { id: ACME, name: 'Acme' } },
 *   customers: { first: { organizationId: ACME, name: 'First customer' } },
 * });
 * ```
 */
export function defineSeed<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  const S extends SeedFixtures<M>,
>(sb: BetterSupabase<M, D, F, E>, fixtures: S & ExactSeed<M, S>): Seed<S> {
  const meta = sb.meta;
  const statements = (): string[] => {
    const keys = Object.keys(fixtures).filter(
      (key) => fixtures[key] !== undefined,
    );
    for (const key of keys) {
      const table = meta.tables[key];
      if (!table) throw new TypeError(`seed: unknown table "${key}"`);
      if (table.kind === "view")
        throw new TypeError(`seed: "${key}" is a view`);
    }
    return order(meta, keys).flatMap((key) => {
      // SAFETY: the loop above rejected unknown tables, and each fixture maps
      // row names to rows.
      const sql = statement(
        meta.tables[key]!,
        fixtures[key] as Readonly<Record<string, Record<string, unknown>>>,
      );
      return sql ? [sql] : [];
    });
  };
  return {
    [SEED]: true,
    rows: fixtures,
    statements,
    sql: () => statements().join("\n\n"),
    async insert(sql) {
      for (const text of statements()) await sql.queryRaw(text);
    },
  };
}
