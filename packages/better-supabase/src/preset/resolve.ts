import type { BlockCategory } from "../blocks/define-block.ts";
import type {
  PresetCatalog,
  PresetCatalogBlock,
  PresetCatalogManifest,
} from "./catalog-types.ts";
import type { Preset, PresetFieldKey } from "./fields.ts";

import { PRESET_CATALOG } from "./catalog.generated.ts";

/** One block in a resolved preset, with why it is there. */
export interface ResolvedPresetBlock {
  readonly name: string;
  readonly title: string;
  readonly category: BlockCategory;
  /** Whether the preset names it, rather than another block requiring it. */
  readonly selected: boolean;
  /** The blocks in the set that require it. */
  readonly requiredBy: readonly string[];
  /** "selected", or "required by comments and tags". */
  readonly reason: string;
}

/** A soft integration between two blocks that are both in the set. */
export interface PresetIntegration {
  /** The block that works with `to`. */
  readonly from: string;
  readonly to: string;
}

/** Something in the preset that can't install, and why. */
export interface PresetConflict {
  readonly block?: string;
  readonly field?: PresetFieldKey;
  readonly reason: string;
}

/** What `resolvePreset` returns. */
export interface ResolvedPreset {
  readonly preset: Preset;
  /** Every block to install, in install order; conflicting blocks are left out. */
  readonly blocks: readonly ResolvedPresetBlock[];
  /** The soft integrations active between blocks in the set. */
  readonly integrations: readonly PresetIntegration[];
  readonly conflicts: readonly PresetConflict[];
  /** The manifests that cover `blocks`, for `lib/blocks.ts`. */
  readonly manifests: readonly PresetCatalogManifest[];
}

/** "a", "a and b", "a, b and c". */
export function listNames(names: readonly string[]): string {
  if (names.length <= 1) {
    return names.join("");
  }
  return `${names.slice(0, -1).join(", ")} and ${names.at(-1) ?? ""}`;
}

// Outside tenant scope a block checks the caller itself, so it needs neither
// the tenant module nor the access contract (as `requiresOf` in
// src/sql/registry.ts).
const TENANT_PROVIDERS: ReadonlySet<string> = new Set(["tenant", "access"]);

function requiresOf(
  block: PresetCatalogBlock,
  preset: Pick<Preset, "access" | "scope">,
): readonly string[] {
  const requires = block.requiresByAccess?.[preset.access] ?? block.requires;
  return preset.scope === "tenant" || TENANT_PROVIDERS.has(block.name)
    ? requires
    : requires.filter((name) => !TENANT_PROVIDERS.has(name));
}

/** `name` and everything it requires, dependencies first. */
function closureOf(
  name: string,
  preset: Pick<Preset, "access" | "scope">,
  byName: ReadonlyMap<string, PresetCatalogBlock>,
): string[] {
  const out: string[] = [];
  const visit = (each: string): void => {
    const block = byName.get(each);
    if (block === undefined || out.includes(each)) {
      return;
    }
    out.push(each);
    for (const dependency of requiresOf(block, preset)) {
      visit(dependency);
    }
  };
  visit(name);
  return out;
}

/**
 * Why `name` can't install with the preset's conventions, or undefined.
 * `/create` disables a block with this reason before it is selected.
 */
export function presetBlockConflict(
  preset: Pick<Preset, "access" | "scope">,
  name: string,
  catalog: PresetCatalog = PRESET_CATALOG,
): string | undefined {
  const byName = new Map(catalog.blocks.map((block) => [block.name, block]));
  if (!byName.has(name)) {
    return `"${name}" is not a block`;
  }
  if (preset.scope === "tenant") {
    return undefined;
  }
  if (TENANT_PROVIDERS.has(name)) {
    return `scope "${preset.scope}" has no tenants`;
  }
  const tenantOnly = closureOf(name, preset, byName).filter(
    (each) =>
      !(byName.get(each)?.scopes ?? [preset.scope]).includes(preset.scope),
  );
  if (tenantOnly.length === 0) {
    return undefined;
  }
  return tenantOnly[0] === name
    ? `it needs tenants, and scope "${preset.scope}" has none`
    : `it needs ${listNames(tenantOnly)}, which need tenants, and scope "${preset.scope}" has none`;
}

function fieldConflicts(preset: Preset): PresetConflict[] {
  const conflicts: PresetConflict[] = [];
  if (preset.framework === "expo" && preset.platforms === "web") {
    conflicts.push({
      field: "platforms",
      reason: "Expo builds a native app: choose native or both",
    });
  }
  if (preset.platforms === "native" && preset.framework !== "expo") {
    conflicts.push({
      field: "framework",
      reason: `a native-only app runs on Expo, not ${preset.framework}`,
    });
  }
  return conflicts;
}

/**
 * The full block set for a preset: the selected blocks and what they
 * require, a reason per block, the soft integrations active between them,
 * and what can't install. It reads the generated catalog, never the SQL
 * renderers, so it runs in the browser.
 */
export function resolvePreset(
  preset: Preset,
  catalog: PresetCatalog = PRESET_CATALOG,
): ResolvedPreset {
  const byName = new Map(catalog.blocks.map((block) => [block.name, block]));
  const conflicts: PresetConflict[] = fieldConflicts(preset);
  const selected = [...new Set(preset.blocks)];
  const installed = new Set<string>();
  const requiredBy = new Map<string, string[]>();
  for (const name of selected) {
    const problem = presetBlockConflict(preset, name, catalog);
    if (problem !== undefined) {
      conflicts.push({ block: name, reason: problem });
      continue;
    }
    for (const each of closureOf(name, preset, byName)) {
      installed.add(each);
    }
  }
  for (const block of catalog.blocks) {
    if (!installed.has(block.name)) {
      continue;
    }
    if (!block.tenantNameClashes?.includes(preset.tenantName)) {
      continue;
    }
    conflicts.push({
      block: block.name,
      field: "tenantName",
      reason: `tenant name "${preset.tenantName}" renames the tenant tables and columns to names the ${block.name} block already uses`,
    });
  }
  const members = catalog.blocks.filter((block) => installed.has(block.name));
  for (const block of members) {
    for (const dependency of requiresOf(block, preset)) {
      requiredBy.set(dependency, [
        ...(requiredBy.get(dependency) ?? []),
        block.name,
      ]);
    }
  }
  const blocks = members.map((block): ResolvedPresetBlock => {
    const by = requiredBy.get(block.name) ?? [];
    const isSelected = selected.includes(block.name);
    return {
      name: block.name,
      title: block.title,
      category: block.category,
      selected: isSelected,
      requiredBy: by,
      reason: isSelected ? "selected" : `required by ${listNames(by)}`,
    };
  });
  const integrations = members.flatMap((block) =>
    block.integrates
      .filter((to) => to !== block.name && installed.has(to))
      .map((to) => ({ from: block.name, to })),
  );
  const manifestNames = new Set(members.map((block) => block.manifest));
  const manifests = catalog.manifests.filter((manifest) =>
    manifestNames.has(manifest.name),
  );
  for (const manifest of manifests) {
    for (const [port, need] of Object.entries(manifest.consumes)) {
      if (need !== "required") {
        continue;
      }
      if (manifests.some((each) => each.provides.some((p) => p === port))) {
        continue;
      }
      conflicts.push({
        block: manifest.name,
        reason: `it needs a ${port} port, and no selected block provides one`,
      });
    }
  }
  return { preset, blocks, integrations, conflicts, manifests };
}
