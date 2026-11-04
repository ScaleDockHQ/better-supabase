import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

import { snapshotColumnTypes } from "../../src/cli/sql-layout.ts";
import { resolveConfig } from "../../src/config/index.ts";

const SNAPSHOT = resolve(
  import.meta.dirname,
  "../../../../supabase/snapshot.json",
);

describe("snapshotColumnTypes", () => {
  it("returns nothing without tables or a snapshot", async () => {
    const root = import.meta.dirname;

    expect(
      await snapshotColumnTypes(resolveConfig({}, root), ["public.x"]),
    ).toEqual(new Map());
    expect(
      await snapshotColumnTypes(
        resolveConfig({ database: { source: { snapshot: SNAPSHOT } } }, root),
        [],
      ),
    ).toEqual(new Map());
  });

  it("maps the columns of the requested tables and skips unknown ones", async () => {
    const config = resolveConfig(
      { database: { source: { snapshot: SNAPSHOT } } },
      import.meta.dirname,
    );

    const types = await snapshotColumnTypes(config, [
      "better_supabase.blocks",
      "public.no_such_table",
    ]);

    expect([...types.keys()]).toEqual(["better_supabase.blocks"]);
    expect(types.get("better_supabase.blocks")?.get("name")).toBe("text");
    expect(types.get("better_supabase.blocks")?.get("version")).toBe("int4");
  });
});
