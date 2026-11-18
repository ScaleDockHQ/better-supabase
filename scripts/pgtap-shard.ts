import { globSync } from "node:fs";
import { fileURLToPath } from "node:url";

import {
  assignShard,
  readDurations,
} from "../packages/better-supabase/tests/unit-shard.ts";

export function pgtapFiles(): string[] {
  return globSync("supabase/tests/**/*.sql").toSorted((a, b) =>
    a.localeCompare(b),
  );
}

export function pgtapShard(
  files: readonly string[],
  durationsMs: ReadonlyMap<string, number>,
  index: number,
  count: number,
): string[] {
  return assignShard(files, (file) => file, durationsMs, index, count).toSorted(
    (a, b) => a.localeCompare(b),
  );
}

function main(): number {
  const index = Number(process.argv[2]);
  const count = Number(process.argv[3]);

  if (
    !(Number.isInteger(index) && Number.isInteger(count)) ||
    index < 1 ||
    index > count
  ) {
    process.stderr.write("usage: pgtap-shard <index> <count>\n");

    return 1;
  }

  const durations = readDurations(
    fileURLToPath(new URL("pgtap-durations.json", import.meta.url)),
  );

  for (const file of pgtapShard(pgtapFiles(), durations, index, count)) {
    process.stdout.write(`${file}\n`);
  }

  return 0;
}

if (import.meta.main) {
  process.exitCode = main();
}
