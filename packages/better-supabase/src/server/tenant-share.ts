import type { AnyAuthorizer, AuthorizerRuntime } from "../core/authorizer.ts";
import type { AuthorizationHooks } from "../core/contracts/authorization-hooks.ts";
import type { DbError } from "../core/errors.ts";
import type { Executor } from "../core/executor.ts";
import type { RequestContext } from "../core/plugin.ts";
import type { Condition, Operation, Selection } from "../ir/types.ts";
import type { SchemaMeta } from "../schema/types.ts";

import { requestOf } from "../core/authorizer.ts";
import { rewrapDb } from "../core/define-runtime.ts";
import { dbError } from "../core/errors.ts";
import { AsyncResult, err } from "../core/result.ts";

/** How a `share: "tenant"` entry is keyed. */
export type TenantShare =
  /** One entry for every caller with `key` in the tenant. */
  | { readonly kind: "shared"; readonly key: string }
  /** Per user: no hook, no tenant, or the hook answered `null`. */
  | { readonly kind: "user" }
  /** Per user, and `error` names the table that can't be shared. */
  | { readonly kind: "refused"; readonly error: DbError };

export interface TenantShareInput {
  readonly meta: SchemaMeta | undefined;
  /** App keys of the tables the entry reads. */
  readonly tables: readonly string[];
  readonly tenant: string | undefined;
  readonly hooks: AuthorizationHooks | undefined;
  readonly authorizer: AnyAuthorizer | undefined;
  readonly context: RequestContext | undefined;
  readonly runtime?: AuthorizerRuntime;
}

const refusal = (table: string, why: string): DbError =>
  dbError("forbidden", `share: "tenant" can't share ${table}: ${why}`, {
    code: "SHARE_REFUSED",
    table,
  });

/**
 * Whether every table may be shared per tenant, and the grant part of the key
 * the provider's `shareKey` hook returns for the caller.
 */
export async function tenantShareOf(
  input: TenantShareInput,
): Promise<TenantShare> {
  if (input.tables.length === 0) {
    return {
      kind: "refused",
      error: refusal("the entry", "it declares no tables"),
    };
  }

  const permissions = new Set<string>();

  for (const table of input.tables) {
    const share = input.meta?.tables[table]?.share;

    if (!share) {
      return {
        kind: "refused",
        error: refusal(
          table,
          "the authorization provider's tables don't list it",
        ),
      };
    }

    if (share.kind === "row") {
      return {
        kind: "refused",
        error: refusal(
          table,
          'its select policy filters by row (share: "row")',
        ),
      };
    }

    for (const key of share.permissions) {
      permissions.add(key);
    }
  }

  const hook = input.hooks?.shareKey;

  if (!hook || input.tenant === undefined) {
    return { kind: "user" };
  }

  const { subject, context } = requestOf(input.context);

  let key: string | null;

  try {
    key = await hook(input.authorizer, [...permissions].toSorted(), {
      subject,
      context,
      ...(input.runtime ? { runtime: input.runtime } : {}),
    });
  } catch {
    key = null;
  }

  return typeof key === "string"
    ? { kind: "shared", key: `${input.tenant}:${key}` }
    : { kind: "user" };
}

function selectionTables(
  selection: Selection | undefined,
  into: string[],
): void {
  for (const include of selection?.includes ?? []) {
    into.push(include.target.key);
    selectionTables(include.selection, into);
    conditionTables(include.where, into);
  }
}

function conditionTables(
  condition: Condition | undefined,
  into: string[],
): void {
  if (!condition) {
    return;
  }

  switch (condition.kind) {
    case "and":
    case "or": {
      for (const item of condition.items) {
        conditionTables(item, into);
      }

      return;
    }

    case "not": {
      conditionTables(condition.item, into);

      return;
    }

    case "relation": {
      into.push(condition.target.key);
      conditionTables(condition.where, into);

      return;
    }

    case "column": {
      return;
    }

    default: {
      const unknown: never = condition;

      throw new TypeError(`unknown condition ${String(unknown)}`);
    }
  }
}

/** Every table an operation reads or writes, by app key. */
function operationTables(op: Operation): readonly string[] {
  const tables: string[] = [op.table.key];

  switch (op.kind) {
    case "select": {
      selectionTables(op.selection, tables);
      conditionTables(op.where, tables);

      for (const term of op.orderBy) {
        if (term.relation) {
          tables.push(term.relation.target.key);
        }
      }

      return tables;
    }

    case "insert": {
      selectionTables(op.returning, tables);

      return tables;
    }

    case "update":
    case "delete": {
      selectionTables(op.returning, tables);
      conditionTables(op.where, tables);

      return tables;
    }

    default: {
      const unknown: never = op;

      throw new TypeError(`unknown operation ${String(unknown)}`);
    }
  }
}

/** What `sharedReader` refused, for the fill to report. */
export interface ShareGuard {
  /** The first refused read, or `undefined`. */
  refused(): DbError | undefined;
}

/**
 * An executor that answers a `forbidden` `DbError` for an operation that
 * touches a table outside `tables`, a set-returning source, or a function call,
 * since none of those is known to read the same rows for every caller.
 */
