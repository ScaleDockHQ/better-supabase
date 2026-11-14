import { describe, expect, it } from "vitest";

import {
  BULK_LIMIT,
  bulk,
  bulkOfSet,
  bulkReportOf,
  checkBulkLimit,
} from "../../src/core/bulk.ts";
import { dbError } from "../../src/core/errors.ts";
import { err, ok } from "../../src/core/result.ts";

describe("bulk", () => {
  it("collects the ids that changed and the ones that failed", async () => {
    const result = await bulk(["a", "b", "c"], "archive", (id) =>
      Promise.resolve(
        id === "b" ? err(dbError("not_found", "No row")) : ok(true),
      ),
    );

    expect(result.ok && result.data.succeeded).toEqual(["a", "c"]);
    expect(result.ok && result.data.failed).toEqual([
      { id: "b", error: dbError("not_found", "No row") },
    ]);
  });

  it("turns a throw into a failed id and keeps going", async () => {
    const result = await bulk(["a", "b"], "go", (id) => {
      if (id === "a") {
        throw new Error("boom");
      }

      return Promise.resolve(ok(true));
    });

    expect(result.ok && result.data.succeeded).toEqual(["b"]);
    expect(result.ok && result.data.failed.map((f) => f.id)).toEqual(["a"]);
  });

  it("runs each distinct id once", async () => {
    const seen: string[] = [];

    await bulk(["a", "a", "b"], "go", (id) => {
      seen.push(id);

      return Promise.resolve(ok(true));
    });

    expect(seen).toEqual(["a", "b"]);
  });

  it("rejects more ids than the limit without running any", async () => {
    let calls = 0;

    const result = await bulk(
      ["a", "b", "c"],
      "go",
      () => {
        calls += 1;

        return Promise.resolve(ok(true));
      },
      { limit: 2 },
    );

    expect(calls).toBe(0);
    expect(!result.ok && result.error.hint).toBe("BULK_TOO_MANY");
  });

  it("defaults the limit to 500", () => {
    const ids = Array.from({ length: BULK_LIMIT + 1 }, (_, i) => String(i));

    expect(checkBulkLimit(ids)?.hint).toBe("BULK_TOO_MANY");
    expect(checkBulkLimit(ids.slice(1))).toBeUndefined();
  });

  it("maps per-row SQL results to the report", () => {
    const report = bulkReportOf([
      { id: "a", ok: true, error: null },
      {
        id: "b",
        ok: false,
        error: {
          code: "TAG_SUBJECT_FORBIDDEN",
          message: "No",
          sqlstate: "42501",
        },
      },
    ]);

    expect(report.succeeded).toEqual(["a"]);
    expect(report.failed[0]?.error).toMatchObject({
      kind: "raised",
      code: "42501",
      hint: "TAG_SUBJECT_FORBIDDEN",
    });
  });

  it("reports a failed row without error details", () => {
    const report = bulkReportOf([{ id: "x", ok: false, error: null }]);

    expect(report.failed[0]?.error).toMatchObject({
      kind: "raised",
      message: "The action failed",
    });
    expect(report.failed[0]?.error.hint).toBeUndefined();
  });
});

describe("bulkOfSet", () => {
  it("passes a failed set call through", async () => {
    const result = await bulkOfSet(["a"], () =>
      Promise.resolve(err(dbError("timeout", "Too slow"))),
    );

    expect(!result.ok && result.error.kind).toBe("timeout");
  });
});
