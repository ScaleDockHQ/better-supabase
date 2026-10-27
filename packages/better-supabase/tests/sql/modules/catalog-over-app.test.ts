import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";

const APP = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
create type public.item_status as enum ('active', 'discontinued', 'archived');
create type public.item_type as enum ('physical', 'digital');
create table public.items (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  name text not null,
  slug text not null,
  item_type public.item_type not null default 'physical',
  status public.item_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, slug)
);
`;

const BLOCKS: AnyBlocksConfig = {
  catalog: {
    tables: { products: "public.items" },
    columns: {
      products: {
        tenant: "org_id",
        title: "name",
        kind: "item_type",
        description: null,
      },
    },
    values: {
      products: {
        status: { draft: null, archived: ["archived", "discontinued"] },
        kind: { service: null },
      },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

describe("catalog over the app's products", () => {
  it(
    "writes enum kinds and moves statuses through a value map",
    { timeout: 60_000 },
    async () => {
      const files = renderBlocks(["catalog"], {
        modules: BLOCKS,
        ownTables: { "public.items": "app.sql" },
      });

      await using stack = await liteStack({
        driver: "pglite",
        migrations: [
          APP,
          ...files
            .filter((file) => file.kind !== "data")
            .map((file) => file.contents),
        ],
        seed: [
          ...files
            .filter((file) => file.kind === "data")
            .map((file) => file.contents),
          `do $$
declare
  v_product jsonb;
  v_id uuid;
  v_moved jsonb;
begin
  ${SERVICE}
  v_product := better_supabase.save_product('${TENANT}', null, 'Chair', null, null, 'digital');
  v_id := (v_product ->> 'id')::uuid;
  if v_product ->> 'status' <> 'active' or (select item_type::text from public.items where id = v_id) <> 'digital' then
    raise exception 'saved %', v_product;
  end if;
  v_moved := better_supabase.set_product_status(v_id, 'archived');
  if v_moved ->> 'from' <> 'active' or (select status::text from public.items where id = v_id) <> 'archived' then
    raise exception 'moved %', v_moved;
  end if;
  update public.items set status = 'discontinued' where id = v_id;
  v_moved := better_supabase.set_product_status(v_id, 'archived');
  if v_moved ->> 'from' <> 'archived' or (select status::text from public.items where id = v_id) <> 'discontinued' then
    raise exception 'kept %', v_moved;
  end if;
end;
$$;`,
        ],
      });

      expect(stack.url).not.toBe("");
    },
  );

  it(
    "ranks by integer positions and prices variants from their own columns",
    { timeout: 60_000 },
    async () => {
      const app = `${APP}
alter table public.items add column currency text not null default 'EUR';
alter table public.items add column default_price_cents bigint;
alter table public.items add column track_inventory boolean not null default true;
create table public.item_variants (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  item_id uuid not null references public.items (id) on delete cascade,
  sku text not null,
  allow_backorder boolean not null default false,
  position integer not null default 0,
  selling_price_cents bigint,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, sku)
);
create table public.item_options (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  item_id uuid not null references public.items (id) on delete cascade,
  name text not null,
  position integer not null default 0,
  unique (item_id, name)
);
create table public.item_option_values (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  option_id uuid not null references public.item_options (id) on delete cascade,
  value text not null,
  position integer not null default 0,
  unique (option_id, value)
);
`;

      const files = renderBlocks(["catalog"], {
        modules: {
          catalog: {
            ...BLOCKS["catalog"],
            tables: {
              products: "public.items",
              variants: "public.item_variants",
              options: "public.item_options",
              optionValues: "public.item_option_values",
              prices: null,
              priceLists: null,
            },
            columns: {
              products: {
                tenant: "org_id",
                title: "name",
                kind: "item_type",
                description: null,
                price: "default_price_cents",
              },
              variants: {
                tenant: "org_id",
                product: "item_id",
                title: null,
                barcode: null,
                weight: null,
                trackInventory: null,
                rank: "position",
                price: "selling_price_cents",
              },
              options: {
                tenant: "org_id",
                product: "item_id",
                rank: "position",
              },
              optionValues: { tenant: "org_id", rank: "position" },
            },
            options: { rankType: "integer" },
          },
        },
        ownTables: {
          "public.items": "app.sql",
          "public.item_variants": "app.sql",
          "public.item_options": "app.sql",
          "public.item_option_values": "app.sql",
        },
      });

      await using stack = await liteStack({
        driver: "pglite",
        migrations: [
          app,
          ...files
            .filter((file) => file.kind !== "data")
            .map((file) => file.contents),
        ],
        seed: [
          ...files
            .filter((file) => file.kind === "data")
            .map((file) => file.contents),
          `do $$
