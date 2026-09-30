import type { Operation } from "../ir/types.ts";
import type { ExecuteContext, ExecuteResult, Executor } from "./executor.ts";

import { err, type Result, toDbError } from "./result.ts";

interface Pending {
  readonly op: Operation;
  readonly context: ExecuteContext;
  readonly resolve: (result: Result<ExecuteResult>) => void;
}

export interface BatchingExecutor {
  readonly executor: Executor;
  /** Call when one of the readers has finished, successfully or not. */
  done(): void;
}

/**
 * Holds operations until each of `readers` has either submitted one or
 * finished, then runs the held ones through `batch` together. A reader that
 * runs a second operation joins the next batch.
 */
export function batchingExecutor(
  base: Executor & { readonly batch: NonNullable<Executor["batch"]> },
  readers: number,
): BatchingExecutor {
  let running = readers;
  const queue: Pending[] = [];

  const flush = (): void => {
    if (queue.length === 0 || queue.length < running) return;
    const items = queue.splice(0);
    base
      .batch(
        items.map((item) => item.op),
        items[0]!.context,
      )
      .then(
        (results) => {
          items.forEach((item, index) => {
            item.resolve(
              results[index] ??
                err(
                  toDbError(
                    new Error(
                      `Executor "${base.name}" returned too few results`,
                    ),
                  ),
                ),
            );
          });
        },
        (cause: unknown) => {
          for (const item of items) item.resolve(err(toDbError(cause)));
        },
      );
  };

  const executor: Executor = {
    name: base.name,
    execute: (op, context) =>
      new Promise((resolve) => {
        queue.push({ op, context, resolve });
        flush();
      }),
    ...(base.rpc ? { rpc: base.rpc.bind(base) } : {}),
  };
  return {
    executor,
    done: () => {
      running -= 1;
      flush();
    },
  };
}
