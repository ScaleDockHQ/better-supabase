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

const VARIANT_APP = `${APP}
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
  manufacturer_part_number text,
  purchase_price_cents bigint,
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, sku)
);
create table public.item_categories (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  parent_id uuid references public.item_categories (id),
  name text not null,
  slug text not null,
  description text,
  icon text not null default 'Package',
  position integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, slug)
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

const VARIANT_BLOCKS: AnyBlocksConfig = {
  catalog: {
    ...BLOCKS["catalog"],
    tables: {
      products: "public.items",
      variants: "public.item_variants",
      options: "public.item_options",
      optionValues: "public.item_option_values",
      categories: "public.item_categories",
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
      options: { tenant: "org_id", product: "item_id", rank: "position" },
      optionValues: { tenant: "org_id", rank: "position" },
      categories: { tenant: "org_id", rank: "position" },
    },
    options: {
      rankType: "integer",
      variantExtraColumns: {
        manufacturer_part_number: "text",
        purchase_price_cents: "bigint",
        is_default: "boolean not null default false",
      },
      categoryExtraColumns: { icon: "text not null default 'Package'" },
    },
  },
};

const VARIANT_OWN = {
  "public.items": "app.sql",
  "public.item_variants": "app.sql",
  "public.item_options": "app.sql",
  "public.item_option_values": "app.sql",
  "public.item_categories": "app.sql",
};

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
  if v_moved ->> 'from' <> 'archived' or (select status::text from public.items where id = v_id) <> 'archived' then
    raise exception 'canonical %', v_moved;
  end if;
  v_moved := better_supabase.set_product_status(v_id, 'discontinued');
  if v_moved ->> 'status' <> 'archived' or (select status::text from public.items where id = v_id) <> 'discontinued' then
    raise exception 'app label %', v_moved;
  end if;
  v_moved := better_supabase.set_product_status(v_id, 'active');
  if (select status::text from public.items where id = v_id) <> 'active' then
    raise exception 'reactivated %', v_moved;
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
      const files = renderBlocks(["catalog"], {
        modules: VARIANT_BLOCKS,
        ownTables: VARIANT_OWN,
      });

      await using stack = await liteStack({
        driver: "pglite",
        migrations: [
          VARIANT_APP,
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
  v_variant jsonb;
  v_category jsonb;
begin
  ${SERVICE}
  v_product := (better_supabase.save_product('${TENANT}', null, 'Shirt', null, null, 'physical', 990, 'usd', false) ->> 'id')::uuid;
  if (select row(default_price_cents, currency, track_inventory)::text from public.items where id = v_product) <> '(990,USD,f)' then
    raise exception 'product settings %', (select row_to_json(i) from public.items i where id = v_product);
  end if;
  perform better_supabase.save_product('${TENANT}', v_product, 'Shirt', null, null, null, null, 'eur', null);
  if (select row(default_price_cents, currency, track_inventory)::text from public.items where id = v_product) <> '(990,EUR,f)' then
    raise exception 'kept settings %', (select row_to_json(i) from public.items i where id = v_product);
  end if;
  v_category := better_supabase.save_category('${TENANT}', null, null, 'Shirts', null, null, '{"icon": "Shirt"}');
  if v_category -> 'fields' ->> 'icon' <> 'Shirt' or (select icon from public.item_categories) <> 'Shirt' then
    raise exception 'category %', v_category;
  end if;
  perform better_supabase.save_category('${TENANT}', (v_category ->> 'id')::uuid, null, 'Tops', null, null, null);
  if (select icon from public.item_categories) <> 'Shirt' then
    raise exception 'kept icon %', (select icon from public.item_categories);
  end if;
  v_option := better_supabase.save_product_option(v_product, null, 'Size', array['S', 'L']);
  if (select position from public.item_options where item_id = v_product) <> 1
    or (select array_agg(position order by value desc) from public.item_option_values) <> array[1, 2] then
    raise exception 'option ranks %', v_option;
  end if;
  v_variant := better_supabase.save_variant(v_product, null, 'SHIRT-S', array[(v_option -> 'values' -> 0 ->> 'id')::uuid], null, null, null, null, null,
    fields => '{"manufacturer_part_number": "MPN-1", "purchase_price_cents": 400, "is_default": true}');
  v_small := (v_variant ->> 'id')::uuid;
  if v_variant -> 'fields' ->> 'manufacturer_part_number' <> 'MPN-1'
    or (select row(purchase_price_cents, is_default)::text from public.item_variants where id = v_small) <> '(400,t)' then
    raise exception 'variant fields %', v_variant;
  end if;
  perform better_supabase.save_variant(v_product, v_small, 'SHIRT-S', array[(v_option -> 'values' -> 0 ->> 'id')::uuid], null, null, null, null, null, fields => '{"is_default": false}');
  if (select row(manufacturer_part_number, is_default)::text from public.item_variants where id = v_small) <> '(MPN-1,f)' then
    raise exception 'variant update %', (select row_to_json(v) from public.item_variants v where id = v_small);
  end if;
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

  it(
    "clears product settings, adds options over a default variant and patches variants",
    { timeout: 60_000 },
    async () => {
      const files = renderBlocks(["catalog"], {
        modules: VARIANT_BLOCKS,
        ownTables: VARIANT_OWN,
      });

      await using stack = await liteStack({
        driver: "pglite",
        migrations: [
          VARIANT_APP,
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
  v_variant uuid;
  v_option jsonb;
begin
  ${SERVICE}
  v_product := (better_supabase.save_product('${TENANT}', null, 'Mug', null, null, 'physical', 990, 'eur', true) ->> 'id')::uuid;
  perform better_supabase.save_product('${TENANT}', v_product, 'Mug', null, null, null, null, null, null, clear => array['price']);
  if (select default_price_cents from public.items where id = v_product) is not null
    or (select currency from public.items where id = v_product) <> 'EUR' then
    raise exception 'cleared %', (select row_to_json(i) from public.items i where id = v_product);
  end if;
  v_variant := (better_supabase.save_variant(v_product, null, 'MUG', null, null, null, null, null, true) ->> 'id')::uuid;
  v_option := better_supabase.save_product_option(v_product, null, 'Colour', array['White', 'Black']);
  if (select count(*) from better_supabase.product_variant_values where variant_id = v_variant) <> 1 then
    raise exception 'default variant got no value %', v_option;
  end if;
  perform better_supabase.save_variant(v_product, v_variant, null, null, null, null, null, null, null);
  if (select row(sku, allow_backorder)::text from public.item_variants where id = v_variant) <> '(MUG,t)'
    or (select count(*) from better_supabase.product_variant_values where variant_id = v_variant) <> 1 then
    raise exception 'patched %', (select row_to_json(v) from public.item_variants v where id = v_variant);
  end if;
end;
$$;`,
        ],
      });

      expect(stack.url).not.toBe("");
    },
  );

  it(
    "inserts extra columns with the row, patches with clears, reorders options and retires referenced variants",
    { timeout: 60_000 },
    async () => {
      const catalog = VARIANT_BLOCKS["catalog"];

      const blocks: AnyBlocksConfig = {
        catalog: {
          ...catalog,
          columns: {
            ...catalog?.columns,
            products: {
              ...catalog?.columns?.["products"],
              description: "description",
            },
            variants: {
              ...catalog?.columns?.["variants"],
              barcode: "ean",
              status: "status",
            },
          },
          values: {
            ...catalog?.values,
            variants: { status: { archived: ["archived", "discontinued"] } },
          },
          options: {
            ...catalog?.options,
            extraColumns: { digital_delivery: "text" },
            variantInUse: "public.variant_in_use",
          },
        },
      };

      const files = renderBlocks(["catalog"], {
        modules: blocks,
        ownTables: VARIANT_OWN,
      });

      await using stack = await liteStack({
        driver: "pglite",
        migrations: [
          `${VARIANT_APP}
alter table public.items add column description text;
alter table public.items add column digital_delivery text;
alter table public.items add constraint items_digital check ((item_type = 'digital') = (digital_delivery is not null));
alter table public.item_variants alter column sku drop not null;
alter table public.item_variants add column ean text;
alter table public.item_variants add column status public.item_status not null default 'active';
create table public.order_lines (id uuid primary key default gen_random_uuid(), variant_id uuid not null references public.item_variants (id));
create table public.pinned_variants (variant_id uuid primary key);
create function public.variant_in_use(variant uuid) returns boolean language sql stable as $$
  select exists (select 1 from public.pinned_variants p where p.variant_id = variant);
$$;`,
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
  v_digital uuid;
  v_product uuid;
  v_size jsonb;
  v_colour jsonb;
  v_small uuid;
  v_medium uuid;
  v_large uuid;
begin
  ${SERVICE}
  v_digital := (better_supabase.save_product('${TENANT}', null, 'Manual', null, 'A guide', 'digital', null, null, null, fields => '{"digital_delivery": "download"}') ->> 'id')::uuid;
  if (select digital_delivery from public.items where id = v_digital) <> 'download' then
    raise exception 'digital %', (select row_to_json(i) from public.items i where id = v_digital);
  end if;
  perform better_supabase.save_product('${TENANT}', v_digital, null, 'user-guide', null, null, null, null, null);
  if (select row(name, slug, description)::text from public.items where id = v_digital) <> '(Manual,user-guide,"A guide")' then
    raise exception 'patched %', (select row_to_json(i) from public.items i where id = v_digital);
  end if;
  perform better_supabase.save_product('${TENANT}', v_digital, 'Handbook', null, null, null, null, null, null, clear => array['description', 'slug']);
  if (select row(name, slug, description)::text from public.items where id = v_digital) <> '(Handbook,handbook,)' then
    raise exception 'cleared %', (select row_to_json(i) from public.items i where id = v_digital);
  end if;
  v_product := (better_supabase.save_product('${TENANT}', null, 'Tee', null, null, 'physical', null, null, null) ->> 'id')::uuid;
  v_size := better_supabase.save_product_option(v_product, null, 'Size', array['S', 'M', 'L']);
  v_colour := better_supabase.save_product_option(v_product, null, 'Colour', array['Red']);
  v_small := (better_supabase.save_variant(v_product, null, 'TEE-S', array[(v_size -> 'values' -> 0 ->> 'id')::uuid, (v_colour -> 'values' -> 0 ->> 'id')::uuid], null, '871', null, null, null) ->> 'id')::uuid;
  v_medium := (better_supabase.save_variant(v_product, null, 'TEE-M', array[(v_size -> 'values' -> 1 ->> 'id')::uuid, (v_colour -> 'values' -> 0 ->> 'id')::uuid], null, null, null, null, null) ->> 'id')::uuid;
  v_large := (better_supabase.save_variant(v_product, null, 'TEE-L', array[(v_size -> 'values' -> 2 ->> 'id')::uuid, (v_colour -> 'values' -> 0 ->> 'id')::uuid], null, null, null, null, null) ->> 'id')::uuid;
  perform better_supabase.save_variant(v_product, v_small, null, null, null, null, null, null, null, clear => array['sku', 'barcode']);
  if (select row(sku, ean)::text from public.item_variants where id = v_small) <> '(,)' then
    raise exception 'variant cleared %', (select row_to_json(v) from public.item_variants v where id = v_small);
  end if;
  perform better_supabase.reorder_product_options(v_product, array[(v_colour ->> 'id')::uuid, (v_size ->> 'id')::uuid]);
  if (select array_agg(name order by position) from public.item_options where item_id = v_product) <> array['Colour', 'Size'] then
    raise exception 'reordered %', (select array_agg(name order by position) from public.item_options where item_id = v_product);
  end if;
  insert into public.order_lines (variant_id) values (v_medium);
  insert into public.pinned_variants (variant_id) values (v_large);
  perform better_supabase.save_product_option(v_product, (v_size ->> 'id')::uuid, 'Size', array['XL']);
  if exists (select 1 from public.item_variants where id = v_small)
    or (select status::text from public.item_variants where id = v_medium) <> 'archived'
    or (select status::text from public.item_variants where id = v_large) <> 'archived'
    or (select array_agg(value) from public.item_option_values where option_id = (v_size ->> 'id')::uuid) <> array['XL'] then
    raise exception 'retired %', (select jsonb_agg(row_to_json(v)) from public.item_variants v);
  end if;
end;
$$;`,
        ],
      });

      expect(stack.url).not.toBe("");
    },
  );

  it("checks separate create, update and delete keys when the config names them", () => {
    const sql = renderBlocks(["catalog"], {
      modules: {
        catalog: {
          permissions: {
            create: "product.create",
            update: "product.update",
            delete: "product.delete",
          },
        },
      },
    })
      .filter((file) => file.module === "catalog")
      .map((file) => file.contents)
      .join("\n");

    const body = (name: string): string =>
      sql.slice(
        sql.indexOf(`function "better_supabase"."${name}"`),
        sql.indexOf("$$;", sql.indexOf(`function "better_supabase"."${name}"`)),
      );

    expect(body("save_product")).toContain("'product.create'");
    expect(body("save_product")).toContain("'product.update'");
    expect(body("set_product_status")).toContain("'product.update'");
    expect(body("delete_product")).toContain("'product.delete'");
    expect(body("delete_variant")).toContain("'product.delete'");
    expect(body("set_price")).toContain("'catalog.manage'");
  });

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
