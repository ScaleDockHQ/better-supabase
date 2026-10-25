import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

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

// The app's own usage tables: renamed columns, no reported or updated
// columns on the counters, a history table without source or metadata that
// isn't partitioned, distinct subjects without a first-seen time, and quotas
// with an enum period and no creation time.
const APP = `
create type public.quota_window as enum ('day', 'week', 'month', 'year', 'billing');

create table public.meter_counts (
  org_id uuid not null,
  meter text not null,
  day date not null,
  amount numeric not null default 0
);

create table public.meter_keys (
  org_id uuid not null,
  meter text not null,
  key text not null,
  qty numeric not null,
  recorded_at timestamptz not null default now()
);

create table public.meter_log (
  id bigint generated always as identity primary key,
  org_id uuid not null,
  meter text not null,
  qty numeric not null,
  actor_id uuid,
  recorded_at timestamptz not null default now()
);

create table public.meter_seen (
  org_id uuid not null,
  meter text not null,
  period_start date not null,
  subject text not null
);

create table public.plan_limits (
  id uuid primary key default gen_random_uuid(),
  org_id uuid,
  plan text,
  meter text not null,
  "limit" numeric,
  period public.quota_window not null default 'month'
);
`;

const OWN_TABLES = {
  "public.meter_counts": "app.sql",
  "public.meter_keys": "app.sql",
  "public.meter_log": "app.sql",
  "public.meter_seen": "app.sql",
  "public.plan_limits": "app.sql",
};

const BLOCKS: AnyBlocksConfig = {
  usage: {
    options: {
      history: true,
      partitioned: true,
      meters: { "api.calls": {}, seats: { kind: "distinct" } },
    },
    tables: {
      counters: "public.meter_counts",
      events: "public.meter_keys",
      history: "public.meter_log",
      distinct: "public.meter_seen",
      quotas: "public.plan_limits",
    },
    columns: {
      counters: {
        tenant: "org_id",
        value: "amount",
        reported: null,
        updatedAt: null,
      },
      events: { tenant: "org_id", key: "key", quantity: "qty" },
      history: {
        tenant: "org_id",
        quantity: "qty",
        source: null,
        metadata: null,
      },
      distinct: { tenant: "org_id", firstSeen: null },
      quotas: { tenant: "org_id", createdAt: null },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["usage"], {
    modules: BLOCKS,
    ownTables: OWN_TABLES,
  });

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

describe("usage over the app's tables", BOOT, () => {
  it("records usage once per key, keeps history, counts distinct subjects and enforces an enum-period quota", async () => {
    await expect(
      run(`do $$
declare
  v_result jsonb;
begin
  ${SERVICE}
  v_result := better_supabase.record_usage('${TENANT}', 'api.calls', 3, 'k1', 'ignored');
  if not (v_result ->> 'recorded')::boolean or (v_result ->> 'today')::numeric <> 3 then
    raise exception 'recorded %', v_result;
  end if;
  v_result := better_supabase.record_usage('${TENANT}', 'api.calls', 3, 'k1');
  if (v_result ->> 'recorded')::boolean then
    raise exception 'counted a repeated key: %', v_result;
  end if;
  perform better_supabase.record_usage('${TENANT}', 'api.calls', 2);
  if (select amount from public.meter_counts where org_id = '${TENANT}') <> 5
    or (select count(*) from public.meter_counts) <> 1 then
    raise exception 'counters %', (select jsonb_agg(c) from public.meter_counts c);
  end if;
  if (select count(*) from public.meter_keys) <> 1 or (select count(*) from public.meter_log) <> 2 then
    raise exception 'keys or history';
  end if;
  v_result := better_supabase.usage_history('${TENANT}');
  if jsonb_array_length(v_result) <> 2 or v_result -> 0 -> 'source' <> 'null'::jsonb then
    raise exception 'history %', v_result;
  end if;
  insert into public.plan_limits (org_id, meter, "limit", period) values ('${TENANT}', 'api.calls', 6, 'day');
  v_result := better_supabase.usage_status('${TENANT}', 'api.calls');
  if v_result ->> 'period' <> 'day' or (v_result ->> 'remaining')::numeric <> 1 then
    raise exception 'status %', v_result;
  end if;
  perform better_supabase.consume_quota('${TENANT}', 'api.calls', 1);
  begin
    perform better_supabase.consume_quota('${TENANT}', 'api.calls', 1);
    raise exception 'consumed past the quota';
  exception when sqlstate 'BSQ29' then
    null;
  end;
  perform better_supabase.track_usage('${TENANT}', 'seats', 'ann');
  v_result := better_supabase.track_usage('${TENANT}', 'seats', 'ann');
  if (v_result ->> 'recorded')::boolean or (select count(*) from public.meter_seen) <> 1
    or better_supabase.usage_used('${TENANT}', 'seats', 'month') <> 1 then
    raise exception 'tracked %', v_result;
  end if;
  if better_supabase.unreported_usage() <> '[]'::jsonb or better_supabase.mark_usage_reported('${TENANT}', 'api.calls', current_date, 1) then
    raise exception 'reported usage without a reported column';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
