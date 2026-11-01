import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";
const PRODUCT = "33333333-3333-4333-8333-333333333333";
const VARIANT = "44444444-4444-4444-8444-444444444444";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// The app's own carts and orders: renamed columns, enum statuses, and no
// email, billing address, cancel reason or tax transaction columns. The
// render adds the columns the app's tables lack.
const APP = `
create type public.basket_state as enum ('open', 'converted', 'abandoned');
create type public.purchase_state as enum ('pending_payment', 'paid', 'partially_fulfilled', 'fulfilled', 'completed', 'cancelled', 'refunded');

create table public.baskets (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  shopper_id uuid not null,
  currency char(3) not null,
  state public.basket_state not null default 'open',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.purchases (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  number text not null,
  state public.purchase_state not null default 'pending_payment',
  currency char(3) not null,
  total bigint not null default 0
);
`;

const OWN_TABLES = {
  "public.baskets": "app.sql",
  "public.purchases": "app.sql",
};

const BLOCKS: AnyBlocksConfig = {
  orders: {
    tables: { carts: "public.baskets", orders: "public.purchases" },
    columns: {
      carts: {
        tenant: "org_id",
        user: "shopper_id",
        status: "state",
        email: null,
        billingAddress: null,
      },
      orders: {
        tenant: "org_id",
        status: "state",
        email: null,
        billingAddress: null,
        cancelReason: null,
        taxTransaction: null,
      },
    },
  },
};

// Everyone may do everything in the tenant: these tests are about the tables.
const ALLOW = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.can_user(member uuid, scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $$ select '${TENANT}'::uuid $$;
insert into auth.users (id) values ('${ALICE}');
insert into better_supabase.memberships (organization_id, user_id, role) values ('${TENANT}', '${ALICE}', 'owner');
insert into better_supabase.products (id, tenant_id, slug, title, kind, status)
  values ('${PRODUCT}', '${TENANT}', 'mug', 'Mug', 'digital', 'active');
insert into better_supabase.product_variants (id, tenant_id, product_id, sku, track_inventory)
  values ('${VARIANT}', '${TENANT}', '${PRODUCT}', 'MUG-1', false);
insert into better_supabase.product_prices (tenant_id, variant_id, currency, amount)
  values ('${TENANT}', '${VARIANT}', 'EUR', 1250);
`;

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

const AS_ALICE = `perform set_config('request.jwt.claims', '{"sub":"${ALICE}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${ALICE}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["orders"], {
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
      ALLOW,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("orders over the app's tables", BOOT, () => {
  it("fills a cart, places the order and records a payment in enum columns", async () => {
    await expect(
      run(`do $$
declare
  v_cart uuid;
  v_order jsonb;
  v_id uuid;
  v_board jsonb;
begin
  ${AS_ALICE}
  v_cart := (better_supabase.create_cart('${TENANT}', 'EUR') ->> 'id')::uuid;
  perform better_supabase.add_to_cart(v_cart, '${VARIANT}', 2);
  perform better_supabase.add_to_cart(v_cart, '${VARIANT}', 1);
  if (select quantity from better_supabase.cart_lines where cart_id = v_cart) <> 3 then
    raise exception 'cart line upsert';
  end if;
  ${SERVICE}
  v_order := better_supabase.place_order(v_cart);
  v_id := (v_order ->> 'id')::uuid;
  if (select state from public.baskets where id = v_cart) <> 'converted'
    or (select state from public.purchases where id = v_id) <> 'pending_payment'
    or (select total from public.purchases where id = v_id) <> 3750 then
    raise exception 'placed %', v_order;
  end if;
  perform better_supabase.record_payment(v_id, 'test', 'pay_1', 'succeeded', 'EUR', 3750, 3750);
  perform better_supabase.record_payment(v_id, 'test', 'pay_1', 'succeeded', 'EUR', 3750, 3750);
  if (select count(*) from better_supabase.order_payments) <> 1 or (select state from public.purchases where id = v_id) <> 'paid' then
    raise exception 'paid %', (select state from public.purchases where id = v_id);
  end if;
  v_board := better_supabase.order_status_board('${TENANT}');
  if v_board #>> '{columns,0,status}' <> 'paid'
    or v_board #>> '{columns,0,count}' <> '1'
    or v_board #>> '{columns,0,totals,0,total}' <> '3750'
    or v_board #>> '{columns,0,orders,0,id}' <> v_id::text then
    raise exception 'board %', v_board;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses an email the app's cart table has no column for", async () => {
    await expect(
      run(`do $$
begin
  ${AS_ALICE}
  perform better_supabase.create_cart('${TENANT}', 'EUR', null, 'alice@example.com');
end;
$$;`),
    ).rejects.toThrow(/no email column/);
  });
});
