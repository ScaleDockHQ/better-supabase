import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";

// The app's own cache table: renamed columns, an enum kind, and no model, hit
// counter or timestamps besides the expiry.
const APP = `
create type public.cache_kind as enum ('generate', 'stream', 'embed', 'other');

create table public.llm_cache (
  cache_key text primary key,
  org_id uuid,
  kind public.cache_kind not null default 'generate',
  payload jsonb not null,
  expires timestamptz not null
);
`;

const OWN_TABLES = { "public.llm_cache": "app.sql" };

const BLOCKS: AnyBlocksConfig = {
  "ai-cache": {
    tables: { entries: "public.llm_cache" },
    columns: {
      entries: {
        key: "cache_key",
        tenant: "org_id",
        value: "payload",
        expiresAt: "expires",
        model: null,
        hits: null,
        createdAt: null,
        lastHitAt: null,
      },
    },
  },
};

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["ai-cache"], {
    modules: BLOCKS,
    ownTables: OWN_TABLES,
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
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("ai-cache over the app's table", BOOT, () => {
  it("stores, replaces, reads and deletes entries without the optional columns", async () => {
    await expect(
      run(`do $$
declare
  v_entry jsonb;
begin
  v_entry := better_supabase.ai_cache_set('k1', '{"text": "hi"}'::jsonb, 60, '${TENANT}', 'embed');
  if v_entry ->> 'kind' <> 'embed' or v_entry -> 'model' <> 'null'::jsonb or (v_entry ->> 'hits')::integer <> 0 then
    raise exception 'stored %', v_entry;
  end if;
  perform better_supabase.ai_cache_set('k1', '{"text": "again"}'::jsonb, 60, '${TENANT}', 'generate');
  if (select count(*) from public.llm_cache) <> 1 or (select kind from public.llm_cache) <> 'generate' then
    raise exception 'replaced into % rows', (select count(*) from public.llm_cache);
  end if;
  v_entry := better_supabase.ai_cache_get('k1');
  if v_entry -> 'value' ->> 'text' <> 'again' then
    raise exception 'read %', v_entry;
  end if;
  if better_supabase.ai_cache_delete(tenant => '${TENANT}') <> 1 then
    raise exception 'deleted nothing';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
