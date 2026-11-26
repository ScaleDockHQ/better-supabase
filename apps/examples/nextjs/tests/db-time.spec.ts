import { expect, test } from "@playwright/test";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { Client } from "pg";

import { ROUTES } from "./routes.manifest";
import {
  openableRoutes,
  perfUser,
  recordPerf,
  signIn,
} from "./support/example-session";

// What the database does inside the calls of one route: per page, the
// statements PostgREST ran as the app's role, read back from
// `pg_stat_statements` (planning time on) and the function statistics
// (`track_functions = all`). Buffers and rows are the same on every run and
// carry the budgets; milliseconds sit next to them and only warn. Each route
// is rendered once to fill the caches, the statistics are reset and it is
// rendered again, so the numbers are those of a warm render. Run with
// `BSB_PERF_USER=member` for the member. Writes db-time-<user>.json.
//
// Buffers are also checked against `tests/db-time.baseline.<tier>.json`
// (`BSB_DB_TIME_TIER`, default `seed`), the committed buffers of each route
// as the admin: a route fails when it reads more than 25 percent and 64
// buffers over its baseline. `BSB_DB_TIME_UPDATE=1` rewrites the entries of
// the routes it ran, which is how a tier gets its first baseline.

const DATABASE_URL =
  process.env["BSB_DB_ADMIN_URL"] ??
  "postgresql://supabase_admin:postgres@127.0.0.1:21600/postgres";

/** Statements over this many milliseconds are a finding. */
const SLOW_STATEMENT_MS = 100;

/** A route may read this share of its baseline buffers more, plus the slack. */
const BUFFER_GROWTH = 1.25;
const BUFFER_SLACK = 64;

const user = perfUser();

const BASELINE = `tests/db-time.baseline.${process.env["BSB_DB_TIME_TIER"] ?? "seed"}.json`;

function readBaseline(): Record<string, number> {
  // SAFETY: this file is only written by writeBaseline, as route to buffers.
  return existsSync(BASELINE)
    ? (JSON.parse(readFileSync(BASELINE, "utf-8")) as Record<string, number>)
    : {};
}

function writeBaseline(route: string, buffers: number): void {
  const known = { ...readBaseline(), [route]: buffers };

  const sorted = Object.fromEntries(
    Object.entries(known).toSorted(([a], [b]) => a.localeCompare(b)),
  );

  mkdirSync(dirname(BASELINE), { recursive: true });

  writeFileSync(BASELINE, `${JSON.stringify(sorted, null, 2)}\n`);
}

const admin = new Client({ connectionString: DATABASE_URL });

interface Row {
  readonly query: string;
  readonly calls: string;
  readonly exec: number;
  readonly plan: number;
  readonly rows: string;
  readonly buffers: string;
}

test.beforeAll(async () => {
  await admin.connect();
  await admin.query("alter system set pg_stat_statements.track_planning = on");
  await admin.query("alter system set track_functions = 'all'");
  await admin.query("select pg_reload_conf()");
});

test.afterAll(async () => {
  await admin.query("alter system reset pg_stat_statements.track_planning");
  await admin.query("alter system reset track_functions");
  await admin.query("select pg_reload_conf()");
  await admin.end();
});

test.beforeEach(async ({ page }) => {
  await signIn(page, user);
});

async function statements(): Promise<readonly Row[]> {
  const { rows } = await admin.query<Row>(`
    select s.query, s.calls::text, s.total_exec_time as exec,
      s.total_plan_time as plan, s.rows::text,
      (s.shared_blks_hit + s.shared_blks_read)::text as buffers
    from pg_stat_statements s
    join pg_roles r on r.oid = s.userid
    where r.rolname in ('authenticated', 'anon')
      and s.query not like '%pg_stat_statements%'
      and s.query not ilike 'set %'
      and s.query not ilike 'select set_config%'
    order by s.total_exec_time + s.total_plan_time desc
  `);

  return rows;
}

for (const entry of openableRoutes(ROUTES)) {
  test(`${entry.route} database time as ${user}`, async ({ page }) => {
    const heading = page.getByRole("heading", { level: 1 }).first();

    await page.goto(entry.url);
    await expect(heading).toBeVisible({ timeout: 20_000 });

    await admin.query("select pg_stat_statements_reset()");
    await page.goto(entry.url);
    await expect(heading).toBeVisible({ timeout: 20_000 });
    await page.waitForTimeout(300);

    const rows = await statements();

    const sum = (pick: (row: Row) => number): number =>
      rows.reduce((total, row) => total + pick(row), 0);

    const slowest = Math.max(
      0,
      ...rows.map((row) => row.exec / Number(row.calls)),
    );

    recordPerf(`db-time-${user}.json`, entry.route, {
      statements: rows.length,
      calls: sum((row) => Number(row.calls)),
      execMs: Math.round(sum((row) => row.exec) * 100) / 100,
      planMs: Math.round(sum((row) => row.plan) * 100) / 100,
      rows: sum((row) => Number(row.rows)),
      buffers: sum((row) => Number(row.buffers)),
      slowestMs: Math.round(slowest * 100) / 100,
    });

    const buffers = sum((row) => Number(row.buffers));

    if (process.env["BSB_DB_TIME_UPDATE"] === "1") {
      if (user === "admin") {
        writeBaseline(entry.route, buffers);
      }
    } else if (user === "admin") {
      const baseline = readBaseline()[entry.route];

      if (baseline !== undefined) {
        expect(
          buffers,
          `${entry.route} reads ${buffers} buffers, baseline ${baseline}`,
        ).toBeLessThanOrEqual(baseline * BUFFER_GROWTH + BUFFER_SLACK);
      }
    }

    if (slowest > SLOW_STATEMENT_MS) {
      test
        .info()
        .annotations.push({
          type: "slow statement",
          description: `${rows[0]?.query.slice(0, 160)}`,
        });
    }
  });
}
