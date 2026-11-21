import { describe, expect, it } from "vitest";

import { upgradePlan } from "../../src/sql/upgrade.ts";

describe("workflow-sdk upgrades", () => {
  it("backfills wake_pending with true before the default becomes false", () => {
    const plans = upgradePlan(
      [{ module: "workflow-sdk", version: 5 }],
      {},
      undefined,
    );

    const plan = plans.find((entry) => entry.module === "workflow-sdk");

    expect(plan?.to).toBe(8);
    expect(plan?.steps.map((step) => step.from)).toEqual([5, 6, 7]);

    const sql = plan?.steps[0]?.sql ?? "";
    const add = sql.indexOf('"wake_pending" boolean not null default true');
    const clear = sql.indexOf('"wake_pending" set default false');

    expect(add).toBeGreaterThanOrEqual(0);
    expect(clear).toBeGreaterThan(add);
  });

  it("runs every step from an older version in order", () => {
    const [plan] = upgradePlan(
      [{ module: "workflow-sdk", version: 4 }],
      {},
      undefined,
    );

    expect(plan?.steps.map((step) => step.from)).toEqual([4, 5, 6, 7]);
  });
});
