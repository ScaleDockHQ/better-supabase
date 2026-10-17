import * as v from "valibot";

import type { BlockSummary } from "./block-filter";

// Written by scripts/build-catalog.ts from SQL_MODULES before every build,
// dev, typecheck, lint and test run (Turbo `//#catalog`).
import catalogJson from "./catalog.json";

const names = v.array(v.string());

const catalogSchema = v.object({
  categories: names,
  blocks: v.array(
    v.object({
      name: v.string(),
      title: v.string(),
      category: v.string(),
      description: v.string(),
      requires: names,
      integrates: names,
      modes: names,
      events: names,
      subpath: v.nullable(v.string()),
      react: v.nullable(v.object({ subpath: v.string(), source: v.string() })),
      docs: v.string(),
    }),
  ),
});

export type CatalogBlock = v.InferOutput<
  typeof catalogSchema
>["blocks"][number];

const catalog = v.parse(catalogSchema, catalogJson);

export const blockCategories: readonly string[] = catalog.categories;
export const blocks: readonly CatalogBlock[] = catalog.blocks;

export function getBlock(name: string): CatalogBlock | undefined {
  return blocks.find((block) => block.name === name);
}

export function blockPath(name: string): string {
  return `/blocks/${name}`;
}

/** The `generateStaticParams` of `app/blocks/[name]`: one page per catalog block. */
export function blockStaticParams(): { name: string }[] {
  return blocks.map((block) => ({ name: block.name }));
}

export function blockSummaries(): BlockSummary[] {
  return blocks.map((block) => ({
    name: block.name,
    title: block.title,
    category: block.category,
    description: block.description,
    requires: block.requires,
    hasReact: block.react !== null,
  }));
}

/** The command that installs the block's SQL today. */
export function installCommand(name: string): string {
  return `npx better-supabase sql add ${name}`;
}

const configKey = (name: string): string =>
  /^[a-z_][a-z0-9_]*$/i.test(name) ? name : JSON.stringify(name);

/**
 * The `blocks` entries in `better-supabase.config.ts` for `block` and
 * the modules `sql add` installs with it (`installed`, dependencies first).
 */
export function configSnippet(
  block: CatalogBlock,
  installed: readonly string[],
): string {
  const dependencies = installed.filter((name) => name !== block.name);

  const lines = [
    `import { defineConfig } from "better-supabase/config";`,
    "",
    "export default defineConfig({",
    "  blocks: {",
  ];

  if (dependencies.length > 0) {
    lines.push(`    // Required by ${block.name}; sql add installs them too.`);

    for (const name of dependencies) {
      lines.push(`    ${configKey(name)}: {},`);
    }
  }

  const modes = block.modes.map((mode) => `"${mode}"`).join(", ");
  lines.push(
    `    // Modes: ${modes}. The default is "managed".`,
    `    ${configKey(block.name)}: { mode: "managed" },`,
    "  },",
    "});",
  );

  return lines.join("\n");
}
