import { readFile } from "node:fs/promises";
import { posix, resolve } from "node:path";

import type { BlockConfig, ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliOptions } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";
import type { Now } from "../sql/migrations.ts";

import {
  type CreateDesign,
  type DesignChange,
  designConfig,
  diffAppTables,
  designOf,
  encodePreset,
  isPresetName,
  type Preset,
  PRESET_NAMES,
  presetOf,
  resolvePreset,
} from "../../preset/index.ts";
import { findConfig, loadConfig } from "../config.ts";
import {
  CONVENTION_ARGS,
  CONVENTION_COMPLETIONS,
  conventionFlags,
  hasConventionFlags,
  withConventions,
} from "../conventions.ts";
import { defineCliCommand } from "../core/command.ts";
import { CliError } from "../core/errors.ts";
import { applyPlan, type FilePlan, planResult } from "../core/files.ts";
import { display } from "../core/io.ts";
import { commandMeta } from "../core/manifest.ts";
import { AUTHZ_NOTE, createUrlParam } from "../create-url.ts";
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
import { writeDesign } from "../sql/design-edit.ts";
import { syncModules } from "../sql/sync.ts";
import { type Paint, plain } from "../style.ts";
import { adoptSchemas, snapshotTables, withAdoptedBlock } from "./adopt.ts";
import { SOURCE_ARGS, sourceArgs } from "./source-args.ts";

