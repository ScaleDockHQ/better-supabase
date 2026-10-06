import type { FunctionSource, MutationOp, Operation } from "../ir/types.ts";
import type { ExecuteContext, ExecuteResult, Executor } from "./executor.ts";

import {
  compilePostgrest,
  type PostgrestCompileOptions,
  type PostgrestPlan,
} from "../compile/postgrest.ts";
import { invalidRequest } from "../ir/build.ts";
import {
  type DbError,
  dbError,
  mapDbError,
  type RawDbError,
  withMaxAffected,
} from "./errors.ts";
import { chunkRead, queryLength } from "./in-chunks.ts";
import { err, ok, type Result, toDbError } from "./result.ts";
import { deadline, isTimeout } from "./timeout.ts";

interface PostgrestResponseLike {
  readonly data: unknown;
  readonly error: RawDbError | null;
  readonly count?: number | null;
  readonly status?: number;
}

/** The subset of the postgrest-js builder the executor calls. */
interface BuilderLike extends PromiseLike<PostgrestResponseLike> {
  select(
    columns?: string,
    options?: { count?: string; head?: boolean },
  ): BuilderLike;
  insert(
    values: unknown,
    options?: { defaultToNull?: boolean; count?: string },
  ): BuilderLike;
  upsert(
    values: unknown,
    options?: {
      onConflict?: string;
      ignoreDuplicates?: boolean;
      defaultToNull?: boolean;
      count?: string;
    },
  ): BuilderLike;
  update(values: unknown, options?: { count?: string }): BuilderLike;
  delete(options?: { count?: string }): BuilderLike;
  filter(column: string, operator: string, value: unknown): BuilderLike;
  or(filters: string, options?: { referencedTable?: string }): BuilderLike;
  order(
    column: string,
    options?: {
      ascending?: boolean;
      nullsFirst?: boolean;
      referencedTable?: string;
    },
  ): BuilderLike;
  limit(count: number, options?: { referencedTable?: string }): BuilderLike;
  range(from: number, to: number): BuilderLike;
  single(): BuilderLike;
  maybeSingle(): BuilderLike;
  abortSignal(signal: AbortSignal): BuilderLike;
  /** postgrest-js 2.x: `Prefer: handling=strict, max-affected=<rows>`. */
  maxAffected?(rows: number): BuilderLike;
  /** postgrest-js 2.x: retries idempotent requests on network errors, 503 and 520. */
  retry?(enabled: boolean): BuilderLike;
}

/**
 * Anything with `schema(name).from(table)` or `from(table)`: a supabase-js
 * `SupabaseClient` or a bare `PostgrestClient`.
 */
export interface PostgrestClientLike {
  // Parameters are `never` so generically typed clients (`SupabaseClient<Database>`) match.
  from(relation: never): unknown;
  schema?(schema: never): unknown;
  rpc?(fn: never, args?: never): unknown;
}

interface ScopedClient {
  from(relation: string): unknown;
  rpc?(
    fn: string,
    args?: object,
    options?: { get?: boolean; count?: string; head?: boolean },
  ): unknown;
}

interface LooseClient extends ScopedClient {
  schema?(schema: string): ScopedClient;
}

function scope(client: PostgrestClientLike, schema: string): ScopedClient {
  // SAFETY: PostgrestClientLike is structural; every supported client has
  // from() and may have schema() and rpc().
  // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- PostgrestClientLike is structural and `schema()` is optional at runtime.
  const loose = client as unknown as LooseClient;
  if (schema === "public" || !loose.schema) return loose;
  let schemas = scopedClients.get(client);
  if (!schemas) {
    schemas = new Map();
    scopedClients.set(client, schemas);
  }
  let scoped = schemas.get(schema);
  if (!scoped) {
    scoped = loose.schema(schema);
    schemas.set(schema, scoped);
  }
  return scoped;
}

/** `schema()` builds a new client on every call; one per client and schema is enough. */
const scopedClients = new WeakMap<object, Map<string, ScopedClient>>();

function fromTable(
  client: PostgrestClientLike,
  schema: string,
  table: string,
): BuilderLike {
  // SAFETY: from() on a supabase-js or postgrest-js client returns a query
  // builder with these methods.
  return scope(client, schema).from(table) as BuilderLike;
}

