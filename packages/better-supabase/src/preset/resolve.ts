import type { BlockCategory, PartDefaults } from "../blocks/define-block.ts";
import type { BlockSqlLink } from "../sql/links.ts";
import type {
  PresetCatalog,
  PresetCatalogBlock,
  PresetCatalogManifest,
} from "./catalog-types.ts";
import type { Preset, PresetFieldKey, PresetInstance } from "./fields.ts";

import { linkNeedsRelations } from "../sql/links.ts";
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

/** A declared link between two blocks that are both in the set. */
export interface PresetLink {
  /** The block that declares the link. */
  readonly from: string;
  readonly to: string;
  readonly key: string;
  readonly kind: BlockSqlLink["kind"];
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

/** A composite in a resolved preset, with the parts it installs (ADR 0177). */
export interface ResolvedComposite {
  readonly name: string;
  /** Its parts' manifest names, composites among them. */
  readonly parts: readonly string[];
  /** What it sets on each part until the app does. */
  readonly defaults: Readonly<Record<string, PartDefaults>>;
}

/** What `resolvePreset` returns. */
export interface ResolvedPreset {
  readonly preset: Preset;
  /** Every block to install, in install order; conflicting blocks are left out. */
  readonly blocks: readonly ResolvedPresetBlock[];
  /** The soft integrations active between blocks in the set. */
  readonly integrations: readonly PresetIntegration[];
  /** The declared links active between blocks in the set. */
  readonly links: readonly PresetLink[];
  readonly conflicts: readonly PresetConflict[];
  /** The manifests that cover `blocks`, for `lib/blocks.ts`. */
  readonly manifests: readonly PresetCatalogManifest[];
  /** The composites among the selected blocks, outermost first. */
  readonly composites: readonly ResolvedComposite[];
  /**
   * The options each part gets: its composites' defaults, in selection order,
   * then the preset's own `instances.<part>.options`, which win key by key.
   */
  readonly partOptions: Readonly<
    Record<string, Readonly<Record<string, unknown>>>
  >;
  /**
   * The settings each part gets from its composites, with the preset's own
   * instance over them: options, entity names and subject settings, merged key
   * by key.
   */
  readonly partInstances: Readonly<Record<string, PresetInstance>>;
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
const TENANT_PROVIDERS: ReadonlySet<string> = new Set([
  "memberships",
  "permissions",
]);

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

interface Expanded {
  readonly names: readonly string[];
  readonly composites: readonly ResolvedComposite[];
  readonly partOf: ReadonlyMap<string, readonly string[]>;
}

/**
 * `names` with each composite replaced by the SQL modules of its parts (and its
 * own glue modules), recursively. A composite's name is its manifest's name.
 */
function expandComposites(
  names: readonly string[],
  catalog: PresetCatalog,
): Expanded {
  const manifests = new Map(catalog.manifests.map((each) => [each.name, each]));
  const composites: ResolvedComposite[] = [];
  const partOf = new Map<string, string[]>();
  const out: string[] = [];

  const visit = (name: string, owner: string | undefined): void => {
    const manifest = manifests.get(name);
    const parts = manifest?.composes;

    if (manifest === undefined || parts === undefined) {
      if (!out.includes(name)) {
        out.push(name);
      }

      if (owner !== undefined) {
        partOf.set(name, [...(partOf.get(name) ?? []), owner]);
      }

      return;
    }

    if (!composites.some((each) => each.name === name)) {
      composites.push({ name, parts, defaults: manifest.defaults ?? {} });
    }

    for (const sql of manifest.sql) {
      visit(sql, owner ?? name);
    }

    for (const part of parts) {
      const partManifest = manifests.get(part);

      for (const sql of partManifest?.composes === undefined
        ? (partManifest?.sql ?? [part])
        : [part]) {
        visit(sql, name);
      }
    }
  };

  for (const name of names) {
    visit(name, undefined);
  }

  return { names: out, composites, partOf };
}

/**
 * What each part gets: its composites' defaults in selection order, then the
 * preset's own `instances.<part>` over them, key by key.
 */
function partInstancesOf(
  preset: Preset,
  composites: readonly ResolvedComposite[],
): Record<string, PresetInstance> {
  const layers = new Map<string, PartDefaults[]>();

  for (const composite of composites) {
    for (const [part, defaults] of Object.entries(composite.defaults)) {
      layers.set(part, [...(layers.get(part) ?? []), defaults]);
    }
  }

  const keyed = <T>(
    pick: (layer: PartDefaults) => Readonly<Record<string, T>> | undefined,
    each: readonly PartDefaults[],
  ): { readonly [key: string]: T } | undefined => {
    const merged: Record<string, T> = {};

    for (const layer of each) {
      Object.assign(merged, pick(layer));
    }

    return Object.keys(merged).length === 0 ? undefined : merged;
  };

  return Object.fromEntries(
    [...layers].map(([part, defaults]) => {
      const own = preset.instances?.[part];

      const all: readonly PartDefaults[] =
        own === undefined ? defaults : [...defaults, own];

      const options = keyed((layer) => layer.options, all);
      const names = keyed((layer) => layer.names, all);
      const subjects = keyed((layer) => layer.subjects, all);

      return [
        part,
        {
          ...own,
          ...(options === undefined ? {} : { options }),
          ...(names === undefined ? {} : { names }),
          ...(subjects === undefined ? {} : { subjects }),
        },
      ];
    }),
  );
}

/** The options each part gets from its composites and the preset. */
function partOptionsOf(
  instances: Readonly<Record<string, PresetInstance>>,
): Record<string, Record<string, unknown>> {
  return Object.fromEntries(
    Object.entries(instances).flatMap(([part, instance]) =>
      Object.keys(instance.options ?? {}).length === 0
        ? []
        : [[part, { ...instance.options }]],
    ),
  );
}

/**
 * The full block set for a preset: the selected blocks and what they require, a
 * reason per block, the soft integrations active between them, and what can't
 * install. It reads the generated catalog, never the SQL renderers, so it runs
 * in the browser.
 */
export function resolvePreset(
  preset: Preset,
  catalog: PresetCatalog = PRESET_CATALOG,
): ResolvedPreset {
  const byName = new Map(catalog.blocks.map((block) => [block.name, block]));
  const conflicts: PresetConflict[] = fieldConflicts(preset);
  const instances = Object.entries(preset.instances ?? {});

  const expanded = expandComposites(preset.blocks, catalog);

  const selected = [
    ...new Set([
      ...expanded.names,
      ...instances.flatMap(([key, instance]) =>
        (instance.block ?? key) === key ? [key] : [],
      ),
    ]),
  ];

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

  for (const [key, instance] of instances) {
    const block = instance.block ?? key;

    if (selected.includes(block)) {
      continue;
    }

    const problem = presetBlockConflict(preset, block, catalog);

    if (problem !== undefined) {
      conflicts.push({ block: key, reason: problem });
      continue;
    }

    for (const each of closureOf(block, preset, byName).slice(1)) {
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

  // A declared conversion or relation between two installed blocks needs the
  // relations block to record it, so it is added like a required block.
  const linkNeeds = new Map<string, string[]>();

  for (const block of catalog.blocks) {
    if (!installed.has(block.name)) {
      continue;
    }

    for (const link of block.links ?? []) {
      if (linkNeedsRelations(link) && installed.has(link.target.block)) {
        linkNeeds.set("relations", [
          ...new Set([...(linkNeeds.get("relations") ?? []), block.name]),
        ]);
      }
    }
  }

  if (linkNeeds.has("relations") && !installed.has("relations")) {
    for (const each of closureOf("relations", preset, byName)) {
      installed.add(each);
    }
  }

  const members = catalog.blocks.filter((block) => installed.has(block.name));

  for (const [dependency, by] of linkNeeds) {
    requiredBy.set(dependency, [...(requiredBy.get(dependency) ?? []), ...by]);
  }

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
    const owners = expanded.partOf.get(block.name) ?? [];

    return {
      name: block.name,
      title: block.title,
      category: block.category,
      selected: isSelected,
      requiredBy: by,
      reason:
        owners.length > 0 && !preset.blocks.includes(block.name)
          ? `part of ${listNames(owners)}`
          : isSelected
            ? "selected"
            : `required by ${listNames(by)}`,
    };
  });

  const integrations = members.flatMap((block) =>
    block.integrates
      .filter((to) => to !== block.name && installed.has(to))
      .map((to) => ({ from: block.name, to })),
  );

  const links = members.flatMap((block) =>
    (block.links ?? [])
      .filter((link) => installed.has(link.target.block))
      .map((link): PresetLink => ({
        from: block.name,
        to: link.target.block,
        key: link.key,
        kind: link.kind,
      })),
  );

  const manifestNames = new Set([
    ...members.map((block) => block.manifest),
    ...expanded.composites.map((each) => each.name),
  ]);

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

  const partInstances = partInstancesOf(preset, expanded.composites);

  return {
    preset,
    blocks,
    integrations,
    links,
    conflicts,
    manifests,
    composites: expanded.composites,
    partOptions: partOptionsOf(partInstances),
    partInstances,
  };
}

/** What removing a composite leaves behind. */
export interface CompositeRemoval {
  /** The preset's `blocks` after the removal. */
  readonly blocks: readonly string[];
  /** Parts that stay installed, and why. */
  readonly kept: readonly { readonly name: string; readonly reason: string }[];
  /** Parts that go with it. */
  readonly removed: readonly string[];
}

/**
 * Removing a composite takes out its glue and its defaults. Its parts stay as
 * ordinary blocks unless `withParts` is set, and even then a part another
 * selected block or composite still needs stays (ADR 0177).
 */
export function removeComposite(
  preset: Preset,
  name: string,
  options: { readonly withParts?: boolean } = {},
  catalog: PresetCatalog = PRESET_CATALOG,
): CompositeRemoval {
  const manifest = catalog.manifests.find((each) => each.name === name);

  if (manifest?.composes === undefined) {
    throw new TypeError(`"${name}" is not a composite block`);
  }

  if (!preset.blocks.includes(name)) {
    throw new TypeError(`"${name}" is not installed`);
  }

  const parts = expandComposites(manifest.composes, catalog).names;
  const rest = preset.blocks.filter((each) => each !== name);

  if (options.withParts !== true) {
    return {
      blocks: [...new Set([...rest, ...parts])],
      kept: parts.map((part) => ({
        name: part,
        reason: "stays as its own block",
      })),
      removed: [],
    };
  }

  const left = resolvePreset({ ...preset, blocks: rest }, catalog);
  const still = new Map(left.blocks.map((each) => [each.name, each.reason]));

  const kept = parts.flatMap((part) => {
    const reason = still.get(part);

    return reason === undefined ? [] : [{ name: part, reason }];
  });

  return {
    blocks: rest,
    kept,
    removed: parts.filter((part) => !still.has(part)),
  };
}
