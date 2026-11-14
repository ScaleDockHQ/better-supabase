import { describe, expect, it } from "vitest";

import {
  createJobs,
  jobRef,
  jobResultOf,
  parseJobId,
} from "../../src/core/jobs.ts";
import { AsyncResult } from "../../src/core/result.ts";

describe("jobs", () => {
  it("names a job by its kind and id", () => {
    expect(jobRef("bulk", "r1")).toEqual({ jobId: "bulk:r1" });
    expect(parseJobId("bulk:r:1")).toEqual({ kind: "bulk", id: "r:1" });
    expect(parseJobId("nokind")).toBeUndefined();
    expect(parseJobId(":x")).toBeUndefined();
  });

  const jobs = createJobs({
    bulk: {
      get: (id) =>
        AsyncResult.ok(
          id === "r1"
            ? jobResultOf("bulk", id, {
                status: "running",
                progress: { done: 1, total: 4 },
              })
            : null,
        ),
    },
  });

  it("routes to the source of the kind", async () => {
    const result = await jobs.get("bulk:r1");

    expect(result.ok && result.data).toMatchObject({
      jobId: "bulk:r1",
      status: "running",
      done: false,
      progress: { done: 1, total: 4 },
      result: null,
      error: null,
    });
  });

  it("is not_found for an id the source does not know", async () => {
    const result = await jobs.get("bulk:nope");

    expect(!result.ok && result.error.kind).toBe("not_found");
  });

  it("is invalid_input for an unknown kind", async () => {
    for (const id of ["import:1", "x", "constructor:1"]) {
      const result = await jobs.get(id);

      expect(!result.ok && result.error.hint).toBe("JOB_KIND_UNKNOWN");
    }
  });

  it("marks completed and failed jobs done", () => {
    expect(jobResultOf("bulk", "a", { status: "completed" }).done).toBe(true);
    expect(jobResultOf("bulk", "a", { status: "failed" }).done).toBe(true);
  });
});
