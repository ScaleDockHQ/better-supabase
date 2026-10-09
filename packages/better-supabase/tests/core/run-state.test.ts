import { describe, expect, it } from "vitest";

import { FINAL_RUN_STATES, runStateOf } from "../../src/core/run-state.ts";

describe("run states", () => {
  it("reads a stored state, falling back for unknown values", () => {
    expect(runStateOf("done", FINAL_RUN_STATES, "failed")).toBe("failed");
    expect(runStateOf("cancelled", FINAL_RUN_STATES, "failed")).toBe(
      "cancelled",
    );
    expect(runStateOf("waiting", FINAL_RUN_STATES, "failed")).toBe("failed");
    expect(runStateOf(3, FINAL_RUN_STATES, "failed")).toBe("failed");
  });
});
