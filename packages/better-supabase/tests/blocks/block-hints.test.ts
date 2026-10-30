import { describe, expect, it } from "vitest";

import { blockHint, isBlockHint } from "../../src/blocks/block-hints.ts";
import { dbError } from "../../src/core/errors.ts";

describe("block hints", () => {
  const locked = dbError("forbidden", "locked", { hint: "TASK_LOCKED" });

  it("matches an error carrying one of the hints", () => {
    expect(isBlockHint(locked, "TASK_LOCKED", "TASK_FORBIDDEN")).toBe(true);
    expect(isBlockHint(locked, "TASK_FORBIDDEN")).toBe(false);
  });

  it("rejects an error without a hint and no error", () => {
    expect(isBlockHint(dbError("forbidden", "no"), "TASK_LOCKED")).toBe(false);
    expect(isBlockHint(undefined, "TASK_LOCKED")).toBe(false);
  });

  it("reads the hint of a block's error", () => {
    expect(blockHint<"tasks">(locked)).toBe("TASK_LOCKED");
    expect(blockHint<"tasks">(dbError("forbidden", "no"))).toBeUndefined();
  });
});
