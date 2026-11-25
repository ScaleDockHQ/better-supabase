// Merges the Next.js example's numbers into one line per route: first load and
// server bundle (tests/next-build baselines), the HTML payload, the database
// budget and the cold, warm and client timings that budgets.spec.ts and
// cold-warm.spec.ts leave in perf-results/example-perf, and the SCALE_MS lines
// of a pgTAP scale run. It also summarizes the page, action and auth
// measurements (pages-<user>.json, actions-<user>.json, auth-cost.json). Run with
// `node scripts/example-perf-report.ts [--scale <pgtap-output>] [--json]`;
// `--write` saves apps/examples/nextjs/perf/report.json and
// docs/agents/example-perf.md.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
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
  readonly serverRaw: number | null;
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
  readonly server: Readonly<Record<string, { readonly raw: number }>>;
  readonly payload: Sizes;
  readonly budgets: Measures;
  readonly coldWarm: Measures;
  /** Page render cost by user, from measure-pages.spec.ts. */
  readonly pages?: Readonly<Record<string, Measures>>;
  /** Action cost by user, from actions.spec.ts. */
  readonly actions?: Readonly<Record<string, Measures>>;
  readonly auth?: Measures;
  readonly actionCoverage?: Measures;
  /** Cache tiers by route and scenario, from cache.spec.ts. */
  readonly cache?: Measures;
  /**
   * Uncompressed first-load JS per route, from
   * `.next/diagnostics/route-bundle-stats.json`.
   */
  readonly firstLoadJs?: Readonly<Record<string, number>>;
}

export interface Worst {
  readonly name: string;
  readonly value: number;
}

export interface Summary {
  readonly user: string;
  readonly routes: number;
  readonly calls: number;
  readonly worstCalls: readonly Worst[];
  readonly worstWaves: readonly Worst[];
  readonly worstWarmMs: readonly Worst[];
  readonly overOneVerification: readonly string[];
  readonly adminCallRoutes: readonly string[];
}

const worst = (
  measures: Measures,
  field: string,
  count = 10,
): readonly Worst[] =>
  Object.entries(measures)
    .map(([name, values]) => ({ name, value: values[field] ?? 0 }))
    .toSorted((a, b) => b.value - a.value)
    .slice(0, count);

/** Totals and the worst routes of one user's page measurements. */
export const summarizePages = (user: string, pages: Measures): Summary => ({
  user,
  routes: Object.keys(pages).length,
  calls: Object.values(pages).reduce((sum, v) => sum + (v["calls"] ?? 0), 0),
  worstCalls: worst(pages, "calls"),
  worstWaves: worst(pages, "waves"),
  worstWarmMs: worst(pages, "warmMs"),
  overOneVerification: Object.entries(pages)
    .filter(([, v]) => (v["verifications"] ?? 0) > 1)
    .map(([name]) => name),
  adminCallRoutes: Object.entries(pages)
    .filter(([, v]) => (v["adminCalls"] ?? 0) > 0)
    .map(([name]) => name),
});

const table = (rows: readonly (readonly (string | number)[])[]): string =>
  rows.map((row) => `| ${row.join(" | ")} |`).join("\n");

/** The scenarios of cache.spec.ts, in the order of a visitor's day. */
const CACHE_SCENARIOS = ["hard1", "hard2", "user2", "restart"] as const;

/** `served` of `visits` as a percentage, or `-` with no visits. */
const ratio = (served: number, visits: number): string =>
  visits === 0 ? "-" : `${Math.round((served / visits) * 100)}%`;

/**
 * The Caching section: calls per scenario for each route, the hit ratio of each
 * tier on the second hard load, and the writes that expire the most tags. A
 * private or public entry records only its miss, so its visits are the most
 * misses any scenario saw and its hits are visits minus misses.
 */
