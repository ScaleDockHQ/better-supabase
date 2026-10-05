import { randomUUID } from "node:crypto";
import { DatabaseSync, type SQLInputValue } from "node:sqlite";

import type {
  PowerSyncDatabaseLike,
  SqliteContextLike,
} from "../../src/powersync/index.ts";
import type { ColumnMeta, SchemaMeta } from "../../src/schema/types.ts";

function sqliteType(column: ColumnMeta): string {
  if (column.array || column.json) return "TEXT";
  switch (column.type) {
    case "bool":
    case "int2":
    case "int4":
    case "int8":
      return "INTEGER";
    case "float4":
    case "float8":
    case "numeric":
      return "REAL";
    default:
      return "TEXT";
  }
}

function defaultOf(column: ColumnMeta): string {
  if (!column.hasDefault) return "";
  if (column.type === "timestamptz")
    return " default (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))";
  if (column.json) return " default '{}'";
  if (column.type === "bool") return " default 0";
  const first = column.enum?.[0];
  return first === undefined ? "" : ` default '${first}'`;
}

const quote = (name: string): string => `"${name}"`;

/** SQLite tables shaped like the schema, as PowerSync's views would be. */
export function sqliteDdl(meta: SchemaMeta): string[] {
  return Object.values(meta.tables)
    .filter((table) => table.kind === "table")
    .map((table) => {
      const columns = Object.values(table.columns).map(
        (column) =>
          `${quote(column.db)} ${sqliteType(column)}${column.nullable || column.hasDefault ? "" : " not null"}${defaultOf(column)}`,
      );
      const key = table.primaryKey.map((app) => table.columns[app]!.db);
      const constraints = [
        `primary key (${key.map(quote).join(", ")})`,
        ...Object.values(table.uniqueKeys).map(
          (unique) =>
            `unique (${unique.map((app) => quote(table.columns[app]!.db)).join(", ")})`,
        ),
      ];
      return `create table ${quote(table.name)} (${[...columns, ...constraints].join(", ")})`;
    });
}

const WRITES = /^\s*(?:insert into|update|delete from)\s+"([^"]+)"/i;

/**
 * A `PowerSyncDatabaseLike` over `node:sqlite`, with the `uuid()` function
 * PowerSync registers and change notifications for written tables.
 */
export function createSqlite(meta: SchemaMeta): {
  readonly db: PowerSyncDatabaseLike;
  readonly sqlite: DatabaseSync;
  readonly statements: string[];
} {
  const sqlite = new DatabaseSync(":memory:");
  sqlite.function("uuid", () => randomUUID());
  for (const statement of sqliteDdl(meta)) sqlite.exec(statement);
  const statements: string[] = [];
  const listeners = new Set<{
    readonly tables: readonly string[] | undefined;
    readonly onChange: (event: { changedTables: string[] }) => unknown;
  }>();
  let pending = new Set<string>();
  const notify = (): void => {
    const changed = [...pending];
    pending = new Set();
    if (changed.length === 0) return;
    for (const listener of listeners) {
      const relevant = listener.tables
        ? changed.filter((table) => listener.tables!.includes(table))
        : changed;
      if (relevant.length > 0)
        void listener.onChange({ changedTables: relevant });
    }
  };
  let depth = 0;
  const context: SqliteContextLike = {
    getAll<T>(sql: string, parameters: unknown[] = []): Promise<T[]> {
      statements.push(sql);
      try {
        // SAFETY: the executor binds only SqliteValue parameters; rows are plain objects.
        const rows = sqlite
          .prepare(sql)
          .all(...(parameters as SQLInputValue[])) as T[];
        return Promise.resolve(rows);
      } catch (cause) {
        return Promise.reject(cause);
      }
    },
    execute(sql: string, parameters: unknown[] = []): Promise<unknown> {
      statements.push(sql);
      try {
        // SAFETY: the executor binds only SqliteValue parameters.
        const result = sqlite
          .prepare(sql)
          .run(...(parameters as SQLInputValue[]));
        const table = WRITES.exec(sql)?.[1];
        if (table) pending.add(table);
        if (depth === 0) notify();
        return Promise.resolve(result);
      } catch (cause) {
        return Promise.reject(cause);
      }
    },
  };
  const db: PowerSyncDatabaseLike = {
    ...context,
    async writeTransaction<T>(
      callback: (tx: SqliteContextLike) => Promise<T>,
    ): Promise<T> {
      sqlite.exec("begin");
      depth += 1;
      try {
        const result = await callback(context);
        sqlite.exec("commit");
        depth -= 1;
        notify();
        return result;
      } catch (cause) {
        sqlite.exec("rollback");
        depth -= 1;
        pending = new Set();
        throw cause;
      }
    },
    onChange(handler, options) {
      const listener = {
        tables: options?.tables,
        onChange: handler.onChange,
      };
      listeners.add(listener);
      const remove = (): void => {
        listeners.delete(listener);
      };
      options?.signal?.addEventListener("abort", remove, { once: true });
      return remove;
    },
  };
  return { db, sqlite, statements };
}
