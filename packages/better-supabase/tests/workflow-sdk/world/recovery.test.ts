import type { Pool } from "pg";

import { describe, expect, it, vi } from "vitest";

import {
  clearOwedWake,
  sweepOwedWakes,
} from "../../../src/workflow-sdk/world/recovery.ts";

const body = (value: unknown): string =>
  Buffer.from(JSON.stringify(value)).toString("base64");

function message(queueName: string, value: unknown) {
  return { queueName, messageId: "msg_1", attempt: 1, body: body(value) };
}

describe("clearOwedWake", () => {
  it("clears the flag of the run an orchestrator message names", async () => {
    const query = vi.fn(async () => ({ rows: [] }));

    await clearOwedWake(
      { query } as unknown as Pool,
      "__wkf_workflow_",
      message("__wkf_workflow_a", { runId: "wrun_1" }),
    );

    expect(query).toHaveBeenCalledWith(
      expect.stringContaining("set wake_pending = false"),
      ["wrun_1"],
    );
  });

  it("leaves step messages, bodies without a run and bad bodies alone", async () => {
    const query = vi.fn(async () => ({ rows: [] }));
    const pool = { query } as unknown as Pool;

    await clearOwedWake(
      pool,
      "__wkf_workflow_",
      message("__wkf_step_a", { runId: "wrun_1" }),
    );
    await clearOwedWake(
      pool,
      "__wkf_workflow_",
      message("__wkf_workflow_a", {}),
    );
    await clearOwedWake(pool, "__wkf_workflow_", {
      queueName: "__wkf_workflow_a",
      messageId: "m",
      attempt: 1,
      body: Buffer.from("not json").toString("base64"),
    });

    expect(query).not.toHaveBeenCalled();
  });

  it("ignores a failed update", async () => {
    const query = vi.fn(async () => {
      throw new Error("no table");
    });

    await expect(
      clearOwedWake(
        { query },
        "__wkf_workflow_",
        message("__wkf_workflow_a", { runId: "wrun_1" }),
      ),
    ).resolves.toBeUndefined();
  });
});

describe("sweepOwedWakes", () => {
  const logger = {
    debug: vi.fn(),
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  };

  it("queues a wake-up per owed run under a key that holds for one window", async () => {
    const query = vi.fn(async () => ({
      rows: [
        { id: "wrun_1", name: "a", spec_version: "3" },
        { id: "wrun_2", name: "b", spec_version: null },
      ],
    }));

    const queue = vi.fn(async () => ({}));

    const woken = await sweepOwedWakes({
      pool: { query } as unknown as Pool,
      queue,
      logger,
      recoverAfter: 60,
      prefix: "__x_wkf_workflow_",
    });

    expect(woken).toBe(2);
    expect(query).toHaveBeenCalledWith(
      expect.stringContaining("wake_pending"),
      [60],
    );
    expect(queue.mock.calls[0] as unknown[]).toEqual([
      "__x_wkf_workflow_a",
      { runId: "wrun_1", runSpecVersion: 3 },
      { idempotencyKey: expect.stringMatching(/^wake:wrun_1:\d+$/) },
    ]);
    expect((queue.mock.calls[1] as unknown[])[1]).toEqual({
      runId: "wrun_2",
      runSpecVersion: 0,
    });
  });

  it("logs a run it could not wake and carries on", async () => {
    const query = vi.fn(async () => ({
      rows: [
        { id: "wrun_1", name: "a", spec_version: "3" },
        { id: "wrun_2", name: "b", spec_version: "3" },
      ],
    }));

    const queue = vi
      .fn()
      .mockRejectedValueOnce(new Error("down"))
      .mockResolvedValueOnce({});

    const woken = await sweepOwedWakes({
      pool: { query } as unknown as Pool,
      queue,
      logger,
      recoverAfter: 60,
      prefix: "__wkf_workflow_",
    });

    expect(woken).toBe(1);
    expect(logger.warn).toHaveBeenCalledWith(
      expect.stringContaining("could not be sent again"),
      expect.objectContaining({ runId: "wrun_1" }),
    );
  });
});
