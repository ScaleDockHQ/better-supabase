import { describe, expect, it } from "vitest";

import { contentBlock } from "../../../src/blocks/content/index.ts";
import {
  BLOCK_TICKS_QUEUE,
  blockSchedules,
  blockTickHandler,
  blockTickSchema,
} from "../../../src/blocks/queue/index.ts";
import { slaBlock } from "../../../src/blocks/sla/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult } from "../../../src/core/result.ts";

describe("blockSchedules", () => {
  it("turns each block timer into a block_ticks schedule", () => {
    expect(
      blockSchedules([
        slaBlock,
        { name: "custom", schedules: [] },
        {
          name: "reports",
          schedules: [
            {
              name: "nightly",
              cron: "0 3 * * *",
              runs: "build()",
              description: "Builds the reports.",
            },
          ],
        },
      ]),
    ).toEqual([
      {
        name: "block:sla.check",
        cron: "* * * * *",
        queue: BLOCK_TICKS_QUEUE,
        payload: { block: "sla", name: "check" },
      },
      {
        name: "block:reports.nightly",
        cron: "0 3 * * *",
        queue: BLOCK_TICKS_QUEUE,
        payload: { block: "reports", name: "nightly" },
      },
    ]);
  });

  it("publishes the due content entries every five minutes", () => {
    expect(blockSchedules([contentBlock])).toEqual([
      {
        name: "block:content.publish",
        cron: "*/5 * * * *",
        queue: BLOCK_TICKS_QUEUE,
        payload: { block: "content", name: "publish" },
      },
    ]);
  });

  it("checks the tick payload", async () => {
    expect(
      await blockTickSchema["~standard"].validate({ block: "sla", name: "x" }),
    ).toEqual({ value: { block: "sla", name: "x" } });
    expect(
      await blockTickSchema["~standard"].validate({ block: 1 }),
    ).toHaveProperty("issues");
  });
});

describe("blockTickHandler", () => {
  it("runs the handler a tick names and throws on a failure or a missing one", async () => {
    const ran: string[] = [];

    const handle = blockTickHandler({
      "sla.check": () => {
        ran.push("sla");

        return AsyncResult.ok(3);
      },
      "sequences.run-due": () => AsyncResult.err(dbError("unexpected", "down")),
    });

    await handle({ block: "sla", name: "check" });
    expect(ran).toEqual(["sla"]);
    await expect(
      handle({ block: "sequences", name: "run-due" }),
    ).rejects.toThrow("sequences.run-due: down");
    await expect(handle({ block: "x", name: "y" })).rejects.toThrow(
      "No handler for the block timer x.y",
    );
  });
});
