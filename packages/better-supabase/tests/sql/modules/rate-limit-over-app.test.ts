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

// The app's own limits table: renamed columns and no primary key.
const APP = `
create table public.api_limits (
  route text not null,
  max_hits integer not null,
  per interval not null,
  claim text not null default 'sub'
);
`;

const BLOCKS: AnyBlocksConfig = {
  "rate-limit": {
    options: { preRequest: false },
    tables: { rules: "public.api_limits" },
    columns: {
      rules: {
        scope: "route",
        maxRequests: "max_hits",
        period: "per",
        keyClaim: "claim",
      },
    },
  },
};

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["rate-limit"], {
    modules: BLOCKS,
    ownTables: { "public.api_limits": "app.sql" },
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

describe("rate-limit over the app's tables", BOOT, () => {
  it("writes, replaces and applies a rule in the app's table", async () => {
    await expect(
      run(`do $$
begin
  perform better_supabase.set_rate_limit('/rpc/invite', 5);
  perform better_supabase.set_rate_limit('/rpc/invite', 1, interval '1 hour', 'email');
  if (select count(*) from public.api_limits) <> 1
    or (select max_hits || claim from public.api_limits) <> '1email' then
    raise exception 'rules %', (select jsonb_agg(l) from public.api_limits l);
  end if;
  if not (select h.allowed from better_supabase.hit_rate_limit('/rpc/invite', 'a') h)
    or (select h.allowed from better_supabase.hit_rate_limit('/rpc/invite', 'a') h) then
    raise exception 'the rule was not applied';
  end if;
  perform better_supabase.set_rate_limit('/rpc/invite', null);
  if exists (select 1 from public.api_limits) then
    raise exception 'the rule was not removed';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
