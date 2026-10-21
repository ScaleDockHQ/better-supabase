import type { DbError } from "../core/errors.ts";
import type { Executor } from "../core/executor.ts";

import { err, type Result } from "../core/result.ts";

/**
 * An executor for credentials that did not verify: every query, function call
 * and batch answers `error`, so a handler that skips the route guard gets a 401
 * `Result` and never queries as anon.
 */
export function refusingExecutor(error: DbError): Executor {
  const refuse = <T>(): Result<T> => err(error);

  return {
    name: "refused",
    // `db.$search` then reports the refusal and not an unsupported executor.
    functionSources: true,
    execute: () => Promise.resolve(refuse()),
    rpc: () => Promise.resolve(refuse()),
    batch: (ops) => Promise.resolve(ops.map(() => refuse())),
  };
}
