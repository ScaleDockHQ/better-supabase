import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const files = renderBlocks(["inventory"]);

const sql = files.map((file) => file.contents).join("\n");

const page = sql.slice(
  sql.indexOf(
    'create or replace function "better_supabase"."page_inventory_movements"',
  ),
);

// The movement JSON's productId lookup, as the page function renders it.
const productOf = page.slice(
  page.indexOf("'productId', ") + "'productId', ".length,
  page.indexOf(",\n      'locationId'"),
);

describe("page_inventory_movements", () => {
  it("resolves the product filter's variants once, not per row", () => {
    expect(page).toMatch(
      /\(x\."metadata" ->> 'variantId'\)::uuid in \(select v\."id" from "better_supabase"\."product_variants" v where/,
    );
  });

  it(
    "looks up a movement's product through the variant key's index",
    { timeout: 60_000 },
    async () => {
      await using stack = await liteStack({
        driver: "pglite",
        migrations: [
          `do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end $$;`,
          ...files
            .filter((file) => file.kind === "schema")
            .map((file) =>
              file.contents.replaceAll(
                /^create extension[^;]*btree_gist[^;]*;$/gim,
                "",
              ),
            ),
        ],
        seed: [
          `do $$
declare
  v_line text;
  v_plan text := '';
begin
  set local enable_seqscan = off;
  for v_line in execute 'explain select ${productOf.replaceAll("'", "''")} from better_supabase.ledger_transactions x' loop
    v_plan := v_plan || v_line || chr(10);
  end loop;
  if v_plan not like '%Index%product_variants%' then
    raise exception 'no index scan on the variants: %', v_plan;
  end if;
end $$;`,
        ],
      });

      expect(stack.url).not.toBe("");
    },
  );
});
