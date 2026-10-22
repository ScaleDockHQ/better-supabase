import type { AnyBlocksConfig, ResolvedConfig } from "../../config/index.ts";
import type {
  Preset,
  PresetFieldKey,
  PresetName,
  PresetSpec,
  ResolvedPreset,
} from "../../preset/index.ts";
import type { CommandResult } from "../core/io.ts";

import {
  CONVENTION_FIELDS,
  presetAndDesignOf,
  presetConfig,
  presetOf,
  presetSpec,
  resolvePreset,
} from "../../preset/index.ts";
import { CliError } from "../core/errors.ts";

const messageOf = (error: unknown): string =>
  error instanceof Error ? error.message : String(error);

/** The value of a convention field, for printing. */
function fieldValue(preset: Preset, key: PresetFieldKey): string {
  const value = preset[key];

  if (typeof value === "string") {
    return value;
  }

  return value.length === 0 ? "none" : value.join(", ");
}

/** A preset and what it resolves to, as lines. */
function describe(resolved: ResolvedPreset): string[] {
  const { preset } = resolved;
  const width = Math.max(...CONVENTION_FIELDS.map((field) => field.key.length));
  const spec = presetSpec(preset);

  const lines = [
    `Preset: ${typeof spec === "string" ? spec : "custom"}`,
    "",
    ...CONVENTION_FIELDS.map(
      (field) =>
        `  ${field.key.padEnd(width)}  ${fieldValue(preset, field.key)}`,
    ),
    "",
    `Blocks (${String(resolved.blocks.length)}):`,
    ...resolved.blocks.map(
      (block) => `  ${block.name}${block.selected ? "" : ` (${block.reason})`}`,
    ),
  ];

  if (resolved.conflicts.length > 0) {
    lines.push(
      "",
      "Can't install:",
      ...resolved.conflicts.map(
        (conflict) =>
          `  ${conflict.block ?? conflict.field ?? ""}: ${conflict.reason}`,
      ),
    );
  }

  return lines;
}

interface PresetData {
  /** The preset as the config's `preset` key takes it. */
  readonly spec: PresetName | PresetSpec;
  readonly preset: Preset;
  readonly blocks: ResolvedPreset["blocks"];
  readonly integrations: ResolvedPreset["integrations"];
  readonly conflicts: ResolvedPreset["conflicts"];
}

function presetData(resolved: ResolvedPreset): PresetData {
  return {
    spec: presetSpec(resolved.preset),
    preset: resolved.preset,
    blocks: resolved.blocks,
    integrations: resolved.integrations,
    conflicts: resolved.conflicts,
  };
}

export async function decodePresetInput(
  value: string | undefined,
): Promise<CommandResult> {
  if (value === undefined) {
    throw new CliError(
      "input_required",
      "Name a preset, a design code or a /create URL.",
      { missing: ["<preset>"] },
    );
  }

  let preset: Preset;

  try {
    ({ preset } = await presetAndDesignOf(value));
  } catch (error) {
    throw new CliError("usage", messageOf(error));
  }

  const resolved = resolvePreset(preset);

  return {
    code: resolved.conflicts.length > 0 ? 1 : 0,
    output: describe(resolved).join("\n"),
    data: presetData(resolved),
  };
}

/** How the config differs from the preset it names. */
function drift(
  config: ResolvedConfig,
  resolved: ResolvedPreset,
): { readonly added: string[]; readonly changed: string[] } {
  const base = presetConfig(resolved);
  const baseBlocks: AnyBlocksConfig = base.blocks;
  const fromPreset = new Set(Object.keys(baseBlocks));
  const added = config.blockNames.filter((name) => !fromPreset.has(name));
  const changed: string[] = [];

  if ((base.casing ?? "snake") !== config.casing) {
    changed.push(
      `casing is ${config.casing}, the preset sets ${base.casing ?? "snake"}`,
    );
  }

  for (const name of fromPreset) {
    const own = config.blocks[name];
    const preset = baseBlocks[name] ?? {};

    const keys = Object.keys(own ?? {}).filter(
      (key) => key !== "schema" && key !== "api" && !(key in preset),
    );

    if (keys.length > 0) {
      changed.push(`${name} sets ${keys.join(", ")}`);
    }
  }

  return { added, changed };
}

export function presetInfo(config: ResolvedConfig): CommandResult {
  if (config.preset === undefined) {
    return {
      code: 0,
      output:
        "The config names no preset. Start one with `better-supabase add --preset <name>`.",
      data: { preset: null },
    };
  }

  let preset: Preset;

  try {
    preset = presetOf(config.preset);
  } catch (error) {
    throw new CliError("usage", messageOf(error));
  }

  const resolved = resolvePreset(preset);
  const { added, changed } = drift(config, resolved);

  const lines = [
    ...describe(resolved),
    "",
    added.length === 0 && changed.length === 0
      ? "The config adds nothing to the preset."
      : "The config differs from the preset:",
    ...added.map((name) => `  + ${name}`),
    ...changed.map((line) => `  ~ ${line}`),
  ];

  return {
    code: 0,
    output: lines.join("\n"),
    data: { ...presetData(resolved), added, changed },
  };
}
