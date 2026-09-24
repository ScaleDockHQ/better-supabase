import type { Operation } from '../ir/types.ts';
import type { ErrorMapper } from './errors.ts';
import type { Result } from './result.ts';

export interface ExecuteContext {
  readonly signal?: AbortSignal;
  readonly errorMappers: readonly ErrorMapper[];
}

export interface ExecuteResult {
  /** Rows keyed by the aliases in the operation's selection. */
  readonly rows: readonly Record<string, unknown>[];
  readonly count: number | null;
}

/**
 * Runs IR operations. PostgREST (`postgrestExecutor`) and SQL
 * (`better-supabase/postgres`) are built in; any other backend can implement
 * this interface and prove it with `testExecutor` from `better-supabase/testing`.
 */
export interface Executor {
  readonly name: string;
  execute(
    op: Operation,
    context: ExecuteContext,
  ): Promise<Result<ExecuteResult>>;
  /** Calls a database function. Optional; `db.$rpc` fails without it. */
  rpc?(
    name: string,
    args: Readonly<Record<string, unknown>>,
    context: ExecuteContext & { readonly schema: string },
  ): Promise<Result<unknown>>;
}
