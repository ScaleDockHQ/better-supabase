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

const NAMES = [
  "memberships",
  "permissions",
  "ledger",
  "periods",
  "commissions",
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

describe("commissions in Postgres", BOOT, () => {
  it("accrues on tiers once, builds and pays a statement, and reverses", async () => {
    await expect(
      run(`do $$
declare
  v_plan jsonb;
  v_c1 jsonb;
  v_c2 jsonb;
  v_st jsonb;
  v_lines jsonb;
begin
  ${SERVICE}
  v_plan := better_supabase.save_commission_plan('${TENANT}', 'Tiered', 'tiered', null,
    '[{"upTo":100000,"bps":1000},{"upTo":null,"bps":500}]'::jsonb);
  perform better_supabase.assign_commission_plan('${TENANT}', (v_plan ->> 'id')::uuid, '${ALICE}');
  v_c1 := better_supabase.accrue_commission('${TENANT}', '${ALICE}', 'invoices', 'inv-1', 80000, 'EUR', '2099-03-05');
  if (v_c1 ->> 'amount')::bigint <> 8000 then raise exception 'first %', v_c1; end if;
  if (better_supabase.accrue_commission('${TENANT}', '${ALICE}', 'invoices', 'inv-1', 80000, 'EUR', '2099-03-05') ->> 'id') <> (v_c1 ->> 'id') then
    raise exception 'accrual is not idempotent';
  end if;
  v_c2 := better_supabase.accrue_commission('${TENANT}', '${ALICE}', 'invoices', 'inv-2', 40000, 'EUR', '2099-03-20');
  if (v_c2 ->> 'amount')::bigint <> 3000 then raise exception 'marginal %', v_c2; end if;
  v_st := better_supabase.build_commission_statement('${TENANT}', '${ALICE}', 'EUR', '2099-03-01', '2099-03-31');
  if (v_st ->> 'total')::bigint <> 11000 then raise exception 'statement %', v_st; end if;
  v_st := better_supabase.finalize_commission_statement((v_st ->> 'id')::uuid);
  v_lines := better_supabase.commission_payroll_lines('${TENANT}', '2099-03-01', '2099-03-31');
  if jsonb_array_length(v_lines) <> 1 then raise exception 'payroll %', v_lines; end if;
  v_st := better_supabase.pay_commission_statement((v_st ->> 'id')::uuid);
  if v_st ->> 'status' <> 'paid' then raise exception 'paid %', v_st; end if;
  begin
    perform better_supabase.reverse_commission((v_c1 ->> 'id')::uuid, 'late');
    raise exception 'reversed a commission on a paid statement';
  exception when others then
    if sqlerrm like 'reversed%' then raise; end if;
  end;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