export const cacheLines = (
  cache: Measures,
  actions: Measures | undefined,
): readonly string[] => {
  const routes = Object.entries(cache);

  if (routes.length === 0) {
    return [];
  }

  const sum = (scenario: string, field: string): number =>
    routes.reduce(
      (total, [, v]) => total + (v[`${scenario}_${field}`] ?? 0),
      0,
    );

  const visits = (field: string): number =>
    routes.reduce(
      (total, [, v]) =>
        total +
        Math.max(...CACHE_SCENARIOS.map((s) => v[`${s}_${field}`] ?? 0)),
      0,
    );

  const privateVisits = visits("privateMisses");
  const publicVisits = visits("publicMisses");

  const tiers = (scenario: string): readonly (string | number)[] => {
    const remote = sum(scenario, "remoteHits");
    const remoteAll = remote + sum(scenario, "remoteMisses");
    const kept = sum(scenario, "keptHits");
    const keptAll = kept + sum(scenario, "keptMisses");

    return [
      scenario,
      sum(scenario, "calls"),
      ratio(remote, remoteAll),
      ratio(kept, keptAll),
      ratio(privateVisits - sum(scenario, "privateMisses"), privateVisits),
      ratio(publicVisits - sum(scenario, "publicMisses"), publicVisits),
      sum(scenario, "handlerBytesRead"),
    ];
  };

  const writes = Object.entries(actions ?? {})
    .map(([name, v]) => ({ name, value: v["expiredTags"] ?? 0 }))
    .filter((w) => w.value > 0)
    .toSorted((a, b) => b.value - a.value)
    .slice(0, 10);

  return [
    "## Caching",
    "",
    `${routes.length} routes, each loaded as a hard load, a second hard load, a second user of the organization and on a restarted server (tests/cache.spec.ts). Calls are database calls summed over the routes; a ratio is the share of lookups a tier served.`,
    "",
    table([
      [
        "Scenario",
        "Calls",
        "Remote",
        "Kept",
        "Private",
        "Public",
        "Remote bytes read",
      ],
      ["---", "---", "---", "---", "---", "---", "---"],
      ...CACHE_SCENARIOS.map(tiers),
    ]),
    "",
    "Calls saved by the second hard load, by route:",
    "",
    table([
      ["Route", "Hard 1", "Hard 2", "User 2", "Restart", "Kept bytes"],
      ["---", "---", "---", "---", "---", "---"],
      ...routes.map(([route, v]) => [
        route,
        v["hard1_calls"] ?? "-",
        v["hard2_calls"] ?? "-",
        v["user2_calls"] ?? "-",
        v["restart_calls"] ?? "-",
        v["hard2_keptBytes"] ?? "-",
      ]),
    ]),
    "",
    writes.length === 0
      ? "No measured action expired a tag."
      : "Actions that expire the most tags:",
    "",
    ...(writes.length === 0
      ? []
      : [
          table([
            ["Action", "Tags"],
            ["---", "---"],
            ...writes.map((w) => [w.name, w.value]),
          ]),
          "",
        ]),
  ];
};

