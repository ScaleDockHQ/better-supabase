import { describe, expect, it } from "vitest";

import { legacyOptionTables } from "../../src/sql/legacy-options.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";
import { renderBlocks } from "../../src/sql/render.ts";
import { withAppColumns } from "./app-columns.ts";

// The SQL of each module that takes `extraColumns` (ADR 0015), with one
// extra column, next to the default output in render-golden.test.ts. The
// column must reach the managed table, the reads and the writes.

const EXTRA = { app_note: "text" };

const MODULES = Object.entries(SQL_MODULES)
  .filter(([name]) => legacyOptionTables(name, "extraColumns").length > 0)
  .map(([name]) => name);

function render(module: string): string {
  return renderBlocks([module], withAppColumns(module, { extraColumns: EXTRA }))
    .filter((file) => file.module === module)
    .map((file) => `-- ==== ${file.kind} ${file.path}\n${file.contents}`)
    .join("\n");
}

describe("SQL module output with extra columns", () => {
  it("lists the modules that take extraColumns", async () => {
    await expect(`${MODULES.join("\n")}\n`).toMatchFileSnapshot(
      "__golden__/extra-columns/index.txt",
    );
  });

  it.each(MODULES)("%s reads and writes the column as a field", (module) => {
    expect(render(module)).toContain("app_note");
    expect(render(module)).not.toContain('add column "app_note"');
  });

  it.each(MODULES)("%s renders the golden SQL", async (module) => {
    await expect(render(module)).toMatchFileSnapshot(
      `__golden__/extra-columns/${module}.sql`,
    );
  });
});
