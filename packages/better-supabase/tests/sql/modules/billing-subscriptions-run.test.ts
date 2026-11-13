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

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["billing", "ledger"]);

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

describe("native subscriptions on PGlite", BOOT, () => {
  it("prorates an upgrade halfway through the period and posts it once", async () => {
    await expect(
      run(`do $$
declare
  v_sub jsonb;
  v_result jsonb;
  v_again jsonb;
begin
  ${SERVICE}
  v_sub := better_supabase.create_native_subscription('${TENANT}', 'pro', 'eur', 3000, 2, 'month', '2026-01-01T00:00:00Z');
  v_result := better_supabase.prorate_change((v_sub ->> 'id')::uuid, 6000, null, ((v_sub ->> 'period_starts_at')::timestamptz + ((v_sub ->> 'period_ends_at')::timestamptz - (v_sub ->> 'period_starts_at')::timestamptz) / 2));
  if v_result ->> 'credit' <> '3000' or v_result ->> 'charge' <> '6000' or v_result ->> 'net' <> '3000' or v_result ->> 'transaction_id' is null then
    raise exception 'upgrade %', v_result;
  end if;
  if (select sum(amount) from better_supabase.ledger_entries) <> 0 or (select count(*) from better_supabase.ledger_transactions) <> 1 then
    raise exception 'ledger';
  end if;
  v_again := better_supabase.prorate_change((v_sub ->> 'id')::uuid, 3000, 2, ((v_sub ->> 'period_starts_at')::timestamptz + ((v_sub ->> 'period_ends_at')::timestamptz - (v_sub ->> 'period_starts_at')::timestamptz) / 2));
  if v_again ->> 'net' <> '-3000' then
    raise exception 'downgrade %', v_again;
  end if;
  if not better_supabase.cancel_native_subscription((v_sub ->> 'id')::uuid) then
    raise exception 'cancel';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
