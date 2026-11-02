import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";
const BOB = "33333333-3333-4333-8333-333333333333";

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
insert into auth.users (id) values ('${ALICE}'), ('${BOB}');
insert into better_supabase.memberships (organization_id, user_id, role) values ('${TENANT}', '${ALICE}', 'owner');
`;

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

const NAMES = ["memberships", "permissions", "ledger", "referrals"];

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 120_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(NAMES, {});

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      ...files
        .filter((file) => file.kind !== "data")
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

describe("referrals in Postgres", BOOT, () => {
  it("attributes once, rewards once on qualify and reverses on void", async () => {
    await expect(
      run(`do $$
declare
  v_code jsonb;
  v_ref jsonb;
begin
  ${SERVICE}
  v_code := better_supabase.create_referral_code('${TENANT}', '${ALICE}', 'WELCOME1', null, 500, 'EUR');
  v_ref := better_supabase.attribute_referral('${TENANT}', 'WELCOME1', '${BOB}');
  if v_ref ->> 'status' <> 'attributed' then raise exception 'attribute %', v_ref; end if;
  if (better_supabase.attribute_referral('${TENANT}', 'WELCOME1', '${BOB}') ->> 'id') <> (v_ref ->> 'id') then
    raise exception 'attribution is not idempotent';
  end if;
  v_ref := better_supabase.qualify_referral('${TENANT}', '${BOB}', null, 'invoices/inv-1');
  if v_ref ->> 'status' <> 'rewarded' then raise exception 'qualify %', v_ref; end if;
  if (better_supabase.qualify_referral('${TENANT}', '${BOB}', null, 'invoices/inv-2') ->> 'id') <> (v_ref ->> 'id') then
    raise exception 'qualify is not idempotent';
  end if;
  if (select count(*) from better_supabase.ledger_transactions where reference_type = 'referrals') <> 1 then
    raise exception 'reward posted more than once';
  end if;
  v_ref := better_supabase.void_referral((v_ref ->> 'id')::uuid, 'fraud');
  if v_ref ->> 'status' <> 'void' then raise exception 'void %', v_ref; end if;
  if better_supabase.qualify_referral('${TENANT}', '${ALICE}') is not null then
    raise exception 'unreferred user qualified';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
