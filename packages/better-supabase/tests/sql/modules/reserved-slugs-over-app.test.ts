import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// The app's own word list: a renamed column, no reason and no primary key.
// The data files add the module's words to it.
const APP = `
create table public.blocked_names (
  word text not null
);
create table public.teams (
  id uuid primary key default gen_random_uuid(),
  handle text not null
);
`;

const BLOCKS: AnyBlocksConfig = {
  "reserved-slugs": {
    options: { slugs: ["billing-portal"] },
    tables: { slugs: "public.blocked_names" },
    columns: { slugs: { slug: "word", reason: null } },
  },
};

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["reserved-slugs"], {
    modules: BLOCKS,
    ownTables: { "public.blocked_names": "app.sql" },
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

describe("reserved-slugs over the app's tables", BOOT, () => {
  it("adds its words to the app's list and enforces all of them", async () => {
    await expect(
      run(`insert into public.blocked_names (word) values ('acme');
do $$
begin
  if (select count(*) from public.blocked_names where word = 'admin') <> 1
    or not exists (select 1 from public.blocked_names where word = 'www')
    or not exists (select 1 from public.blocked_names where word = 'billing-portal') then
    raise exception 'words %', (select jsonb_agg(b.word) from public.blocked_names b);
  end if;
  if better_supabase.slug_problem('acme') is distinct from 'reserved'
    or better_supabase.slug_problem('Bad Slug') is distinct from 'invalid'
    or better_supabase.slug_problem('my-team') is not null then
    raise exception 'slug_problem';
  end if;
  perform better_supabase.track_slug('public.teams', 'handle');
  insert into public.teams (handle) values ('my-team');
  begin
    insert into public.teams (handle) values ('acme');
    raise exception 'a reserved handle went in';
  exception when check_violation then
    null;
  end;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
