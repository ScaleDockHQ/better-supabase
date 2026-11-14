import { describe, expect, it } from "vitest";

import { createDataLifecycle } from "../../../src/blocks/data-lifecycle/index.ts";
import { createJobs } from "../../../src/core/jobs.ts";

const exportRow = (overrides: Record<string, unknown> = {}) => ({
  id: "x1",
  subject: "user",
  user_id: "u1",
  organization_id: null,
  subject_type: null,
  subject_id: null,
  format: "ndjson",
  status: "ready",
  bucket: "data-exports",
  files: ["x1/public.profiles.ndjson"],
  error: null,
  requested_by: "u1",
  requested_at: "2026-10-06T12:00:00Z",
  completed_at: null,
  expires_at: null,
  ...overrides,
});

function lifecycle(results: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];

  const client = createDataLifecycle({
    transport: {
      call(_schema, fn, args) {
        calls.push([fn, { ...args }]);

        return Promise.resolve(results[fn]);
      },
    },
  });

  return { calls, client, jobs: createJobs({ export: client.jobs }) };
}

describe("data lifecycle jobs", () => {
  it("starts an export as a job", async () => {
    const { calls, client } = lifecycle({
      request_data_export: exportRow({ status: "pending" }),
    });

    expect(await client.startExportJob().orThrow()).toEqual({
      jobId: "export:x1",
    });
    expect(
      await client.startExportJob({ organizationId: "org-1" }).orThrow(),
    ).toEqual({ jobId: "export:x1" });
    expect(calls[0]).toEqual(["request_data_export", { subject: "user" }]);
    expect(calls[1]?.[1]).toEqual({ subject: "organization", tenant: "org-1" });
  });

  it("reads a pending, ready and failed export", async () => {
    const pending = lifecycle({
      get_data_export: exportRow({ status: "pending" }),
    });

    const ready = lifecycle({ get_data_export: exportRow() });

    const failed = lifecycle({
      get_data_export: exportRow({ status: "failed", error: "no space" }),
    });

    expect(await pending.jobs.get("export:x1").orThrow()).toMatchObject({
      status: "pending",
      done: false,
      result: null,
    });
    expect(await ready.jobs.get("export:x1").orThrow()).toMatchObject({
      status: "completed",
      done: true,
      result: { id: "x1" },
    });
    expect((await failed.jobs.get("export:x1").orThrow())?.error).toMatchObject(
      { message: "no space", hint: "DATA_EXPORT_FAILED" },
    );
  });

  it("is not_found for an export the caller cannot see", async () => {
    const { jobs } = lifecycle({ get_data_export: null });
    const result = await jobs.get("export:nope");

    expect(!result.ok && result.error.kind).toBe("not_found");
  });
});
