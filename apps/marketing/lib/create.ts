import {
  encodePreset,
  listNames,
  namedPreset,
  type Preset,
  PRESET_CATALOG,
  PRESET_NAMES,
  presetBlockConflict,
  presetOf,
  type PresetName,
  PRESETS,
  type ResolvedPreset,
} from "better-supabase/preset";

import { blockCategories, blocks } from "./blocks";

/** One file `/create/migrations` returns. */
export interface PresetMigrationFile {
  readonly path: string;
  readonly module: string;
  readonly contents: string;
}

/** The preset `/create` starts from without `?preset=`. */
export const DEFAULT_PRESET: PresetName = "saas";

/** The preset in `?preset=`, a name or a code; the default when it is missing or unreadable. */
export function initialPreset(param: string | null): Preset {
  if (param === null || param === "") {
    return namedPreset(DEFAULT_PRESET);
  }
  try {
    return presetOf(param);
  } catch {
    return namedPreset(DEFAULT_PRESET);
  }
}

/** The URL `/create` keeps in sync with the selection. */
export function createHref(preset: Preset): string {
  return `/create?preset=${encodePreset(preset)}`;
}

/** The named preset whose blocks the selection matches, if any. */
export function matchingPreset(preset: Preset): PresetName | undefined {
  const selected = [...new Set(preset.blocks)].toSorted();
  return PRESET_NAMES.find((name) => {
    const blocksOf = [...new Set(PRESETS[name].blocks)].toSorted();
    return (
      blocksOf.length === selected.length &&
      blocksOf.every((block, index) => block === selected[index])
    );
  });
}

/** The selection with `name` switched on or off. */
export function toggleBlock(preset: Preset, name: string): Preset {
  const blocks = preset.blocks.includes(name)
    ? preset.blocks.filter((each) => each !== name)
    : [...preset.blocks, name];
  return { ...preset, blocks };
}

/** A named preset's blocks with the conventions the user already picked. */
export function applyNamedPreset(preset: Preset, name: PresetName): Preset {
  return { ...preset, blocks: PRESETS[name].blocks };
}

export type BlockRowState =
  | { readonly kind: "selected" }
  | { readonly kind: "required"; readonly by: readonly string[] }
  | { readonly kind: "conflict"; readonly reason: string }
  | { readonly kind: "available"; readonly worksWith: readonly string[] };

export interface BlockRow {
  readonly name: string;
  readonly title: string;
  readonly description: string;
  readonly state: BlockRowState;
}

export interface BlockGroup {
  readonly category: string;
  readonly rows: readonly BlockRow[];
}

/** What the row says under the block's name. */
export function rowNote(state: BlockRowState): string | undefined {
  switch (state.kind) {
    case "selected": {
      return undefined;
    }
    case "required": {
      return `Required by ${listNames(state.by)}`;
    }
    case "conflict": {
      return `Unavailable: ${state.reason}`;
    }
    case "available": {
      return state.worksWith.length === 0
        ? undefined
        : `Works with ${listNames(state.worksWith)}`;
    }
    default: {
      const unknown: never = state;
      return unknown;
    }
  }
}

/** Every block, grouped by the `/blocks` categories, with its state in this selection. */
export function blockGroups(
  preset: Preset,
  resolved: ResolvedPreset,
): readonly BlockGroup[] {
  const installed = new Map(
    resolved.blocks.map((block) => [block.name, block]),
  );
  const integrates = new Map(
    PRESET_CATALOG.blocks.map((block) => [block.name, block.integrates]),
  );
  const stateOf = (name: string): BlockRowState => {
    const block = installed.get(name);
    if (block?.selected === true) {
      return { kind: "selected" };
    }
    if (block !== undefined) {
      return { kind: "required", by: block.requiredBy };
    }
    const reason = presetBlockConflict(preset, name);
    if (reason !== undefined) {
      return { kind: "conflict", reason };
    }
    const worksWith = resolved.blocks
      .filter(
        (each) =>
          (integrates.get(each.name) ?? []).includes(name) ||
          (integrates.get(name) ?? []).includes(each.name),
      )
      .map((each) => each.name);
    return { kind: "available", worksWith };
  };
  return blockCategories
    .map((category) => ({
      category,
      rows: blocks
        .filter((block) => block.category === category)
        .map((block) => ({
          name: block.name,
          title: block.title,
          description: block.description,
          state: stateOf(block.name),
        })),
    }))
    .filter((group) => group.rows.length > 0);
}

export interface GraphNode {
  readonly name: string;
  readonly x: number;
  readonly y: number;
  readonly selected: boolean;
}

export interface GraphEdge {
  readonly from: string;
  readonly to: string;
  /** `requires` is a hard dependency; `integrates` a soft one. */
  readonly kind: "requires" | "integrates";
}

export interface GraphLayout {
  readonly width: number;
  readonly height: number;
  readonly nodes: readonly GraphNode[];
  readonly edges: readonly GraphEdge[];
}

export const NODE_WIDTH = 148;
export const NODE_HEIGHT = 28;
const COLUMN_GAP = 56;
const ROW_GAP = 12;
const PADDING = 8;

/**
 * Columns by dependency depth: a block sits one column right of the deepest
 * block it requires, so every `requires` edge points left.
 */
export function graphLayout(resolved: ResolvedPreset): GraphLayout {
  const names = new Set(resolved.blocks.map((block) => block.name));
  const requires = new Map<string, string[]>();
  for (const block of resolved.blocks) {
    for (const dependent of block.requiredBy) {
      requires.set(dependent, [...(requires.get(dependent) ?? []), block.name]);
    }
  }
  const depth = new Map<string, number>();
  const depthOf = (name: string): number => {
    const known = depth.get(name);
    if (known !== undefined) {
      return known;
    }
    const own =
      Math.max(-1, ...(requires.get(name) ?? []).map((each) => depthOf(each))) +
      1;
    depth.set(name, own);
    return own;
  };
  const columns: string[][] = [];
  for (const block of resolved.blocks) {
    const column = depthOf(block.name);
    columns[column] = [...(columns[column] ?? []), block.name];
  }
  const nodes = columns.flatMap((column, x) =>
    column.map((name, y) => ({
      name,
      x: PADDING + x * (NODE_WIDTH + COLUMN_GAP),
      y: PADDING + y * (NODE_HEIGHT + ROW_GAP),
      selected: resolved.blocks.some(
        (block) => block.name === name && block.selected,
      ),
    })),
  );
  const edges: GraphEdge[] = [
    ...[...requires].flatMap(([from, tos]) =>
      tos.map((to) => ({ from, to, kind: "requires" as const })),
    ),
    ...resolved.integrations
      .filter((each) => names.has(each.from) && names.has(each.to))
      .map((each) => ({ ...each, kind: "integrates" as const })),
  ];
  const rows = Math.max(0, ...columns.map((column) => column.length));
  return {
    width:
      PADDING * 2 +
      Math.max(0, columns.length * (NODE_WIDTH + COLUMN_GAP) - COLUMN_GAP),
    height: PADDING * 2 + Math.max(0, rows * (NODE_HEIGHT + ROW_GAP) - ROW_GAP),
    nodes,
    edges,
  };
}
