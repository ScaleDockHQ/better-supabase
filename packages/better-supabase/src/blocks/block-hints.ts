import type { DbError } from "../core/errors.ts";
import type { BlockHints } from "./hint-codes.generated.ts";

export type { BlockHints } from "./hint-codes.generated.ts";

/**
 * A hint code the errors of block `B` can carry (`BlockHint<"tasks">`), or of
 * any block.
 */
export type BlockHint<B extends keyof BlockHints = keyof BlockHints> =
  BlockHints[B];

/**
 * Whether `error` carries one of `hints`, narrowing its `hint` to them:
 * `isBlockHint(result.error, "WORK_ITEM_LOCKED")`. A hint no block raises is a
 * type error.
 */
export function isBlockHint<const H extends BlockHint>(
  error: DbError | undefined,
  ...hints: readonly H[]
): error is DbError & { readonly hint: H } {
  const hint = error?.hint;

  return hint !== undefined && hints.some((each) => each === hint);
}

/**
 * The hint of an error from block `B`, typed as that block's hint codes, for an
 * exhaustive `switch`. It types the value without checking it: an error from
 * your own SQL can carry a code the block doesn't list.
 */
export function blockHint<B extends keyof BlockHints>(
  error: DbError,
): BlockHint<B> | undefined {
  // SAFETY: the caller names the block the error came from; its functions
  // raise the codes `BlockHints` lists for it.
  return error.hint as BlockHint<B> | undefined;
}
