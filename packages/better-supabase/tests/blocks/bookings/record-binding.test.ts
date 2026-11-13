import { describe, expect, it } from "vitest";

import {
  createBookings,
  bookingsBinding,
  bookingsBlock,
} from "../../../src/blocks/bookings/index.ts";

function transport(calls: [string, Record<string, unknown>][]) {
  return {
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push([fn, args]);

      return Promise.resolve([]);
    },
  };
}

describe("bookingsBinding", () => {
  it("reads the customer's bookings in the block's organization", async () => {
    const calls: [string, Record<string, unknown>][] = [];

    const client = createBookings({
      tenant: "org-1",
      transport: transport(calls),
    });

    const loaded = await bookingsBinding.load(
      client,
      { type: "user", id: "s1" },
      undefined,
    );

    expect(loaded.ok && loaded.data).toEqual([]);

    expect(calls).toEqual([
      [
        "list_bookings_for_customer",
        { tenant: "org-1", customer: "s1", page_size: null },
      ],
    ]);
    expect(bookingsBlock.record).toBe(bookingsBinding);
    expect(bookingsBinding.events).toEqual(["booking.*"]);
  });

  it("fails without an organization", async () => {
    const client = createBookings({ transport: transport([]) });

    const loaded = await bookingsBinding.load(
      client,
      { type: "user", id: "s1" },
      undefined,
    );

    expect(loaded.ok).toBe(false);
  });
});
