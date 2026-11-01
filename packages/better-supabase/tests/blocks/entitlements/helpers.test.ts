import { describe, expect, it } from "vitest";

import { createEntitlements } from "../../../src/blocks/entitlements/entitlements.ts";
import { createUsage } from "../../../src/blocks/usage/index.ts";

function transport(answer: (fn: string) => unknown) {
  const calls: string[] = [];

  return {
    calls,
    call(_schema: string, fn: string) {
      calls.push(fn);

      return Promise.resolve(answer(fn));
    },
  };
}

describe("entitlements helpers", () => {
  it("require fails with a forbidden error naming the entitlement", async () => {
    const entitlements = createEntitlements({
      transport: transport(() => false),
    });

    const result = await entitlements.require({
      organizationId: "o",
      key: "exports",
    });

    expect(result.ok).toBe(false);
    expect(!result.ok && result.error).toMatchObject({
      kind: "forbidden",
      permission: "entitlement:exports",
    });
  });

  it("require succeeds and all answers per key through the hooks", async () => {
    const seen: string[] = [];

    const entitlements = createEntitlements({
      transport: transport(() => true),
      hooks: { has: { before: ([input]) => void seen.push(input.key) } },
    });

    expect(
      await entitlements
        .require({ organizationId: "o", key: "audit" })
        .orThrow(),
    ).toBe(true);

    expect(
      await entitlements
        .all({ organizationId: "o", keys: ["a", "b"] })
        .orThrow(),
    ).toEqual({ a: true, b: true });

    expect(seen).toEqual(["audit", "a", "b"]);
  });
});

describe("entitlements.seatsLeft", () => {
  const seats = (value: unknown) =>
    createEntitlements({ transport: transport(() => value) });

  it("subtracts the seats used from the plan's number, never below 0", async () => {
    expect(
      await seats(10).seatsLeft({ organizationId: "o", used: 4 }).orThrow(),
    ).toBe(6);
    expect(
      await seats(3).seatsLeft({ organizationId: "o", used: 5 }).orThrow(),
    ).toBe(0);
  });

  it("is undefined when the plan sets no number", async () => {
    expect(
      await seats(null).seatsLeft({ organizationId: "o", used: 4 }).orThrow(),
    ).toBeUndefined();
  });
});

const status = (remaining: number | null) => ({
  meter: "m",
  used: 0,
  limit: remaining,
  remaining,
  unlimited: remaining === null,
  period: "month",
  resets_at: "2026-12-01T00:00:00Z",
});

describe("usage.canConsume", () => {
  it("fits when there is no quota or enough is left", async () => {
    const none = createUsage({ transport: transport(() => status(null)) });

    expect(
      await none.canConsume({ organizationId: "o", meter: "m" }).orThrow(),
    ).toBe(true);

    const some = createUsage({ transport: transport(() => status(3)) });

    expect(
      await some
        .canConsume({ organizationId: "o", meter: "m", quantity: 3 })
        .orThrow(),
    ).toBe(true);

    expect(
      await some
        .canConsume({ organizationId: "o", meter: "m", quantity: 4 })
        .orThrow(),
    ).toBe(false);
  });
});
