import { readFile } from "node:fs/promises";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliOptions } from "../core/command.ts";
import type { FilePlan } from "../core/files.ts";
import type { CommandResult } from "../core/io.ts";
import type { CliEnv } from "../env.ts";
import type { AdoptProposal, ExistingTable } from "../sql/adopt.ts";
import type { ConfigEdit } from "../sql/config-edit.ts";
import type { Paint } from "../style.ts";
import type { SnapshotSource } from "./snapshot.ts";

import { defineCliCommand, list } from "../core/command.ts";
import { CliError } from "../core/errors.ts";
import { applyPlan, planResult } from "../core/files.ts";
import { display } from "../core/io.ts";
import { commandMeta } from "../core/manifest.ts";
import { latestMigrationVersion } from "../doctor/migration-safety.ts";
import { toCatalog } from "../introspect/index.ts";
import {
  describeProposal,
  existingTables,
  proposeAdoption,
} from "../sql/adopt.ts";
import {
  setBlockInConfig,
  setBlockInJson,
  setPathInConfig,
  setPathInJson,
} from "../sql/config-edit.ts";
import { plain } from "../style.ts";
import { blockNames } from "./blocks.ts";
import { loadSnapshot } from "./snapshot.ts";
import { SOURCE_ARGS, sourceArgs } from "./source-args.ts";

const ADOPT_ARGS = {
  block: {
    type: "positional",
    required: false,
    description: "The block to adopt existing tables for",
  },
  tables: {
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
  check: {
    type: "boolean",
    description:
      "Write nothing; exit 1 with the diff when the config lacks this mapping",
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

/**
 * `edit` with `doctor.migrationSafety.since` set to the newest migration when
 * the config has none, so doctor's lock checks skip the migrations that ran
 * before the tables were adopted.
 */
async function withMigrationSince(
  config: ResolvedConfig,
  file: string,
  edit: ConfigEdit,
): Promise<ConfigEdit> {
  if (!edit.ok || config.doctor.migrationSafety?.since !== undefined) {
    return edit;
  }

  const since = await latestMigrationVersion(config.root);

  if (since === undefined) {
    return edit;
  }

  const path = ["doctor", "migrationSafety", "since"] as const;

  const next = file.endsWith(".json")
    ? setPathInJson(edit.text, path, since)
    : setPathInConfig(edit.text, path, since);

  return next.ok ? next : edit;
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
    throw new CliError(
      "usage",
      "Name the block to adopt, e.g. `better-supabase adopt teams --tables public.teams`.",
    );
  }

  const proposal = proposeAdoption(block, await deps.tables(), {
    from: list(args.tables),
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

  const edit = await withMigrationSince(
    config,
    file,
    withAdoptedBlock(file, source, proposal),
  );

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

  const plan: FilePlan = {
    root: config.root,
    regenerate: "better-supabase adopt",
    files: [{ path: file, contents: edit.text, policy: "edit" }],
  };

  const applied = await applyPlan(plan, args, paint);

  if (applied.mode === "check") {
    return planResult(plan, applied, { data: { ...data, written: false } });
  }

  if (applied.drift) {
    lines.push("", ...applied.diffs);
  }

  if (applied.mode === "dry-run" || !applied.drift) {
    lines.push(
      "",
      applied.drift
        ? "Dry run: nothing written. Run without --dry-run to write it."
        : `${shown} already holds this mapping.`,
    );

    return {
      code: 0,
      output: lines.join("\n"),
      data: { ...data, written: false },
    };
  }

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
  lists: ["tables"],
  completions: { block: blockNames },
  run: async (args, { config, configFile, env, io, log, paint, signal }) => {
    const tables = snapshotTables(config, env, {
      ...(await sourceArgs(args, io)),
      ...(signal ? { signal } : {}),
    });

    return runAdopt(config, args, {
      paint,
      tables: () => log.progress("Reading the schema", tables),
      ...(configFile === undefined ? {} : { configFile }),
    });
  },
});
