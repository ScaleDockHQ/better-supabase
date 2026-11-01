import { describe, expect, it } from "vitest";

import { createDeals } from "../../src/blocks/deals/index.ts";
import { createTasks } from "../../src/blocks/tasks/index.ts";

function transport(result: unknown) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push([fn, args]);

      return Promise.resolve(result);
    },
  };
}

const REFUSED = {
  accepted: [],
  rejected: [
    {
      dealId: "d1",
      workItemId: "d1",
      field: "stageId",
      hint: "LOCKED",
      reason: "locked",
    },
  ],
};

const OK = {
  accepted: [{ dealId: "d1", workItemId: "d1", field: "stageId" }],
  rejected: [],
};

describe("moveStage and move", () => {
  it("send one strict stage change through update and the hooks", async () => {
    const t = transport(OK);
    const seen: string[] = [];

    const deals = createDeals({
      transport: t,
      hooks: { update: { before: () => void seen.push("update") } },
    });

    expect(
      await deals.moveStage({ dealId: "d1", stageId: "s2" }).orThrow(),
    ).toBe(true);
    expect(seen).toEqual(["update"]);
    expect(t.calls[0]).toEqual([
      "update_deals",
      { changes: [{ dealId: "d1", field: "stageId", value: "s2" }] },
    ]);
  });

  it("return a refused move as the error", async () => {
    const deals = createDeals({ transport: transport(REFUSED) });
    const moved = await deals.moveStage({ dealId: "d1", stageId: "s2" });
    expect(moved.ok ? undefined : moved.error).toMatchObject({
      hint: "LOCKED",
    });

    const tasks = createTasks({ transport: transport(REFUSED) });
    const result = await tasks.move({ workItemId: "d1", stageId: "s2" });
    expect(result.ok).toBe(false);
  });
});
