import { describe, expect, it } from "vitest";

import { legacyOptionTables } from "../../src/sql/legacy-options.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";
import { renderBlocks } from "../../src/sql/render.ts";
import { withAppColumns } from "./app-columns.ts";

// Each module that takes `extraColumns` (ADR 0015) carries one extra column
// into its reads and writes.

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
  it("lists modules that take extraColumns", () => {
    expect(MODULES.length).toBeGreaterThan(0);
  });

  it.each(MODULES)("%s reads and writes the column as a field", (module) => {
    expect(render(module)).toContain("app_note");
    expect(render(module)).not.toContain('add column "app_note"');
  });
});
