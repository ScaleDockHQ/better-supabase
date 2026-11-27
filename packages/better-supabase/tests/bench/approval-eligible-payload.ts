// approval_eligible_ids the way a multi-tenant page payload reads it, against the
// local stack: the caller owns 14 of 60 tenants with 2,400 pending requests in
// all. A policy that asks per member tenant plus once without a tenant runs 15
// sets per scan, and a payload scans the requests table three times in one
// read-only transaction. The fixture is committed so the reads run without a
// transaction id, as PostgREST reads do, and removed at the end.
//   pnpm env:local && node tests/bench/approval-eligible-payload.ts [--runs 7] [--json]
import { Client } from "pg";

import { summarize } from "./stats.ts";

const TENANTS = 60;
const OWNED = 14;
const PER_TENANT = 40;
const SCANS = 3;
const ME = "00000000-0000-4000-8000-0000000000a1";
const REQUESTER = "00000000-0000-4000-8000-0000000000a2";
const KIND = "bench_payload";

const runsAt = process.argv.indexOf("--runs");
const runs = runsAt === -1 ? 7 : Number(process.argv[runsAt + 1]);
const asJson = process.argv.includes("--json");
const url = process.env["SUPABASE_DB_URL"];

if (!url) {
  throw new Error("SUPABASE_DB_URL is not set; run pnpm env:local");
}

const tenant = (n: number): string =>
  `00000000-0000-4000-8000-${(0xbe_00_00_00_00_00 + n).toString(16)}`;

const tenants = Array.from({ length: TENANTS }, (_, n) => tenant(n + 1));
const owned = tenants.slice(0, OWNED);

const client = new Client({ connectionString: url });

await client.connect();

const cleanup = async (): Promise<void> => {
  await client.query(
    `delete from better_supabase.approval_requests where subject_type = $1`,
    [KIND],
  );
  await client.query(
    "delete from public.organizations where id = any($1::uuid[])",
    [tenants],
  );
};

const claims = JSON.stringify({ sub: ME, role: "authenticated" });

const hasSetForm = async (): Promise<boolean> => {
  const { rows } = await client.query<{ found: boolean }>(
    "select to_regprocedure('better_supabase.approval_eligible_ids_in(uuid[])') is not null as found",
  );

  return rows[0]?.found === true;
};

/**
 * Runs `body` in one read-only transaction as the caller and returns its
 * milliseconds and calls.
 */
const timed = async (
  body: () => Promise<unknown>,
): Promise<{ ms: number; calls: Record<string, number> }> => {
  await client.query("begin read only");
  await client.query("set local track_functions = 'all'");
  await client.query(
    "select set_config('request.jwt.claims', $1, true), set_config('request.jwt.claim.sub', $2, true)",
    [claims, ME],
  );
  await client.query("set local role authenticated");

  const before = await client.query<{ funcname: string; calls: string }>(
    "select funcname, calls from pg_stat_xact_user_functions where schemaname = 'better_supabase'",
  );

  const started = performance.now();

  await body();

  const ms = performance.now() - started;

  const after = await client.query<{ funcname: string; calls: string }>(
    "select funcname, calls from pg_stat_xact_user_functions where schemaname = 'better_supabase'",
  );

  await client.query("rollback");

  const base = new Map(
    before.rows.map((row) => [row.funcname, Number(row.calls)]),
  );

  const calls: Record<string, number> = {};

  for (const row of after.rows) {
    const delta = Number(row.calls) - (base.get(row.funcname) ?? 0);

    if (delta > 0) {
      calls[row.funcname] = delta;
    }
  }

  return { ms, calls };
};

const perTenantPolicy = `select count(*) from (
  select better_supabase.approval_eligible_ids(m) from unnest($1::uuid[]) m
  union all
  select better_supabase.approval_eligible_ids()
) x`;

