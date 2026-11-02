import { describe, expect, it } from "vitest";

import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import { AGENT_MANDATE_TYPES } from "../../src/sql/modules/agent-checkout-values.ts";

describe("AP2 v0.2", () => {
  it("is pinned to the release whose credential types the block signs", () => {
    expect(SPEC_PINS.ap2).toBe("0.2");
  });

  it("uses the open and closed checkout mandate types", () => {
    expect(AGENT_MANDATE_TYPES).toEqual([
      "mandate.checkout.open.1",
      "mandate.checkout.1",
    ]);
  });
});