/** A POST to the function: arguments such as query vectors are too long for a URL. */
function fromFunction(
  client: PostgrestClientLike,
  source: FunctionSource,
  options: { count?: string; head?: boolean },
): BuilderLike {
  const scoped = scope(client, source.schema);
  if (!scoped.rpc) {
    throw new TypeError(
      `better-supabase: the client has no rpc(), needed to read from ${source.name}`,
    );
  }
  // SAFETY: rpc() on a supabase-js or postgrest-js client returns a filter
  // builder with these methods.
  return scoped.rpc(source.name, source.args, options) as BuilderLike;
}

function applyFilters(builder: BuilderLike, plan: PostgrestPlan): BuilderLike {
  let query = builder;
  for (const filter of plan.filters) {
    query =
      filter.kind === "filter"
        ? query.filter(filter.path, filter.operator, filter.value)
        : query.or(
            filter.expression,
            filter.referencedTable
              ? { referencedTable: filter.referencedTable }
              : {},
          );
  }
  return query;
}

function applyOrderAndLimits(
  builder: BuilderLike,
  plan: PostgrestPlan,
): BuilderLike {
  let query = builder;
  for (const order of plan.orders) {
    const options: {
      ascending: boolean;
      nullsFirst?: boolean;
      referencedTable?: string;
    } = {
      ascending: order.ascending,
    };
    if (order.nullsFirst !== undefined) options.nullsFirst = order.nullsFirst;
    if (order.referencedTable) options.referencedTable = order.referencedTable;
    query = query.order(order.column, options);
  }
  for (const limit of plan.limits) {
    query = query.limit(
      limit.count,
      limit.referencedTable ? { referencedTable: limit.referencedTable } : {},
    );
  }
  if (plan.range) query = query.range(plan.range.from, plan.range.to);
  return query;
}

/** A mutation without `returning` reports its row count, `exact` unless the op says otherwise. */
function countOf(op: MutationOp, plan: PostgrestPlan): { count?: string } {
  return plan.select === undefined ? { count: op.count ?? "exact" } : {};
}

function bounded(
  query: BuilderLike,
  op: MutationOp,
  plan: PostgrestPlan,
): BuilderLike {
  if (plan.maxAffected === undefined) return query;
  if (!query.maxAffected) {
    invalidRequest(
      '"maxAffected" needs @supabase/postgrest-js 2 or later',
      op.table.key,
    );
  }
  return query.maxAffected(plan.maxAffected);
}

function build(
  client: PostgrestClientLike,
  op: Operation,
  plan: PostgrestPlan,
): BuilderLike {
  const base = fromTable(client, op.table.schema, op.table.name);
  switch (op.kind) {
    case "select": {
      const options: { count?: string; head?: boolean } = {};
      if (op.count) options.count = op.count;
      if (op.head) options.head = true;
      const selected = op.source
        ? fromFunction(client, op.source, options).select(plan.select)
        : base.select(plan.select, options);
      let query = applyOrderAndLimits(applyFilters(selected, plan), plan);
      if (op.single === "one") query = query.single();
      if (op.single === "maybe") query = query.maybeSingle();
      return query;
    }
    case "insert": {
      const rows = op.rows.length === 1 ? op.rows[0] : op.rows;
      const count = countOf(op, plan);
      let query = op.onConflict
        ? base.upsert(rows, {
            onConflict: op.onConflict.columns.join(","),
            ignoreDuplicates: op.onConflict.action === "ignore",
            defaultToNull: op.defaultToNull,
            ...count,
          })
        : base.insert(rows, { defaultToNull: op.defaultToNull, ...count });
      if (plan.select !== undefined) query = query.select(plan.select);
      return query;
    }
    case "update": {
      let query = applyFilters(base.update(op.set, countOf(op, plan)), plan);
      if (plan.select !== undefined) query = query.select(plan.select);
      return bounded(query, op, plan);
    }
    case "delete": {
      let query = applyFilters(base.delete(countOf(op, plan)), plan);
      if (plan.select !== undefined) query = query.select(plan.select);
      return bounded(query, op, plan);
    }
    default: {
      const exhaustive: never = op;
      return exhaustive;
    }
  }
}

