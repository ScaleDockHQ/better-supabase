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
});
