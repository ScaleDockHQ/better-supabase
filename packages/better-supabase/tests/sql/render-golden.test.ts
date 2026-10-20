import { describe, expect, it } from "vitest";

import type { ModuleLayout } from "../../src/sql/module-types.ts";

import { SQL_MODULES } from "../../src/sql/registry.ts";
import { renderModules } from "../../src/sql/render.ts";

// Refactors of the module builders keep every file here byte-identical; an
// intended change to the SQL goes in its own commit with the golden diff.

const NAMES = Object.keys(SQL_MODULES);

interface Variant {
  readonly name: string;
  readonly applies: (module: string) => boolean;
  readonly modules: (module: string) => readonly string[];
  readonly layout: (module: string) => ModuleLayout;
}

const VARIANTS: readonly Variant[] = [
  {
    name: "alone",
    applies: () => true,
    modules: (module) => [module],
    layout: () => ({}),
  },
  {
    name: "with every module",
    applies: (module) => module !== "pgtap",
    modules: () => NAMES.filter((name) => name !== "pgtap"),
    layout: () => ({ modules: { usage: { options: { history: true } } } }),
  },
  {
    name: "schema app_private",
    applies: () => true,
    modules: (module) => [module],
    layout: (module) => ({ modules: { [module]: { schema: "app_private" } } }),
  },
  {
    name: "api schema",
    applies: () => true,
    modules: (module) => [module],
    layout: (module) => ({ modules: { [module]: { api: "api" } } }),
  },
  {
    name: "adopt",
    applies: (module) => SQL_MODULES[module]?.modes?.includes("adopt") ?? false,
    modules: (module) => [module],
    layout: (module) => ({
      modules: {
        [module]: { mode: "adopt", ...ADOPT_OPTIONS[module] },
      },
    }),
  },
];

/** Options an adopted module refuses to render without. */
const ADOPT_OPTIONS: Record<string, { options: Record<string, unknown> }> = {
  "webhooks-out": { options: { defaultFormat: "standard" } },
};

function render(variant: Variant, module: string): string {
  let files;

  try {
    files = renderModules(variant.modules(module), variant.layout(module));
  } catch (cause) {
    return `-- ==== ${variant.name}: throws\n-- ${String(cause instanceof Error ? cause.message : cause)}\n`;
  }

  return files
    .filter((file) => file.module === module)
    .map(
      (file) =>
        `-- ==== ${variant.name}: ${file.kind} ${file.path}\n${file.contents}`,
    )
    .join("\n");
}

describe("SQL module output", () => {
  it.each(NAMES)("%s renders the golden SQL", async (module) => {
    const out = VARIANTS.filter((variant) => variant.applies(module))
      .map((variant) => render(variant, module))
      .join("\n");

    await expect(out).toMatchFileSnapshot(`__golden__/${module}.sql`);
  });
});