function rowsOf(data: unknown): readonly Record<string, unknown>[] {
  if (data === null || data === undefined) return [];
  if (Array.isArray(data)) {
    // SAFETY: PostgREST returns a list of row objects for a multi-row query.
    return data as Record<string, unknown>[];
  }
  // SAFETY: PostgREST returns one row object for a single-row query.
  return [data as Record<string, unknown>];
}

const ONLY_ROWS = /there are only (\d+) rows/;

/**
 * PostgREST answers a counted read whose offset is past the last row with
 * 416 (`PGRST103`); the SQL executor returns no rows and the total.
 */
function pastLastRow(op: Operation, error: RawDbError): number | undefined {
  if (op.kind !== "select" || !op.count || error.code !== "PGRST103") {
    return undefined;
  }
  const match = ONLY_ROWS.exec(error.details ?? "");
  return match ? Number(match[1]) : undefined;
}

const aborted = (): DbError => dbError("aborted", "The request was aborted");

function tune(
  builder: BuilderLike,
  signal: AbortSignal | undefined,
  retry: boolean | undefined,
): BuilderLike {
  let query = builder;
  if (signal) query = query.abortSignal(signal);
  if (retry !== undefined && query.retry) query = query.retry(retry);
  return query;
}

const timedOut = (ms: number): DbError =>
  dbError("timeout", `The request timed out after ${ms} ms`);

export interface PostgrestExecutorOptions extends PostgrestCompileOptions {
  /**
   * The longest query string a read may send, in characters. A longer read
   * is split along its longest `in` list into reads that fit, or fails with
   * `invalid_request` when it can't be split. Defaults to 6000, below the
   * 8 KB request line the Supabase API gateway and common proxies accept,
   * or to the client's `db.urlLengthLimit` when that is lower.
   */
  readonly urlLengthLimit?: number;
  /** @deprecated Renamed to `urlLengthLimit`, which wins when both are set. */
  readonly maxUrlLength?: number;
  /**
   * Aborts each request after this many milliseconds with a `timeout`
   * error. A call's own `timeout` replaces it. Off by default.
   */
  readonly timeout?: number;
  /**
   * postgrest-js retries of idempotent requests (GET and HEAD) on network
   * errors, 503 and 520. A call's own `retry` replaces it. Defaults to the
   * client's setting, which is on.
   */
  readonly retry?: boolean;
}

const DEFAULT_URL_LENGTH_LIMIT = 6000;

/** `urlLengthLimit` on a bare `PostgrestClient`, or on supabase-js's `rest` client. */
function clientUrlLengthLimit(client: PostgrestClientLike): number | undefined {
  // SAFETY: both fields are read only after a typeof check.
  const loose = client as {
    readonly urlLengthLimit?: unknown;
    readonly rest?: { readonly urlLengthLimit?: unknown };
  };
  const limit = loose.urlLengthLimit ?? loose.rest?.urlLengthLimit;
  return typeof limit === "number" && limit > 0 ? limit : undefined;
}

/** The query-string budget for one read: the option, else the lower of 6000 and the client's limit. */
export function resolveUrlLengthLimit(
  client: PostgrestClientLike,
  options: Pick<PostgrestExecutorOptions, "urlLengthLimit" | "maxUrlLength">,
): number {
  // oxlint-disable-next-line typescript/no-deprecated -- the alias stays readable until it is removed.
  const explicit = options.urlLengthLimit ?? options.maxUrlLength;
  if (explicit !== undefined) return explicit;
  const fromClient = clientUrlLengthLimit(client);
  return fromClient === undefined
    ? DEFAULT_URL_LENGTH_LIMIT
    : Math.min(fromClient, DEFAULT_URL_LENGTH_LIMIT);
}

