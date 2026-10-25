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

// The app's own registry of audited tables: renamed columns, only the ignore
// list, and no primary key.
const APP = `
create table public.audit_registry (
  tbl regclass not null,
  skip text[] not null default '{}'
);
create table public.customers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid,
  name text
);
`;

const BLOCKS: AnyBlocksConfig = {
  audit: {
    tables: { registry: "public.audit_registry" },
    columns: {
      registry: {
        target: "tbl",
        ignore: "skip",
        keyColumns: null,
        redact: null,
        category: null,
        eventPrefix: null,
        targetType: null,
        tenantColumn: null,
        labelColumn: null,
      },
    },
  },
};

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["audit"], {
    modules: BLOCKS,
    ownTables: { "public.audit_registry": "app.sql" },
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

describe("audit registry over the app's table", BOOT, () => {
  it("reads legacy settings from it and forgets unaudited tables", async () => {
    await expect(
      run(`insert into public.audit_registry (tbl, skip) values ('public.customers', '{name}');
do $$
begin
  if better_supabase.audit_settings('public.customers') <> '{"ignore": ["name"]}'::jsonb then
    raise exception 'settings %', better_supabase.audit_settings('public.customers');
  end if;
  perform better_supabase.audit('public.customers');
  if exists (select 1 from public.audit_registry) then
    raise exception 'audit() kept the legacy row';
  end if;
  insert into public.audit_registry (tbl) values ('public.customers');
  perform better_supabase.unaudit('public.customers'::regclass);
  if exists (select 1 from public.audit_registry) then
    raise exception 'unaudit() kept the row';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
