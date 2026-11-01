import type { Result } from "../core/result.ts";

import { err } from "../core/result.ts";

/** The first failed result of a group of reads that ran together, if any. */
export const firstFailure = (
  results: readonly Result<unknown>[],
): Result<never> | undefined => {
  for (const result of results) {
    if (!result.ok) {
      return err(result.error);
    }
  }

  return undefined;
};

/** The value type of an `AsyncResult`. */
export type ValueOf<R> = R extends PromiseLike<Result<infer T>> ? T : never;
