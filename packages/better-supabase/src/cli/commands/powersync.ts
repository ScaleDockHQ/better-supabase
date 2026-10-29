import { existsSync } from "node:fs";
import { readdir, readFile } from "node:fs/promises";
import { join, resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { BlockSqlLayout } from "../../sql/index.ts";
import type { AnyCommand } from "../core/command.ts";
import type { PlanFlags, PlannedFile } from "../core/files.ts";
import type { CommandResult } from "../core/io.ts";
import type { PowerSyncInstance } from "../powersync/streams.ts";
import type { Now } from "../sql/migrations.ts";

import { attachmentReadRoles, renderBlocks } from "../../sql/index.ts";
import { defineCliCommand } from "../core/command.ts";
import { applyPlan, PLAN_ARGS, planResult } from "../core/files.ts";
import { commandMeta } from "../core/manifest.ts";
import {
  isPowerSyncBlock,
  POWERSYNC_BLOCKS,
  powersyncOutput,
  publicationSql,
} from "../powersync/streams.ts";
import { migrationsDir, snapshotColumnTypes } from "../sql-layout.ts";
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

/** The qualified app tables `blocks.<key>.tables` maps the instance onto. */
function mappedTables(config: ResolvedConfig, key: string): string[] {
  const { tables, schema } = config.instances[key]?.config ?? {};

  return Object.values(tables ?? {}).flatMap((name) => {
    if (typeof name !== "string") {
      return [];
    }

    if (name.includes(".")) {
      return [name];
    }

    return typeof schema === "string" ? [`${schema}.${name}`] : [];
  });
}

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

const PUBLISHED = [
  /alter publication powersync add table ((?:"(?:[^"]|"")+"|[a-z_][a-z0-9_$]*)\.(?:"(?:[^"]|"")+"|[a-z_][a-z0-9_$]*))/g,
  /create publication powersync for table ([^;]+);/g,
  /\('((?:[^']|'')+)'\)/g,
];

const unquote = (part: string): string =>
  part.startsWith('"') ? part.slice(1, -1).replaceAll('""', '"') : part;

/** The `schema.table` names an earlier publication migration added. */
function publishedBy(sql: string): Set<string> {
  const found = new Set<string>();

  for (const pattern of PUBLISHED) {
    for (const match of sql.matchAll(pattern)) {
      for (const table of match[1]!.split(",")) {
        found.add(
          table
            .trim()
            .replaceAll("''", "'")
            .split(".")
            .map((part) => unquote(part.trim()))
            .join("."),
        );
      }
    }
  }

  return found;
}

/**
 * The publication migration: `create publication` the first time, then one that
 * adds the tables no earlier migration added. A pushed migration is never
 * rewritten, so a change gets a new one.
 */
async function publicationMigration(
  config: ResolvedConfig,
  tables: readonly string[],
  now: Now,
): Promise<PlannedFile | undefined> {
  const dir = resolve(config.root, migrationsDir(config));
  const names = existsSync(dir) ? (await readdir(dir)).toSorted() : [];
  const earlier = names.filter((name) => name.endsWith(PUBLICATION_SUFFIX));

  const published =
    earlier.length === 0
      ? undefined
      : new Set(
          (
            await Promise.all(
              earlier.map((name) => readFile(join(dir, name), "utf-8")),
            )
          ).flatMap((sql) => [...publishedBy(sql)]),
        );

  const sql = publicationSql(tables, published);

  return sql === undefined
    ? undefined
    : {
        path: join(dir, `${stampAfter(names, now())}${PUBLICATION_SUFFIX}`),
        contents: sql,
        policy: "create",
        note: "adds the tables to the powersync publication",
      };
}

/**
 * By attachments instance, the roles whose keys grant its `read` permission,
 * when access runs on the `roles` model.
 */
function readRolesOf(
  config: ResolvedConfig,
  layout: BlockSqlLayout,
  instances: readonly PowerSyncInstance[],
): Map<string, readonly string[]> {
  return new Map(
    instances.flatMap((instance) => {
      if (instance.block !== "attachments") {
        return [];
      }

      const roles = attachmentReadRoles(
        layout,
        config.blockNames,
        instance.key,
      );

      if (roles === undefined) {
        return [];
      }

      return [[instance.key, roles] as const];
    }),
  );
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

  const mapped = Object.keys(config.instances).map(
    (key) => [key, mappedTables(config, key)] as const,
  );

  const types = await snapshotColumnTypes(
    config,
    mapped.flatMap(([, tables]) => tables),
  );

  const own = new Map(
    mapped.map(([key, tables]) => [
      key,
      new Map(
        tables.flatMap((table) => {
          const columns = types.get(table);

          return columns === undefined ? [] : [[table, columns] as const];
        }),
      ),
    ]),
  );

  const layout = await layoutFor(config, {}, config.blockNames);
  let output: ReturnType<typeof powersyncOutput>;

  try {
    output = powersyncOutput({
      files: renderBlocks(config.blockNames, layout),
      instances,
      own,
      readRoles: readRolesOf(config, layout, instances),
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
  const migration = await publicationMigration(config, output.published, now);

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
