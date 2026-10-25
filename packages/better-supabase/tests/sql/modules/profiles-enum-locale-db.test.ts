import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";
import { ownTablesOf } from "../../fixtures/own-tables.ts";

const ADA = "11111111-1111-4111-8111-111111111111";
const BOB = "22222222-2222-4222-8222-222222222222";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

const APP = `
create type public.app_locale as enum ('en', 'nl', 'de');

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  username text,
  locale public.app_locale,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
`;

const BLOCKS: AnyBlocksConfig = {
  profiles: {
    tables: { profiles: "public.profiles" },
    columns: { profiles: { locale: "locale" } },
    options: { metadata: { locale: "locale" } },
  },
};

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["profiles"], {
    modules: BLOCKS,
    ownTables: ownTablesOf(BLOCKS),
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

describe("profiles over an app table with an enum locale", BOOT, () => {
  it("signs up with a locale label, and with one the enum lacks", async () => {
    await expect(
      run(`insert into auth.users (id, email, raw_user_meta_data) values
  ('${ADA}', 'ada@example.com', '{"locale": "nl"}'),
  ('${BOB}', 'bob@example.com', '{"locale": "xx"}');
do $$
declare
  v_ada public.app_locale;
  v_bob public.app_locale;
begin
  perform better_supabase.sync_profile('${ADA}');
  perform better_supabase.sync_profile('${BOB}');
  select locale into v_ada from public.profiles where id = '${ADA}';
  select locale into v_bob from public.profiles where id = '${BOB}';
  if v_ada is distinct from 'nl' or v_bob is not null then
    raise exception 'synced % and %', v_ada, v_bob;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("updates the locale through update_my_profile", async () => {
    await expect(
      run(`insert into auth.users (id, email) values ('${ADA}', 'ada@example.com');
do $$
declare
  v_locale public.app_locale;
begin
  perform better_supabase.sync_profile('${ADA}');
  perform set_config('request.jwt.claim.sub', '${ADA}', true);
  perform better_supabase.update_my_profile('{"locale": "de"}');
  select locale into v_locale from public.profiles where id = '${ADA}';
  if v_locale is distinct from 'de' then
    raise exception 'updated to %', v_locale;
  end if;
  begin
    perform better_supabase.update_my_profile('{"locale": "xx"}');
    raise exception 'accepted a label the enum lacks';
  exception when invalid_text_representation then
    null;
  end;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