const APPLY_ARGS = {
  preset: {
    type: "string",
    description:
      "A named preset, a code from /create or its URL; a URL's design (&design=) adds its app tables and extra columns",
    valueHint: "name|code|url",
  },
  package: {
    type: "string",
    description:
      "Workspace package whose config to edit, relative to --cwd; a Create URL's package= sets it too",
    valueHint: "dir",
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
  "allow-breaking": {
    type: "boolean",
    description:
      "Write a design that drops, renames or retypes app table columns, or makes one required without a default",
  },
  "dry-run": {
    type: "boolean",
    description: "Show the config diff and write nothing",
  },
  check: {
    type: "boolean",
    description:
      "Write nothing; exit 1 with the diff when the config lacks the preset",
  },
} as const;

type ApplyOptions = CliOptions<typeof APPLY_ARGS & typeof CONVENTION_ARGS>;

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

    if ((config.blocks[block]?.mode ?? "managed") !== "managed") {
      continue;
    }

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

/**
 * The design in `input`'s `&design=`, checked against the blocks the config
 * gets: an extra column needs its block in the preset or the config.
 */
async function designFor(
  config: ResolvedConfig,
  input: string,
  preset: Preset,
): Promise<CreateDesign | undefined> {
  const design = await designOf(input);

  if (design === undefined) {
    return undefined;
  }

  const resolved = resolvePreset(preset);

  const blocks = new Set([
    ...config.blockNames,
    ...resolved.blocks.map((block) => block.name),
  ]);

  for (const module of Object.keys(design.extraColumns ?? {})) {
    if (!blocks.has(module)) {
      throw new TypeError(
        `design.extraColumns.${module}: neither the preset nor the config installs the ${module} block`,
      );
    }
  }

  designConfig(
    resolved,
    design.appTables === undefined ? {} : { appTables: design.appTables },
  );

  return design;
}

/** Each breaking change with its expand-and-contract steps. */
function describeBreaking(changes: readonly DesignChange[]): string[] {
  return [
    "Breaking changes to app tables:",
    ...changes.flatMap((change) => [
      `  ${change.summary}`,
      ...change.steps.map((step, index) => `    ${String(index + 1)}. ${step}`),
    ]),
  ];
}

/** The config file edited for `--only`: the `preset` key, or the blocks. */
function edited(
  file: string,
  source: string,
  name: string | undefined,
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
      : (name ?? encodePreset(preset));

  return json
    ? setPresetInJson(source, value)
    : setPresetInConfig(source, value);
}

/**
 * The config of the workspace package `pkg` names, relative to the root
 * config's directory, and its file; the root config without one.
 */
async function packageTarget(
  config: ResolvedConfig,
  deps: ApplyDeps,
  pkg: string | undefined,
  reload: (root: string, file: string) => Promise<ResolvedConfig>,
): Promise<{ readonly config: ResolvedConfig; readonly deps: ApplyDeps }> {
  if (pkg === undefined) {
    return { config, deps };
  }

  const root = resolve(config.root, posix.normalize(pkg.replaceAll("\\", "/")));

  const file = findConfig(root);

  if (file === undefined) {
    throw new CliError(
      "config_not_found",
      `--package ${pkg} has no better-supabase config. Start one with \`better-supabase init --package ${pkg}\`.`,
    );
  }

  return {
    config: await reload(root, file),
    deps: { ...deps, configFile: file },
  };
}

/**
 * Applies a preset to an existing project: sets `preset` in the config (or,
 * with `--only blocks`, lists its blocks), shows the diff, then writes the
 * module files of every block the config now holds.
 */
export async function runApply(
  rootConfig: ResolvedConfig,
  args: ApplyOptions,
  rootDeps: ApplyDeps,
): Promise<CommandResult> {
  const input = args.preset;

  if (input === undefined) {
    throw new CliError(
      "usage",
      "Pass --preset with a named preset, a code from /create or its URL.",
    );
  }

  const only = args.only;

  if (only !== undefined && only !== "blocks" && only !== "conventions") {
    throw new CliError("usage", '--only must be "blocks" or "conventions"');
  }

  const flags = conventionFlags(args);

  if (only === "blocks" && hasConventionFlags(flags)) {
    throw new CliError(
      "usage",
      "--only blocks leaves the conventions, so it takes no convention flags.",
    );
  }

  const reload =
    rootDeps.reload ?? ((root: string, path: string) => loadConfig(root, path));

  const { config, deps } = await packageTarget(
    rootConfig,
    rootDeps,
    args.package ?? createUrlParam(input, "package"),
    reload,
  );

  const file = deps.configFile;

  if (file === undefined) {
    throw new CliError(
      "config_not_found",
      `No config file to apply the preset to. Start a project with \`better-supabase init --preset ${input}\`.`,
    );
  }

  let preset: Preset;

  try {
    preset = presetOf(input);
  } catch (error) {
    throw new CliError(
      "usage",
      error instanceof Error ? error.message : String(error),
    );
  }

  preset = withConventions(preset, flags);

  const name =
    isPresetName(input) && !hasConventionFlags(flags) ? input : undefined;

  let design: CreateDesign | undefined;

  try {
    design =
      only === "conventions"
        ? undefined
        : await designFor(config, input, preset);
  } catch (error) {
    throw new CliError(
      "usage",
      error instanceof Error ? error.message : String(error),
    );
  }

  const conflict = describeConflicts(
    only === "conventions" ? { ...preset, blocks: [] } : preset,
  );

  if (conflict !== undefined) {
    throw new CliError("usage", conflict);
  }

  const breaking =
    design?.appTables === undefined
      ? []
      : diffAppTables(config.appTables, design.appTables, {
          keepMissing: true,
        }).filter((change) => change.breaking);

  const shown = display(config.root, file);

  if (
    breaking.length > 0 &&
    args["allow-breaking"] !== true &&
    args["dry-run"] !== true
  ) {
    return {
      code: 1,
      output: describeBreaking(breaking).join("\n"),
      data: { file: shown, written: false, breaking },
      error: `Nothing was written: the design has ${breaking.length === 1 ? "a breaking change" : `${String(breaking.length)} breaking changes`} to tables the app already has. Follow the steps above, or pass --allow-breaking to write it anyway.`,
    };
  }

  const source = await readFile(file, "utf-8");
  const edit = edited(file, source, name, preset, only);

  if (!edit.ok) {
    return {
      code: 1,
      error: `${shown} wasn't changed: ${edit.reason}. Set preset: "${encodePreset(preset)}" in it yourself.`,
    };
  }

  const withDesign =
    design === undefined ? edit : writeDesign(file, edit.text, design, config);

  if (!withDesign.ok) {
    return {
      code: 1,
      error: `${shown} wasn't changed: ${withDesign.reason}. Download the config from /create and copy its appTables and extraColumns yourself.`,
    };
  }

  const paint = deps.paint ?? plain;
  let text = withDesign.text;

  const lines: string[] =
    breaking.length === 0 ? [] : [...describeBreaking(breaking), ""];

  if (createUrlParam(input, "authz") !== undefined) {
    lines.push(AUTHZ_NOTE, "");
  }

  let adopted: Readonly<Record<string, BlockConfig>> = {};

  if (args.adopt === true) {
    if (only === "conventions" || deps.tables === undefined) {
      throw new CliError(
        "usage",
        only === "conventions"
          ? "--adopt maps blocks, and --only conventions takes none."
          : "--adopt needs the database or a snapshot to read the tables from.",
      );
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
        error: `Nothing was written: ${adoption.refused.map((proposal) => proposal.block).join(", ")} ${adoption.refused.length === 1 ? "has a table" : "have tables"} under the default names that can't be adopted as they are, and the managed block would skip them. Fix what the report lists, map them with \`better-supabase adopt <block> --tables <schema.table>\`, or leave the block out of the preset.`,
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

  const plan: FilePlan = {
    root: config.root,
    regenerate: "better-supabase apply",
    files: [{ path: file, contents: text, policy: "edit" }],
  };

  const applied = await applyPlan(plan, args, paint);

  if (applied.mode === "check") {
    return planResult(plan, applied, { data: { ...data, written: false } });
  }

  lines.push(...applied.diffs);

  if (applied.mode === "dry-run") {
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
  meta: commandMeta("apply"),
  args: { ...APPLY_ARGS, ...CONVENTION_ARGS, ...SOURCE_ARGS },
  completions: {
    ...CONVENTION_COMPLETIONS,
    preset: () => PRESET_NAMES,
    only: () => ["blocks", "conventions"],
  },
  run: async (args, { config, configFile, env, io, paint, signal }) =>
    runApply(config, args, {
      now: () => new Date(),
      paint,
      tables: snapshotTables(config, env, {
        ...(await sourceArgs(args, io)),
        ...(signal ? { signal } : {}),
      }),
      ...(configFile === undefined ? {} : { configFile }),
    }),
});
