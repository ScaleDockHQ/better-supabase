import { readFile, writeFile } from "node:fs/promises";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliOptions } from "../command.ts";
import type { CommandResult } from "../io.ts";
import type { Now } from "../sql/migrations.ts";

import {
  encodePreset,
  isPresetName,
  type Preset,
  presetOf,
  resolvePreset,
} from "../../preset/index.ts";
import { defineCliCommand } from "../command.ts";
import { loadConfig } from "../config.ts";
import { fileDiff } from "../diff.ts";
import { display } from "../io.ts";
import {
  addBlocksToConfig,
  addBlocksToJson,
  type ConfigEdit,
  setPresetInConfig,
  setPresetInJson,
} from "../sql/config-edit.ts";
import { syncModules } from "../sql/sync.ts";
import { type Paint, painter, plain } from "../style.ts";

const APPLY_ARGS = {
  preset: {
    type: "string",
    description: "A named preset, a code from /create or its URL",
    valueHint: "name|code|url",
  },
  only: {
    type: "string",
    description:
      "blocks: add the preset's blocks to blocks and leave the conventions; conventions: take the conventions and no blocks",
    valueHint: "blocks|conventions",
  },
  "dry-run": {
    type: "boolean",
    description: "Show the config diff and write nothing",
  },
} as const;

type ApplyOptions = CliOptions<typeof APPLY_ARGS>;

/** What `runApply` reads from outside. */
export interface ApplyDeps {
  readonly configFile?: string;
  readonly now: Now;
  readonly paint?: Paint;
  /** Loads the config file again after the edit; `loadConfig` by default. */
  readonly reload?: (root: string, file: string) => Promise<ResolvedConfig>;
}

const describeConflicts = (preset: Preset): string | undefined => {
  const { conflicts } = resolvePreset(preset);
  return conflicts.length === 0
    ? undefined
    : `The preset can't install: ${conflicts.map((conflict) => `${conflict.block ?? conflict.field ?? ""} (${conflict.reason})`).join("; ")}.`;
};

/** The config file edited for `--only`: the `preset` key, or the blocks. */
function edited(
  file: string,
  source: string,
  input: string,
  preset: Preset,
  only: string | undefined,
): ConfigEdit {
  const json = file.endsWith(".json");
  if (only === "blocks") {
    const names = resolvePreset(preset).blocks.map((block) => block.name);
    return json
      ? addBlocksToJson(source, names)
      : addBlocksToConfig(source, names);
  }
  const value =
    only === "conventions"
      ? encodePreset({ ...preset, blocks: [] })
      : isPresetName(input)
        ? input
        : encodePreset(preset);
  return json
    ? setPresetInJson(source, value)
    : setPresetInConfig(source, value);
}

/**
 * Applies a preset to an existing project: sets `preset` in the config (or,
 * with `--only blocks`, lists its blocks), shows the diff, then writes the
 * module files of every block the config now holds.
 */
export async function runApply(
  config: ResolvedConfig,
  args: ApplyOptions,
  deps: ApplyDeps,
): Promise<CommandResult> {
  const input = args.preset;
  if (input === undefined) {
    return {
      code: 2,
      error:
        "Pass --preset with a named preset, a code from /create or its URL.",
    };
  }
  const only = args.only;
  if (only !== undefined && only !== "blocks" && only !== "conventions") {
    return { code: 2, error: '--only must be "blocks" or "conventions"' };
  }
  const file = deps.configFile;
  if (file === undefined) {
    return {
      code: 2,
      error: `No config file to apply the preset to. Start a project with \`better-supabase init --preset ${input}\`.`,
    };
  }
  let preset: Preset;
  try {
    preset = presetOf(input);
  } catch (error) {
    return {
      code: 2,
      error: error instanceof Error ? error.message : String(error),
    };
  }
  const conflict = describeConflicts(
    only === "conventions" ? { ...preset, blocks: [] } : preset,
  );
  if (conflict !== undefined) return { code: 2, error: conflict };
  const source = await readFile(file, "utf8");
  const edit = edited(file, source, input, preset, only);
  const shown = display(config.root, file);
  if (!edit.ok) {
    return {
      code: 1,
      error: `${shown} wasn't changed: ${edit.reason}. Set preset: "${encodePreset(preset)}" in it yourself.`,
    };
  }
  const paint = deps.paint ?? plain;
  if (edit.text === source) {
    return { code: 0, output: `${shown} already holds the preset.` };
  }
  const lines = [fileDiff(shown, source, edit.text, paint)];
  if (args["dry-run"] === true) {
    lines.push(
      "",
      "Dry run: nothing written. Run without --dry-run to apply it.",
    );
    return { code: 0, output: lines.join("\n") };
  }
  await writeFile(file, edit.text);
  const reload =
    deps.reload ?? ((root: string, path: string) => loadConfig(root, path));
  const next = await reload(config.root, file);
  const synced = await syncModules(next, {}, paint, deps.now);
  lines.push("", `Updated ${shown}.`, "", synced.output ?? synced.error ?? "");
  return { code: synced.code, output: lines.join("\n") };
}

export const applyCommand: AnyCommand = defineCliCommand({
  meta: {
    name: "apply",
    description:
      "Applies a preset to an existing project: edits the config, shows the diff and writes the blocks' modules",
  },
  args: APPLY_ARGS,
  run: (args, { config, configFile, io }) =>
    runApply(config, args, {
      now: () => new Date(),
      paint: painter(io.color),
      ...(configFile === undefined ? {} : { configFile }),
    }),
});
