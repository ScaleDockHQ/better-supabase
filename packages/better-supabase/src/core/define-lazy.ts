import type { SchemaMeta } from "../schema/types.ts";
import type { Result } from "./result.ts";

import { installFunctions } from "../schema/define.ts";
import { dbError } from "./errors.ts";
import { containsPlaceholder } from "./read-set.ts";
import { AsyncResult } from "./result.ts";
import { isQuerySpec } from "./spec.ts";

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
