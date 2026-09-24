import type { Operation } from '../ir/types.ts';
import type { ExecuteContext, ExecuteResult, Executor } from './executor.ts';

import { compilePostgrest, type PostgrestPlan } from '../compile/postgrest.ts';
import {
  type DbError,
  dbError,
  mapDbError,
  type RawDbError,
} from './errors.ts';
import { err, ok, type Result, toDbError } from './result.ts';

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
  rpc?(fn: string, args?: object): unknown;
}

interface LooseClient extends ScopedClient {
  schema?(schema: string): ScopedClient;
}

function scope(client: PostgrestClientLike, schema: string): ScopedClient {
  const loose = client as unknown as LooseClient;
  return schema !== 'public' && loose.schema ? loose.schema(schema) : loose;
}

function fromTable(
  client: PostgrestClientLike,
  schema: string,
  table: string,
): BuilderLike {
  return scope(client, schema).from(table) as BuilderLike;
}

function applyFilters(builder: BuilderLike, plan: PostgrestPlan): BuilderLike {
  let query = builder;
  for (const filter of plan.filters) {
    query =
      filter.kind === 'filter'
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

function applyShape(builder: BuilderLike, plan: PostgrestPlan): BuilderLike {
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
    case 'select': {
      const options: { count?: string; head?: boolean } = {};
      if (op.count) options.count = op.count;
      if (op.head) options.head = true;
      let query = applyShape(
        applyFilters(base.select(plan.select, options), plan),
        plan,
      );
      if (op.single === 'one') query = query.single();
      if (op.single === 'maybe') query = query.maybeSingle();
      return query;
    }
    case 'insert': {
      const rows = op.rows.length === 1 ? op.rows[0] : op.rows;
      const count = plan.select === undefined ? { count: 'exact' } : {};
      let query = op.onConflict
        ? base.upsert(rows, {
            onConflict: op.onConflict.columns.join(','),
            ignoreDuplicates: op.onConflict.action === 'ignore',
            defaultToNull: op.defaultToNull,
            ...count,
          })
        : base.insert(rows, { defaultToNull: op.defaultToNull, ...count });
      if (plan.select !== undefined) query = query.select(plan.select);
      return query;
    }
    case 'update': {
      const count = plan.select === undefined ? { count: 'exact' } : {};
      let query = applyFilters(base.update(op.set, count), plan);
      if (plan.select !== undefined) query = query.select(plan.select);
      return query;
    }
    case 'delete': {
      const count = plan.select === undefined ? { count: 'exact' } : {};
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
  if (Array.isArray(data)) return data as Record<string, unknown>[];
  return [data as Record<string, unknown>];
}

/** Executes IR operations through a supabase-js client. */
const aborted = (): DbError => dbError('aborted', 'The request was aborted');

export function postgrestExecutor(client: PostgrestClientLike): Executor {
  return {
    name: 'postgrest',
    async execute(
      op: Operation,
      context: ExecuteContext,
    ): Promise<Result<ExecuteResult>> {
      let plan: PostgrestPlan;
      try {
        plan = compilePostgrest(op);
      } catch (cause) {
        return err(toDbError(cause));
      }
      if (plan.never) return ok({ rows: [], count: 0 });
      if (context.signal?.aborted) return err(aborted());

      let query = build(client, op, plan);
      if (context.signal) query = query.abortSignal(context.signal);

      const response = await query;
      if (response.error) {
        if (context.signal?.aborted) return err(aborted());
        return err(mapDbError(response.error, context.errorMappers));
      }
      return ok({ rows: rowsOf(response.data), count: response.count ?? null });
    },
    async rpc(name, args, context): Promise<Result<unknown>> {
      const scoped = scope(client, context.schema);
      if (!scoped.rpc) {
        return err(toDbError(new Error('The client does not support rpc()')));
      }
      if (context.signal?.aborted) return err(aborted());
      let query = scoped.rpc(name, args) as BuilderLike;
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

/** The compiled plan for an operation; useful for debugging and tests. */
export function explainPostgrest(op: Operation): PostgrestPlan {
  return compilePostgrest(op);
}
