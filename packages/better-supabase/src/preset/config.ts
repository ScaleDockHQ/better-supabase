import type {
  AccessBlockConfig,
  BlockConfig,
  AnyBlocksConfig,
} from "../config/blocks.ts";
import type { BetterSupabaseConfig } from "../config/types/config.ts";
import type { Preset } from "./fields.ts";
import type { ResolvedPreset } from "./resolve.ts";

import { decodePreset, isPresetCode } from "./code.ts";
import { DEFAULT_CONVENTIONS } from "./fields.ts";
import { isPresetName, namedPreset, PRESET_NAMES } from "./presets.ts";
import { listNames, resolvePreset } from "./resolve.ts";

/** A named preset, a code, a `/create?preset=` URL, or a preset object. */
export type PresetInput =
  | string
  | (Partial<Preset> & { readonly blocks?: readonly string[] });

/** Reads a named preset, a code or a `/create?preset=` URL into a `Preset`. */
export function presetOf(input: PresetInput): Preset {
  if (typeof input !== "string") {
    return { ...DEFAULT_CONVENTIONS, ...input, blocks: input.blocks ?? [] };
  }

  const value = /[?&]preset=([^&#]+)/.exec(input)?.[1] ?? input;

  if (isPresetName(value)) {
    return namedPreset(value);
  }

  if (isPresetCode(value)) {
    return decodePreset(value).preset;
  }

  throw new TypeError(
    `preset: "${input}" is not a preset. Use a name (${PRESET_NAMES.join(", ")}), a code from /create, or its URL.`,
  );
}

/**
 * The conventions that map onto config keys; `tenantName` takes any name
 * `sql.naming.tenant` allows.
 */
export type ConfigConventions = Pick<
  Preset,
  "casing" | "idType" | "scope" | "access" | "api"
> & { readonly tenantName: string };

/**
 * `blocks.access` for the conventions: the model and id type that differ from
 * the defaults.
 */
function accessEntry(conventions: ConfigConventions): AccessBlockConfig {
  return {
    ...(conventions.access === "roles" ? {} : { model: conventions.access }),
    ...(conventions.idType === "uuid" ? {} : { idType: conventions.idType }),
  };
}

/** The `blocks` entry each block gets from the preset's conventions. */
function conventionEntry(
  name: string,
  preset: Preset,
): BlockConfig | AccessBlockConfig {
  return name === "access" ? accessEntry(preset) : {};
}

/** `sql` for the conventions, or undefined when they are the defaults. */
function sqlOf(conventions: ConfigConventions): BetterSupabaseConfig["sql"] {
  const sql = {
    ...(conventions.api === "none" ? {} : { api: conventions.api }),
    ...(conventions.scope === "tenant" ? {} : { scope: conventions.scope }),
    ...(conventions.tenantName === "organization"
      ? {}
      : { naming: { tenant: conventions.tenantName } }),
  };

  return Object.keys(sql).length === 0 ? undefined : sql;
}

/**
 * The config keys conventions set without a preset: `casing`, `sql`, and
 * `blocks.access` when the access model or id type differ from the defaults.
 */
export function conventionConfig(
  conventions: ConfigConventions,
): Pick<BetterSupabaseConfig, "casing" | "sql"> & {
  readonly blocks?: { readonly access: AccessBlockConfig };
} {
  const sql = sqlOf(conventions);
  const access = accessEntry(conventions);

  return {
    casing: conventions.casing,
    ...(sql === undefined ? {} : { sql }),
    ...(Object.keys(access).length === 0 ? {} : { blocks: { access } }),
  };
}

/**
 * The config keys a resolved preset sets: its blocks and the conventions that
 * differ from the defaults.
 */
export function presetConfig(
  resolved: ResolvedPreset,
): Pick<BetterSupabaseConfig, "casing" | "sql" | "integrations"> & {
  readonly blocks: AnyBlocksConfig;
} {
  const { preset } = resolved;
  const sql = sqlOf(preset);

  return {
    ...(preset.casing === "snake" ? {} : { casing: preset.casing }),
    ...(sql === undefined ? {} : { sql }),
    ...(preset.integrations.length === 0
      ? {}
      : { integrations: preset.integrations }),
    blocks: Object.fromEntries(
      resolved.blocks.map((block) => [
        block.name,
        conventionEntry(block.name, preset),
      ]),
    ),
  };
}

function isBlockList(
  blocks: NonNullable<BetterSupabaseConfig["blocks"]>,
): blocks is readonly string[] {
  return Array.isArray(blocks);
}

function blocksOf(blocks: BetterSupabaseConfig["blocks"]): AnyBlocksConfig {
  if (blocks === undefined) {
    return {};
  }

  if (!isBlockList(blocks)) {
    return blocks;
  }

  return Object.fromEntries(blocks.map((name) => [name, {}]));
}

/**
 * `config` with its `preset` expanded: the preset's blocks (and what they
 * require) and conventions first, then the config's own keys over them, so
 * explicit config wins. A block in both keeps the preset's settings that the
 * config's entry leaves unset. Expanding twice gives the same config.
 */
export function expandPreset(
  config: BetterSupabaseConfig,
): BetterSupabaseConfig {
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
    blocks[name] = { ...blocks[name], ...entry };
  }

  return {
    ...base,
    ...config,
    ...(config.sql === undefined && base.sql === undefined
      ? {}
      : { sql: { ...base.sql, ...config.sql } }),
    blocks,
  };
}
