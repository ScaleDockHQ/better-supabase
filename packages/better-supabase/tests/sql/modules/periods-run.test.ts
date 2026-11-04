import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// Everyone may do everything in the tenant: these tests are about the engine.
const ALLOW = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.can_user(member uuid, scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $$ select '${TENANT}'::uuid $$;
insert into auth.users (id) values ('${ALICE}');
insert into better_supabase.memberships (organization_id, user_id, role) values ('${TENANT}', '${ALICE}', 'owner');
`;

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

const NAMES = [
  "memberships",
  "permissions",
  "approvals",
  "ledger",
  "leave",
  "periods",
];

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 120_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(NAMES, {});

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      ...files
        .filter((file) => file.kind === "schema")
        .map((file) => file.contents),
    ],
    seed: [
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      ALLOW,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("periods in Postgres", BOOT, () => {
  it("creates a calendar period on demand, blocks overlaps and closes it once", async () => {
    await expect(
      run(`do $$
declare
  v_period jsonb;
  v_id uuid;
begin
  ${SERVICE}
  v_period := better_supabase.period_for('${TENANT}', 'leave_year', '2099-06-15');
  v_id := (v_period ->> 'id')::uuid;
  if v_period ->> 'startsOn' <> '2099-01-01' or v_period ->> 'endsOn' <> '2099-12-31' or v_period ->> 'status' <> 'open' then
    raise exception 'period %', v_period;
  end if;
  if (better_supabase.period_for('${TENANT}', 'leave_year', '2099-01-01') ->> 'id')::uuid <> v_id then
    raise exception 'not the same period';
  end if;
  if better_supabase.period_for('${TENANT}', 'unknown_kind', '2099-01-01') is not null then
    raise exception 'an unknown kind has no calendar';
  end if;
  begin
    perform better_supabase.create_period('${TENANT}', 'leave_year', '2099-12-31', '2100-02-01');
    raise exception 'overlap allowed';
  exception when sqlstate '23P01' then null;
  end;
  if not better_supabase.period_is_open('${TENANT}', 'leave_year', '2099-03-01') then
    raise exception 'open period reads closed';
  end if;
  perform better_supabase.lock_period(v_id);
  if better_supabase.period_is_open('${TENANT}', 'leave_year', '2099-03-01') then
    raise exception 'locked period reads open';
  end if;
  if (better_supabase.close_period(v_id) ->> 'status') <> 'closed' then
    raise exception 'not closed';
  end if;
  if (better_supabase.close_period(v_id) ->> 'status') <> 'closed' then
    raise exception 'close is not idempotent';
  end if;
  if (better_supabase.reopen_period(v_id, 'late') ->> 'status') <> 'open' then
    raise exception 'not reopened';
  end if;
  if jsonb_array_length(better_supabase.list_periods('${TENANT}', '{"kind":"leave_year"}')) <> 1 then
    raise exception 'list %', better_supabase.list_periods('${TENANT}');
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
