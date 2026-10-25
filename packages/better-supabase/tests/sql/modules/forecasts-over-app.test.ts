import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const USER = "22222222-2222-4222-8222-222222222222";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// The app's own snapshots and snapshot deals: an enum outcome, no target or
// taker, and no owner, stage, category or dates on the deals. The module adds
// the columns it is missing.
const APP = `
create type public.call_outcome as enum ('open', 'won', 'lost');

create table public.forecast_calls (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  pipeline_id uuid,
  period_start date not null,
  period_end date not null,
  currency text not null,
  totals jsonb not null,
  deal_count integer not null default 0,
  taken_at timestamptz not null default now()
);

create table public.forecast_call_deals (
  snapshot_id uuid not null references public.forecast_calls (id) on delete cascade,
  org_id uuid not null,
  deal_id uuid not null,
  name text not null,
  outcome public.call_outcome not null,
  amount bigint not null
);
`;

const OWN_TABLES = {
  "public.forecast_calls": "app.sql",
  "public.forecast_call_deals": "app.sql",
};

const BLOCKS: AnyBlocksConfig = {
  forecasts: {
    tables: {
      snapshots: "public.forecast_calls",
      deals: "public.forecast_call_deals",
    },
    columns: {
      snapshots: { tenant: "org_id", target: null, takenBy: null },
      deals: {
        tenant: "org_id",
        owner: null,
        stage: null,
        forecast: null,
        closeOn: null,
        closedAt: null,
      },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role","sub":"${USER}"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config('request.jwt.claim.sub', '${USER}', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(
    [
      "memberships",
      "permissions",
      "subjects",
      "pipelines",
      "deals",
      "forecasts",
    ],
    { modules: BLOCKS, ownTables: OWN_TABLES },
  );

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      APP,
      ...files
        .filter((file) => file.kind !== "data")
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

describe("forecasts over the app's tables", BOOT, () => {
  it("snapshots deals into an enum outcome column and compares two snapshots", async () => {
    await expect(
      run(`do $$
declare
  v_deal uuid;
  v_first jsonb;
  v_second jsonb;
  v_changes jsonb;
begin
  ${SERVICE}
  v_deal := (better_supabase.create_deal('${TENANT}', '{"name": "Acme", "closeOn": "2026-12-01", "amount": "5000", "currency": "EUR"}'::jsonb, null) ->> 'id')::uuid;
  v_first := better_supabase.take_forecast_snapshot('${TENANT}', null, '2026-10-01', '2026-12-31', 'eur');
  if (v_first ->> 'dealCount')::integer <> 1 or v_first -> 'target' <> 'null'::jsonb then
    raise exception 'first %', v_first;
  end if;
  if (select outcome from public.forecast_call_deals where snapshot_id = (v_first ->> 'id')::uuid) <> 'open' then
    raise exception 'outcome not copied';
  end if;
  perform better_supabase.close_deal(v_deal, 'won', null);
  v_second := better_supabase.take_forecast_snapshot('${TENANT}', null, '2026-10-01', '2026-12-31', 'EUR');
  v_changes := better_supabase.forecast_changes((v_first ->> 'id')::uuid, (v_second ->> 'id')::uuid);
  if v_changes -> 'deals' -> 0 ->> 'change' <> 'won' or v_changes -> 'deals' -> 0 -> 'after' ->> 'outcome' <> 'won' then
    raise exception 'changes %', v_changes;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses a target the app's table has no column for", async () => {
    await expect(
      run(`do $$
begin
  ${SERVICE}
  perform better_supabase.take_forecast_snapshot('${TENANT}', null, '2026-10-01', '2026-12-31', 'EUR', 100);
end;
$$;`),
    ).rejects.toThrow(/no target column/);
  });
});
