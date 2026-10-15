import { readFile, writeFile } from "node:fs/promises";

import type { BlockConfig, ResolvedConfig } from "../../config/index.ts";
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
  type AdoptProposal,
  adoptableBlocks,
  describeProposal,
  type ExistingTable,
  hasDefaultTable,
  proposeAdoption,
} from "../sql/adopt.ts";
import {
  addBlocksToConfig,
  addBlocksToJson,
  type ConfigEdit,
  setPresetInConfig,
  setPresetInJson,
} from "../sql/config-edit.ts";
import { syncModules } from "../sql/sync.ts";
import { type Paint, painter, plain } from "../style.ts";
import { adoptSchemas, snapshotTables, withAdoptedBlock } from "./adopt.ts";
import { SOURCE_ARGS, sourceArgs } from "./source-args.ts";

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
  adopt: {
    type: "boolean",
    description:
      "Map the preset's blocks onto tables the database already has under their default names (adopt mode)",
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
  /** The tables in the database, read for `--adopt`. */
  readonly tables?: () => Promise<readonly ExistingTable[]>;
}

interface Adoption {
  readonly text: string;
  readonly lines: readonly string[];
  readonly adopted: readonly AdoptProposal[];
  readonly refused: readonly AdoptProposal[];
}

/**
 * `text` with an adopt-mode entry for each of `blocks` that has a table
 * under one of its default names. A block the config already sets to another
 * mode is left as it is.
 */
function adoptBlocks(
  config: ResolvedConfig,
  file: string,
  text: string,
  blocks: readonly string[],
  tables: readonly ExistingTable[],
): Adoption {
  const schemas = adoptSchemas(config);
  const adoptable = new Set(adoptableBlocks());
  const adopted: AdoptProposal[] = [];
  const refused: AdoptProposal[] = [];
  const lines: string[] = [];
  let next = text;
  for (const block of blocks) {
    if (!adoptable.has(block) || !hasDefaultTable(block, tables, schemas)) {
      continue;
    }
    if ((config.blocks[block]?.mode ?? "managed") !== "managed") continue;
    const proposal = proposeAdoption(block, tables, {
      blocks: config.blocks,
      schemas,
    });
    lines.push(`Adopting ${block}:`, ...describeProposal(proposal));
    if (proposal.errors.length > 0) {
      refused.push(proposal);
      continue;
    }
    const edit = withAdoptedBlock(file, next, proposal);
    if (!edit.ok) {
      refused.push({
        ...proposal,
        errors: [`blocks.${block} can't be set: ${edit.reason}.`],
      });
      continue;
    }
    next = edit.text;
    adopted.push(proposal);
  }
  return { text: next, lines, adopted, refused };
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
  let text = edit.text;
  const lines: string[] = [];
  let adopted: Readonly<Record<string, BlockConfig>> = {};
  if (args.adopt === true) {
    if (only === "conventions" || deps.tables === undefined) {
      return {
        code: 2,
        error:
          only === "conventions"
            ? "--adopt maps blocks, and --only conventions takes none."
            : "--adopt needs the database or a snapshot to read the tables from.",
      };
    }
    const adoption = adoptBlocks(
      config,
      file,
      text,
      resolvePreset(preset).blocks.map((block) => block.name),
      await deps.tables(),
    );
    if (adoption.refused.length > 0) {
      return {
        code: 1,
        output: adoption.lines.join("\n"),
        data: {
          file: shown,
          written: false,
          refused: Object.fromEntries(
            adoption.refused.map((proposal) => [
              proposal.block,
              proposal.errors,
            ]),
          ),
        },
        error: `Nothing was written: ${adoption.refused.map((proposal) => proposal.block).join(", ")} ${adoption.refused.length === 1 ? "has a table" : "have tables"} under the default names that can't be adopted as they are, and the managed block would skip them. Fix what the report lists, map them with \`better-supabase adopt <block> --from <schema.table>\`, or leave the block out of the preset.`,
      };
    }
    text = adoption.text;
    adopted = Object.fromEntries(
      adoption.adopted.map((proposal) => [proposal.block, proposal.entry]),
    );
    lines.push(
      ...(adoption.lines.length === 0
        ? ["No existing tables to adopt: every block stays managed."]
        : adoption.lines),
      "",
    );
  }
  const data = { file: shown, adopted, contents: text };
  if (text === source) {
    lines.push(`${shown} already holds the preset.`);
    return {
      code: 0,
      output: lines.join("\n"),
      data: { ...data, written: false },
    };
  }
  lines.push(fileDiff(shown, source, text, paint));
  if (args["dry-run"] === true) {
    lines.push(
      "",
      "Dry run: nothing written. Run without --dry-run to apply it.",
    );
    return {
      code: 0,
      output: lines.join("\n"),
      data: { ...data, written: false },
    };
  }
  await writeFile(file, text);
  const reload =
    deps.reload ?? ((root: string, path: string) => loadConfig(root, path));
  const next = await reload(config.root, file);
  const synced = await syncModules(next, {}, paint, deps.now);
  lines.push("", `Updated ${shown}.`, "", synced.output ?? synced.error ?? "");
  return {
    code: synced.code,
    output: lines.join("\n"),
    data: { ...data, written: true },
  };
}

export const applyCommand: AnyCommand = defineCliCommand({
  meta: {
    name: "apply",
    description:
      "Applies a preset to an existing project: edits the config, shows the diff and writes the blocks' modules",
  },
  args: { ...APPLY_ARGS, ...SOURCE_ARGS },
  run: async (args, { config, configFile, env, io, signal }) =>
    runApply(config, args, {
      now: () => new Date(),
      paint: painter(io.color),
      tables: snapshotTables(config, env, {
        ...(await sourceArgs(args, io)),
        ...(signal ? { signal } : {}),
      }),
      ...(configFile === undefined ? {} : { configFile }),
    }),
});
