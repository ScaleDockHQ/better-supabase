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

// The app's own deals and lines: renamed columns, an enum outcome and
// forecast category, no product, seats, next step, flags, source or slip
// columns, and no discount, tax or creation columns on its lines. The module
// adds the pipeline, totals and other columns it is missing.
const APP = `
create type public.deal_result as enum ('open', 'won', 'lost');
create type public.deal_call as enum ('commit', 'best_case', 'pipeline', 'omit');

create table public.opportunities (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  seq bigint not null,
  code text not null,
  title text not null,
  owner_user_id uuid,
  amount bigint not null default 0,
  currency char(3) not null,
  result public.deal_result not null default 'open',
  call public.deal_call,
  close_on date not null,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  crm_ref text
);

create table public.opportunity_lines (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  opportunity_id uuid not null references public.opportunities (id) on delete cascade,
  product_type text,
  product_id text,
  label text not null,
  qty numeric(18, 4) not null,
  unit_amount bigint not null,
  position integer not null
);
`;

const OWN_TABLES = {
  "public.opportunities": "app.sql",
  "public.opportunity_lines": "app.sql",
};

const BLOCKS: AnyBlocksConfig = {
  deals: {
    tables: {
      deals: "public.opportunities",
      lines: "public.opportunity_lines",
    },
    columns: {
      deals: {
        tenant: "org_id",
        number: "seq",
        identifier: "code",
        name: "title",
        outcome: "result",
        forecast: "call",
        closeOn: "close_on",
        product: null,
        seats: null,
        existingAmount: null,
        slippedFrom: null,
        pushCount: null,
        nextStep: null,
        nextAt: null,
        nextKind: null,
        flags: null,
        source: null,
        lostReason: null,
        createdBy: null,
      },
      lines: {
        tenant: "org_id",
        parent: "opportunity_id",
        description: "label",
        quantity: "qty",
        discountBps: null,
        taxRateBps: null,
        taxCode: null,
        createdAt: null,
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
    ["memberships", "permissions", "subjects", "pipelines", "deals"],
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

describe("deals over the app's tables", BOOT, () => {
  it("creates, edits, prices and closes a deal in enum outcome and forecast columns", async () => {
    await expect(
      run(`do $$
declare
  v_deal jsonb;
  v_id uuid;
  v_changes jsonb;
  v_lines jsonb;
  v_closed jsonb;
begin
  ${SERVICE}
  v_deal := better_supabase.create_deal('${TENANT}', '{"name": "Acme renewal", "closeOn": "2026-12-01", "amount": "5000", "currency": "eur", "forecast": "pipeline"}'::jsonb, null);
  v_id := (v_deal ->> 'id')::uuid;
  if v_deal ->> 'name' <> 'Acme renewal' or v_deal ->> 'tenant_id' <> '${TENANT}'
    or v_deal ->> 'outcome' <> 'open' or v_deal ->> 'forecast_category' <> 'pipeline'
    or v_deal ->> 'existing_amount' <> '0' or v_deal ? 'crm_ref' or v_deal ? 'title' then
    raise exception 'created %', v_deal;
  end if;
  if (select code from public.opportunities where id = v_id) is null then
    raise exception 'no identifier';
  end if;
  v_changes := better_supabase.update_deals(jsonb_build_array(
    jsonb_build_object('dealId', v_id, 'field', 'forecast', 'value', 'commit'),
    jsonb_build_object('dealId', v_id, 'field', 'nextStep', 'value', 'call them')
  ));
  if jsonb_array_length(v_changes -> 'accepted') <> 1 or jsonb_array_length(v_changes -> 'rejected') <> 1
    or (select call from public.opportunities where id = v_id) <> 'commit' then
    raise exception 'changes %', v_changes;
  end if;
  perform better_supabase.update_deals(jsonb_build_array(
    jsonb_build_object('dealId', v_id, 'field', 'amountSource', 'value', 'line_items')
  ));
  v_lines := better_supabase.set_deal_lines(v_id, '[{"description": "Seats", "quantity": 3, "unitAmount": "2000"}]'::jsonb);
  if (select amount from public.opportunities where id = v_id) <> 6000
    or (select total from public.opportunities where id = v_id) <> 6000 then
    raise exception 'lines %', v_lines;
  end if;
  perform better_supabase.set_deal_members(v_id, jsonb_build_array(jsonb_build_object('userId', '${USER}', 'role', 'lead')));
  if (better_supabase.deal_health((select pipeline_id from public.opportunities where id = v_id)) -> 0 ->> 'noNextStep')::boolean is not true then
    raise exception 'health %', better_supabase.deal_health((select pipeline_id from public.opportunities where id = v_id));
  end if;
  v_closed := better_supabase.close_deal(v_id, 'lost', 'went elsewhere');
  if (select result from public.opportunities where id = v_id) <> 'lost'
    or jsonb_array_length(v_closed -> 'members') <> 1 then
    raise exception 'closed %', v_closed;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses a product the app's table has no column for", async () => {
    await expect(
      run(`do $$
begin
  ${SERVICE}
  perform better_supabase.create_deal('${TENANT}', '{"name": "Acme", "closeOn": "2026-12-01", "currency": "EUR", "product": "pro"}'::jsonb, null);
end;
$$;`),
    ).rejects.toThrow(/no product column/);
  });
});
