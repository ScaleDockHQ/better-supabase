// Plans approval_eligible_ids over pending requests in 10 tenants: the old body
// (approval_eligible per request) against the set-based one, on in-process
// Postgres (PGlite).
//   node tests/bench/approval-eligible-ids.ts
import type { BlockSqlAccessProvider } from "../../src/sql/module-types.ts";

import { loadLite, migrateLite, seedLite } from "../../src/lite/runtime.ts";
import { renderBlocks } from "../../src/sql/render.ts";

const SIZES = [54, 5000];
const TENANTS = 10;
const RUNS = 5;
const USER = "44444444-4444-4444-8444-444444444444";

const SETUP = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
create schema if not exists auth;
create table if not exists auth.users (id uuid primary key);
create schema if not exists authz;
create table authz.grants (user_id uuid not null, tenant uuid, permission text not null);
create function authz.ids_with(permission text) returns setof uuid
  language sql stable as $$
    select g.tenant from authz.grants g where g.user_id = auth.uid() and g.permission = ids_with.permission and g.tenant is not null
  $$;
create function authz.is_platform(permission text) returns boolean
  language sql stable as $$ select false $$;
grant usage on schema authz to authenticated;
`;

const PROVIDER: BlockSqlAccessProvider = {
  name: "bench",
  scope: "organization",
  idType: "uuid",
  functions: {
    idsWith: "authz.ids_with({permission})",
    isPlatform: "authz.is_platform({permission})",
  },
};

const files = renderBlocks(["permissions", "approvals"], {
  modules: {
    permissions: { model: "provider" },
    approvals: {
      options: {
        policies: {
          invoice: {
            send: {
              steps: [{ approvers: { permission: "invoices.approve" } }],
            },
          },
        },
      },
    },
  },
  accessProvider: PROVIDER,
});

const lite = await loadLite();

if (!lite) {
  throw new Error("Install @supabase/lite to run this benchmark.");
}

const connection = await lite.createPgliteConnection();
const target = { driver: "pglite", connection } as const;

await migrateLite(connection, [
  SETUP,
  ...files.filter((f) => f.kind === "schema").map((f) => f.contents),
]);

for (const file of files.filter((f) => f.kind === "data")) {
  await seedLite(target, file.contents);
}

const { driver } = connection;

// The body approval_eligible_ids had before 0.54: one approval_eligible call per pending request.
await driver.exec(`
create function better_supabase.old_eligible_ids(tenant uuid default null)
returns setof uuid language sql stable security definer set search_path = '' as $$
  select r.id from better_supabase.approval_requests r
  where r.status = 'pending'
    and (old_eligible_ids.tenant is null or r.tenant_id = old_eligible_ids.tenant)
    and better_supabase.approval_eligible(r)
$$;
`);

const explain = async (sql: string): Promise<string[]> => {
  const { rows } = await driver.query(`explain (analyze, buffers) ${sql}`);

  return rows.map((row) => String(Object.values(row as object)[0]));
};

const ms = (lines: readonly string[]): number =>
  Number(/Execution Time: ([\d.]+) ms/u.exec(lines.join("\n"))?.[1]);

const median = (values: readonly number[]): number =>
  [...values].toSorted((a, b) => a - b)[Math.floor(values.length / 2)]!;

const out: string[] = [];

for (const size of SIZES) {
  await driver.exec(`
    truncate better_supabase.approval_requests cascade;
    truncate authz.grants;
    insert into authz.grants
      select '${USER}', ('00000000-0000-4000-8000-' || lpad(t::text, 12, '0'))::uuid, 'invoices.approve'
      from generate_series(1, ${TENANTS}) t;
    insert into better_supabase.approval_requests (tenant_id, subject_type, subject_id, action, policy, requested_by)
      select ('00000000-0000-4000-8000-' || lpad((n % ${TENANTS} + 1)::text, 12, '0'))::uuid,
        'invoice', 'i-' || n, 'send', better_supabase.approval_policy('invoice', 'send'), gen_random_uuid()
      from generate_series(1, ${size}) n;
    analyze better_supabase.approval_requests;
    select set_config('request.jwt.claims', '{"sub":"${USER}","role":"authenticated"}', false),
      set_config('request.jwt.claim.sub', '${USER}', false),
      set_config('request.jwt.claim.role', 'authenticated', false);
  `);

  const { rows: counted } = await driver.query(
    "select (select count(*) from better_supabase.old_eligible_ids()) as old, (select count(*) from better_supabase.approval_eligible_ids()) as new",
  );

  out.push(`${size} requests, rows returned: ${JSON.stringify(counted[0])}`);

  for (const [label, fn] of [
    ["before", "old_eligible_ids"],
    ["after", "approval_eligible_ids"],
  ] as const) {
    const times: number[] = [];
    let last: string[] = [];

    for (let run = 0; run < RUNS; run += 1) {
      last = await explain(`select count(*) from better_supabase.${fn}()`);
      times.push(ms(last));
    }

    out.push(
      `${size} pending requests, ${label}: median ${median(times).toFixed(1)} ms`,
      ...last.filter((line) => /Buffers|Execution/u.test(line)).slice(-2),
    );
  }
}

console.log(out.join("\n"));

await connection.close();
