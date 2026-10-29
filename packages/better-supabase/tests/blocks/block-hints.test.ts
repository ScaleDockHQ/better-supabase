import { describe, expect, it } from "vitest";

import { blockHint, isBlockHint } from "../../src/blocks/block-hints.ts";
import { dbError } from "../../src/core/errors.ts";

describe("block hints", () => {
  const locked = dbError("forbidden", "locked", { hint: "WORK_ITEM_LOCKED" });

  it("matches an error carrying one of the hints", () => {
    expect(isBlockHint(locked, "WORK_ITEM_LOCKED", "WORK_ITEM_FORBIDDEN")).toBe(
      true,
    );
    expect(isBlockHint(locked, "WORK_ITEM_FORBIDDEN")).toBe(false);
  });

  it("rejects an error without a hint and no error", () => {
    expect(isBlockHint(dbError("forbidden", "no"), "WORK_ITEM_LOCKED")).toBe(
      false,
    );
    expect(isBlockHint(undefined, "WORK_ITEM_LOCKED")).toBe(false);
  });

  it("reads the hint of a block's error", () => {
    expect(blockHint<"tasks">(locked)).toBe("WORK_ITEM_LOCKED");
    expect(blockHint<"tasks">(dbError("forbidden", "no"))).toBeUndefined();
  });
});
