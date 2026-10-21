import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { BLOCK_MANIFESTS } from "../../src/blocks/registry.ts";
import { SQL_MODULES } from "../../src/sql/index.ts";
import { formatNameRegistry, moduleNameSet } from "../../src/sql/name-sets.ts";

const FILE = join(
  import.meta.dirname,
  "../../src/blocks/name-registry.generated.ts",
);

describe("the block names registry", () => {
  it("matches the SQL modules (run `pnpm catalog` when it doesn't)", () => {
    expect(readFileSync(FILE, "utf-8")).toBe(
      formatNameRegistry(Object.values(SQL_MODULES)),
    );
  });

  it("covers every module a block manifest installs", () => {
    const installed = new Set(BLOCK_MANIFESTS.flatMap((block) => block.sql));
    const named = new Set(Object.keys(SQL_MODULES));

    for (const name of installed) {
      expect(named).toContain(name);
    }
  });

  it("reads tables, functions and actions from the module", () => {
    const module = SQL_MODULES["work-items"];

    if (module === undefined) {
      throw new Error("no work-items module");
    }

    const names = moduleNameSet(module);
    expect(Object.keys(names.tables)).toEqual([
      "items",
      "assignees",
      "projects",
      "iterations",
    ]);
    expect(names.functions).toContain("list_work_items");
    expect(names.actions).toEqual(["read", "write", "manage"]);
  });
});
