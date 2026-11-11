import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { renderBlocks } from "../../src/sql/render.ts";
import { dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const SCRATCH = `bsb_partition_${process.pid}`;
const LOG = "better_supabase.audit_events";

const scratchUrl = (): string => {
  const url = new URL(dbUrl);
  url.pathname = `/${SCRATCH}`;

  return url.toString();
};

/**
 * The few `auth` objects the audit module reads, in a database with no Auth
 * service.
 */
const AUTH_STUBS = `
  create schema if not exists auth;
  create table auth.users (id uuid primary key default gen_random_uuid(), email text);
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(current_setting('request.jwt.claims', true)::jsonb->>'sub', '')::uuid $$;
  create function auth.jwt() returns jsonb language sql stable as
    $$ select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb) $$;
  create function auth.role() returns text language sql stable as $$ select 'authenticated' $$;
`;

/** Schema files first, then data files: the data files repeat event triggers. */
const inApplyOrder = <T extends { readonly kind: string }>(
  files: readonly T[],
): readonly T[] => [
  ...files.filter((file) => file.kind === "schema"),
  ...files.filter((file) => file.kind !== "schema" && file.kind !== "test"),
];

const SEED_ROWS = 6000;

const ignoreTerminatedIdleClient = (error: Error & { code?: string }) => {
  if (error.code !== "57P01") {
    throw error;
  }
};

describe.skipIf(!live)("convert_audit_log_to_partitioned", () => {
  const admin = new Pool({ connectionString: dbUrl, max: 1 });
  admin.on("error", ignoreTerminatedIdleClient);
  let pool: Pool;

  const one = async <T>(sql: string): Promise<T> =>
    (await pool.query(sql)).rows[0] as T;

  beforeAll(async () => {
    await admin.query(`drop database if exists ${SCRATCH} with (force)`);
    await admin.query(`create database ${SCRATCH}`);
    pool = new Pool({ connectionString: scratchUrl(), max: 4 });
    pool.on("error", ignoreTerminatedIdleClient);
    await pool.query(AUTH_STUBS);

    // The log as an app that never set the option has it, then the procedure
    // an app that turns the option on gets.
    for (const file of inApplyOrder(renderBlocks(["audit"], {}))) {
      await pool.query(file.contents);
    }

    // `sql upgrade` after turning the option on: the module reruns over the
    // existing log, which stays unpartitioned, and adds the procedure.
    for (const file of inApplyOrder(
      renderBlocks(["audit"], {
        rerunnable: true,
        modules: { audit: { options: { partitioned: true } } },
      }),
    )) {
      await pool.query(file.contents);
    }

    await pool.query(
      `insert into ${LOG} (op, event_type, idempotency_key, occurred_at)
       select 'event', 'seed.' || (n % 7), 'seed-' || n,
              now() - make_interval(days => n % 150)
       from generate_series(1, ${SEED_ROWS}) n`,
    );
    await pool.query(`analyze ${LOG}`);
  });

  afterAll(async () => {
    await pool.end();
    await admin.query(`drop database if exists ${SCRATCH} with (force)`);
    await admin.end();
  });

  it("keeps every row, the sequence and the policies, and takes writes during the copy", async () => {
    const before = await one<{ n: string; max: string }>(
      `select count(*) as n, max(id) as max from ${LOG}`,
    );

    const policiesBefore = await one<{ names: string[] }>(
      `select coalesce(array_agg(policyname order by policyname), '{}') as names
       from pg_policies where schemaname = 'better_supabase' and tablename = 'audit_events'`,
    );

    const feed = { writing: true };
    let written = 0;

    const writer = (async () => {
      while (feed.writing) {
        await pool.query(
          `insert into ${LOG} (op, event_type, idempotency_key) values ('event', 'live.write', $1)`,
          [`live-${written}`],
        );
        written += 1;
      }
    })();

    try {
      await pool.query(
        "call better_supabase.convert_audit_log_to_partitioned(500, false)",
      );
    } finally {
      feed.writing = false;
      await writer;
    }

    const kind = await one<{ relkind: string }>(
      `select relkind from pg_class where oid = '${LOG}'::regclass`,
    );

    expect(kind.relkind).toBe("p");
    expect(written).toBeGreaterThan(0);

    const after = await one<{ n: string; distinct: string; max: string }>(
      `select count(*) as n, count(distinct id) as distinct, max(id) as max from ${LOG}`,
    );

    expect(Number(after.n)).toBe(Number(before.n) + written);
    expect(after.distinct).toBe(after.n);
    expect(Number(after.max)).toBeGreaterThanOrEqual(Number(before.max));

    const unpartitioned = await one<{ n: string }>(
      "select count(*) as n from better_supabase.audit_events_unpartitioned",
    );

    // Writes after the swap land in the new table only.
    expect(Number(unpartitioned.n)).toBeGreaterThanOrEqual(Number(before.n));
    expect(Number(unpartitioned.n)).toBeLessThanOrEqual(Number(after.n));

    const next = await one<{ id: string }>(
      `insert into ${LOG} (op, event_type) values ('event', 'after.swap') returning id`,
    );

    expect(Number(next.id)).toBeGreaterThan(Number(after.max));

    const policiesAfter = await one<{ names: string[] }>(
      `select coalesce(array_agg(policyname order by policyname), '{}') as names
       from pg_policies where schemaname = 'better_supabase' and tablename = 'audit_events'`,
    );

    expect(policiesAfter.names).toEqual(policiesBefore.names);

    const triggers = await one<{ n: string }>(
      `select count(*) as n from pg_trigger where tgrelid = '${LOG}'::regclass and not tgisinternal`,
    );

    expect(Number(triggers.n)).toBeGreaterThan(0);

    const idempotency = await one<{ def: string }>(
      `select indexdef as def from pg_indexes
       where schemaname = 'better_supabase' and tablename = 'audit_events' and indexdef ilike '%idempotency_key%'`,
    );

    expect(idempotency.def).toContain("occurred_at");
  });

  it("prunes partitions for a date range and rerunning changes nothing", async () => {
    const plan = (
      await pool.query(
        `explain (analyze, costs off, timing off, summary off) select count(*) from ${LOG}
         where occurred_at between now() - interval '10 days' and now()`,
      )
    ).rows
      .map((row: { "QUERY PLAN": string }) => row["QUERY PLAN"])
      .join("\n");

    const scanned = [
      ...plan.matchAll(/Scan(?: using \S+)? on (?:better_supabase\.)?(\S+)/g),
    ].map((match) => match[1]!);

    const months = scanned.filter((name) => /_p\d{6}$/.test(name));

    const total = await one<{ n: string }>(
      `select count(*) as n from pg_inherits where inhparent = '${LOG}'::regclass`,
    );

    expect(months.length).toBeGreaterThan(0);
    // A closed range reads the months it touches, not the 3 months ahead.
    expect(months.length).toBeLessThanOrEqual(2);
    expect(Number(total.n)).toBeGreaterThan(months.length + 1);

    const rows = await one<{ n: string }>(`select count(*) as n from ${LOG}`);
    await pool.query(
      "call better_supabase.convert_audit_log_to_partitioned(500, false)",
    );
    expect(
      (await one<{ n: string }>(`select count(*) as n from ${LOG}`)).n,
    ).toBe(rows.n);
  });
});
