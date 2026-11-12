// The declared entity surface in the block consistency audit, built from the
// `entities` of every block manifest (ADR 0689). `pnpm catalog` writes it
// between its markers, and `pnpm catalog:check` and the drift test fail when it
// is stale.
import { join } from "node:path";

import type { EntitySurface } from "../packages/better-supabase/src/blocks/entity-surface.ts";

import {
  ENTITY_METHODS,
  ENTITY_MUTABILITIES,
} from "../packages/better-supabase/src/blocks/entity-surface.ts";
import { BLOCK_MANIFESTS } from "../packages/better-supabase/src/blocks/registry.ts";

export const AUDIT_REPORT: string = join(
  import.meta.dirname,
  "../docs/agents/block-consistency-audit.md",
);

const START =
  "<!-- entity-matrix:start, written by `pnpm catalog`; do not edit by hand -->";

const END = "<!-- entity-matrix:end -->";

const NONE = "-";

const list = (values: readonly string[] | undefined): string =>
  values === undefined || values.length === 0 ? NONE : values.join(", ");

const flag = (value: boolean | undefined): string => (value ? "y" : NONE);

function searchOf(surface: EntitySurface): string {
  const search = surface.search;

  if (search === undefined || search === false) {
    return NONE;
  }

  return search === true ? "y" : list(search);
}

function emitsOf(surface: EntitySurface, emitted: boolean): string {
  return list(
    ENTITY_METHODS.filter((method) => surface.emits?.[method] === emitted),
  );
}

/** Pads a table the way the formatter does, so the generated text is stable. */
function table(
  header: readonly string[],
  rows: readonly (readonly string[])[],
): readonly string[] {
  const widths = header.map((title, column) =>
    Math.max(title.length, 3, ...rows.map((row) => (row[column] ?? "").length)),
  );

  const line = (cells: readonly string[]): string =>
    `| ${cells.map((cell, column) => cell.padEnd(widths[column] ?? 0)).join(" | ")} |`;

  return [
    line(header),
    `| ${widths.map((width) => "-".repeat(width)).join(" | ")} |`,
    ...rows.map(line),
  ];
}

/**
 * The generated section: mutability totals by category, then one row per
 * declared entity.
 */
export function entityMatrix(): string {
  const blocks = BLOCK_MANIFESTS.toSorted((a, b) =>
    a.category === b.category
      ? a.name.localeCompare(b.name)
      : a.category.localeCompare(b.category),
  );

  const entries = blocks.flatMap((block) =>
    Object.entries(block.entities ?? {}).map(
      ([key, surface]) => [block, key, surface] as const,
    ),
  );

  const categories = [...new Set(blocks.map((block) => block.category))];

  const totals = categories.map((category) => {
    const inCategory = entries.filter(([block]) => block.category === category);

    return [
      category,
      String(new Set(inCategory.map(([block]) => block.name)).size),
      String(inCategory.length),
      ...ENTITY_MUTABILITIES.map((mutability) =>
        String(
          inCategory.filter(
            ([, , surface]) => surface.mutability === mutability,
          ).length,
        ),
      ),
    ];
  });

  const rows = entries.map(([block, key, surface]) => [
    block.name,
    block.category,
    key,
    surface.mutability ?? NONE,
    emitsOf(surface, true),
    emitsOf(surface, false),
    list(surface.sorts),
    list(surface.facets),
    searchOf(surface),
    flag(surface.realtime),
    flag(surface.offline),
    flag(surface.versioned),
  ]);

  return [
    START,
    "",
    "Generated from the `entities` of every block manifest. `Emits` lists the methods that record an event and `No event` the mutating methods that record none (EX-1216). A `-` means the manifest does not declare the field yet.",
    "",
    ...table(
      ["Category", "Blocks", "Entities", ...ENTITY_MUTABILITIES],
      totals,
    ),
    "",
    ...table(
      [
        "Block",
        "Category",
        "Entity",
        "Mutability",
        "Emits",
        "No event",
        "Sorts",
        "Facets",
        "Search",
        "Realtime",
        "Offline",
        "Versioned",
      ],
      rows,
    ),
    "",
    END,
  ].join("\n");
}

/**
 * The audit report with its generated entity matrix replaced, or `undefined`
 * without markers.
 */
export function withEntityMatrix(page: string): string | undefined {
  const from = page.indexOf(START);
  const to = page.indexOf(END);

  return from === -1 || to < from
    ? undefined
    : page.slice(0, from) + entityMatrix() + page.slice(to + END.length);
}
