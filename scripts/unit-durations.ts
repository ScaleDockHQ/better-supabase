// Turns a Vitest JSON report into the duration map the unit shards pack on,
// or prints the slowest files for the coverage job's step summary.
//
//   node scripts/unit-durations.ts --write packages/better-supabase/tests/unit-durations.json report.json
//   node scripts/unit-durations.ts --summary report.json
import { readFileSync, writeFileSync } from "node:fs";
import * as v from "valibot";

const MARKER = "packages/better-supabase/";
const SLOWEST = 20;

const reportSchema = v.object({
  testResults: v.array(
    v.object({ name: v.string(), startTime: v.number(), endTime: v.number() }),
  ),
});

export interface FileDuration {
  readonly file: string;
  readonly durationMs: number;
}

type VitestJsonReport = v.InferOutput<typeof reportSchema>;

/** File durations from a parsed Vitest JSON report, in path order. */
function durationsFromReport(report: VitestJsonReport): FileDuration[] {
  return report.testResults
    .map((result) => {
      const name = result.name.replaceAll("\\", "/");
      const at = name.lastIndexOf(MARKER);

      return {
        file: at === -1 ? name : name.slice(at + MARKER.length),
        durationMs: Math.max(0, Math.round(result.endTime - result.startTime)),
      };
    })
    .toSorted((a, b) => a.file.localeCompare(b.file));
}

/** File durations from a Vitest `--reporter=json` document. */
export function durationsFromJson(json: string): FileDuration[] {
  return durationsFromReport(v.parse(reportSchema, JSON.parse(json)));
}

/** A markdown table of the files that take the longest. */
export function slowestFilesSummary(rows: readonly FileDuration[]): string {
  const slowest = rows
    .toSorted((a, b) => b.durationMs - a.durationMs)
    .slice(0, SLOWEST);

  const lines = [
    "## Slowest unit files",
    "",
    "| File | Seconds |",
    "| --- | --- |",
    ...slowest.map(
      (row) => `| \`${row.file}\` | ${(row.durationMs / 1000).toFixed(1)} |`,
    ),
    "",
  ];

  return lines.join("\n");
}

function usage(): number {
  process.stderr.write(
    "usage: unit-durations --write <out.json> <report.json> | --summary <report.json>\n",
  );

  return 1;
}

function main(): number {
  const [flag, first, second] = process.argv.slice(2);

  if (flag === "--summary") {
    if (first === undefined) {
      return usage();
    }

    process.stdout.write(
      slowestFilesSummary(durationsFromJson(readFileSync(first, "utf-8"))),
    );

    return 0;
  }

  if (flag !== "--write" || first === undefined || second === undefined) {
    return usage();
  }

  const durations = Object.fromEntries(
    durationsFromJson(readFileSync(second, "utf-8")).map((row) => [
      row.file,
      row.durationMs,
    ]),
  );

  writeFileSync(first, `${JSON.stringify(durations, null, 2)}\n`);

  return 0;
}

if (import.meta.main) {
  process.exitCode = main();
}
