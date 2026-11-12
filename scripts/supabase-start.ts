/**
 * Starts the local stack after checking the macOS shared memory cap. Every
 * running native stack holds segments and `kern.sysv.shmmni` allows 32, so a
 * start past the cap fails late with an unclear error; this fails early and
 * names the fix.
 */
import { execFileSync, spawnSync } from "node:child_process";
import { exit, platform } from "node:process";

import { countSegments } from "./supabase-prune.ts";

/** Segments one stack needs, with room for the next one. */
export const SEGMENT_CAP = 24;

export const overCap = (segments: number): boolean => segments >= SEGMENT_CAP;

function main(): void {
  if (platform === "darwin") {
    const segments = countSegments(
      execFileSync("ipcs", ["-m"], { encoding: "utf-8" }),
    );

    if (overCap(segments)) {
      console.error(
        `${segments} shared memory segments are in use (macOS allows 32). ` +
          "Run `pnpm supabase:prune --apply` to stop stacks of merged branches, " +
          "or `pnpm supabase:prune --destroy --apply` to delete them.",
      );
      exit(1);
    }
  }

  for (const [command, args] of [
    ["pnpm", ["exec", "supabase", "start", "--runtime", "native"]],
    ["pnpm", ["env:local"]],
  ] as const) {
    const result = spawnSync(command, args, { stdio: "inherit" });

    if (result.status !== 0) {
      exit(result.status ?? 1);
    }
  }
}

if (import.meta.main) {
  main();
}
