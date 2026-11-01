import type { Result } from "../core/result.ts";

import { dbError } from "../core/errors.ts";
import { err, ok } from "../core/result.ts";

/** What `update` reports for cell edits: the ones applied and the ones refused. */
interface ChangeOutcome {
  readonly rejected: readonly {
    readonly field: string;
    readonly hint?: string;
    readonly reason: string;
  }[];
}

/**
 * With `strict`, the first refused change becomes a `raised` error that keeps
 * the refusal's hint as its code, instead of an entry in `rejected` that a
 * caller has to remember to read. Changes that were accepted stay applied
 * (`atomic` rolls a batch back).
 */
export function strictChanges<R extends ChangeOutcome>(
  result: R,
  strict: boolean | undefined,
): Promise<Result<R>> {
  const [first] = result.rejected;

  if (strict !== true || first === undefined) {
    return Promise.resolve(ok(result));
  }

  return Promise.resolve(
    err(
      dbError("raised", `${first.field}: ${first.reason}`, {
        ...(first.hint === undefined ? {} : { hint: first.hint }),
      }),
    ),
  );
}
