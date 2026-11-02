import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../../src/core/block-transport.ts";

import {
  BLOCK_TICKS_QUEUE,
  blockSchedules,
  blockTickHandler,
  maintenanceTick,
  maintenanceTimer,
} from "../../../src/blocks/queue/index.ts";

function fake(scheduler: string, fail = false) {
  const calls: string[] = [];

  const transport: BlockTransport = {
    call: (schema, fn) => {
      calls.push(`${schema}.${fn}`);

      if (fail && fn === "maintenance") {
        return Promise.reject(new Error("boom"));
      }

      return Promise.resolve(
        fn === "maintenance_scheduler"
          ? scheduler
          : [{ job: "purge", status: "ok" }],
      );
    },
  };

  return { calls, transport };
}

describe("maintenanceTick", () => {
  it("schedules the tick on block_ticks", () => {
    expect(blockSchedules([maintenanceTimer])).toEqual([
      {
        name: "block:housekeeping.maintenance",
        cron: "*/5 * * * *",
        queue: BLOCK_TICKS_QUEUE,
        payload: { block: "housekeeping", name: "maintenance" },
      },
    ]);
  });

  it("runs maintenance when pg_cron is missing", async () => {
    const { calls, transport } = fake("none");
    const result = await maintenanceTick(transport)();

    expect(result).toMatchObject({
      ok: true,
      data: { scheduler: "none", jobs: [{ job: "purge", status: "ok" }] },
    });
    expect(calls).toEqual([
      "better_supabase.maintenance_scheduler",
      "better_supabase.maintenance",
    ]);
  });

  it("skips when pg_cron runs the dispatcher, unless forced", async () => {
    const skipped = fake("pg_cron");

    expect(await maintenanceTick(skipped.transport)()).toMatchObject({
      ok: true,
      data: { scheduler: "pg_cron", jobs: [] },
    });
    expect(skipped.calls).toEqual(["better_supabase.maintenance_scheduler"]);

    const forced = fake("pg_cron");

    await maintenanceTick(forced.transport, { force: true })();
    expect(forced.calls).toContain("better_supabase.maintenance");
  });

  it("returns a failed result so the queue retries", async () => {
    const { transport } = fake("none", true);

    const handle = blockTickHandler({
      "housekeeping.maintenance": maintenanceTick(transport, { schema: "x" }),
    });

    await expect(
      handle({ block: "housekeeping", name: "maintenance" }),
    ).rejects.toThrow("housekeeping.maintenance");
  });
});
