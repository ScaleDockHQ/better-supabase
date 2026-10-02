import { describe, expect, it, onTestFinished, vi } from "vitest";

import { DbException } from "../../src/core/errors.ts";
import { temporal, temporalMissing } from "../../src/core/temporal-required.ts";
import { TEMPORAL_POLYFILL } from "../../src/core/temporal.ts";

describe("temporal", () => {
  it("returns the runtime's Temporal", () => {
    expect(temporal()).toBe(globalThis.Temporal);
  });

  it("throws an unexpected error that names the polyfill when Temporal is missing", () => {
    vi.stubGlobal("Temporal", undefined);
    onTestFinished(() => {
      vi.unstubAllGlobals();
    });
    expect(() => temporal()).toThrow(DbException);
    expect(temporalMissing()).toMatchObject({
      kind: "unexpected",
      status: 500,
      message: expect.stringContaining(TEMPORAL_POLYFILL),
    });
  });
});
