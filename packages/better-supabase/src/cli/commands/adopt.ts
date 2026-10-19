import { readFile, writeFile } from "node:fs/promises";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliOptions } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";
import type { CliEnv } from "../env.ts";
import type { SnapshotSource } from "./snapshot.ts";

import { defineCliCommand, list } from "../core/command.ts";
import { display } from "../core/io.ts";
import { commandMeta } from "../core/manifest.ts";
import { fileDiff } from "../diff.ts";
import { toCatalog } from "../introspect/index.ts";
import { withSpinner } from "../prompts.ts";
import {
  type AdoptProposal,
  describeProposal,
  type ExistingTable,
  existingTables,
  proposeAdoption,
} from "../sql/adopt.ts";
import {
  type ConfigEdit,
  setBlockInConfig,
  setBlockInJson,
} from "../sql/config-edit.ts";
import { type Paint, painter, plain } from "../style.ts";
import { loadSnapshot } from "./snapshot.ts";
import { SOURCE_ARGS, sourceArgs } from "./source-args.ts";

const ADOPT_ARGS = {
  block: {
    type: "positional",
    required: false,
    description: "The block to adopt existing tables for",
  },
  from: {
    type: "string",
    description:
      "The existing tables, as table or schema.table; the block's other tables are looked up by their default names",
    valueHint: "schema.table,...",
  },
  "dry-run": {
    type: "boolean",
    description:
      "Show the proposed mapping and the config diff, and write nothing",
  },
} as const;

type AdoptOptions = CliOptions<typeof ADOPT_ARGS>;

/** What `runAdopt` reads from outside. */
export interface AdoptDeps {
  readonly configFile?: string;
  readonly paint?: Paint;
  /** The tables in the database: introspected, or from the snapshot. */
  readonly tables: () => Promise<readonly ExistingTable[]>;
}

/** The schemas searched for a block's default table names. */
export const adoptSchemas = (config: ResolvedConfig): readonly string[] => [
  ...new Set(["public", ...config.schemas]),
];

/** `source` with `blocks.<block>` set to the proposal's entry. */
export function withAdoptedBlock(
  file: string,
  source: string,
  proposal: AdoptProposal,
): ConfigEdit {
  return file.endsWith(".json")
    ? setBlockInJson(source, proposal.block, proposal.entry)
    : setBlockInConfig(source, proposal.block, proposal.entry);
}

/** The tables `loadSnapshot` reads, for the adopt commands. */
export function snapshotTables(
  config: ResolvedConfig,
  env: CliEnv,
  source: SnapshotSource,
): () => Promise<readonly ExistingTable[]> {
  return async () =>
    existingTables(toCatalog(await loadSnapshot(config, env, source)).tables);
}

/**
 * Proposes `blocks.<block>` in adopt mode over existing tables, reports what
 * can't map, and writes the entry to the config when everything maps.
 */
export async function runAdopt(
  config: ResolvedConfig,
  args: AdoptOptions,
  deps: AdoptDeps,
): Promise<CommandResult> {
  const block = args.block;

  if (block === undefined) {
    return {
      code: 2,
      error:
        "Name the block to adopt, e.g. `better-supabase adopt teams --from public.teams`.",
    };
  }

  const proposal = proposeAdoption(block, await deps.tables(), {
    from: list(args.from),
    blocks: config.blocks,
    schemas: adoptSchemas(config),
  });

  const lines = [`Adopting ${block}:`, ...describeProposal(proposal)];

  const data = {
    block,
    entry: proposal.entry,
    tables: proposal.tables,
    errors: proposal.errors,
    warnings: proposal.warnings,
  };

  if (proposal.errors.length > 0) {
    return {
      code: 1,
      output: lines.join("\n"),
      error: `blocks.${block} wasn't written: fix what the report lists, then run adopt again.`,
      data: { ...data, written: false },
    };
  }

  const file = deps.configFile;

  if (file === undefined) {
    lines.push(
      "",
      `No config file: add this to blocks yourself.`,
      `${block}: ${JSON.stringify(proposal.entry, null, 2)}`,
    );

    return {
      code: 0,
      output: lines.join("\n"),
      data: { ...data, written: false },
    };
  }

  const source = await readFile(file, "utf-8");
  const edit = withAdoptedBlock(file, source, proposal);
  const shown = display(config.root, file);

  if (!edit.ok) {
    return {
      code: 1,
      output: lines.join("\n"),
      error: `${shown} wasn't changed: ${edit.reason}. Set blocks.${block} in it yourself.`,
      data: { ...data, written: false },
    };
  }

  const paint = deps.paint ?? plain;

  if (edit.text !== source) {
    lines.push("", fileDiff(shown, source, edit.text, paint));
  }

  if (args["dry-run"] === true || edit.text === source) {
    lines.push(
      "",
      edit.text === source
        ? `${shown} already holds this mapping.`
        : "Dry run: nothing written. Run without --dry-run to write it.",
    );

    return {
      code: 0,
      output: lines.join("\n"),
      data: { ...data, written: false },
    };
  }

  await writeFile(file, edit.text);
  lines.push(
    "",
    `Updated ${shown}. Run \`better-supabase sql sync\` to write the block's module over these tables.`,
  );

  return {
    code: 0,
    output: lines.join("\n"),
    data: { ...data, written: true },
  };
}

export const adoptCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("adopt"),
  args: { ...ADOPT_ARGS, ...SOURCE_ARGS },
  lists: ["from"],
  run: async (args, { config, configFile, env, io, signal }) => {
    const tables = snapshotTables(config, env, {
      ...(await sourceArgs(args, io)),
      ...(signal ? { signal } : {}),
    });

    return runAdopt(config, args, {
      paint: painter(io.color),
      tables: () => withSpinner(io.prompts, "Reading the schema", tables),
      ...(configFile === undefined ? {} : { configFile }),
    });
  },
});