function gate(
  executor: Executor,
  tables: ReadonlySet<string>,
  record: (error: DbError) => void,
): Executor {
  const refuse = (error: DbError) => {
    record(error);

    return err(error);
  };

  const check = (op: Operation): DbError | undefined => {
    if (op.kind === "select" && op.source) {
      return refusal(
        `${op.source.schema}.${op.source.name}`,
        "a function source isn't in the entry's tables",
      );
    }

    const outside = operationTables(op).find((table) => !tables.has(table));

    return outside === undefined
      ? undefined
      : refusal(outside, "the entry's tables don't list it");
  };

  return {
    name: executor.name,
    ...(executor.functionSources === undefined
      ? {}
      : { functionSources: executor.functionSources }),
    execute: (op, context) => {
      const error = check(op);

      return error
        ? Promise.resolve(refuse(error))
        : executor.execute(op, context);
    },
    rpc: (name) =>
      Promise.resolve(
        refuse(refusal(name, "a function call isn't in the entry's tables")),
      ),
    batch: async (ops, context) => {
      const errors = ops.map(check);
      const first = errors.find((error) => error !== undefined);

      if (first) {
        record(first);

        return errors.map((error) => err(error ?? first));
      }

      return executor.batch
        ? executor.batch(ops, context)
        : Promise.all(ops.map((op) => executor.execute(op, context)));
    },
  };
}

/** A value whose every call answers `error` and whose every property is another. */
function refusingValue(
  error: DbError,
  record: (error: DbError) => void,
): unknown {
  const fn = (): AsyncResult<never> => {
    record(error);

    return AsyncResult.err(error);
  };

  return new Proxy(fn, {
    get: (_target, prop) =>
      prop === "then" ? undefined : refusingValue(error, record),
    apply: () => fn(),
  });
}

const PASS = new Set([
  "$context",
  "$stats",
  "$decode",
  "$decodeReadSet",
  "$table",
]);

/** `db` reading only `tables`, with the escape hatches refused. */
function sharedDb<T extends object>(
  db: T,
  tables: ReadonlySet<string>,
  record: (error: DbError) => void,
): T {
  const gated = rewrapDb(db, (executor) => gate(executor, tables, record));

  const hatch = (name: string): unknown =>
    refusingValue(
      refusal(name, "a shared entry reads through its tables only"),
      record,
    );

  if (!gated) {
    return db;
  }

  return new Proxy(gated, {
    // The db's getters and methods look their state up by `this`, so they read
    // from the target, never the proxy.
    get: (target, prop) => {
      if (typeof prop === "string" && prop.startsWith("$") && !PASS.has(prop)) {
        return hatch(prop);
      }

      // SAFETY: a db is a plain object; reading a missing key gives undefined.
      const value = (target as Record<PropertyKey, unknown>)[prop];

      if (typeof value !== "function") {
        return value;
      }

      // SAFETY: checked to be a function above; it runs with the db as `this`.
      return (value as (...args: unknown[]) => unknown).bind(target);
    },
  });
}

/**
 * The caller's context for a `share: "tenant"` fill: `db` and `sql` read only
 * `tables` (an operation on another table, a function call or a raw client
 * answers a `forbidden` `DbError` that names it), and the guard reports the
 * first refusal so the entry is not stored. The reads still run through the
 * caller's own client, under RLS.
 */
export function sharedReader<Ctx extends object>(
  ctx: Ctx,
  tables: readonly string[],
): { readonly ctx: Ctx; readonly guard: ShareGuard } {
  let first: DbError | undefined;

  const record = (error: DbError): void => {
    first ??= error;
  };

  const allowed = new Set(tables);
  // SAFETY: a server context carries `db`, and `sql` with direct Postgres.
  const source = ctx as Ctx & { readonly db?: object; readonly sql?: object };
  const dbs = new Map<"db" | "sql", object>();

  const reader = (name: "db" | "sql", db: object): object => {
    const existing = dbs.get(name);

    if (existing) {
      return existing;
    }

    const shared = sharedDb(db, allowed, record);
    dbs.set(name, shared);

    return shared;
  };

  const wrapped = new Proxy(ctx, {
    get: (target, prop) => {
      if (prop === "db" && source.db) {
        return reader("db", source.db);
      }

      if (prop === "sql" && source.sql) {
        return reader("sql", source.sql);
      }

      if (prop === "supabase" || prop === "storage") {
        return refusingValue(
          refusal(prop, "a shared entry reads through its tables only"),
          record,
        );
      }

      // SAFETY: a context is a plain object; reading a missing key gives undefined.
      return (target as Record<PropertyKey, unknown>)[prop];
    },
  });

  return { ctx: wrapped, guard: { refused: () => first } };
}

/**
 * Logs a `share: "tenant"` refusal once per message: the entry falls back to
 * one per user, which is correct but slower, so the app hears about it once.
 */
export function shareRefusalLogger(logger: {
  warn(message: string, context?: Readonly<Record<string, unknown>>): void;
}): (name: string, error: DbError) => void {
  const logged = new Set<string>();

  return (name, error) => {
    if (logged.has(error.message)) {
      return;
    }

    logged.add(error.message);
    logger.warn(`${name} keeps its entries per user: ${error.message}`, {
      error,
    });
  };
}
