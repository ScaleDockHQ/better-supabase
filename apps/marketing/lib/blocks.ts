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

export function blockPath(name: string): `/blocks/${string}` {
  return `/blocks/${name}`;
}

/** The `generateStaticParams` of `app/(blocks)/blocks/[name]`: one page per catalog block. */
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

export interface BlockGroup {
  readonly category: string;
  readonly blocks: readonly BlockSummary[];
}

/** The block summaries per category, in catalog order. */
export function blockGroups(): BlockGroup[] {
  const summaries = blockSummaries();

  return blockCategories.map((category) => ({
    category,
    blocks: summaries.filter((block) => block.category === category),
  }));
}

/** Other blocks in the same category, for the "More in" strip. */
export function relatedBlocks(name: string, limit = 6): BlockSummary[] {
  const block = getBlock(name);

  if (!block) {
    return [];
  }

  return blockSummaries()
    .filter((other) => other.category === block.category && other.name !== name)
    .slice(0, limit);
}

/** A box in a dependency graph: a block, or the `*` wildcard of "every module". */
export interface DependencyNodeSpec {
  readonly id: string;
  readonly label: string;
  /** `null` for the wildcard, which is no block of its own. */
  readonly category: string | null;
  readonly href: string | null;
  /** The block a page is about, or the blocks a preset selects. */
  readonly focus: boolean;
}

export interface DependencyNode extends DependencyNodeSpec {
  readonly x: number;
  readonly y: number;
}

export interface DependencyEdge {
  readonly from: string;
  readonly to: string;
  /** `requires` is a hard dependency; `integrates` a soft one. */
  readonly kind: "requires" | "integrates";
}

export interface DependencyLayout {
  readonly width: number;
  readonly height: number;
  readonly nodeWidth: number;
  readonly nodeHeight: number;
  readonly nodes: readonly DependencyNode[];
  readonly edges: readonly DependencyEdge[];
}

const GRAPH_NODE_HEIGHT = 36;

/** The advance of one `text-xs` monospace character, which sizes the boxes. */
const GRAPH_CHAR_WIDTH = 7.2;

/** The icon tile, its insets and the right padding around a label. */
const GRAPH_NODE_CHROME = 52;
const GRAPH_MIN_NODE_WIDTH = 120;
const GRAPH_COLUMN_GAP = 72;
const GRAPH_ROW_GAP = 12;
const GRAPH_PADDING = 12;

/** Room on the right for an edge that loops between two boxes of one column. */
const GRAPH_LOOP_ROOM = 32;

/**
 * Places `columns` left to right, each centered on the tallest one. Empty
 * columns are dropped, and every box gets the width of the longest label.
 */
export function columnLayout(
  columns: readonly (readonly DependencyNodeSpec[])[],
  edges: readonly DependencyEdge[],
): DependencyLayout {
  const filled = columns.filter((column) => column.length > 0);
  const specs = filled.flat();

  const nodeWidth = Math.max(
    GRAPH_MIN_NODE_WIDTH,
    ...specs.map((spec) =>
      Math.ceil(GRAPH_NODE_CHROME + spec.label.length * GRAPH_CHAR_WIDTH),
    ),
  );

  const columnHeight = (count: number): number =>
    Math.max(0, count * (GRAPH_NODE_HEIGHT + GRAPH_ROW_GAP) - GRAPH_ROW_GAP);

  const tallest = Math.max(
    0,
    ...filled.map((column) => columnHeight(column.length)),
  );

  const nodes = filled.flatMap((column, x) => {
    const top = GRAPH_PADDING + (tallest - columnHeight(column.length)) / 2;

    return column.map((spec, y) => ({
      ...spec,
      x: GRAPH_PADDING + x * (nodeWidth + GRAPH_COLUMN_GAP),
      y: top + y * (GRAPH_NODE_HEIGHT + GRAPH_ROW_GAP),
    }));
  });

  const columnOf = new Map(
    filled.flatMap((column, x) => column.map((spec) => [spec.id, x] as const)),
  );

  const loops = edges.some(
    (edge) =>
      columnOf.get(edge.from) !== undefined &&
      columnOf.get(edge.from) === columnOf.get(edge.to),
  );

  return {
    width:
      GRAPH_PADDING * 2 +
      Math.max(
        0,
        filled.length * (nodeWidth + GRAPH_COLUMN_GAP) - GRAPH_COLUMN_GAP,
      ) +
      (loops ? GRAPH_LOOP_ROOM : 0),
    height: GRAPH_PADDING * 2 + tallest,
    nodeWidth,
    nodeHeight: GRAPH_NODE_HEIGHT,
    nodes,
    edges: edges.filter(
      (edge) => columnOf.has(edge.from) && columnOf.has(edge.to),
    ),
  };
}

const WILDCARD = "*";

function graphNode(name: string, focus = false): DependencyNodeSpec {
  if (name === WILDCARD) {
    return {
      id: WILDCARD,
      label: "every module",
      category: null,
      href: null,
      focus,
    };
  }

  return {
    id: name,
    label: name,
    category: getBlock(name)?.category ?? null,
    href: blockPath(name),
    focus,
  };
}

/**
 * The block in the middle, the modules it requires on the left and the
 * modules it works with on the right. A module in both lists counts as required.
 */
export function blockGraphLayout(block: CatalogBlock): DependencyLayout {
  const requires = [...new Set(block.requires)].filter(
    (name) => name !== block.name,
  );

  const integrates = [...new Set(block.integrates)].filter(
    (name) => name !== block.name && !requires.includes(name),
  );

  return columnLayout(
    [
      requires.map((name) => graphNode(name)),
      [graphNode(block.name, true)],
      integrates.map((name) => graphNode(name)),
    ],
    [
      ...requires.map((to) => ({
        from: block.name,
        to,
        kind: "requires" as const,
      })),
      ...integrates.map((to) => ({
        from: block.name,
        to,
        kind: "integrates" as const,
      })),
    ],
  );
}

const listFormat = new Intl.ListFormat("en", {
  style: "long",
  type: "conjunction",
});

const graphLabel = (name: string): string =>
  name === WILDCARD ? "every module" : name;

/** The text alternative of `blockGraphLayout`, one sentence. */
export function blockGraphSummary(block: CatalogBlock): string {
  const layout = blockGraphLayout(block);

  const of = (kind: DependencyEdge["kind"]): string[] =>
    layout.edges
      .filter((edge) => edge.kind === kind)
      .map((edge) => graphLabel(edge.to));

  const requires = of("requires");
  const integrates = of("integrates");

  const parts = [
    requires.length > 0 ? `requires ${listFormat.format(requires)}` : null,
    integrates.length > 0
      ? `works with ${listFormat.format(integrates)}`
      : null,
  ].filter((part) => part !== null);

  return parts.length === 0
    ? `${block.name} has no dependencies.`
    : `${block.name} ${parts.join(", and ")}.`;
}

/** The command that installs the block's SQL today. */
export function installCommand(name: string): string {
  return `npx better-supabase add ${name}`;
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
    lines.push(`    // Required by ${block.name}; add installs them too.`);

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
