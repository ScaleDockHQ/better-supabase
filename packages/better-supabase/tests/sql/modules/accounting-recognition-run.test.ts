import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

const NAMES = ["memberships", "permissions", "ledger", "periods", "accounting"];

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 120_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(NAMES, {
    modules: { accounting: { options: { recognition: true } } },
  });

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
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("revenue recognition on PGlite", BOOT, () => {
  it("defers an amount, splits it by month and posts a month when its period closes", async () => {
    await expect(
      run(`do $$
declare
  v_schedule jsonb;
  v_again jsonb;
  v_period jsonb;
  v_list jsonb;
begin
  ${SERVICE}
  perform better_supabase.setup_accounting('${TENANT}', 'EUR');
  v_schedule := better_supabase.schedule_revenue_recognition('${TENANT}', 'invoice', 'inv-1', 1200, 'EUR', '2099-01-01', '2099-03-31', 'line-1');
  if (v_schedule ->> 'rows')::int <> 3 or v_schedule ->> 'deferral_entry_id' is null then
    raise exception 'schedule %', v_schedule;
  end if;
  v_again := better_supabase.schedule_revenue_recognition('${TENANT}', 'invoice', 'inv-1', 1200, 'EUR', '2099-01-01', '2099-03-31', 'line-1');
  if v_again ->> 'id' <> v_schedule ->> 'id' then
    raise exception 'not idempotent';
  end if;
  if (select sum(amount) from better_supabase.accounting_recognition_rows) <> 1200 then
    raise exception 'rows do not add up';
  end if;
  v_period := better_supabase.period_for('${TENANT}', 'revenue_recognition', '2099-01-15');
  perform better_supabase.close_period((v_period ->> 'id')::uuid);
  if (select count(*) from better_supabase.accounting_recognition_rows where status = 'posted') <> 1 then
    raise exception 'january not posted';
  end if;
  if (select count(*) from better_supabase.accounting_recognition_rows where status = 'pending') <> 2 then
    raise exception 'later months should stay pending';
  end if;
  v_list := better_supabase.list_revenue_recognition_schedules('${TENANT}');
  if jsonb_array_length(v_list) <> 1 or v_list -> 0 ->> 'rows' <> '3' or v_list -> 0 ->> 'recognized' <> '413' then
    raise exception 'schedule list %', v_list;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
