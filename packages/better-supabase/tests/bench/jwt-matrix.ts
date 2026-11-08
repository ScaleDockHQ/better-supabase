// The JWT matrix (ADR 0523): memberships (1, 50, 150, 500) by custom roles (200,
// 500), each with per-tenant permission overrides. For every cell it times the
// pieces of an access token hook against the local stack (`membership_claims`,
// `permission_claims` for the active tenant, `feature_claims`) with and without
// the hook plan's fast path, measures the claim, token and cookie bytes, the
// `tenant_ids_with` call, and the token verification cold and warm behind the
// session memo. Everything database-side runs in one transaction that is rolled
// back, so the fixture stays as it was.
//   pnpm env:local && node tests/bench/jwt-matrix.ts [--runs 7] [--json]
import { Client } from "pg";

import { clearKeyCaches } from "../../src/auth/resolve.ts";
import { createSupabase } from "../../src/core/define.ts";
import { createServer } from "../../src/server/server.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { summarize } from "./stats.ts";

const MEMBERSHIPS = [1, 50, 150, 500] as const;
const CUSTOM_ROLES = [200, 500] as const;

/** Override rows per tenant: the user's role has these permissions flipped. */
const OVERRIDES_PER_TENANT = 10;

/** Permissions each custom role grants. */
const PERMISSIONS_PER_ROLE = 40;

/** The access token hook must answer within this (Supabase Auth). */
const AUTH_HOOK_LIMIT_MS = 2000;

/** `@supabase/ssr` splits the session cookie into chunks of this size. */
const COOKIE_CHUNK_BYTES = 3180;

/** What the session cookie carries besides the access token (user, refresh). */
const COOKIE_OVERHEAD_BYTES = 1200;

const runsAt = process.argv.indexOf("--runs");
const runs = runsAt === -1 ? 7 : Number(process.argv[runsAt + 1]);
const asJson = process.argv.includes("--json");
const url = process.env["SUPABASE_DB_URL"];

if (!url) {
  throw new Error("SUPABASE_DB_URL is not set; run pnpm env:local");
}

const client = new Client({ connectionString: url });

await client.connect();

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const signer = await createTestSigner();

const server = createServer(createSupabase(schema), {
  env: {
    url: PROJECT_URL,
    publishableKey: "sb_publishable_test",
    jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
  },
  auth: { jwks: signer.jwks },
});

interface Cell {
  readonly memberships: number;
  readonly customRoles: number;
  readonly hookFullMs: number;
  readonly hookFastMs: number;
  readonly membershipsBytes: number;
  readonly permissionsBytes: number;
  readonly tokenBytes: number;
  readonly cookieBytes: number;
  readonly cookieChunks: number;
  readonly tenantIdsWithMs: number;
  readonly verifyColdUs: number;
  readonly verifyWarmUs: number;
}

const query = async <T extends object>(
  sql: string,
  values: unknown[] = [],
): Promise<T[]> => (await client.query<T>(sql, values)).rows;

function only<T>(rows: readonly T[]): T {
  const [row] = rows;

  if (row === undefined) {
    throw new Error("The query returned no row");
  }

  return row;
}

const median = (samples: readonly number[]): number => summarize(samples).p50;

async function timed(sql: string, values: unknown[] = []): Promise<number> {
  const samples: number[] = [];

  for (let run = 0; run < runs; run += 1) {
    const started = performance.now();
    await client.query(sql, values);
    samples.push(performance.now() - started);
  }

  return median(samples);
}

async function verifyCost(token: string): Promise<[number, number]> {
  const request = (): Request =>
    new Request("https://app.test/", {
      headers: { authorization: `Bearer ${token}` },
    });

  const cold: number[] = [];
  const warm: number[] = [];

  for (let run = 0; run < 200; run += 1) {
    clearKeyCaches();
    server.sessions.clear();

    const started = performance.now();
    await server.context(request());
    cold.push((performance.now() - started) * 1000);
  }

  await server.context(request());

  for (let run = 0; run < 200; run += 1) {
    const started = performance.now();
    await server.context(request());
    warm.push((performance.now() - started) * 1000);
  }

  return [median(cold), median(warm)];
}

