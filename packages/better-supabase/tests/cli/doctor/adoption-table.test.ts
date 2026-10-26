import { describe, expect, it } from "vitest";

import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import {
  adoptionRows,
  adoptionText,
} from "../../../src/cli/doctor/adoption-table.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { moduleSnapshotFixture } from "../fixtures/library.ts";

const snapshot = await parseSnapshot(moduleSnapshotFixture);

const rows = (config = resolveConfig({}, "/project")) =>
  adoptionRows({
    config,
    snapshot,
    configToml: undefined,
    envFiles: [],
    gitignore: "",
    sources: [],
  });

describe("doctor --adoption", () => {
  it("lists one sorted row per table in the read schemas", () => {
    const list = rows();

    expect(list.length).toBeGreaterThan(0);
    expect(list.map((row) => row.table)).toEqual(
      list.map((row) => row.table).toSorted((a, b) => a.localeCompare(b)),
    );
    expect(
      list.every((row) => ["block", "adopted", "yours"].includes(row.status)),
    ).toBe(true);
  });

  it("prints an aligned table", () => {
    const text = adoptionText([
      { table: "public.notes", status: "yours", features: [] },
      {
        table: "public.posts",
        status: "adopted",
        block: "comments",
        features: ["scope"],
      },
    ]);

    expect(text).toContain("Table");
    expect(text).toContain("adopted by comments");
    expect(text).toContain("scope");
    expect(text).toContain("-");
  });

  it("says so when there are no tables", () => {
    expect(adoptionText([])).toBe("No tables in the read schemas.");
  });
});
