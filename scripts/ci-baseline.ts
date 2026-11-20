// Prints waiting, setup and running time per CI job at p50 and p95 for the last runs of a workflow.
// Usage: node scripts/ci-baseline.ts [--runs 150] [--workflow ci.yml] [--event pull_request]
import { spawnSync } from "node:child_process";
import { argv, exit } from "node:process";
import { parseArgs } from "node:util";

interface Step {
  readonly name: string;
  readonly started_at: string | null;
  readonly completed_at: string | null;
}

interface Job {
  readonly name: string;
  readonly conclusion: string | null;
  readonly created_at: string;
  readonly started_at: string;
  readonly completed_at: string | null;
  readonly steps?: readonly Step[];
}

interface Run {
  readonly id: number;
  readonly conclusion: string | null;
}

/**
 * Steps that install tools and restore caches count as setup, everything after
 * them as running.
 */
const SETUP_STEP =
  /^(Set up job|Run actions\/checkout|Checkout|Set up|Run \.\/\.github\/actions\/setup|Post |Complete job)/;

export function percentile(values: readonly number[], p: number): number {
  if (values.length === 0) {
    return 0;
  }

  const sorted = values.toSorted((a, b) => a - b);

  const index = Math.min(
    sorted.length - 1,
    Math.max(0, Math.ceil((p / 100) * sorted.length) - 1),
  );

  return sorted[index] ?? 0;
}

function seconds(from: string | null, to: string | null): number {
  if (from === null || to === null) {
    return 0;
  }

  return Math.max(0, (Date.parse(to) - Date.parse(from)) / 1000);
}

function gh(args: readonly string[]): string {
  const result = spawnSync("gh", args, {
    encoding: "utf-8",
    maxBuffer: 256 * 1024 * 1024,
  });

  if (result.status !== 0) {
    console.error(result.stderr || "gh failed. Is it installed and logged in?");
    exit(2);
  }

  return result.stdout;
}

interface JobTimes {
  readonly waiting: number;
  readonly setup: number;
  readonly running: number;
}

/**
 * Splits a job into time spent waiting for a runner, in setup steps and in the
 * rest.
 */
export function splitJob(job: Job): JobTimes {
  const waiting = seconds(job.created_at, job.started_at);
  const total = seconds(job.started_at, job.completed_at);

  const setup = (job.steps ?? [])
    .filter((step) => SETUP_STEP.test(step.name))
    .reduce(
      (sum, step) => sum + seconds(step.started_at, step.completed_at),
      0,
    );

  return { waiting, setup, running: Math.max(0, total - setup) };
}

function generic(name: string): string {
  return name
    .replaceAll(/\s*\(\d+\/\d+\)/g, "")
    .replaceAll(/\s+\d+\/\d+$/g, "");
}

if (import.meta.main) {
  const { values } = parseArgs({
    args: argv.slice(2),
    options: {
      runs: { type: "string", default: "150" },
      workflow: { type: "string", default: "ci.yml" },
      event: { type: "string", default: "pull_request" },
    },
  });

  // SAFETY: `gh run list --json databaseId,conclusion` prints exactly these fields.
  const runs = JSON.parse(
    gh([
      "run",
      "list",
      "--workflow",
      values.workflow,
      "--event",
      values.event,
      "--limit",
      values.runs,
      "--json",
      "databaseId,conclusion",
    ]),
  ) as { databaseId: number; conclusion: string | null }[];

  const finished: Run[] = runs
    .filter((run) => run.conclusion !== "cancelled" && run.conclusion !== "")
    .map((run) => ({ id: run.databaseId, conclusion: run.conclusion }));

  const byJob = new Map<
    string,
    { waiting: number[]; setup: number[]; running: number[]; failed: number }
  >();

  for (const run of finished) {
    const lines = gh([
      "api",
      "--paginate",
      `repos/{owner}/{repo}/actions/runs/${run.id}/jobs?per_page=100`,
      "--jq",
      ".jobs[]",
    ])
      .split("\n")
      .filter((line) => line.trim() !== "");

    // SAFETY: `gh api --jq .jobs[]` prints one job object per line with the Job fields.
    const jobs = lines.map((line) => JSON.parse(line) as Job);

    for (const job of jobs) {
      if (job.conclusion === "skipped" || job.completed_at === null) {
        continue;
      }

      const key = generic(job.name);

      const entry = byJob.get(key) ?? {
        waiting: [],
        setup: [],
        running: [],
        failed: 0,
      };

      const parts = splitJob(job);

      entry.waiting.push(parts.waiting);
      entry.setup.push(parts.setup);
      entry.running.push(parts.running);
      entry.failed += job.conclusion === "failure" ? 1 : 0;
      byJob.set(key, entry);
    }
  }

  const rows = [...byJob.entries()]
    .map(([name, entry]) => ({
      name,
      count: entry.running.length,
      failed: entry.failed,
      wait50: percentile(entry.waiting, 50),
      setup50: percentile(entry.setup, 50),
      setup95: percentile(entry.setup, 95),
      run50: percentile(entry.running, 50),
      run95: percentile(entry.running, 95),
    }))
    .toSorted((a, b) => b.run95 + b.setup95 - (a.run95 + a.setup95));

  console.log(
    `${values.workflow} (${values.event}): ${finished.length} finished runs, seconds`,
  );
  console.log(
    "job".padEnd(44) +
      ["n", "fail", "wait50", "setup50", "setup95", "run50", "run95"]
        .map((title) => title.padStart(9))
        .join(""),
  );

  for (const row of rows) {
    console.log(
      row.name.slice(0, 43).padEnd(44) +
        [
          row.count,
          row.failed,
          row.wait50,
          row.setup50,
          row.setup95,
          row.run50,
          row.run95,
        ]
          .map((value) => String(Math.round(value)).padStart(9))
          .join(""),
    );
  }
}
