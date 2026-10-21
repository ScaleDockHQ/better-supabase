import { describe, expect, it } from "vitest";

import type { BlockScope } from "../../src/config/blocks.ts";
import type { ModuleLayout } from "../../src/sql/module-types.ts";

import { BLOCK_SCOPES } from "../../src/config/blocks.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";
import { renderModules } from "../../src/sql/render.ts";

// The SQL each module writes under a convention (`sql.scope`,
// `blocks.tenant.entities`), next to the default output in render-golden.test.ts. A
// module gets a file only where the convention changes its SQL.

const NAMES = Object.keys(SQL_MODULES);

interface Convention {
  readonly name: string;
  readonly applies: (module: string) => boolean;
  readonly layout: ModuleLayout;
}

const runsIn = (module: string, scope: BlockScope): boolean =>
  (SQL_MODULES[module]?.scopes ?? BLOCK_SCOPES).includes(scope);

const CONVENTIONS: readonly Convention[] = [
  {
    name: "scope-user",
    applies: (module) => runsIn(module, "user"),
    layout: { scope: "user" },
  },
  {
    name: "scope-none",
    applies: (module) => runsIn(module, "none"),
    layout: { scope: "none" },
  },
  {
    name: "naming-workspace",
    applies: () => true,
    layout: {
      modules: { tenant: { entities: { organization: "workspace" } } },
    },
  },
];

function render(module: string, layout: ModuleLayout): string {
  let files;

  try {
    files = renderModules([module], layout);
  } catch (cause) {
    return `-- ==== throws\n-- ${cause instanceof Error ? cause.message : String(cause)}\n`;
  }

  return files
    .filter((file) => file.module === module)
    .map((file) => `-- ==== ${file.kind} ${file.path}\n${file.contents}`)
    .join("\n");
}

describe.each(CONVENTIONS)("SQL module output with $name", (convention) => {
  const changed = NAMES.filter(
    (module) =>
      module !== "pgtap" &&
      convention.applies(module) &&
      render(module, convention.layout) !== render(module, {}),
  );

  it("lists the modules whose SQL the convention changes", async () => {
    await expect(`${changed.join("\n")}\n`).toMatchFileSnapshot(
      `__golden__/${convention.name}/index.txt`,
    );
  });

  it.each(changed)("%s renders the golden SQL", async (module) => {
    await expect(render(module, convention.layout)).toMatchFileSnapshot(
      `__golden__/${convention.name}/${module}.sql`,
    );
  });
});
