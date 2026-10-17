import { describe, expect, it } from "vitest";

import { createTargets } from "../../../src/blocks/targets/index.ts";

function transport(
  results: Record<string, (args: Record<string, unknown>) => unknown>,
) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push([fn, args]);
      const result = results[fn];

      if (!result) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }

      return Promise.resolve(result(args));
    },
  };
}

const ROW = {
  id: "t1",
  name: "Quota",
  metric: "deals.won_amount",
  owner_user_id: "u1",
  team_id: null,
  period_start: "2026-10-01",
  period_end: "2026-12-31",
  currency: "EUR",
  goal: 1000,
};

describe("targets block", () => {
  it("saves goals as text and dates as ISO", async () => {
    const t = transport({ save_target: () => ROW });

    const target = await createTargets({ transport: t })
      .save("o", {
        name: "Quota",
        metric: "deals.won_amount",
        goal: 1000n,
        actual: 5n,
        periodStart: Temporal.PlainDate.from("2026-10-01"),
      })
      .orThrow();

    expect(t.calls[0]?.[1]).toEqual({
      tenant: "o",
      target: null,
      attrs: {
        name: "Quota",
        metric: "deals.won_amount",
        periodStart: "2026-10-01",
        goal: "1000",
        actual: "5",
      },
    });
    expect(target).toMatchObject({
      goal: 1000n,
      ownerId: "u1",
      currency: "EUR",
    });
    expect(target.teamId).toBeUndefined();
    expect(target.periodEnd.toString()).toBe("2026-12-31");
  });

  it("reads progress with attainment", async () => {
    const t = transport({
      target_progress: () => [{ ...ROW, progress: "600", attainment: 0.6 }],
      save_target: () => ROW,
    });

    const targets = createTargets({ transport: t });

    const [row] = await targets
      .progress("o", {
        on: Temporal.PlainDate.from("2026-11-01"),
        ownerId: "u1",
      })
      .orThrow();

    expect(row).toMatchObject({ progress: 600n, attainment: 0.6 });
    expect(t.calls[0]?.[1]).toEqual({
      tenant: "o",
      on_date: "2026-11-01",
      owner: "u1",
    });
    await targets.progress("o").orThrow();
    expect(t.calls[1]?.[1]).toEqual({
      tenant: "o",
      on_date: null,
      owner: null,
    });
    await targets.save("o", { id: "t1", archived: true }).orThrow();
    expect(t.calls[2]?.[1]).toEqual({
      tenant: "o",
      target: "t1",
      attrs: { archived: true },
    });
  });
});
