import type { Page } from "@playwright/test";
import type { DbStats } from "better-supabase";

import { expect, test } from "@playwright/test";
import { readFileSync, writeFileSync } from "node:fs";

import { ACTIONS } from "./actions.manifest";
import { ROUTES } from "./routes.manifest";
import {
  openableRoutes,
  perfUser,
  recordPerf,
  signIn,
} from "./support/example-session";

// Calls every action of the manifest once, as a browser would (a POST with the
// action's id in `Next-Action`), and records the database calls, waves and time
// of the request from the debug route, by action name. The ids come from the
// build's server reference manifest. Also records how many actions the build
// has and how many the manifest covers. Needs the production build with the
// testing API (see instant-nav.rig.md).

interface WorkerEntry {
  readonly moduleId?: string;
}

interface ReferenceEntry {
  readonly filename: string;
  readonly exportedName: string;
  readonly workers: Readonly<Record<string, WorkerEntry>>;
}

interface Known {
  readonly id: string;
  readonly file: string;
  readonly name: string;
  /** The routes of the pages that bundle the action. */
  readonly routes: readonly string[];
}

/** `app/[locale]/(app)/crm/deals/[id]/page` becomes `/crm/deals/[id]`. */
function routeOf(worker: string): string {
  const segments = worker
    .replace(/^app\//, "")
    .replace(/\/page$/, "")
    .split("/")
    .filter((part) => part !== "[locale]" && !/^\(.*\)$/.test(part));

  return `/${segments.join("/")}`;
}

function knownActions(): readonly Known[] {
  const manifest = JSON.parse(
    readFileSync(".next/server/server-reference-manifest.json", "utf-8"),
    // SAFETY: Next.js writes this file as { node: { [id]: entry } }.
  ) as { node: Record<string, ReferenceEntry> };

  return Object.entries(manifest.node).flatMap(([id, entry]) => {
    const file = entry.filename.replace(/^.*\/src\//, "");

    return file.endsWith("-actions.ts")
      ? [
          {
            id,
            file,
            name: entry.exportedName,
            routes: Object.keys(entry.workers)
              .filter((worker) => worker.endsWith("/page"))
              .map(routeOf),
          },
        ]
      : [];
  });
}

const known = knownActions();

const byKey = new Map(
  known.map((entry) => [`${entry.file}#${entry.name}`, entry]),
);

const urls = new Map(
  openableRoutes(ROUTES).map((entry) => [entry.route, entry.url]),
);

/**
 * The URL of a page that bundles the action. A page that does not carry the
 * action answers 409 ("unrecognized action"), so the listed page is used only
 * when the build bundles the action there.
 */
function pageFor(entry: Known, preferred?: string): string | undefined {
  const own = preferred === undefined ? undefined : urls.get(preferred);

  if (own !== undefined && entry.routes.includes(preferred ?? "")) {
    return own;
  }

  return entry.routes.flatMap((route) => urls.get(route) ?? []).at(0);
}

/** Names of actions that only read; the rest need arguments or write. */
const READS = /^(load|list|get|search|fetch|read|count|find|lookup|suggest)/;

const listed = new Set(
  ACTIONS.map((action) => `${action.file}#${action.name}`),
);

const generated = known.filter(
  (entry) =>
    !listed.has(`${entry.file}#${entry.name}`) && READS.test(entry.name),
);

const skipped = known.filter(
  (entry) =>
    !listed.has(`${entry.file}#${entry.name}`) && !READS.test(entry.name),
);

test.beforeEach(async ({ page }) => {
  await signIn(page, perfUser());
});

async function callAction(
  page: Page,
  key: string,
  entry: Known,
  preferred: string | undefined,
  args: readonly unknown[],
): Promise<void> {
  const url = pageFor(entry, preferred);

  expect(url, `no openable page bundles ${key}`).toBeDefined();
  await page.goto(url ?? "/");

  const reply = await page.request.post(url ?? "/", {
    headers: {
      "Next-Action": entry.id,
      "Content-Type": "text/plain;charset=UTF-8",
      Accept: "text/x-component",
    },
    data: JSON.stringify(args),
  });

  const requestId = reply.headers()["x-bsb-request-id"];
  const statsPath = reply.headers()["x-bsb-stats"];

  expect(requestId).toBeDefined();

  const stats = await page.request.get(statsPath ?? "");
  // SAFETY: the debug route answers with a DbStats object.
  const body = (await stats.json()) as DbStats;
  const entries = body.entries ?? [];
  const misses = entries.filter((e) => e.outcome === "miss").length;

  recordPerf(`actions-${perfUser()}.json`, key, {
    status: reply.status(),
    calls: body.calls,
    waves: body.waves,
    ms: body.ms,
    verifications: body.verifications,
    adminCalls: body.adminCalls,
    tables: body.tables.length,
    hits: entries.length - misses,
    misses,
    tagCalls: body.tagCalls ?? 0,
    expiredTags: body.expiredTags?.length ?? 0,
    keptBytes: entries.reduce((sum, e) => sum + (e.bytes ?? 0), 0),
  });
}

test("the manifest lists the actions the build has", () => {
  const covered = ACTIONS.filter((action) =>
    byKey.has(`${action.file}#${action.name}`),
  ).length;

  recordPerf("actions-coverage.json", "all", {
    actions: known.length,
    listed: covered,
    generatedReads: generated.length,
    covered: covered + generated.length,
    skippedNeedArguments: skipped.length,
  });

  // The actions a build has without a case: each is a read run with no
  // arguments or a write that needs arguments from a person.
  writeFileSync(
    `${process.env["BSB_PERF_DIR"] ?? "perf-results/example-perf"}/actions-skipped.json`,
    JSON.stringify(
      skipped.map((entry) => `${entry.file}#${entry.name}`).toSorted(),
      null,
      2,
    ),
  );
  expect(covered).toBe(ACTIONS.length);
});

for (const action of [...ACTIONS].toSorted(
  (a, b) => Number(a.mutates) - Number(b.mutates),
)) {
  test(`${action.name} database cost`, async ({ page }) => {
    const entry = byKey.get(`${action.file}#${action.name}`);
    expect(entry).toBeDefined();

    await callAction(
      page,
      action.name,
      entry!,
      action.page,
      action.resolve ? await action.resolve() : action.args,
    );
  });
}

for (const entry of generated) {
  test(`${entry.file}#${entry.name} database cost`, async ({ page }) => {
    await callAction(page, `${entry.file}#${entry.name}`, entry, undefined, []);
  });
}
