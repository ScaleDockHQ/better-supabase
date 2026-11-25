// The unit time budget (ADR 1230). As a Vitest reporter, on the coverage job's merge and on the
// validation projects, it writes each file's time and every test past 40% of its limit to
// `unit-times.json` in the working directory. As a script, it checks such files against the
// budget, or writes the budget or the shard packing from one or more runs.
//
//   node scripts/unit-durations.ts --check unit-times.json           (library: files, total, tests)
//   node scripts/unit-durations.ts --check-tests unit-times.json...  (validation projects: tests)
//   node scripts/unit-durations.ts --write unit-times.json...
//   node scripts/unit-durations.ts --pack unit-times.json...
import type { Reporter, TestModule } from "vitest/node";

import { readFileSync, writeFileSync } from "node:fs";
import { relative } from "node:path";
import { fileURLToPath } from "node:url";
import * as v from "valibot";

// The shards pack on DURATIONS. BUDGET holds each file's time, the library's summed time and the
// tests already past half their limit. They are separate files: a file's time depends on its
// shard neighbours, so a budget refresh must not repack the shards.
export const DURATIONS = "packages/better-supabase/tests/unit-durations.json";
export const BUDGET = "scripts/unit-time-budget.json";

const ROOT = fileURLToPath(new URL("..", import.meta.url));
const LIBRARY = "packages/better-supabase/";
const SLOWEST = 20;

// A test's limit is half of its timeout, capped at the unit project's 20 seconds, so raising a
// test's timeout does not raise its limit. Tests past WATCH of the limit are recorded, so the
// budget also lists the ones that hover just under it and would fail at random.
const TIMEOUT_CAP_MS = 20_000;
const WATCH = 0.8;

// A time fails when it runs this much over its baseline, and by at least SLACK_MS. A file's time
// moved by up to 1.8 times between green runs with other files on its shard (runs 45452166250,
// 45454066955, 45483751800 and 45577725387), so 50% failed on noise alone.
const GROWTH = 2;
const SLACK_MS = 5000;

// The library's summed file time is steadier than one file's; it fails 15% over the budget.
const TOTAL_GROWTH = 1.15;

const timesSchema = v.object({
  files: v.record(v.string(), v.number()),
  slowTests: v.array(
    v.object({ id: v.string(), durationMs: v.number(), timeoutMs: v.number() }),
  ),
});

const budgetSchema = v.object({
  totalMs: v.number(),
  files: v.record(v.string(), v.number()),
  slowTests: v.record(v.string(), v.number()),
});

export type UnitTimes = v.InferOutput<typeof timesSchema>;

export type Budget = v.InferOutput<typeof budgetSchema>;

/** Half of a test's timeout, capped at half the unit project's timeout. */
export function limitOf(timeoutMs: number): number {
  return Math.min(timeoutMs, TIMEOUT_CAP_MS) / 2;
}

