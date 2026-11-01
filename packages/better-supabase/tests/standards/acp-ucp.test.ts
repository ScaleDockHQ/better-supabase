import { describe, expect, it } from "vitest";

import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import {
  CHECKOUT_PROTOCOLS,
  CHECKOUT_SESSION_STATUSES,
} from "../../src/sql/modules/agent-checkout-values.ts";

describe("ACP and UCP checkout sessions", () => {
  it("pins both protocol revisions", () => {
    expect(SPEC_PINS.acp).toBe("2026-04-17");
    expect(SPEC_PINS.ucp).toBe("2026-08-25");
  });

  it("opens a session under one of the two protocols", () => {
    expect(CHECKOUT_PROTOCOLS).toEqual(["acp", "ucp"]);
  });

  it("moves a session through the states both protocols share", () => {
    expect(CHECKOUT_SESSION_STATUSES).toEqual([
      "open",
      "ready",
      "completed",
      "canceled",
    ]);
  });
});
