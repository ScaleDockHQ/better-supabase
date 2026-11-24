// The unit time budget (ADR 1230). As a Vitest reporter on the coverage job's merge, it writes
// each file's time and every test past half its timeout to `unit-times.json` in the
// working directory. As a script, it checks that file against the budget, or writes the budget
// or the shard packing from one or more runs.
//
//   node scripts/unit-durations.ts --check unit-times.json
//   node scripts/unit-durations.ts --write unit-times.json [more-unit-times.json ...]
//   node scripts/unit-durations.ts --pack unit-times.json [more-unit-times.json ...]
import type { Reporter, TestModule } from "vitest/node";

import { readFileSync, writeFileSync } from "node:fs";
import * as v from "valibot";

// The shards pack on DURATIONS. BUDGET holds each file's time and the tests already past half
// their timeout. They are separate files: a file's time depends on its shard neighbours, so a
// budget refresh must not repack the shards.
export const DURATIONS = "packages/better-supabase/tests/unit-durations.json";
export const BUDGET = "scripts/unit-time-budget.json";

const SLOWEST = 20;

// Blob reports keep the CI runner's absolute paths; file names start after this.
const LIBRARY = "packages/better-supabase/";

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

const budgetSchema = v.object({
  files: v.record(v.string(), v.number()),
  slowTests: v.record(v.string(), v.number()),
});

export type UnitTimes = v.InferOutput<typeof timesSchema>;

/** Collects the times while Vitest replays the merged blob reports. */
export default class UnitTimesReporter implements Reporter {
  onTestRunEnd(testModules: readonly TestModule[]): void {
    const times: UnitTimes = { files: {}, slowTests: [] };

    for (const module of testModules) {
      const path = module.moduleId.replaceAll("\\", "/");
      const file = path.slice(path.lastIndexOf(LIBRARY) + LIBRARY.length);
      const diagnostic = module.diagnostic();

      // Import and setup time count too: a shard's wall time follows the sum, not the tests alone.
      times.files[file] = Math.round(
        diagnostic.duration +
          diagnostic.collectDuration +
          diagnostic.setupDuration +
          diagnostic.prepareDuration +
          diagnostic.environmentSetupDuration,
      );

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
    `${times.slowTests.length} tests ran past half their timeout; \`${BUDGET}\` lists the known ones.`,
    "",
  ].join("\n");
}

function sortedRecord(
  map: ReadonlyMap<string, number>,
): Record<string, number> {
  return Object.fromEntries(
    [...map].toSorted((a, b) => a[0].localeCompare(b[0])),
  );
}

function readTimes(path: string): UnitTimes {
  return v.parse(timesSchema, JSON.parse(readFileSync(path, "utf-8")));
}

function main(): number {
  const [flag, ...paths] = process.argv.slice(2);
  const [timesPath] = paths;

  if (
    timesPath === undefined ||
    (flag !== "--check" && flag !== "--write" && flag !== "--pack")
  ) {
    process.stderr.write(
      "usage: unit-durations --check <unit-times.json> | --write|--pack <unit-times.json>...\n",
    );

    return 1;
  }

  if (flag !== "--check") {
    const { files, slowTests } = slowestOf(paths.map(readTimes));

    if (flag === "--pack") {
      writeFileSync(
        DURATIONS,
        `${JSON.stringify(sortedRecord(files), null, 2)}\n`,
      );
    } else {
      const budget = {
        files: sortedRecord(files),
        slowTests: sortedRecord(slowTests),
      };

      writeFileSync(BUDGET, `${JSON.stringify(budget, null, 2)}\n`);
    }

    return 0;
  }

  const budget = v.parse(
    budgetSchema,
    JSON.parse(readFileSync(BUDGET, "utf-8")),
  );

  const times = readTimes(timesPath);
  const durations = new Map(Object.entries(budget.files));

  const found = findings(
    times,
    durations,
    new Map(Object.entries(budget.slowTests)),
  );

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
