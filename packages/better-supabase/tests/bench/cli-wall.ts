/**
 * Wall-clock time of the shipped CLI as a process: the numbers behind the CLI
 * and doctor speed work. Each command runs against a validation project, once
 * cold (compile cache and render cache removed) and then warm, and the script
 * prints the p50, p95 and mean of the warm runs.
 *
 *     pnpm --filter better-supabase build
 *     node tests/bench/cli-wall.ts [runs] [project]
 */
import { spawn } from "node:child_process";
import { rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

import { format, summarize } from "./stats.ts";

const bin = resolve(import.meta.dirname, "../../bin/better-supabase.js");
const runs = Number(process.argv[2] ?? 7);

const project = resolve(
  import.meta.dirname,
  "../../../../tests",
  process.argv[3] ?? "validation-crm",
);

const cache = join(tmpdir(), "bsb-cli-wall-compile-cache");

const commands: readonly (readonly string[])[] = [
  ["--version"],
  ["codes"],
  ["doctor"],
  ["gen", "--check"],
];

function run(args: readonly string[]): Promise<number> {
  const start = performance.now();

  return new Promise((done, fail) => {
    const child = spawn(process.execPath, [bin, ...args], {
      cwd: project,
      stdio: "ignore",
      env: { ...process.env, NODE_COMPILE_CACHE: cache },
    });

    child.on("error", fail);
    child.on("close", () => {
      done(performance.now() - start);
    });
  });
}

for (const args of commands) {
  await rm(cache, { recursive: true, force: true });

  const cold = await run(args);
  const warm: number[] = [];

  for (let each = 0; each < runs; each += 1) {
    warm.push(await run(args));
  }

  console.log(`${args.join(" ").padEnd(16)} cold ${cold.toFixed(0)} ms`);
  console.log(format(`  warm`, summarize(warm)));
}