try {
  await cleanup();
  await client.query(
    `insert into public.organizations (id, name, slug)
     select t, 'Bench approvals ' || n, 'bench-approvals-' || n
     from unnest($1::uuid[]) with ordinality as x(t, n)`,
    [tenants],
  );
  await client.query(
    `insert into public.memberships (organization_id, user_id, role)
     select t, $2::uuid, (select id from better_supabase.roles where key = 'owner')
     from unnest($1::uuid[]) t`,
    [owned, ME],
  );
  await client.query(
    `insert into public.memberships (organization_id, user_id, role)
     select t, $2::uuid, (select id from better_supabase.roles where key = 'member')
     from unnest($1::uuid[]) t`,
    [tenants, REQUESTER],
  );
  await client.query(
    `insert into better_supabase.approval_requests (tenant_id, subject_type, subject_id, action, policy, requested_by)
     select t, $2, 'r-' || n || '-' || g, 'approve',
       jsonb_build_object('selfApproval', false, 'steps', jsonb_build_array(jsonb_build_object('required', 1, 'approvers',
         case g % 20
           when 0 then jsonb_build_object('users', jsonb_build_array($3::text))
           when 1 then jsonb_build_object('role', 'owner')
           when 2 then jsonb_build_object('role', 'owner')
           when 3 then jsonb_build_object('role', 'owner')
           when 4 then jsonb_build_object('permission', 'invoices.approve')
           when 5 then jsonb_build_object('permission', 'invoices.approve')
           when 6 then jsonb_build_object('permission', 'invoices.approve')
           when 7 then jsonb_build_object('permission', 'invoices.approve')
           else jsonb_build_object('permission', 'approvals.manage')
         end))),
       case when g = 1 then $3::uuid else $4::uuid end
     from unnest($1::uuid[]) with ordinality as x(t, n), generate_series(1, ${PER_TENANT}) g`,
    [tenants, KIND, ME, REQUESTER],
  );
  await client.query("analyze better_supabase.approval_requests");

  const setForm = await hasSetForm();

  const scenarios: [string, () => Promise<unknown>][] = [
    [
      "all tenants, one call",
      () =>
        client.query(
          "select count(*) from better_supabase.approval_eligible_ids()",
        ),
    ],
    [
      "one tenant, one call",
      () =>
        client.query(
          "select count(*) from better_supabase.approval_eligible_ids($1)",
          [owned[0]],
        ),
    ],
    [
      `per-tenant policy (${OWNED} + 1 calls), ${SCANS} scans`,
      async () => {
        for (let scan = 0; scan < SCANS; scan += 1) {
          await client.query(perTenantPolicy, [owned]);
        }
      },
    ],
    ...(setForm
      ? ([
          [
            `set form, ${SCANS} scans`,
            async () => {
              for (let scan = 0; scan < SCANS; scan += 1) {
                await client.query(
                  "select count(*) from better_supabase.approval_eligible_ids_in()",
                );
              }
            },
          ],
          [
            `set form for the ${OWNED} owned tenants, ${SCANS} scans`,
            async () => {
              for (let scan = 0; scan < SCANS; scan += 1) {
                await client.query(
                  "select count(*) from better_supabase.approval_eligible_ids_in($1::uuid[])",
                  [owned],
                );
              }
            },
          ],
        ] as [string, () => Promise<unknown>][])
      : []),
  ];

  const { rows: counted } = await client.query<{ all: string; mine: string }>(
    `select (select count(*) from better_supabase.approval_requests where subject_type = $1) as all,
       (select count(*) from better_supabase.approval_requests where subject_type = $1 and tenant_id = any($2::uuid[])) as mine`,
    [KIND, owned],
  );

  const out: Record<string, unknown> = {
    pending: Number(counted[0]?.all),
    inOwnedTenants: Number(counted[0]?.mine),
  };

  for (const [label, body] of scenarios) {
    const times: number[] = [];
    let calls: Record<string, number> = {};

    for (let run = 0; run < runs; run += 1) {
      const result = await timed(body);

      times.push(result.ms);
      calls = result.calls;
    }

    const stats = summarize(times);

    out[label] = {
      p50: Number(stats.p50.toFixed(1)),
      p95: Number(stats.p95.toFixed(1)),
      calls: Object.fromEntries(
        Object.entries(calls).filter(([name]) =>
          /^(can|member_can|tenant_ids_with|approval_eligible_ids(_in)?)$/u.test(
            name,
          ),
        ),
      ),
    };
  }

  console.log(asJson ? JSON.stringify(out) : out);
} finally {
  await cleanup();
  await client.end();
}
