import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../../src/core/block-transport.ts";

import { createWorkflows } from "../../../src/blocks/workflows/workflows.ts";
import { createJobs } from "../../../src/core/jobs.ts";

const run = (status: string, extra: Record<string, unknown> = {}) => ({
  id: "r1",
  engine: "workflow-sdk",
  externalId: "wrun_1",
  definition: "onboard",
  tenant: "t1",
  actor: "u1",
  status,
  attributes: {},
  error: null,
  createdAt: "2026-01-01T00:00:00Z",
  updatedAt: "2026-01-01T00:00:01Z",
  startedAt: null,
  completedAt: null,
  cancelRequestedAt: null,
  ...extra,
});

function jobsOf(row: unknown) {
  const transport: BlockTransport = { call: () => Promise.resolve(row) };

  return createJobs({ workflow: createWorkflows({ transport }).jobs });
}

describe("workflows jobs", () => {
  it("reads a queued or waiting run as pending or running", async () => {
    const queued = await jobsOf(run("queued")).get("workflow:r1").orThrow();
    const waiting = await jobsOf(run("waiting")).get("workflow:r1").orThrow();

    expect(queued).toMatchObject({ status: "pending", done: false });
    expect(waiting).toMatchObject({ status: "running", done: false });
  });

  it("reads a completed run with the run as its result", async () => {
    const job = await jobsOf(run("completed")).get("workflow:r1").orThrow();

    expect(job).toMatchObject({
      jobId: "workflow:r1",
      status: "completed",
      done: true,
      result: { id: "r1" },
    });
  });

  it("reads a failed or cancelled run as failed with a hint", async () => {
    const failed = await jobsOf(run("failed", { error: "boom" }))
      .get("workflow:r1")
      .orThrow();

    const cancelled = await jobsOf(run("cancelled"))
      .get("workflow:r1")
      .orThrow();

    expect(failed?.error).toMatchObject({
      message: "boom",
      hint: "WORKFLOW_RUN_FAILED",
    });
    expect(cancelled?.error).toMatchObject({ hint: "WORKFLOW_RUN_CANCELLED" });
  });

  it("is not_found for a run the caller cannot see", async () => {
    const result = await jobsOf(null).get("workflow:nope");

    expect(!result.ok && result.error.kind).toBe("not_found");
  });
});
