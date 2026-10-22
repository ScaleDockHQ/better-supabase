import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";
import type { SqlFlags } from "../sql/args.ts";
import type { Now } from "../sql/migrations.ts";
import type { Paint } from "../style.ts";

import { defineCliCommand } from "../core/command.ts";
import { commandMeta } from "../core/manifest.ts";
import { SQL_ARGS } from "../sql/args.ts";
import { syncModules } from "../sql/sync.ts";
import { upgrade } from "../sql/upgrade.ts";
import { plain } from "../style.ts";

const UPGRADE_ARGS = {
  check: {
    type: "boolean",
    description:
      "Write nothing; exit 1 when a block is behind its current version or a schema file is stale",
  },
  "tests-dir": SQL_ARGS["tests-dir"],
  "dry-run": SQL_ARGS["dry-run"],
} as const;

/**
 * Brings the blocks' SQL up to the config and this release: first the upgrade
 * steps of blocks behind their current version (renames, backfills, the 0.15
 * prefix), which need the old files to compare against, then every block's
 * schema and test files rendered from the config.
 */
export async function runUpgrade(
  config: ResolvedConfig,
  args: SqlFlags,
  paint: Paint = plain,
  now: Now = () => new Date(),
): Promise<CommandResult> {
  const upgraded = await upgrade(config, args, paint, now);

  if (upgraded.code !== 0) {
    return upgraded;
  }

  const synced = await syncModules(config, args, paint, now);

  return {
    ...synced,
    output: [upgraded.output, synced.output]
      .filter((text) => text !== undefined && text !== "")
      .join("\n"),
    data: { upgrade: upgraded.data, sync: synced.data },
  };
}

export const upgradeCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("upgrade"),
  args: UPGRADE_ARGS,
  run: (args, { config, paint }) => runUpgrade(config, args, paint),
});