/** Collects the times while Vitest runs or replays a project's tests. */
export default class UnitTimesReporter implements Reporter {
  onTestRunEnd(testModules: readonly TestModule[]): void {
    const times: UnitTimes = { files: {}, slowTests: [] };

    for (const module of testModules) {
      const file = relative(ROOT, module.moduleId).replaceAll("\\", "/");
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
        const timeoutMs = test.options.timeout ?? TIMEOUT_CAP_MS;

        if (durationMs > limitOf(timeoutMs) * WATCH) {
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

/** The library's summed file time in one run. */
export function libraryTotal(times: UnitTimes): number {
  return Object.entries(times.files)
    .filter(([file]) => file.startsWith(LIBRARY))
    .reduce((sum, [, ms]) => sum + ms, 0);
}

/**
 * The budget from several runs: each file's and listed test's slowest time, and
 * the slowest library total. A file's time swings by up to 1.8 times with its
 * shard neighbours.
 */
export function budgetOf(runs: readonly UnitTimes[]): Budget {
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

  return {
    totalMs: Math.max(0, ...runs.map(libraryTotal)),
    files: sortedRecord(files),
    slowTests: sortedRecord(slowTests),
  };
}

/** True when `ms` grew past the budget over `before`: twice, and five seconds. */
export function grew(ms: number, before: number): boolean {
  return ms > before * GROWTH && ms - before > SLACK_MS;
}

/** Tests past their limit that the budget does not list, or that doubled since. */
export function testFindings(times: UnitTimes, budget: Budget): string[] {
  return times.slowTests.flatMap((test) => {
    const before = budget.slowTests[test.id];

    if (
      test.durationMs <= limitOf(test.timeoutMs) ||
      (before !== undefined && !grew(test.durationMs, before))
    ) {
      return [];
    }

    return [
      `Test over its ${seconds(limitOf(test.timeoutMs))} s limit: \`${test.id}\` took ${seconds(test.durationMs)} s${before === undefined ? "" : `, baseline ${seconds(before)} s`}.`,
    ];
  });
}

/** Every finding for a library run: grown files, the summed time and the tests. */
export function findings(times: UnitTimes, budget: Budget): string[] {
  const files = Object.entries(times.files).flatMap(([file, ms]) => {
    const before = budget.files[file];

    return before !== undefined && grew(ms, before)
      ? [
          `File over its time budget: \`${file}\` took ${seconds(ms)} s, baseline ${seconds(before)} s.`,
        ]
      : [];
  });

  const total = libraryTotal(times);

  const totals =
    total > budget.totalMs * TOTAL_GROWTH
      ? [
          `Summed test time over budget: ${seconds(total)} s, budget ${seconds(budget.totalMs)} s (+${Math.round((TOTAL_GROWTH - 1) * 100)}%).`,
        ]
      : [];

  return [...files, ...totals, ...testFindings(times, budget)];
}

function seconds(ms: number): string {
  return (ms / 1000).toFixed(1);
}

/** A markdown table of the files that take the longest. */
export function slowestFilesSummary(times: UnitTimes, budget: Budget): string {
  const slowest = Object.entries(times.files)
    .toSorted((a, b) => b[1] - a[1])
    .slice(0, SLOWEST);

  return [
    "## Slowest unit files",
    "",
    "| File | Seconds | Baseline |",
    "| --- | --- | --- |",
    ...slowest.map(([file, ms]) => {
      const before = budget.files[file];

      return `| \`${file}\` | ${seconds(ms)} | ${before === undefined ? "new" : seconds(before)} |`;
    }),
    "",
    `Summed time ${seconds(libraryTotal(times))} s, budget ${seconds(budget.totalMs)} s. ${times.slowTests.length} tests ran past ${WATCH * 100}% of their limit; \`${BUDGET}\` lists the known ones.`,
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

function report(found: readonly string[]): number {
  for (const line of found) {
    process.stdout.write(`\n${line}\n`);
  }

  if (found.length === 0) {
    return 0;
  }

  process.stdout.write(
    "\nMake the test faster or split it. After a deliberate change, refresh the budget (docs/agents/tooling.md).\n",
  );

  return 1;
}

const FLAGS = new Set(["--check", "--check-tests", "--write", "--pack"]);

function main(): number {
  const [flag, ...paths] = process.argv.slice(2);

  if (paths.length === 0 || flag === undefined || !FLAGS.has(flag)) {
    process.stderr.write(
      "usage: unit-durations --check|--check-tests|--write|--pack <unit-times.json>...\n",
    );

    return 1;
  }

  const runs = paths.map(readTimes);

  if (flag === "--write") {
    writeFileSync(BUDGET, `${JSON.stringify(budgetOf(runs), null, 2)}\n`);

    return 0;
  }

  if (flag === "--pack") {
    const library = Object.entries(budgetOf(runs).files)
      .filter(([file]) => file.startsWith(LIBRARY))
      .map(([file, ms]) => [file.slice(LIBRARY.length), ms]);

    writeFileSync(
      DURATIONS,
      `${JSON.stringify(Object.fromEntries(library), null, 2)}\n`,
    );

    return 0;
  }

  const budget = v.parse(
    budgetSchema,
    JSON.parse(readFileSync(BUDGET, "utf-8")),
  );

  if (flag === "--check-tests") {
    return report(runs.flatMap((run) => testFindings(run, budget)));
  }

  const [times] = runs;

  if (times === undefined) {
    return 1;
  }

  process.stdout.write(slowestFilesSummary(times, budget));

  return report(findings(times, budget));
}

if (import.meta.main) {
  process.exitCode = main();
}
