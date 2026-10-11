import { describe, expect, it } from "vitest";

import {
  DEFAULT_TYPE_PREFIX,
  stripTypePrefix,
} from "../../src/events/cloud-event.ts";

describe("stripTypePrefix", () => {
  it("removes the default prefix and its dot", () => {
    expect(stripTypePrefix(`${DEFAULT_TYPE_PREFIX}.order.paid`)).toBe(
      "order.paid",
    );
  });

  it("takes a custom prefix with or without a trailing dot", () => {
    expect(stripTypePrefix("acme.order.paid", "acme")).toBe("order.paid");
    expect(stripTypePrefix("acme.order.paid", "acme.")).toBe("order.paid");
  });

  it("leaves other types unchanged", () => {
    expect(stripTypePrefix("other.order.paid", "acme")).toBe(
      "other.order.paid",
    );
  });
});
