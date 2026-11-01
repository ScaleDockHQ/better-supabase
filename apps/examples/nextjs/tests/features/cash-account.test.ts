import { describe, expect, it } from "vitest";

import type { ChartAccount } from "@/features/tills/cash-account";

import { planCashAccount } from "@/features/tills/cash-account";

const account = (overrides: Partial<ChartAccount>): ChartAccount => ({
  id: "a1",
  code: "1000",
  name: "Cash",
  type: "asset",
  active: true,
  ...overrides,
});

describe("planCashAccount", () => {
  it("maps an unused euro asset account named for cash", () => {
    expect(
      planCashAccount([account({ id: "cash" })], new Set(), "Front"),
    ).toEqual({ kind: "map", accountId: "cash" });
  });

  it.each([
    ["is used by a till", account({ id: "cash" }), new Set(["cash"])],
    ["is archived", account({ active: false }), new Set<string>()],
    ["is not an asset", account({ type: "expense" }), new Set<string>()],
    ["is in another currency", account({ currency: "USD" }), new Set<string>()],
    ["has no cash in its name", account({ name: "Bank" }), new Set<string>()],
  ])("creates an account when the cash account %s", (_name, cash, used) => {
    expect(planCashAccount([cash], used, "Front")).toEqual({
      kind: "create",
      code: "1001",
      name: "Cash Front",
    });
  });

  it("starts at 1000 and skips codes the chart has", () => {
    expect(planCashAccount([], new Set(), "Bar")).toEqual({
      kind: "create",
      code: "1000",
      name: "Cash Bar",
    });
    expect(
      planCashAccount(
        [
          account({ code: "1000", name: "Bank" }),
          account({ code: "1001", name: "Bank" }),
        ],
        new Set(),
        "Bar",
      ),
    ).toMatchObject({ code: "1002" });
  });
});
