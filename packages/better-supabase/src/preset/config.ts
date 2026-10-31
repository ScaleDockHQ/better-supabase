import type {
  AccessBlockConfig,
  BlockConfig,
  AnyBlocksConfig,
  BlocksConfig,
  EntityConfig,
} from "../config/blocks.ts";
import type {
  BetterSupabaseConfig,
  FlatConfig,
} from "../config/types/config.ts";
import type { Preset, PresetInstance } from "./fields.ts";
import type { ResolvedPreset } from "./resolve.ts";

import { asBlocksConfig } from "../config/blocks.ts";
import { flattenConfig, groupConfig } from "../config/groups.ts";
import { DEFAULT_TENANT } from "../core/entity-naming.ts";
import { isPresetName, namedPreset } from "./presets.ts";
import { listNames, resolvePreset } from "./resolve.ts";
import { presetOfSpec } from "./spec.ts";

/** A named preset, a `/create?preset=` URL, or a preset object. */
export type PresetInput =
  | string
  | (Partial<Preset> & { readonly blocks?: readonly string[] });

/**
 * Reads a named preset, a `/create?preset=<name>` URL or a preset object
 * (`PresetSpec`) into a `Preset`. A preset code from 0.14 throws, naming the
 * codemod that converts it.
 */
export function presetOf(input: PresetInput): Preset {
  if (typeof input !== "string") {
    return presetOfSpec(input);
  }

  const value = /[?&]preset=([^&#]+)/.exec(input)?.[1] ?? input;

  return isPresetName(value) ? namedPreset(value) : presetOfSpec(value);
}

/**
 * The conventions that map onto config keys; `tenantName` takes any name
 * `blocks.memberships.names.organization` allows.
 */
export type ConfigConventions = Pick<
  Preset,
  "casing" | "idType" | "scope" | "access" | "api"
> & { readonly tenantName: string };

/**
 * `blocks.permissions` for the conventions: the model and id type that differ
 * from the defaults.
 */
function accessEntry(conventions: ConfigConventions): AccessBlockConfig {
  return {
    ...(conventions.access === "roles" ? {} : { model: conventions.access }),
    ...(conventions.idType === "uuid" ? {} : { idType: conventions.idType }),
  };
}

/**
 * `blocks.memberships` for the conventions: the tenant's name when it isn't
 * `organization`.
 */
function tenantEntry(conventions: ConfigConventions): BlockConfig {
  return conventions.tenantName === DEFAULT_TENANT.singular
    ? {}
    : { entities: { organization: conventions.tenantName } };
}

/** The `blocks` entry each block gets from the preset's conventions. */
function conventionEntry(
  name: string,
  preset: Preset,
): BlockConfig | AccessBlockConfig {
  if (name === "permissions") {
    return accessEntry(preset);
  }

  return name === "memberships" ? tenantEntry(preset) : {};
}

/** `sql` for the conventions, or undefined when they are the defaults. */
function sqlOf(conventions: ConfigConventions): FlatConfig["sql"] {
  const sql = {
    ...(conventions.api === "none" ? {} : { api: conventions.api }),
    ...(conventions.scope === "tenant" ? {} : { scope: conventions.scope }),
  };

  return Object.keys(sql).length === 0 ? undefined : sql;
}

/**
 * The config keys conventions set without a preset: `casing`, `sql`,
 * `blocks.permissions` when the access model or id type differ from the
 * defaults, and `blocks.memberships` when the tenant has another name.
 */
export function conventionConfig(
  conventions: ConfigConventions,
): Pick<FlatConfig, "casing" | "sql"> & {
  readonly blocks?: {
    readonly permissions?: AccessBlockConfig;
    readonly memberships?: BlockConfig;
    readonly "rls-guard": BlockConfig;
  };
} {
  const sql = sqlOf(conventions);
  const access = accessEntry(conventions);
  const tenant = tenantEntry(conventions);

  // ADR 0104: a new project starts with the guard that keeps row level security on.
  const blocks = {
    ...(Object.keys(access).length === 0 ? {} : { permissions: access }),
    ...(Object.keys(tenant).length === 0 ? {} : { memberships: tenant }),
    "rls-guard": {},
  };

  return {
    casing: conventions.casing,
    ...(sql === undefined ? {} : { sql }),
    blocks,
  };
}

/**
 * The config keys a resolved preset sets: its blocks and the conventions that
 * differ from the defaults.
 */
export function presetConfig(
  resolved: ResolvedPreset,
): Pick<FlatConfig, "casing" | "sql" | "integrations"> & {
  readonly blocks: BlocksConfig;
} {
  const { preset } = resolved;
  const sql = sqlOf(preset);

  return {
    ...(preset.casing === "snake" ? {} : { casing: preset.casing }),
    ...(sql === undefined ? {} : { sql }),
    ...(preset.integrations.length === 0
      ? {}
      : { integrations: preset.integrations }),
    blocks: asBlocksConfig(instanceEntries(resolved)),
  };
}

/**
 * A preset instance as a flat `blocks` entry: `names` is `entities` there, and
 * an entity with `subjects` settings becomes `{ name, team, auditReads }`.
 */
function flatInstance(instance: PresetInstance): BlockConfig {
  const { names = {}, subjects = {}, ...rest } = instance;

  const keys = [...new Set([...Object.keys(names), ...Object.keys(subjects)])];

  if (keys.length === 0) {
    return rest;
  }

  const entities = Object.fromEntries(
    keys.map((key) => {
      const name = names[key];
      const settings = subjects[key];

      return [
        key,
        settings === undefined
          ? name
          : { ...(name === undefined ? {} : { name }), ...settings },
      ];
    }),
  );

  return { ...rest, entities };
}

/**
 * The `blocks` entries of a resolved preset: each block with its convention
 * entry, then the preset's instances over them.
 */
function instanceEntries(
  resolved: ResolvedPreset,
): Record<string, BlockConfig | AccessBlockConfig> {
  const { preset } = resolved;

  const blocks: Record<string, BlockConfig | AccessBlockConfig> =
    Object.fromEntries(
      resolved.blocks.map((block) => [
        block.name,
        conventionEntry(block.name, preset),
      ]),
    );

  for (const [key, instance] of Object.entries(preset.instances ?? {})) {
    if (resolved.conflicts.some((conflict) => conflict.block === key)) {
      continue;
    }

    blocks[key] = { ...blocks[key], ...flatInstance(instance) };
  }

  return blocks;
}

function isBlockList(
  blocks: NonNullable<FlatConfig["blocks"]>,
): blocks is readonly string[] {
  return Array.isArray(blocks);
}

function blocksOf(blocks: FlatConfig["blocks"]): AnyBlocksConfig {
  if (blocks === undefined) {
    return {};
  }

  if (!isBlockList(blocks)) {
    return blocks;
  }

  return Object.fromEntries(blocks.map((name) => [name, {}]));
}

/**
 * A literal config after `defineConfig`: the same type without a preset, and
 * with one, every key but `blocks`, `database`, `gen` and `adapters` as
 * written, those merged with the preset's.
 */
export type ExpandedConfig<C extends BetterSupabaseConfig> = C extends {
  readonly preset: NonNullable<BetterSupabaseConfig["preset"]>;
}
  ? Omit<C, "blocks" | "database" | "gen" | "adapters"> &
      Pick<BetterSupabaseConfig, "blocks" | "database" | "gen" | "adapters">
  : C;

/**
 * `config` with its `preset` expanded: the preset's blocks (and what they
 * require) and conventions first, then the config's own keys over them, so
 * explicit config wins. A block in both keeps the preset's settings that the
 * config's entry leaves unset, and merges `options` key by key. Expanding twice
 * gives the same config.
 */
export function expandPreset<const C extends BetterSupabaseConfig>(
  config: C,
): ExpandedConfig<C>;
export function expandPreset(
  config: BetterSupabaseConfig,
): BetterSupabaseConfig {
  if (config.preset === undefined) {
    return config;
  }

  return groupConfig(expandFlatPreset(flattenConfig(config)));
}

type Entities = BlockConfig["entities"];

type EntityEntry = string | EntityConfig | undefined;

/** One entity: a name given as a string keeps the preset's other settings. */
function mergedEntity(preset: EntityEntry, own: EntityEntry): EntityEntry {
  if (own === undefined) {
    return preset;
  }

  if (preset === undefined || typeof preset === "string") {
    return own;
  }

  return typeof own === "string"
    ? { ...preset, name: own }
    : { ...preset, ...own };
}

/** `entities` entity by entity, or the config's own when either is shorthand. */
function mergedEntities(preset: Entities, own: Entities): Entities {
  if (own === undefined || preset === undefined) {
    return own ?? preset;
  }

  if (typeof preset === "string" || typeof own === "string") {
    return own;
  }

  const presetEntries: Readonly<Record<string, EntityEntry>> = preset;
  const ownEntries: Readonly<Record<string, EntityEntry>> = own;

  const keys = new Set([
    ...Object.keys(presetEntries),
    ...Object.keys(ownEntries),
  ]);

  return Object.fromEntries(
    [...keys].map((key) => [
      key,
      mergedEntity(presetEntries[key], ownEntries[key]),
    ]),
  );
}

/** `expandPreset` on the flat shape `resolveConfig` reads. */
export function expandFlatPreset(config: FlatConfig): FlatConfig {
  if (config.preset === undefined) {
    return config;
  }

  const resolved = resolvePreset(presetOf(config.preset));

  if (resolved.conflicts.length > 0) {
    throw new TypeError(
      `preset: ${listNames(
        resolved.conflicts.map(
          (conflict) =>
            `${conflict.block ?? conflict.field ?? ""} (${conflict.reason})`,
        ),
      )} can't install.`,
    );
  }

  const base = presetConfig(resolved);
  const own = blocksOf(config.blocks);

  const blocks: Record<string, BlockConfig | AccessBlockConfig | undefined> =
    Object.fromEntries(Object.entries(base.blocks));

  for (const [name, entry] of Object.entries(own)) {
    const preset = blocks[name];
    const options = { ...preset?.options, ...entry?.options };
    const entities = mergedEntities(preset?.entities, entry?.entities);

    blocks[name] = {
      ...preset,
      ...entry,
      ...(Object.keys(options).length === 0 ? {} : { options }),
      ...(entities === undefined ? {} : { entities }),
    };
  }

  return {
    ...base,
    ...config,
    ...(config.sql === undefined && base.sql === undefined
      ? {}
      : { sql: { ...base.sql, ...config.sql } }),
    blocks: asBlocksConfig(blocks),
  };
}
