import type { FunctionSource, Operation } from "../ir/types.ts";
import type { ExecuteContext, ExecuteResult, Executor } from "./executor.ts";

import { compilePostgrest, type PostgrestPlan } from "../compile/postgrest.ts";
import {
  type DbError,
  dbError,
  mapDbError,
  type RawDbError,
} from "./errors.ts";
import { chunkRead, queryLength } from "./in-chunks.ts";
import { err, ok, type Result, toDbError } from "./result.ts";

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
      const count = plan.select === undefined ? { count: "exact" } : {};
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
      const count = plan.select === undefined ? { count: "exact" } : {};
      let query = applyFilters(base.update(op.set, count), plan);
      if (plan.select !== undefined) query = query.select(plan.select);
      return query;
    }
    case "delete": {
      const count = plan.select === undefined ? { count: "exact" } : {};
      let query = applyFilters(base.delete(count), plan);
      if (plan.select !== undefined) query = query.select(plan.select);
      return query;
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

export interface PostgrestExecutorOptions {
  /**
   * The longest query string a read may send, in characters. A longer read
   * is split along its longest `in` list into reads that fit, or fails with
   * `invalid_request` when it can't be split. Defaults to 6000, below the
   * 8 KB request line the Supabase API gateway and common proxies accept.
   */
  readonly maxUrlLength?: number;
}

/** Executes IR operations through a supabase-js client. */
export function postgrestExecutor(
  client: PostgrestClientLike,
  options: PostgrestExecutorOptions = {},
): Executor {
  const maxUrlLength = options.maxUrlLength ?? 6000;
  const execute = async (
    op: Operation,
    context: ExecuteContext,
  ): Promise<Result<ExecuteResult>> => {
    let plan: PostgrestPlan;
    try {
      plan = compilePostgrest(op);
    } catch (cause) {
      return err(toDbError(cause));
    }
    if (plan.never) return ok({ rows: [], count: 0 });
    if (context.signal?.aborted) return err(aborted());
    if (op.kind === "select" && queryLength(plan) > maxUrlLength) {
      const chunked = chunkRead(op, plan, maxUrlLength);
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
      plan = compilePostgrest(op);
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
    let query = build(client, op, plan);
    if (context.signal) query = query.abortSignal(context.signal);

    const response = await query;
    if (response.error) {
      if (context.signal?.aborted) return err(aborted());
      const total = pastLastRow(op, response.error);
      if (total !== undefined) return ok({ rows: [], count: total });
      return err(mapDbError(response.error, context.errorMappers));
    }
    return ok({ rows: rowsOf(response.data), count: response.count ?? null });
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
      let query = (
        context.get
          ? scoped.rpc(name, queryArgs(args), { get: true })
          : scoped.rpc(name, args)
      ) as BuilderLike;
      if (context.signal) query = query.abortSignal(context.signal);
      const response = await query;
      if (response.error) {
        if (context.signal?.aborted) return err(aborted());
        return err(mapDbError(response.error, context.errorMappers));
      }
      return ok(response.data);
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
export function explainPostgrest(op: Operation): PostgrestPlan {
  return compilePostgrest(op);
}
