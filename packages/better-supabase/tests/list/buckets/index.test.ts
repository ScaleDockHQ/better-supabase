import { describe, expect, it, vi } from "vitest";

import { dbError } from "../../../src/core/errors.ts";
import { err, ok } from "../../../src/core/result.ts";
import { listDateBuckets } from "../../../src/list/buckets/index.ts";

describe("listDateBuckets", () => {
  it("calls the function with the unit, zone, range and facet values", async () => {
    const rpc = vi.fn(() =>
      Promise.resolve(ok([{ bucket: "2026-01-01T00:00:00+00:00", count: 3 }])),
    );

    const result = await listDateBuckets({
      rpc,
      unit: "month",
      timeZone: "Europe/Amsterdam",
      from: new Date("2026-01-01T00:00:00Z"),
      to: "2026-03-01",
      list: {
        facets: [{ key: "state", column: "status" }],
        query: { facets: { state: ["open", "done"] } },
      },
    }).orThrow();

    expect(result).toEqual([{ start: "2026-01-01T00:00:00+00:00", count: 3 }]);
    expect(rpc).toHaveBeenCalledWith({
      unit: "month",
      tz: "Europe/Amsterdam",
      from_at: "2026-01-01T00:00:00.000Z",
      to_at: "2026-03-01",
      equals: { status: ["open", "done"] },
    });
  });

  it("defaults to UTC with no range or filters", async () => {
    const rpc = vi.fn(() => Promise.resolve(ok([])));

    await listDateBuckets({ rpc, unit: "day" }).orThrow();

    expect(rpc).toHaveBeenCalledWith({
      unit: "day",
      tz: "UTC",
      from_at: null,
      to_at: null,
      equals: {},
    });
  });

  it("refuses facets the function cannot narrow by", async () => {
    const rpc = vi.fn(() => Promise.resolve(ok([])));

    for (const facet of [
      { key: "tag", column: "name", relation: { name: "tags" } },
      { key: "state", column: "status" },
    ]) {
      const result = await listDateBuckets({
        rpc,
        unit: "day",
        list: {
          facets: [facet],
          query: {
            facets: { [facet.key]: facet.relation ? ["a"] : ["__unset__"] },
          },
        },
      });

      expect(result.ok).toBe(false);
    }

    expect(rpc).not.toHaveBeenCalled();
  });

  it("passes a database error through and rejects a malformed result", async () => {
    const failed = await listDateBuckets({
      rpc: () => Promise.resolve(err(dbError("forbidden", "no"))),
      unit: "day",
    });

    expect(failed.ok).toBe(false);
    expect(failed.error?.kind).toBe("forbidden");

    const bad = await listDateBuckets({
      rpc: () => Promise.resolve(ok({ nope: true })),
      unit: "day",
    });

    expect(bad.ok).toBe(false);
  });
});
