import { existsSync } from "node:fs";
import { readdir, readFile } from "node:fs/promises";
import { join, resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand } from "../core/command.ts";
import type { PlanFlags, PlannedFile } from "../core/files.ts";
import type { CommandResult } from "../core/io.ts";
import type { PowerSyncInstance } from "../powersync/streams.ts";
import type { Now } from "../sql/migrations.ts";

import { renderBlocks } from "../../sql/index.ts";
import { defineCliCommand } from "../core/command.ts";
import { applyPlan, PLAN_ARGS, planResult } from "../core/files.ts";
import { commandMeta } from "../core/manifest.ts";
import {
  isPowerSyncBlock,
  POWERSYNC_BLOCKS,
  powersyncOutput,
} from "../powersync/streams.ts";
import { migrationsDir } from "../sql-layout.ts";
import { stampAfter } from "../sql/migrations.ts";
import { layoutFor } from "../sql/providers.ts";

const ARGS = {
  instance: {
    type: "string",
    description:
      "Block instances to sync, comma separated. Defaults to gen.powersync.instances",
    valueHint: "keys",
  },
  out: {
    type: "string",
    description:
      "Folder for sync-streams.yaml and schema.ts. Defaults to gen.powersync.out, then powersync",
    valueHint: "dir",
  },
  ...PLAN_ARGS,
} as const;

/** `--instance`, `--out` and the plan flags. */
export interface PowerSyncFlags extends PlanFlags {
  readonly instance?: string | undefined;
  readonly out?: string | undefined;
}

const PUBLICATION_SUFFIX = "_powersync_publication.sql";

const REGENERATE = "better-supabase powersync streams";

function instancesOf(
  config: ResolvedConfig,
  keys: readonly string[],
): PowerSyncInstance[] | string {
  const instances: PowerSyncInstance[] = [];

  for (const key of keys) {
    const block = config.instances[key]?.block;

    if (block === undefined) {
      return `${key} is not a block in the config.`;
    }

    if (!isPowerSyncBlock(block)) {
      return `${key} installs ${block}, which can't sync yet. PowerSync syncs ${POWERSYNC_BLOCKS.slice(0, -1).join(", ")} and ${POWERSYNC_BLOCKS.at(-1)}.`;
    }

    instances.push({ key, block });
  }

  return instances;
}

/**
 * The publication migration, unless the newest one already adds these tables: a
 * pushed migration is never rewritten, so a change gets a new one.
 */
async function publicationMigration(
  config: ResolvedConfig,
  sql: string,
  now: Now,
): Promise<PlannedFile | undefined> {
  const dir = resolve(config.root, migrationsDir(config));
  const names = existsSync(dir) ? (await readdir(dir)).toSorted() : [];
  const latest = names.findLast((name) => name.endsWith(PUBLICATION_SUFFIX));

  if (
    latest !== undefined &&
    (await readFile(join(dir, latest), "utf-8")) === sql
  ) {
    return undefined;
  }

  return {
    path: join(dir, `${stampAfter(names, now())}${PUBLICATION_SUFFIX}`),
    contents: sql,
    policy: "create",
    note: "adds the tables to the powersync publication",
  };
}

/**
 * Writes `sync-streams.yaml` and `schema.ts` for the synced block instances,
 * and a migration that adds their tables to the `powersync` publication.
 */
export async function runPowerSync(
  config: ResolvedConfig,
  args: PowerSyncFlags,
  now: Now = () => new Date(),
): Promise<CommandResult> {
  const settings = config.gen.powersync;

  const keys =
    args.instance === undefined
      ? (settings?.instances ?? [])
      : args.instance
          .split(",")
          .map((key) => key.trim())
          .filter(Boolean);

  if (keys.length === 0) {
    return {
      code: 1,
      errorCode: "config_invalid",
      error:
        "Name the block instances to sync: set gen.powersync.instances, or pass --instance notifications.",
    };
  }

  const instances = instancesOf(config, keys);

  if (typeof instances === "string") {
    return { code: 1, errorCode: "config_invalid", error: instances };
  }

  const layout = await layoutFor(config, {}, config.blockNames);
  let output: ReturnType<typeof powersyncOutput>;

  try {
    output = powersyncOutput({
      files: renderBlocks(config.blockNames, layout),
      instances,
      importFrom: settings?.import ?? "@powersync/common",
    });
  } catch (cause) {
    return {
      code: 1,
      errorCode: "config_invalid",
      error: cause instanceof Error ? cause.message : String(cause),
    };
  }

  const out = resolve(config.root, args.out ?? settings?.out ?? "powersync");
  const migration = await publicationMigration(config, output.publication, now);

  const plan = {
    root: config.root,
    regenerate: REGENERATE,
    files: [
      { path: join(out, "sync-streams.yaml"), contents: output.streams },
      { path: join(out, "schema.ts"), contents: output.schema },
      ...(migration === undefined ? [] : [migration]),
    ],
  };

  const applied = await applyPlan(plan, args);

  return planResult(plan, applied, {
    data: { instances: keys, tables: output.tables },
  });
}

export const powersyncStreamsCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("powersync streams"),
  args: ARGS,
  run: (args, { config }) => runPowerSync(config, args),
});
