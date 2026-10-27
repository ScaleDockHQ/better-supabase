import { Temporal } from "temporal-polyfill";
import { afterEach, describe, expect, it } from "vitest";

import { provideTemporal } from "../../../src/core/temporal.ts";
import { createMaintenance } from "../../../src/workflow-sdk/world/maintenance.ts";

interface Sent {
  readonly fn: string;
  readonly args: readonly unknown[];
}

function fakeCall(answers: Record<string, unknown[][]>): {
  sent: Sent[];
  call: <T>(fn: string, args: readonly unknown[]) => Promise<T[]>;
} {
  const sent: Sent[] = [];

  return {
    sent,
    call: <T>(fn: string, args: readonly unknown[]) => {
      sent.push({ fn, args });

      // SAFETY: each test queues the rows its function returns.
      return Promise.resolve((answers[fn]?.shift() ?? []) as T[]);
    },
  };
}

afterEach(() => {
  provideTemporal(undefined);
});

describe("createMaintenance", () => {
  it("claims, sets and releases run keys", async () => {
    const { sent, call } = fakeCall({
      workflow_claim_run_key: [[{ claimed: false, run_id: "wrun_1" }], []],
    });

    const { runKeys } = createMaintenance(call);

    expect(await runKeys.claim("k")).toEqual({
      claimed: false,
      runId: "wrun_1",
    });
    expect(await runKeys.claim("k")).toEqual({
      claimed: false,
      runId: undefined,
    });

    await runKeys.set("k", "wrun_2");
    await runKeys.release("k");

    expect(sent.map((entry) => entry.fn)).toEqual([
      "workflow_claim_run_key",
      "workflow_claim_run_key",
      "workflow_set_run_key",
      "workflow_release_run_key",
    ]);
    expect(sent[0]?.args).toEqual(["k", "5 minutes"]);
  });

  it("purges in batches until one comes back short", async () => {
    const { sent, call } = fakeCall({
      workflow_purge_runs: [
        [{ workflow_purge_runs: 2 }],
        [{ workflow_purge_runs: 1 }],
      ],
    });

    const total = await createMaintenance(call).purgeRuns({
      olderThan: "7 days",
      statuses: ["failed"],
      batch: 2,
    });

    expect(total).toBe(3);
    expect(sent[0]?.args).toEqual(["7 days", ["failed"], 2]);
  });

  it("purges ended runs older than 30 days by default", async () => {
    const { sent, call } = fakeCall({});

    expect(await createMaintenance(call).purgeRuns()).toBe(0);
    expect(sent[0]?.args).toEqual([
      "30 days",
      ["completed", "failed", "cancelled"],
      500,
    ]);
  });

  it("maps open hooks and their creation time", async () => {
    provideTemporal(Temporal);

    const { sent, call } = fakeCall({
      workflow_open_hooks: [
        [
          {
            hook_id: "hook_1",
            run_id: "wrun_1",
            workflow: "approve",
            tenant_id: null,
            actor_id: "user_1",
            metadata: { step: 1 },
            created_at: "2026-10-27T10:00:00.000Z",
          },
        ],
      ],
    });

    const [hook] = await createMaintenance(call).openHooks({ tenantId: "t1" });

    expect(hook).toMatchObject({
      hookId: "hook_1",
      runId: "wrun_1",
      workflowName: "approve",
      tenantId: undefined,
      actorId: "user_1",
      metadata: { step: 1 },
    });
    expect(hook?.createdAt.toString()).toBe("2026-10-27T10:00:00Z");
    expect(sent[0]?.args).toEqual(["t1", null, 50]);
  });
});