declare
  v_product uuid;
  v_option jsonb;
  v_small uuid;
  v_large uuid;
  v_price jsonb;
begin
  ${SERVICE}
  v_product := (better_supabase.save_product('${TENANT}', null, 'Shirt', null, null, 'physical') ->> 'id')::uuid;
  update public.items set default_price_cents = 990 where id = v_product;
  v_option := better_supabase.save_product_option(v_product, null, 'Size', array['S', 'L']);
  if (select position from public.item_options where item_id = v_product) <> 1
    or (select array_agg(position order by value desc) from public.item_option_values) <> array[1, 2] then
    raise exception 'option ranks %', v_option;
  end if;
  v_small := (better_supabase.save_variant(v_product, null, 'SHIRT-S', array[(v_option -> 'values' -> 0 ->> 'id')::uuid], null, null, null, null, null) ->> 'id')::uuid;
  v_large := (better_supabase.save_variant(v_product, null, 'SHIRT-L', array[(v_option -> 'values' -> 1 ->> 'id')::uuid], null, null, null, null, null) ->> 'id')::uuid;
  if (select position from public.item_variants where id = v_large) <> 2 then
    raise exception 'variant rank %', (select position from public.item_variants where id = v_large);
  end if;
  perform better_supabase.rank_variant(v_large, '0');
  if (select position from public.item_variants where id = v_large) <> 0 then
    raise exception 'ranked %', (select position from public.item_variants where id = v_large);
  end if;
  v_price := better_supabase.set_price(v_small, 'EUR', '1500', null, null, null, null);
  if (select selling_price_cents from public.item_variants where id = v_small) <> 1500 then
    raise exception 'set %', v_price;
  end if;
  if better_supabase.variant_price(v_small, 'EUR') ->> 'amount' <> '1500'
    or better_supabase.variant_price(v_large, 'EUR') ->> 'amount' <> '990'
    or better_supabase.variant_price(v_small, 'USD') is not null then
    raise exception 'prices %', better_supabase.variant_price(v_large, 'EUR');
  end if;
  begin
    perform better_supabase.set_price(v_small, 'USD', '1500', null, null, null, null);
    raise exception 'another currency was accepted';
  exception when others then
    if sqlerrm = 'another currency was accepted' then
      raise;
    end if;
  end;
  begin
    perform better_supabase.save_variant(v_product, v_small, 'SHIRT-S', array[(v_option -> 'values' -> 0 ->> 'id')::uuid], null, null, null, false, null);
    raise exception 'a variant tracking flag was accepted';
  exception when others then
    if sqlerrm = 'a variant tracking flag was accepted' then
      raise;
    end if;
  end;
  perform better_supabase.delete_price(v_small);
  if better_supabase.variant_price(v_small, 'EUR') ->> 'amount' <> '990' then
    raise exception 'deleted %', better_supabase.variant_price(v_small, 'EUR');
  end if;
end;
$$;`,
        ],
      });

      expect(stack.url).not.toBe("");
    },
  );

  it("reads inventory tracking from the product when variants have no column", () => {
    const sql = renderBlocks(["catalog", "inventory"], {
      modules: { catalog: { columns: { variants: { trackInventory: null } } } },
    })
      .filter((file) => file.module === "inventory")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain(
      '"track_inventory" from "better_supabase"."products"',
    );
    expect(() =>
      renderBlocks(["catalog"], {
        modules: { catalog: { options: { rankType: "fractional" } } },
      }),
    ).toThrow(/rankType/);
  });
});
