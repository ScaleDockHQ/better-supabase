import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliOptions } from "../command.ts";
import type { CommandResult } from "../io.ts";

import {
  decodePreset,
  encodePreset,
  isPresetCode,
  listNames,
  type Preset,
  PRESET_FIELDS,
  presetConfig,
  type PresetFieldKey,
  presetOf,
  resolvePreset,
  type ResolvedPreset,
} from "../../preset/index.ts";
import { defineCliCommand } from "../command.ts";

const USAGE = `Usage:
  better-supabase preset decode <name|code|url>   What a preset holds and what it installs
  better-supabase preset info                     The config's preset and how the config differs from it`;

const PRESET_ARGS = {
  action: {
    type: "positional",
    required: false,
    description: "decode or info",
  },
} as const;

type PresetOptions = CliOptions<typeof PRESET_ARGS>;

const messageOf = (error: unknown): string =>
  error instanceof Error ? error.message : String(error);

/** The value of a convention field, for printing. */
function fieldValue(preset: Preset, key: PresetFieldKey): string {
  const value = preset[key];
  if (typeof value === "string") return value;
  return value.length === 0 ? "none" : value.join(", ");
}

/** A preset and what it resolves to, as lines. */
function describe(resolved: ResolvedPreset): string[] {
  const { preset } = resolved;
  const width = Math.max(...PRESET_FIELDS.map((field) => field.key.length));
  const lines = [
    `Code: ${encodePreset(preset)}`,
    "",
    ...PRESET_FIELDS.map(
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
  readonly code: string;
  readonly preset: Preset;
  readonly blocks: ResolvedPreset["blocks"];
  readonly integrations: ResolvedPreset["integrations"];
  readonly conflicts: ResolvedPreset["conflicts"];
}

function presetData(resolved: ResolvedPreset): PresetData {
  return {
    code: encodePreset(resolved.preset),
    preset: resolved.preset,
    blocks: resolved.blocks,
    integrations: resolved.integrations,
    conflicts: resolved.conflicts,
  };
}

function decode(value: string | undefined): CommandResult {
  if (value === undefined) {
    return {
      code: 2,
      error: `Name a preset, a code or a /create URL.\n${USAGE}`,
    };
  }
  let preset: Preset;
  let derived: readonly PresetFieldKey[] = [];
  try {
    const param = /[?&]preset=([^&#]+)/.exec(value)?.[1] ?? value;
    if (isPresetCode(param)) {
      const decoded = decodePreset(param);
      preset = decoded.preset;
      derived = decoded.derived;
    } else {
      preset = presetOf(param);
    }
  } catch (error) {
    return { code: 2, error: messageOf(error) };
  }
  const resolved = resolvePreset(preset);
  const lines = describe(resolved);
  if (derived.length > 0) {
    lines.push(
      "",
      `The code predates ${listNames(derived)}, so they are at their defaults.`,
    );
  }
  return {
    code: resolved.conflicts.length > 0 ? 1 : 0,
    output: lines.join("\n"),
    data: { ...presetData(resolved), derived },
  };
}

/** How the config differs from the preset it names. */
function drift(
  config: ResolvedConfig,
  resolved: ResolvedPreset,
): { readonly added: string[]; readonly changed: string[] } {
  const base = presetConfig(resolved);
  const fromPreset = new Set(Object.keys(base.blocks));
  const added = config.blockNames.filter((name) => !fromPreset.has(name));
  const changed: string[] = [];
  if ((base.casing ?? "snake") !== config.casing) {
    changed.push(
      `casing is ${config.casing}, the preset sets ${base.casing ?? "snake"}`,
    );
  }
  for (const name of fromPreset) {
    const own = config.blocks[name];
    const preset = base.blocks[name] ?? {};
    const keys = Object.keys(own ?? {}).filter(
      (key) => key !== "schema" && key !== "api" && !(key in preset),
    );
    if (keys.length > 0) changed.push(`${name} sets ${keys.join(", ")}`);
  }
  return { added, changed };
}

function info(config: ResolvedConfig): CommandResult {
  if (config.preset === undefined) {
    return {
      code: 0,
      output:
        "The config names no preset. Start one with `better-supabase apply --preset <name|code>`.",
      data: { preset: null },
    };
  }
  let preset: Preset;
  try {
    preset = presetOf(config.preset);
  } catch (error) {
    return { code: 2, error: messageOf(error) };
  }
  const resolved = resolvePreset(preset);
  const { added, changed } = drift(config, resolved);
  const lines = [
    `Preset: ${config.preset}`,
    "",
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
    data: { name: config.preset, ...presetData(resolved), added, changed },
  };
}

export function runPreset(
  config: ResolvedConfig,
  args: PresetOptions,
): CommandResult {
  const [action, value] = args._ ?? [];
  switch (action) {
    case "decode":
      return decode(value);
    case "info":
      return info(config);
    case undefined:
      return { code: 2, error: `Name an action.\n${USAGE}` };
    default:
      return { code: 2, error: `Unknown preset action "${action}".\n${USAGE}` };
  }
}

export const presetCommand: AnyCommand = defineCliCommand({
  meta: {
    name: "preset",
    description:
      "Decodes a preset code, or shows the config's preset and how the config differs from it",
  },
  args: PRESET_ARGS,
  run: (args, { config }) => Promise.resolve(runPreset(config, args)),
});
