// The "How modules work together" matrix on the blocks overview page and the
// default automations table on the automations page, built from the preset
// catalog. `pnpm catalog` writes both between their markers, and
// `pnpm catalog:check` and the drift test fail when either is stale.
import { join } from "node:path";

import type { PresetCatalog } from "../packages/better-supabase/src/preset/catalog-types.ts";

const BLOCKS_DOCS: string = join(
  import.meta.dirname,
  "../apps/docs/content/docs/(blocks)/blocks",
);

export const MATRIX_PAGE: string = join(BLOCKS_DOCS, "index.mdx");

export const AUTOMATIONS_PAGE: string = join(
  BLOCKS_DOCS,
  "(automation)/automations.mdx",
);

const MATRIX_START = "{/* module-matrix:start, written by `pnpm catalog` */}";

const MATRIX_END = "{/* module-matrix:end */}";

const AUTOMATIONS_START =
  "{/* default-automations:start, written by `pnpm catalog` */}";

const AUTOMATIONS_END = "{/* default-automations:end */}";

const code = (names: readonly string[]): string =>
  names.length === 0 ? "none" : names.map((name) => `\`${name}\``).join(", ");

/** The requires and works-with table, one row per block. */
export function moduleMatrix(catalog: PresetCatalog): string {
  const rows = catalog.blocks.map(
    (block) =>
      `| \`${block.name}\` | ${code(block.requires)} | ${code(block.integrates)} |`,
  );

  return [
    MATRIX_START,
    "",
    "| Module | Requires | Works with |",
    "| --- | --- | --- |",
    ...rows,
    "",
    MATRIX_END,
  ].join("\n");
}

/** The default automations table, one row per shipped automation. */
export function defaultAutomations(catalog: PresetCatalog): string {
  const rows = catalog.manifests.flatMap((manifest) =>
    (manifest.automations ?? []).map((automation) => {
      const name = automation.enabled
        ? automation.name
        : `${automation.name} (turned off)`;

      const ships =
        automation.requires.length === 0
          ? "always"
          : `${code(automation.requires)} ${automation.requires.length === 1 ? "is" : "are"} installed`;

      return `| ${name} | \`${manifest.name}\` | \`${automation.trigger}\` | ${code(automation.actions)} | ${ships} |`;
    }),
  );

  return [
    AUTOMATIONS_START,
    "",
    "| Default | Block | Trigger | Action | Ships when |",
    "| --- | --- | --- | --- | --- |",
    ...rows,
    "",
    AUTOMATIONS_END,
  ].join("\n");
}

function replaceSection(
  page: string,
  start: string,
  end: string,
  section: string,
): string | undefined {
  const from = page.indexOf(start);
  const to = page.indexOf(end);

  return from === -1 || to < from
    ? undefined
    : page.slice(0, from) + section + page.slice(to + end.length);
}

/**
 * The matrix page with its generated section replaced, or `undefined` without
 * markers.
 */
export function withModuleMatrix(
  page: string,
  catalog: PresetCatalog,
): string | undefined {
  return replaceSection(page, MATRIX_START, MATRIX_END, moduleMatrix(catalog));
}

/**
 * The automations page with its generated section replaced, or `undefined`
 * without markers.
 */
export function withDefaultAutomations(
  page: string,
  catalog: PresetCatalog,
): string | undefined {
  return replaceSection(
    page,
    AUTOMATIONS_START,
    AUTOMATIONS_END,
    defaultAutomations(catalog),
  );
}
