// The unit time budget (ADR 1230). As a Vitest reporter on the coverage job's merge, it writes
// each file's test time and every test past half its timeout to `unit-times.json` in the
// working directory. As a script, it checks that file against the baselines or writes them.
//
//   node scripts/unit-durations.ts --check unit-times.json
//   node scripts/unit-durations.ts --write unit-times.json [more-unit-times.json ...]
import type { Reporter, TestModule, Vitest } from "vitest/node";

import { readFileSync, writeFileSync } from "node:fs";
import { relative } from "node:path";
import * as v from "valibot";

// The shards pack on this file; the slow tests file lists the tests already past half their timeout.
export const DURATIONS = "packages/better-supabase/tests/unit-durations.json";
export const SLOW_TESTS = "scripts/unit-slow-tests.json";

const SLOWEST = 20;

// The unit project's testTimeout, for a test whose report carries none.
const DEFAULT_TIMEOUT_MS = 20_000;

// A time fails when it runs this much over its baseline, and by at least SLACK_MS: runner noise
// moves a one second file by more than half.
const GROWTH = 1.5;
const SLACK_MS = 5000;

const timesSchema = v.object({
  files: v.record(v.string(), v.number()),
  slowTests: v.array(
    v.object({ id: v.string(), durationMs: v.number(), timeoutMs: v.number() }),
  ),
});

const baselineSchema = v.record(v.string(), v.number());

export type UnitTimes = v.InferOutput<typeof timesSchema>;

/** Collects the times while Vitest replays the merged blob reports. */
export default class UnitTimesReporter implements Reporter {
  private root = "";

  onInit(vitest: Vitest): void {
    this.root = vitest.config.root;
  }

  onTestRunEnd(testModules: readonly TestModule[]): void {
    const times: UnitTimes = { files: {}, slowTests: [] };

    for (const module of testModules) {
      const file = relative(this.root, module.moduleId).replaceAll("\\", "/");

      times.files[file] = Math.round(module.diagnostic().duration);

      for (const test of module.children.allTests()) {
        const durationMs = Math.round(test.diagnostic()?.duration ?? 0);
        const timeoutMs = test.options.timeout ?? DEFAULT_TIMEOUT_MS;

        if (durationMs > timeoutMs / 2) {
          times.slowTests.push({
            id: `${file} > ${test.fullName}`,
            durationMs,
            timeoutMs,
          });
        }
      }
    }

    writeFileSync("unit-times.json", `${JSON.stringify(times)}\n`);
  }
}

/**
 * The slowest time of each file and slow test over several runs. A file's time
 * swings by up to 1.8 times between runs with other files on its shard, so the
 * baselines keep the worst one.
 */
export function slowestOf(
  runs: readonly UnitTimes[],
): Readonly<Record<"files" | "slowTests", Map<string, number>>> {
  const files = new Map<string, number>();
  const slowTests = new Map<string, number>();

  for (const run of runs) {
    for (const [file, ms] of Object.entries(run.files)) {
      files.set(file, Math.max(ms, files.get(file) ?? 0));
    }

    for (const test of run.slowTests) {
      slowTests.set(
        test.id,
        Math.max(test.durationMs, slowTests.get(test.id) ?? 0),
      );
    }
  }

  return { files, slowTests };
}

/** True when `ms` grew past the budget over `before`. */
export function grew(ms: number, before: number): boolean {
  return ms > before * GROWTH && ms - before > SLACK_MS;
}

/** The findings that fail the job, one line each. */
export function findings(
  times: UnitTimes,
  durations: ReadonlyMap<string, number>,
  slowBaseline: ReadonlyMap<string, number>,
): string[] {
  const files = Object.entries(times.files).flatMap(([file, ms]) => {
    const before = durations.get(file);

    return before !== undefined && grew(ms, before)
      ? [
          `File over its time budget: \`${file}\` took ${seconds(ms)} s, baseline ${seconds(before)} s.`,
        ]
      : [];
  });

  const tests = times.slowTests.flatMap((test) => {
    const before = slowBaseline.get(test.id);

    if (before !== undefined && !grew(test.durationMs, before)) {
      return [];
    }

    return [
      `Test over half its ${seconds(test.timeoutMs)} s timeout: \`${test.id}\` took ${seconds(test.durationMs)} s${before === undefined ? "" : `, baseline ${seconds(before)} s`}.`,
    ];
  });

  return [...files, ...tests];
}

function seconds(ms: number): string {
  return (ms / 1000).toFixed(1);
}

/** A markdown table of the files that take the longest. */
export function slowestFilesSummary(
  times: UnitTimes,
  durations: ReadonlyMap<string, number>,
): string {
  const slowest = Object.entries(times.files)
    .toSorted((a, b) => b[1] - a[1])
    .slice(0, SLOWEST);

  return [
    "## Slowest unit files",
    "",
    "| File | Seconds | Baseline |",
    "| --- | --- | --- |",
    ...slowest.map(([file, ms]) => {
      const before = durations.get(file);

      return `| \`${file}\` | ${seconds(ms)} | ${before === undefined ? "new" : seconds(before)} |`;
    }),
    "",
    `${times.slowTests.length} tests ran past half their timeout; \`${SLOW_TESTS}\` lists the known ones.`,
    "",
  ].join("\n");
}

function readMap(path: string): Map<string, number> {
  return new Map(
    Object.entries(
      v.parse(baselineSchema, JSON.parse(readFileSync(path, "utf-8"))),
    ),
  );
}

function sortedJson(entries: [string, number][]): string {
  return `${JSON.stringify(
    Object.fromEntries(entries.toSorted((a, b) => a[0].localeCompare(b[0]))),
    null,
    2,
  )}\n`;
}

function readTimes(path: string): UnitTimes {
  return v.parse(timesSchema, JSON.parse(readFileSync(path, "utf-8")));
}

function main(): number {
  const [flag, ...paths] = process.argv.slice(2);
  const [timesPath] = paths;

  if (timesPath === undefined || (flag !== "--check" && flag !== "--write")) {
    process.stderr.write(
      "usage: unit-durations --check <unit-times.json> | --write <unit-times.json>...\n",
    );

    return 1;
  }

  if (flag === "--write") {
    const { files, slowTests } = slowestOf(paths.map(readTimes));

    writeFileSync(DURATIONS, sortedJson([...files]));
    writeFileSync(SLOW_TESTS, sortedJson([...slowTests]));

    return 0;
  }

  const times = readTimes(timesPath);
  const durations = readMap(DURATIONS);
  const found = findings(times, durations, readMap(SLOW_TESTS));

  process.stdout.write(slowestFilesSummary(times, durations));

  for (const line of found) {
    process.stdout.write(`\n${line}\n`);
  }

  if (found.length > 0) {
    process.stdout.write(
      "\nMake the test faster or split it. After a deliberate change, refresh the baselines (docs/agents/tooling.md).\n",
    );

    return 1;
  }

  return 0;
}

if (import.meta.main) {
  process.exitCode = main();
}