/** Executes IR operations through a supabase-js client. */
export function postgrestExecutor(
  client: PostgrestClientLike,
  options: PostgrestExecutorOptions = {},
): Executor {
  const urlLengthLimit = resolveUrlLengthLimit(client, options);
  const compileOptions: PostgrestCompileOptions =
    options.postgrestVersion === undefined
      ? {}
      : { postgrestVersion: options.postgrestVersion };
  const timeout = isTimeout(options.timeout) ? options.timeout : undefined;
  const execute = async (
    op: Operation,
    context: ExecuteContext,
  ): Promise<Result<ExecuteResult>> => {
    let plan: PostgrestPlan;
    try {
      plan = compilePostgrest(op, compileOptions);
    } catch (cause) {
      return err(toDbError(cause));
    }
    if (plan.never) return ok({ rows: [], count: 0 });
    if (context.signal?.aborted) return err(aborted());
    if (op.kind === "select" && queryLength(plan) > urlLengthLimit) {
      const chunked = chunkRead(op, plan, urlLengthLimit);
      if (!("ops" in chunked)) return err(chunked);
      const results = await Promise.all(
        chunked.ops.map((chunk) => send(chunk, context)),
      );
      const rows: Record<string, unknown>[] = [];
      for (const result of results) {
        if (!result.ok) return result;
        rows.push(...result.data.rows);
      }
      return ok({
        rows: chunked.sort ? chunked.sort(rows) : rows,
        count: null,
      });
    }
    return run(op, plan, context);
  };
  const send = (
    op: Operation,
    context: ExecuteContext,
  ): Promise<Result<ExecuteResult>> => {
    let plan: PostgrestPlan;
    try {
      plan = compilePostgrest(op, compileOptions);
    } catch (cause) {
      return Promise.resolve(err(toDbError(cause)));
    }
    return plan.never
      ? Promise.resolve(ok({ rows: [], count: 0 }))
      : run(op, plan, context);
  };
  const run = async (
    op: Operation,
    plan: PostgrestPlan,
    context: ExecuteContext,
  ): Promise<Result<ExecuteResult>> => {
    let query: BuilderLike;
    try {
      query = build(client, op, plan);
    } catch (cause) {
      return err(toDbError(cause));
    }
    const limit = deadline(context.signal, timeout);
    try {
      query = tune(query, limit.signal, context.retry ?? options.retry);
      const response = await query;
      if (response.error) {
        if (limit.timedOut() && timeout !== undefined)
          return err(timedOut(timeout));
        if (limit.signal?.aborted) return err(aborted());
        const total = pastLastRow(op, response.error);
        if (total !== undefined) return ok({ rows: [], count: total });
        return err(
          withMaxAffected(
            mapDbError(response.error, context.errorMappers),
            plan.maxAffected,
          ),
        );
      }
      return ok({ rows: rowsOf(response.data), count: response.count ?? null });
    } finally {
      limit.clear();
    }
  };
  return {
    name: "postgrest",
    functionSources: true,
    execute,
    async rpc(name, args, context): Promise<Result<unknown>> {
      const scoped = scope(client, context.schema);
      if (!scoped.rpc) {
        return err(toDbError(new Error("The client does not support rpc()")));
      }
      if (context.signal?.aborted) return err(aborted());
      // SAFETY: rpc() on a supabase-js or postgrest-js client returns a filter
      // builder with these methods.
      const built = (
        context.get
          ? scoped.rpc(name, queryArgs(args), { get: true })
          : scoped.rpc(name, args)
      ) as BuilderLike;
      const limit = deadline(context.signal, timeout);
      try {
        const response = await tune(
          built,
          limit.signal,
          context.retry ?? options.retry,
        );
        if (response.error) {
          if (limit.timedOut() && timeout !== undefined)
            return err(timedOut(timeout));
          if (limit.signal?.aborted) return err(aborted());
          return err(mapDbError(response.error, context.errorMappers));
        }
        return ok(response.data);
      } finally {
        limit.clear();
      }
    },
  };
}

/**
 * GET arguments travel in the query string, where supabase-js would print an
 * object as `[object Object]`; json and jsonb parameters take it as JSON.
 */
function queryArgs(
  args: Readonly<Record<string, unknown>>,
): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(args).map(([key, value]) => [
      key,
      typeof value === "object" && value !== null && !Array.isArray(value)
        ? JSON.stringify(value)
        : value,
    ]),
  );
}

/** The compiled plan for an operation; useful for debugging and tests. */
export function explainPostgrest(
  op: Operation,
  options?: PostgrestCompileOptions,
): PostgrestPlan {
  return compilePostgrest(op, options);
}
