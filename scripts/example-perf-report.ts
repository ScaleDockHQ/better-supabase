// Merges the Next.js example's numbers into one line per route: first load and
// server bundle (tests/next-build baselines), the HTML payload, the database
// budget and the cold, warm and client timings that budgets.spec.ts and
// cold-warm.spec.ts leave in test-results/example-perf, and the SCALE_MS lines
// of a pgTAP scale run. Run with
// `node scripts/example-perf-report.ts [--scale <pgtap-output>] [--json]`.
import { existsSync, readFileSync } from "node:fs";
import { argv } from "node:process";

import { ROUTES } from "../apps/examples/nextjs/tests/routes.manifest.ts";

interface Size {
  readonly raw: number;
  readonly gzip: number;
  readonly brotli: number;
}

type Sizes = Readonly<Record<string, Size>>;

type Measures = Readonly<Record<string, Readonly<Record<string, number>>>>;

export interface RouteLine {
  readonly route: string;
  readonly archetype: string;
  readonly firstLoadGzip: number | null;
  readonly serverGzip: number | null;
  readonly htmlGzip: number | null;
  readonly calls: number | null;
  readonly waves: number | null;
  readonly maxCalls: number;
  readonly maxWaves: number;
  readonly coldMs: number | null;
  readonly warmMs: number | null;
  readonly clientMs: number | null;
  readonly scale: boolean;
}

export interface PerfInputs {
  readonly firstLoad: Sizes;
  readonly server: Sizes;
  readonly payload: Sizes;
  readonly budgets: Measures;
  readonly coldWarm: Measures;
}

const key = (route: string): string =>
  `/[locale]/(app)${route === "/" ? "" : route}/page`;

const htmlKey = (route: string): string =>
  `en${route === "/" ? "/index" : route}.html`;

export const buildReport = (inputs: PerfInputs): readonly RouteLine[] =>
  ROUTES.map((entry) => {
    const budget = inputs.budgets[entry.route];
    const timing = inputs.coldWarm[entry.route];

    return {
      route: entry.route,
      archetype: entry.archetype,
      firstLoadGzip: inputs.firstLoad[key(entry.route)]?.gzip ?? null,
      serverGzip: inputs.server[key(entry.route)]?.gzip ?? null,
      htmlGzip: inputs.payload[htmlKey(entry.route)]?.gzip ?? null,
      calls: budget?.["calls"] ?? null,
      waves: budget?.["waves"] ?? null,
      maxCalls: entry.maxCalls,
      maxWaves: entry.maxWaves,
      coldMs: timing?.["cold"] ?? null,
      warmMs: timing?.["warm"] ?? null,
      clientMs: timing?.["client"] ?? null,
      scale: entry.scale,
    };
  });

/** `SCALE_MS name=value` and `SCALE_CALLS name=value` lines of a pgTAP run. */
export const scaleLines = (output: string): readonly string[] =>
  output
    .split("\n")
    .map((line) => /(SCALE_(?:MS|CALLS) \S+=\d+)/.exec(line)?.[1])
    .filter((line): line is string => line !== undefined);

const read = <T>(path: string, fallback: T): T =>
  // SAFETY: these files are written by the repo's own tests and scripts.
  existsSync(path) ? (JSON.parse(readFileSync(path, "utf-8")) as T) : fallback;

const cell = (value: number | null, unit = ""): string =>
  value === null ? "-" : `${value}${unit}`;

export const formatLine = (line: RouteLine): string =>
  [
    line.route,
    line.archetype,
    `first load ${cell(line.firstLoadGzip, " B gz")}`,
    `server ${cell(line.serverGzip, " B gz")}`,
    `html ${cell(line.htmlGzip, " B gz")}`,
    `calls ${cell(line.calls)}/${line.maxCalls}`,
    `waves ${cell(line.waves)}/${line.maxWaves}`,
    `cold ${cell(line.coldMs, " ms")}`,
    `warm ${cell(line.warmMs, " ms")}`,
    `client ${cell(line.clientMs, " ms")}`,
    line.scale ? "scale" : "",
  ]
    .filter((part) => part !== "")
    .join(" | ");

if (argv[1] === import.meta.filename) {
  const perf = "apps/examples/nextjs/test-results/example-perf";

  const report = buildReport({
    firstLoad: read("tests/next-build/baseline.json", {}),
    server: read("tests/next-build/server-baseline.json", {}),
    payload: read("tests/next-build/payload-baseline.json", {}),
    budgets: read(`${perf}/budgets.json`, {}),
    coldWarm: read(`${perf}/cold-warm.json`, {}),
  });

  const scaleFile = argv.includes("--scale")
    ? argv[argv.indexOf("--scale") + 1]
    : undefined;

  const scale = scaleFile ? scaleLines(readFileSync(scaleFile, "utf-8")) : [];

  if (argv.includes("--json")) {
    console.log(JSON.stringify({ routes: report, scale }, null, 2));
  } else {
    for (const line of report) {
      console.log(formatLine(line));
    }

    for (const line of scale) {
      console.log(line);
    }
  }
}
