import { describe, expect, it } from "vitest";

import { createDrive } from "../../../src/blocks/drive/index.ts";

function transport(results: Record<string, (args: unknown) => unknown>) {
  const calls: [string, string, unknown][] = [];

  return {
    calls,
    call(schema: string, fn: string, args: unknown) {
      calls.push([schema, fn, args]);
      const result = results[fn];

      return result
        ? Promise.resolve(result(args))
        : Promise.reject(new Error(`unexpected ${fn}`));
    },
  };
}

const NODE = {
  id: "n1",
  organizationId: "o",
  parentId: null,
  kind: "file",
  name: "plan.pdf",
  rank: null,
  createdBy: null,
  createdAt: "2026-10-01T00:00:00Z",
  updatedAt: "2026-10-02T00:00:00Z",
  deletedAt: null,
  role: "owner",
};

describe("drive changes and retention", () => {
  it("reads a page of the feed and passes the cursor", async () => {
    const fake = transport({
      drive_changes: () => ({
        changes: [
          { removed: false, node: NODE },
          { removed: true, id: "n2" },
        ],
        cursor: "2026-10-02T00:00:00.000000Z|n1",
        more: true,
      }),
    });

    const drive = createDrive({ transport: fake });

    const page = await drive
      .changes("o", { cursor: "c0", pageSize: 2, driveId: "d1" })
      .orThrow();

    expect(page.more).toBe(true);
    expect(page.cursor).toBe("2026-10-02T00:00:00.000000Z|n1");
    expect(page.changes).toHaveLength(2);
    expect(page.changes[0]).toMatchObject({
      removed: false,
      node: { id: "n1" },
    });
    expect(page.changes[1]).toEqual({ removed: true, id: "n2" });
    expect(fake.calls[0]?.[2]).toEqual({
      tenant: "o",
      after: "c0",
      page_size: 2,
      drive: "d1",
    });
  });

  it("has no cursor on an empty first page", async () => {
    const fake = transport({
      drive_changes: () => ({ changes: [], cursor: null, more: false }),
    });

    const page = await createDrive({ transport: fake }).changes("o").orThrow();

    expect(page.cursor).toBeUndefined();
    expect(page.changes).toEqual([]);
    expect(fake.calls[0]?.[2]).toEqual({
      tenant: "o",
      after: null,
      page_size: null,
      drive: null,
    });
  });

  it("sweeps retention and returns the binned count", async () => {
    const fake = transport({ drive_retention_sweep: () => 3 });
    const drive = createDrive({ transport: fake });

    expect(await drive.sweepRetention().orThrow()).toBe(3);
    expect(
      await drive
        .sweepRetention({ organizationId: "o", batchSize: 10 })
        .orThrow(),
    ).toBe(3);
    expect(fake.calls.map(([, , args]) => args)).toEqual([
      { tenant: null, batch_size: null },
      { tenant: "o", batch_size: 10 },
    ]);
  });
});
