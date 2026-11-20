import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";

// The library's test suite may shrink and may not grow past a small margin
// without a deliberate raise in `scripts/test-budget.json`. A long suite is
// the main cost of the unit job, so adding a test is a decision that shows up
// in this file's diff.
const BASELINE = new URL("test-budget.json", import.meta.url);
const ROOT = "packages/better-supabase/tests";
const MARGIN = 0.02;

interface Budget {
  readonly lines: number;
}

export function countLines(text: string): number {
  return text === "" ? 0 : text.split("\n").length - 1;
}

export function overBudget(lines: number, budget: number): boolean {
  return lines > Math.ceil(budget * (1 + MARGIN));
}

function measure(): number {
  const files = execFileSync("git", ["ls-files", ROOT], { encoding: "utf-8" })
    .split("\n")
    .filter((file) => /\.test(?:-d)?\.ts$/.test(file));

  return files.reduce(
    (sum, file) => sum + countLines(readFileSync(file, "utf-8")),
    0,
  );
}

function main(): void {
  const lines = measure();

  if (process.argv.includes("--update")) {
    writeFileSync(
      BASELINE,
      `${JSON.stringify({ lines } satisfies Budget, null, 2)}\n`,
    );
    process.stdout.write(`test budget set to ${lines} lines\n`);

    return;
  }

  // SAFETY: the file is written only by `--update` above.
  const budget = JSON.parse(readFileSync(BASELINE, "utf-8")) as Budget;

  if (overBudget(lines, budget.lines)) {
    process.stderr.write(
      `The library tests hold ${lines} lines, over the budget of ${budget.lines} (+${MARGIN * 100}%). Remove or merge tests, or raise it with \`node scripts/check-test-budget.ts --update\` and say why in the commit.\n`,
    );
    process.exitCode = 1;

    return;
  }

  process.stdout.write(
    `library tests: ${lines} lines, budget ${budget.lines}\n`,
  );
}

if (process.argv[1] === new URL(import.meta.url).pathname) {
  main();
}
