import { describe, expect, it } from "vitest";

import {
  FINAL_RUN_STATES,
  runStateOf,
  sharedRunState,
} from "../../src/core/run-state.ts";

describe("run states", () => {
  it("maps the pre-0.7 names to the shared ones", () => {
    expect(sharedRunState("done")).toBe("completed");
    expect(sharedRunState("error")).toBe("failed");
    expect(sharedRunState("stopped")).toBe("cancelled");
    expect(sharedRunState("succeeded")).toBe("completed");
    expect(sharedRunState("running")).toBe("running");
  });

  it("reads a stored state, falling back for unknown values", () => {
    expect(runStateOf("done", FINAL_RUN_STATES, "failed")).toBe("completed");
    expect(runStateOf("cancelled", FINAL_RUN_STATES, "failed")).toBe(
      "cancelled",
    );
    expect(runStateOf("waiting", FINAL_RUN_STATES, "failed")).toBe("failed");
    expect(runStateOf(3, FINAL_RUN_STATES, "failed")).toBe("failed");
  });
});
