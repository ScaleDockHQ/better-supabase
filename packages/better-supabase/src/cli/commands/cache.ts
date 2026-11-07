import { relative } from "node:path";

import type { AnyCommand } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";

import { cacheRoot, cacheSize, listCache, purgeCache } from "../cache/store.ts";
import { defineCliCommand } from "../core/command.ts";
import { commandMeta } from "../core/manifest.ts";

const ARGS = {
  "dry-run": {
    type: "boolean",
    description: "Name what would be removed and remove nothing",
  },
} as const;

const SIZES = ["B", "kB", "MB", "GB"] as const;

/** `bytes` as `812 B` or `1.4 MB`. */
function size(bytes: number): string {
  let value = bytes;
  let unit = 0;

  while (value >= 1000 && unit < SIZES.length - 1) {
    value /= 1000;
    unit += 1;
  }

  return `${unit === 0 ? String(value) : value.toFixed(1)} ${SIZES[unit]}`;
}

export const cachePurgeCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("cache purge"),
  args: ARGS,
  run: async (args, { config, cwd }): Promise<CommandResult> => {
    const folder = relative(cwd, cacheRoot(config.root)) || ".";

    if (args["dry-run"] === true) {
      const removed = await listCache(config.root);
      const bytes = await cacheSize(config.root);

      return {
        code: 0,
        output:
          removed.length === 0
            ? `Nothing cached in ${folder}.`
            : `Would remove ${String(removed.length)} ${removed.length === 1 ? "entry" : "entries"} (${size(bytes)}) from ${folder}: ${removed.join(", ")}`,
        data: { cache: { folder, removed, bytes }, outcome: "planned" },
      };
    }

    const report = await purgeCache(config.root);

    if (report.removed.length === 0) {
      return {
        code: 0,
        output: `Nothing cached in ${folder}.`,
        data: {
          cache: { folder, removed: [], bytes: 0 },
          outcome: "unchanged",
        },
        next: [
          {
            command: "better-supabase gen",
            when: "to fill the cache on the next run",
          },
        ],
      };
    }

    return {
      code: 0,
      output: `Removed ${String(report.removed.length)} ${report.removed.length === 1 ? "entry" : "entries"} (${size(report.bytes)}) from ${folder}: ${report.removed.join(", ")}`,
      data: {
        cache: { folder, removed: report.removed, bytes: report.bytes },
        outcome: "removed",
      },
    };
  },
});
