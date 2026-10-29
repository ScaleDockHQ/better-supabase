import { describe, expectTypeOf, it } from "vitest";

import type { BlockHint } from "../../src/blocks/block-hints.ts";
import type { DbError } from "../../src/core/errors.ts";

import { blockHint, isBlockHint } from "../../src/blocks/block-hints.ts";

declare const error: DbError | undefined;

describe("block hint types", () => {
  it("narrows the hint to the codes it checked", () => {
    if (isBlockHint(error, "WORK_ITEM_LOCKED", "WORK_ITEM_FORBIDDEN")) {
      expectTypeOf(error.hint).toEqualTypeOf<
        "WORK_ITEM_LOCKED" | "WORK_ITEM_FORBIDDEN"
      >();
    }
  });

  it("rejects a code no block raises", () => {
    // @ts-expect-error: no block raises this hint.
    isBlockHint(error, "NOT_A_BLOCK_HINT");
  });

  it("types one block's hints", () => {
    expectTypeOf<"WORK_ITEM_LOCKED">().toExtend<BlockHint<"tasks">>();
    expectTypeOf<"INVITATION_INVALID">().not.toExtend<BlockHint<"tasks">>();
    expectTypeOf(blockHint<"tasks">).returns.toEqualTypeOf<
      BlockHint<"tasks"> | undefined
    >();
  });
});