/** The markdown of docs/agents/example-perf.md. */
export const markdown = (inputs: PerfInputs, label: string): string => {
  const lines = [
    "# Example performance",
    "",
    `Numbers of the Next.js example, taken on the production build with the testing API (${label}). Written by \`pnpm example:perf-report --write\`; do not edit by hand.`,
    "",
  ];

  for (const [user, pages] of Object.entries(inputs.pages ?? {})) {
    const summary = summarizePages(user, pages);

    lines.push(
      `## Pages as ${user}`,
      "",
      `${summary.routes} routes measured, ${summary.calls} database calls in total for one warm render of each.`,
      "",
      "Most database calls:",
      "",
      table([
        ["Route", "Calls"],
        ["---", "---"],
        ...summary.worstCalls.map((w) => [w.name, w.value]),
      ]),
      "",
      "Slowest warm renders (ms, wall time):",
      "",
      table([
        ["Route", "Ms"],
        ["---", "---"],
        ...summary.worstWarmMs.map((w) => [w.name, w.value]),
      ]),
      "",
      `Routes with more than one token verification: ${summary.overOneVerification.length === 0 ? "none" : summary.overOneVerification.join(", ")}.`,
      "",
      `Routes with service-role calls: ${summary.adminCallRoutes.length === 0 ? "none" : summary.adminCallRoutes.join(", ")}.`,
      "",
    );
  }

  for (const [user, actions] of Object.entries(inputs.actions ?? {})) {
    lines.push(
      `## Actions as ${user}`,
      "",
      table([
        ["Action", "Calls", "Waves", "Ms", "Tables"],
        ["---", "---", "---", "---", "---"],
        ...Object.entries(actions).map(([name, v]) => [
          name,
          v["calls"] ?? "-",
          v["waves"] ?? "-",
          v["ms"] ?? "-",
          v["tables"] ?? "-",
        ]),
      ]),
      "",
    );
  }

  const timings = Object.values(inputs.coldWarm);

  if (timings.length > 0) {
    const median = (field: string): number =>
      timings.map((t) => t[field] ?? 0).toSorted((a, b) => a - b)[
        Math.floor(timings.length / 2)
      ] ?? 0;

    lines.push(
      "## Cold, warm and client navigation (admin)",
      "",
      `${timings.length} routes. Median first hit after a server start ${median("cold")} ms, second hit ${median("warm")} ms, client navigation after prefetch ${median("client")} ms. Slowest first hits:`,
      "",
      table([
        ["Route", "Cold ms"],
        ["---", "---"],
        ...worst(inputs.coldWarm, "cold", 5).map((w) => [w.name, w.value]),
      ]),
      "",
    );
  }

  const sizes = Object.entries(inputs.firstLoadJs ?? {}).toSorted(
    (a, b) => b[1] - a[1],
  );

  if (sizes.length > 0) {
    const median = sizes[Math.floor(sizes.length / 2)]?.[1] ?? 0;

    lines.push(
      "## First-load JavaScript",
      "",
      `${sizes.length} routes, median ${median} B uncompressed. Largest:`,
      "",
      table([
        ["Route", "Bytes"],
        ["---", "---"],
        ...sizes.slice(0, 10).map(([route, bytes]) => [route, bytes]),
      ]),
      "",
    );
  }

  const coverage = inputs.actionCoverage?.["all"];

  if (coverage) {
    lines.push(
      `Actions in the build: ${coverage["actions"]}; measured: ${coverage["covered"]}; not measured: ${coverage["uncovered"]}.`,
      "",
    );
  }

  lines.push(...cacheLines(inputs.cache ?? {}, inputs.actions?.["admin"]));

  if (inputs.auth) {
    lines.push(
      "## Authentication and permissions",
      "",
      table([
        [
          "Scenario",
          "Wall ms",
          "Calls",
          "Verifications",
          "Proxy ms",
          "Auth ms",
        ],
        ["---", "---", "---", "---", "---", "---"],
        ...Object.entries(inputs.auth).map(([name, v]) => [
          name,
          v["wallMs"] ?? "-",
          v["calls"] ?? "-",
          v["verifications"] ?? "-",
          v["timing_bsb-proxy"] ?? "-",
          v["timing_bsb-auth"] ?? "-",
        ]),
      ]),
      "",
    );
  }

  return lines.join("\n");
};

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
      serverRaw: inputs.server[key(entry.route)]?.raw ?? null,
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
    `server ${cell(line.serverRaw, " B")}`,
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
  const perf = "apps/examples/nextjs/perf-results/example-perf";

  const users = ["admin", "member"] as const;

  const byUser = (prefix: string): Record<string, Measures> =>
    Object.fromEntries(
      users.flatMap((user) => {
        const measures = read<Measures>(`${perf}/${prefix}-${user}.json`, {});

        return Object.keys(measures).length === 0 ? [] : [[user, measures]];
      }),
    );

  const inputs: PerfInputs = {
    firstLoad: read("tests/next-build/baseline.json", {}),
    server: read("tests/next-build/server-baseline.json", {}),
    payload: read("tests/next-build/payload-baseline.json", {}),
    budgets: read(`${perf}/budgets.json`, {}),
    coldWarm: read(`${perf}/cold-warm.json`, {}),
    pages: byUser("pages"),
    actions: byUser("actions"),
    auth: read(`${perf}/auth-cost.json`, {}),
    actionCoverage: read(`${perf}/actions-coverage.json`, {}),
    cache: read(`${perf}/cache.json`, {}),
    firstLoadJs: read("apps/examples/nextjs/perf/first-load.json", {}),
  };

  const report = buildReport(inputs);

  const scaleFile = argv.includes("--scale")
    ? argv[argv.indexOf("--scale") + 1]
    : undefined;

  const scale = scaleFile ? scaleLines(readFileSync(scaleFile, "utf-8")) : [];

  if (argv.includes("--write")) {
    const label = argv.includes("--label")
      ? (argv[argv.indexOf("--label") + 1] ?? "seed tier")
      : "seed tier";

    const target = "apps/examples/nextjs/perf/report.json";
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(
      target,
      JSON.stringify({ label, routes: report, scale, ...inputs }, null, 2),
    );
    writeFileSync(
      "docs/agents/example-perf.md",
      `${markdown(inputs, label)}\n`,
    );
  } else if (argv.includes("--json")) {
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
