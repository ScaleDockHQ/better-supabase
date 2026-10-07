import type { Operation } from "../ir/types.ts";
import type { FunctionMeta } from "../schema/types.ts";
import type { ErrorMapper } from "./errors.ts";
import type { Result } from "./result.ts";

export interface ExecuteContext {
  /** Already includes the call's `timeout`, when it has one. */
  readonly signal?: AbortSignal;
  readonly errorMappers: readonly ErrorMapper[];
  /**
   * The call's `retry` setting. PostgREST passes it to postgrest-js, which
   * retries idempotent requests on network errors, 503 and 520; executors
   * without retries ignore it.
   */
  readonly retry?: boolean;
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
  /** Honors `SelectOp.source`. `db.$search` fails on executors without it. */
  readonly functionSources?: boolean;
  execute(
    op: Operation,
    context: ExecuteContext,
  ): Promise<Result<ExecuteResult>>;
  /** Calls a database function. Optional; `db.$rpc` fails without it. */
  rpc?(
    name: string,
    args: Readonly<Record<string, unknown>>,
    context: RpcContext,
  ): Promise<Result<unknown>>;
  /**
   * Runs several reads together, for `db.$many`: one transaction on a SQL
   * connection. Returns one result per operation, in order. Optional;
   * without it `db.$many` runs the operations in parallel.
   */
  batch?(
    ops: readonly Operation[],
    context: ExecuteContext,
  ): Promise<readonly Result<ExecuteResult>[]>;
}

export interface RpcContext extends ExecuteContext {
  readonly schema: string;
  /** The function is `stable`: send it as a GET, so read replicas can serve it. */
  readonly get?: boolean;
  readonly function?: FunctionMeta;
}
