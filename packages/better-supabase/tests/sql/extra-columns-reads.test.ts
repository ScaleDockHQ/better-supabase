import { describe, expect, it } from "vitest";

import { resolveExtraColumns } from "../../src/sql/extra-columns.ts";
import { createReadTracker } from "../../src/sql/pipeline/read-tracking.ts";

const NONE = { reserved: [] as string[], column: () => null };

const tableName = (table: string): { schema: string; name: string } => ({
  schema: "app",
  name: table,
});

/** `resolveExtraColumns` for `teams` over a tracked `appColumns`. */
function resolve(appColumns: Record<string, { name: string; type: string }[]>) {
  const tracker = createReadTracker();
  const layout = tracker.wrap("layout", { appColumns });

  const columns = resolveExtraColumns({
    ...NONE,
    known: { columns: {} },
    table: "teams",
    tableName,
    source: layout,
  });

  return { columns, reads: tracker.reads() };
}

describe("resolveExtraColumns reads", () => {
  it("returns the table's own app columns as fields", () => {
    const { columns } = resolve({
      "app.teams": [{ name: "region", type: "text" }],
    });

    expect(columns.map((column) => column.name)).toEqual(["region"]);
  });

  it("returns nothing when only other tables have app columns", () => {
    expect(
      resolve({ "app.notes": [{ name: "x", type: "text" }] }).columns,
    ).toEqual([]);
  });

  it("never reads the keys of appColumns, so another table's column leaves the render valid", () => {
    const { reads } = resolve({ "app.notes": [{ name: "x", type: "text" }] });

    expect(reads.some((read) => read.kind === "keys")).toBe(false);
  });
});
