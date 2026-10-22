import { describe, expect, it } from "vitest";

import { SQL_MODULES } from "../../src/sql/registry.ts";
import { renderBlocks } from "../../src/sql/render.ts";

// The SQL of each module that takes `extraColumns` (ADR 0015), with one
// extra column, next to the default output in render-golden.test.ts. The
// column must reach the managed table, the reads and the writes.

const EXTRA = { app_note: "text" };

const MODULES = Object.entries(SQL_MODULES)
  .filter(([, module]) => module.names?.options?.includes("extraColumns"))
  .map(([name]) => name);

function render(module: string): string {
  return renderBlocks([module], {
    modules: { [module]: { options: { extraColumns: EXTRA } } },
  })
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

  it.each(MODULES)("%s adds the column to its managed table", (module) => {
    expect(render(module)).toContain(
      'add column if not exists "app_note" text;',
    );
  });

  it.each(MODULES)("%s renders the golden SQL", async (module) => {
    await expect(render(module)).toMatchFileSnapshot(
      `__golden__/extra-columns/${module}.sql`,
    );
  });

  it.each(MODULES)("%s refuses a column that shadows its own", (module) => {
    const tables = SQL_MODULES[module]?.names?.tables ?? {};

    const [name = "id"] = Object.values(
      Object.values(tables)[0]?.columns ?? {},
    );

    expect(() =>
      renderBlocks([module], {
        modules: {
          [module]: { options: { extraColumns: { [name]: "text" } } },
        },
      }),
    ).toThrow(/shadows/);
  });
});
