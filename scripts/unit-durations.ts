// Turns a merged Vitest JSON report into the duration map the unit shards pack on, or checks the
// report against that map for the coverage job's step summary (ADR 1229).
//
//   node scripts/unit-durations.ts --write packages/better-supabase/tests/unit-durations.json report.json
//   node scripts/unit-durations.ts --check packages/better-supabase/tests/unit-durations.json report.json
import { readFileSync, writeFileSync } from "node:fs";
import * as v from "valibot";

const MARKER = "packages/better-supabase/";
const SLOWEST = 20;

// A file fails when it runs this much over its baseline, and by at least SLACK_MS: runner noise
// moves a one second file by more than half.
const GROWTH = 1.5;
const SLACK_MS = 5000;

// Half of the unit project's 20 second testTimeout.
const TEST_LIMIT_MS = 10_000;

const reportSchema = v.object({
  testResults: v.array(
    v.object({
      name: v.string(),
      startTime: v.number(),
      endTime: v.number(),
      assertionResults: v.optional(
        v.array(
          v.object({
            fullName: v.string(),
            duration: v.optional(v.nullable(v.number())),
          }),
        ),
        [],
      ),
    }),
  ),
});

const baselineSchema = v.record(v.string(), v.number());

export interface FileDuration {
  readonly file: string;
  readonly durationMs: number;
}

export interface SlowTest {
  readonly file: string;
  readonly test: string;
  readonly durationMs: number;
}

type VitestJsonReport = v.InferOutput<typeof reportSchema>;

function relativeName(name: string): string {
  const path = name.replaceAll("\\", "/");
  const at = path.lastIndexOf(MARKER);

  return at === -1 ? path : path.slice(at + MARKER.length);
}

function parseReport(json: string): VitestJsonReport {
  return v.parse(reportSchema, JSON.parse(json));
}

/** File durations from a Vitest `--reporter=json` document, in path order. */
export function durationsFromJson(json: string): FileDuration[] {
  return parseReport(json)
    .testResults.map((result) => ({
      file: relativeName(result.name),
      durationMs: Math.max(0, Math.round(result.endTime - result.startTime)),
    }))
    .toSorted((a, b) => a.file.localeCompare(b.file));
}

/** Tests that ran longer than half their timeout. */
export function slowTestsFromJson(json: string): SlowTest[] {
  return parseReport(json).testResults.flatMap((result) =>
    result.assertionResults
      .filter((test) => (test.duration ?? 0) > TEST_LIMIT_MS)
      .map((test) => ({
        file: relativeName(result.name),
        test: test.fullName,
        durationMs: Math.round(test.duration ?? 0),
      })),
  );
}

/**
 * Files that grew past the budget over their baseline. A file without a
 * baseline passes.
 */
export function overBaseline(
  rows: readonly FileDuration[],
  baseline: ReadonlyMap<string, number>,
): FileDuration[] {
  return rows.filter((row) => {
    const before = baseline.get(row.file);

    return (
      before !== undefined &&
      row.durationMs > before * GROWTH &&
      row.durationMs - before > SLACK_MS
    );
  });
}

function seconds(ms: number): string {
  return (ms / 1000).toFixed(1);
}

/** A markdown table of the files that take the longest. */
export function slowestFilesSummary(
  rows: readonly FileDuration[],
  baseline: ReadonlyMap<string, number> = new Map(),
): string {
  const slowest = rows
    .toSorted((a, b) => b.durationMs - a.durationMs)
    .slice(0, SLOWEST);

  return [
    "## Slowest unit files",
    "",
    "| File | Seconds | Baseline |",
    "| --- | --- | --- |",
    ...slowest.map((row) => {
      const before = baseline.get(row.file);

      return `| \`${row.file}\` | ${seconds(row.durationMs)} | ${before === undefined ? "new" : seconds(before)} |`;
    }),
    "",
  ].join("\n");
}

function readBaseline(path: string): Map<string, number> {
  return new Map(
    Object.entries(
      v.parse(baselineSchema, JSON.parse(readFileSync(path, "utf-8"))),
    ),
  );
}

function check(baselinePath: string, reportPath: string): number {
  const json = readFileSync(reportPath, "utf-8");
  const rows = durationsFromJson(json);
  const baseline = readBaseline(baselinePath);
  const grown = overBaseline(rows, baseline);
  const slow = slowTestsFromJson(json);

  process.stdout.write(slowestFilesSummary(rows, baseline));

  for (const row of grown) {
    process.stdout.write(
      `\nFile over its time budget: \`${row.file}\` took ${seconds(row.durationMs)} s, baseline ${seconds(baseline.get(row.file) ?? 0)} s.\n`,
    );
  }

  for (const test of slow) {
    process.stdout.write(
      `\nTest over half its timeout: \`${test.file}\` > ${test.test} took ${seconds(test.durationMs)} s.\n`,
    );
  }

  if (grown.length > 0 || slow.length > 0) {
    process.stdout.write(
      "\nMake the test faster or split it. After a deliberate change, refresh the baseline (docs/agents/tooling.md).\n",
    );

    return 1;
  }

  return 0;
}

function usage(): number {
  process.stderr.write(
    "usage: unit-durations --write|--check <durations.json> <report.json>\n",
  );

  return 1;
}

function main(): number {
  const [flag, baselinePath, reportPath] = process.argv.slice(2);

  if (baselinePath === undefined || reportPath === undefined) {
    return usage();
  }

  if (flag === "--check") {
    return check(baselinePath, reportPath);
  }

  if (flag !== "--write") {
    return usage();
  }

  const durations = Object.fromEntries(
    durationsFromJson(readFileSync(reportPath, "utf-8")).map((row) => [
      row.file,
      row.durationMs,
    ]),
  );

  writeFileSync(baselinePath, `${JSON.stringify(durations, null, 2)}\n`);

  return 0;
}

if (import.meta.main) {
  process.exitCode = main();
}