async function cell(memberships: number, customRoles: number): Promise<Cell> {
  await client.query("begin");

  try {
    const { id: user } = only(
      await query<{ id: string }>(
        `insert into auth.users (id, instance_id, aud, role, email)
       values (gen_random_uuid(), '00000000-0000-0000-0000-000000000000',
         'authenticated', 'authenticated', 'matrix-' || gen_random_uuid() || '@bench.test')
       returning id`,
      ),
    );

    await client.query(
      `insert into better_supabase.roles (key, scope)
       select 'bench_role_' || i, 'tenant' from generate_series(1, $1) i`,
      [customRoles],
    );

    await client.query(
      `insert into better_supabase.role_permissions (role_id, permission_id)
       select r.id, p.id
       from better_supabase.roles r
       cross join lateral (
         select id from better_supabase.permissions order by md5(id::text || r.key) limit $1
       ) p
       where r.key like 'bench_role_%'`,
      [PERMISSIONS_PER_ROLE],
    );

    await client.query(
      `insert into public.organizations (id, name, slug)
       select gen_random_uuid(), 'Bench ' || i, 'bench-' || gen_random_uuid() from generate_series(1, $1) i`,
      [memberships],
    );

    await client.query(
      `insert into public.memberships (organization_id, user_id, role)
       select o.id, $1, (select id from better_supabase.roles where key = 'bench_role_' || (1 + (o.rn % $3))::int)
       from (select id, row_number() over () as rn from public.organizations where slug like 'bench-%') o
       limit $2`,
      [user, memberships, customRoles],
    );

    await client.query(
      `insert into better_supabase.permission_overrides (tenant_id, role_id, permission_id, granted)
       select m.organization_id, m.role, p.id, (row_number() over (partition by m.organization_id) % 2 = 0)
       from public.memberships m
       cross join lateral (
         select id from better_supabase.permissions order by md5(id::text || m.organization_id::text) limit $2
       ) p
       where m.user_id = $1`,
      [user, OVERRIDES_PER_TENANT],
    );

    const { tenant } = only(
      await query<{ tenant: string }>(
        "select organization_id as tenant from public.memberships where user_id = $1 limit 1",
        [user],
      ),
    );

    const hookFullMs = await timed(
      `select better_supabase.membership_claims($1),
              better_supabase.permission_claims($1, $2),
              better_supabase.feature_claims($1)`,
      [user, tenant],
    );

    // A fast refresh runs the plan and nothing else.
    const hookFastMs = await timed(
      "select better_supabase.hook_plan(jsonb_build_object('user_id', $1::text, 'authentication_method', 'token_refresh', 'claims', jsonb_build_object('authz_ver', better_supabase.authz_version($1::uuid), 'memberships', '[]'::jsonb)))",
      [user],
    );

    const sizes = only(
      await query<{ memberships: number; permissions: number }>(
        `select octet_length(better_supabase.membership_claims($1)::text) as memberships,
              octet_length(better_supabase.permission_claims($1, $2)::text) as permissions`,
        [user, tenant],
      ),
    );

    const { memberships: membershipClaim, permissions: permissionClaim } = only(
      await query<{ memberships: unknown; permissions: unknown }>(
        `select better_supabase.membership_claims($1) as memberships,
                better_supabase.permission_claims($1, $2) as permissions`,
        [user, tenant],
      ),
    );

    const token = await signer.sign({
      sub: user,
      memberships: membershipClaim,
      permissions: permissionClaim,
      authz_ver: 1,
    });

    const cookieBytes = Math.ceil(
      ((token.length + COOKIE_OVERHEAD_BYTES) * 4) / 3,
    );

    const tenantIdsWithMs = await timed(
      `with claims as (select set_config('request.jwt.claims', json_build_object('sub', $1::text, 'role', 'authenticated')::text, true))
       select count(*) from claims, better_supabase.tenant_ids_with('customers.read')`,
      [user],
    );

    const [verifyColdUs, verifyWarmUs] = await verifyCost(token);

    return {
      memberships,
      customRoles,
      hookFullMs,
      hookFastMs,
      membershipsBytes: sizes.memberships,
      permissionsBytes: sizes.permissions,
      tokenBytes: token.length,
      cookieBytes,
      cookieChunks: Math.ceil(cookieBytes / COOKIE_CHUNK_BYTES),
      tenantIdsWithMs,
      verifyColdUs,
      verifyWarmUs,
    };
  } finally {
    await client.query("rollback");
  }
}

const cells: Cell[] = [];

for (const customRoles of CUSTOM_ROLES) {
  for (const memberships of MEMBERSHIPS) {
    cells.push(await cell(memberships, customRoles));
  }
}

await client.end();

if (asJson) {
  console.log(JSON.stringify(cells, null, 2));
} else {
  console.table(
    cells.map((entry) => ({
      memberships: entry.memberships,
      "custom roles": entry.customRoles,
      "hook full ms": entry.hookFullMs.toFixed(1),
      "hook fast ms": entry.hookFastMs.toFixed(2),
      "memberships B": entry.membershipsBytes,
      "permissions B": entry.permissionsBytes,
      "token B": entry.tokenBytes,
      "cookie B": entry.cookieBytes,
      chunks: entry.cookieChunks,
      "tenant_ids_with ms": entry.tenantIdsWithMs.toFixed(2),
      "verify cold µs": entry.verifyColdUs.toFixed(0),
      "verify warm µs": entry.verifyWarmUs.toFixed(0),
    })),
  );
}

const slow = cells.filter((entry) => entry.hookFullMs > AUTH_HOOK_LIMIT_MS / 2);

for (const entry of slow) {
  console.error(
    `hook at ${String(entry.memberships)} memberships and ${String(entry.customRoles)} custom roles takes ${entry.hookFullMs.toFixed(0)} ms, over half of Auth's ${String(AUTH_HOOK_LIMIT_MS)} ms limit.`,
  );
  process.exitCode = 1;
}
