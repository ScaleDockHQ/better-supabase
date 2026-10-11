import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { ResourceActionSpec } from "../spec/resource.ts";
import type {
  ActionArgs,
  Parsed,
  ResourceAction,
  ResourceContext,
} from "./resource-types.ts";

import { dbError, isDbError } from "../core/errors.ts";
import { err, ok, toDbError, type Result } from "../core/result.ts";
import { isResult } from "./respond.ts";

export async function settled(value: unknown): Promise<Result<unknown>> {
  // SAFETY: repository methods resolve to a Result, and every caller passes one.
  return (await value) as Result<unknown>;
}

function failure(cause: unknown, message: string): Result<never> {
  if (isDbError(cause)) return err(cause);
  const error = toDbError(cause);
  return err(
    error.kind === "unexpected" ? dbError("unexpected", message) : error,
  );
}

/** Runs a hook: its `Result` passes through, anything else is an `unexpected` error. */
export async function runHook(
  name: string,
  call: () => unknown,
): Promise<Result<unknown>> {
  try {
    const value: unknown = await call();
    if (!isResult(value)) {
      return err(
        dbError("unexpected", `The ${name} hook must return a Result`),
      );
    }
    return value.ok
      ? ok(value.data)
      : failure(value.error, `The ${name} hook failed`);
  } catch (cause) {
    return failure(cause, `The ${name} hook failed`);
  }
}

/** Runs an action handler: a `Result` unwraps, a plain value is the data. */
export async function runHandler(
  name: string,
  call: () => unknown,
): Promise<Result<unknown>> {
  try {
    const value: unknown = await call();
    if (!isResult(value)) return ok(value);
    return value.ok
      ? ok(value.data)
      : failure(value.error, `The ${name} action failed`);
  } catch (cause) {
    return failure(cause, `The ${name} action failed`);
  }
}

/** Defines an action and types its handler's `data` and `query` from the schemas. */
export function defineAction<
  DbT = unknown,
  Ref = string,
  I extends StandardSchemaV1 | undefined = undefined,
  Q extends StandardSchemaV1 | undefined = undefined,
>(
  action: Omit<ResourceActionSpec<Ref>, "input" | "query"> & {
    readonly input?: I;
    readonly query?: Q;
    handler(
      ctx: ResourceContext<DbT>,
      args: ActionArgs<Parsed<I>, Parsed<Q>>,
    ): unknown;
  },
): ResourceAction<Ref, DbT> {
  // SAFETY: the handler only receives data and query validated by these schemas.
  return action as ResourceAction<Ref, DbT>;
}
