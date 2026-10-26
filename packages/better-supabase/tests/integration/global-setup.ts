import { Pool } from "pg";

import { stackDbUrl } from "./stack-env.ts";

// The suites sign requests as this user with a tenant claim for Acme or
// Globex. The fixture's `current_tenant_id()` trusts the claim only for a
// member, so the run makes the user one and removes it again afterwards.
const CLAIMS_USER = "00000000-0000-4000-8000-0000000000ff";

const TENANTS = [
  "00000000-0000-4000-8000-000000000001",
  "00000000-0000-4000-8000-000000000002",
];

const ADD = [
  `insert into auth.users (id, email, aud, role, instance_id, email_confirmed_at)
   values ($1, 'claims@example.test', 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now())
   on conflict (id) do nothing`,
  `insert into public.memberships (organization_id, user_id, role)
   select tenant, $1, r.id
   from unnest($2::uuid[]) tenant
   join better_supabase.roles r on r.key = 'member'
   on conflict do nothing`,
];

const REMOVE = [
  "delete from public.memberships where user_id = $1 and organization_id = any($2::uuid[])",
  "delete from auth.users where id = $1",
];

async function run(statements: readonly string[]): Promise<void> {
  const pool = new Pool({ connectionString: stackDbUrl(), max: 1 });

  try {
    for (const sql of statements) {
      const params = sql.includes("$2")
        ? [CLAIMS_USER, TENANTS]
        : [CLAIMS_USER];

      await pool.query(sql, params);
    }
  } finally {
    await pool.end();
  }
}

export async function setup(): Promise<() => Promise<void>> {
  if (!process.env["SUPABASE_DB_URL"]) {
    return async () => {};
  }

  await run(ADD);

  return async () => {
    await run(REMOVE);
  };
}
