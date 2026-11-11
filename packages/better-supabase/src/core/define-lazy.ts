import type { SchemaMeta, TableMeta } from "../schema/types.ts";
import type { Result } from "./result.ts";

import { installFunctions } from "../schema/define.ts";
import { isPlainObject } from "./clone.ts";
import { dbError } from "./errors.ts";
import { containsPlaceholder } from "./read-set.ts";
import { AsyncResult } from "./result.ts";
import { isQuerySpec } from "./spec.ts";

type Loader = NonNullable<SchemaMeta["tableLoaders"]>[string];

const tableLoads = new WeakMap<SchemaMeta, Map<string, Promise<void>>>();

const functionLoads = new WeakMap<SchemaMeta, Promise<void>>();

function loadTable(
  meta: SchemaMeta,
  key: string,
  load: NonNullable<SchemaMeta["tableLoaders"]>[string],
  register: (table: SchemaMeta["tables"][string]) => void,
): Promise<void> {
  let loads = tableLoads.get(meta);

  if (loads === undefined) {
    loads = new Map();
    tableLoads.set(meta, loads);
  }

  const pendingLoads = loads;
  let pending = pendingLoads.get(key);

  if (pending === undefined) {
    pending = load()
      .then((table) => {
        register(table);
      })
      .catch((error: unknown) => {
        pendingLoads.delete(key);
        throw error;
      });
    pendingLoads.set(key, pending);
  }

  return pending;
}

/**
 * A repository whose methods wait for the table module. The getter that returns
 * it is synchronous; the module load happens inside the call.
 */
export function lazyRepository<S>(
  meta: SchemaMeta,
  state: S,
  key: string,
  load: NonNullable<SchemaMeta["tableLoaders"]>[string],
  build: (state: S, key: string) => Record<string, unknown>,
  register: (table: SchemaMeta["tables"][string]) => void,
): Record<string, unknown> {
  return new Proxy(
    {},
    {
      get(_target, prop) {
        if (typeof prop !== "string" || prop === "then") {
          return;
        }

        return (...args: unknown[]) =>
          AsyncResult.from(async () => {
            await loadTable(meta, key, load, register);

            const repo = build(state, key);
            const method = repo[prop];

            if (typeof method !== "function") {
              throw new TypeError(
                `better-supabase: ${key}.${prop} is not a method`,
              );
            }

            // SAFETY: repository methods return a thenable Result.
            return (
              method as (...received: unknown[]) => Promise<Result<unknown>>
            ).apply(repo, args);
          });
      },
    },
  );
}

/** Every object key and string array item inside `value`. */
function argumentNames(value: unknown, names: Set<string>): Set<string> {
  if (Array.isArray(value)) {
    for (const item of value) {
      if (typeof item === "string") {
        names.add(item);
      } else {
        argumentNames(item, names);
      }
    }
  } else if (isPlainObject(value)) {
    for (const [key, item] of Object.entries(value)) {
      names.add(key);
      argumentNames(item, names);
    }
  }

  return names;
}

/**
 * Keys of the unloaded tables that relations named in `names` reach from
 * `table`, following loaded tables only.
 */
function missingTargets(
  meta: SchemaMeta,
  table: TableMeta,
  names: ReadonlySet<string>,
): [string, Loader][] {
  const missing: [string, Loader][] = [];
  const seen = new Set([table.key]);
  const queue = [table];

  for (const from of queue) {
    for (const [name, relation] of Object.entries(from.relations)) {
      if (!names.has(name) || seen.has(relation.table)) {
        continue;
      }

      seen.add(relation.table);
      const target = meta.tables[relation.table];

      if (target) {
        queue.push(target);
      } else {
        const load = meta.tableLoaders?.[relation.table];

        if (load !== undefined) {
          missing.push([relation.table, load]);
        }
      }
    }
  }

  return missing;
}

/**
 * Wraps a repository method of a lazy schema so the tables its arguments reach
 * through relations (includes, counts, relation filters, orderBy) load before
 * the query is built. A call that needs no load runs unchanged.
 */
export function withRelatedTables(
  meta: SchemaMeta,
  table: TableMeta,
  method: (...args: unknown[]) => unknown,
  register: (table: SchemaMeta["tables"][string]) => void,
): (...args: unknown[]) => unknown {
  return function related(this: unknown, ...args: unknown[]): unknown {
    const names = argumentNames(args, new Set());

    if (missingTargets(meta, table, names).length === 0) {
      return method.apply(this, args);
    }

    return AsyncResult.from(async () => {
      let missing = missingTargets(meta, table, names);

      while (missing.length > 0) {
        await Promise.all(
          missing.map(([key, load]) => loadTable(meta, key, load, register)),
        );
        missing = missingTargets(meta, table, names);
      }

      // SAFETY: repository methods that take relation arguments return a thenable Result.
      return method.apply(this, args) as Promise<Result<unknown>>;
    });
  };
}

/** Loads function metadata once, on the first `rpc` call. */
export async function ensureFunctions(meta: SchemaMeta): Promise<void> {
  if (
    meta.loadFunctions === undefined ||
    Object.keys(meta.functions).length > 0
  ) {
    return;
  }

  let pending = functionLoads.get(meta);

  if (pending === undefined) {
    const load = meta.loadFunctions;

    pending = load().then((functions) => {
      installFunctions(meta, functions);
    });
    functionLoads.set(meta, pending);
  }

  await pending;
}

/** Runs one `QuerySpec` against a db, including a spec a read set stored. */
export function runSpec(
  db: Record<string, unknown>,
  spec: unknown,
  signal: AbortSignal | undefined,
): AsyncResult<unknown> {
  if (!isQuerySpec(spec)) {
    return AsyncResult.err(
      dbError(
        "invalid_request",
        "db.$run() expects a QuerySpec from betterSupabase.spec",
      ),
    );
  }

  // SAFETY: isQuerySpec checked the spec, so db[spec.table] is a repository or undefined.
  const repository = db[spec.table] as
    | Record<string, (...args: unknown[]) => AsyncResult<unknown>>
    | undefined;

  const method = repository?.[spec.method];

  if (!method) {
    return AsyncResult.err(
      dbError("invalid_request", `Unknown table "${spec.table}" in QuerySpec`),
    );
  }

  if (containsPlaceholder(spec.args)) {
    return AsyncResult.err(
      dbError(
        "invalid_request",
        "This spec comes from a read set and still holds placeholders; run it with db.$many(readSet, params)",
      ),
    );
  }

  const args = [...spec.args];

  if (signal) {
    const index = spec.method === "get" ? 1 : 0;
    // SAFETY: the options argument of a repository method is an object or undefined.
    args[index] = { ...(args[index] as object | undefined), signal };
  }

  return method(...args);
}
