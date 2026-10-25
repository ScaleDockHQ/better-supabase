import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// The app's own keys table: renamed columns, an enum kind, and no rate limit
// window, last use, rotation or creator columns.
const APP = `
create type public.token_kind as enum ('test', 'live');

create table public.app_tokens (
  id uuid primary key default gen_random_uuid(),
  org_id uuid,
  user_id uuid,
  label text not null,
  prefix text not null,
  public_id text not null,
  secret_hash text not null,
  scopes text[] not null default '{}',
  kind public.token_kind,
  expires_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);
`;

const OWN_TABLES = { "public.app_tokens": "app.sql" };

const BLOCKS: AnyBlocksConfig = {
  "api-keys": {
    tables: { keys: "public.app_tokens" },
    columns: {
      keys: {
        tenant: "org_id",
        name: "label",
        rateLimit: null,
        windowStart: null,
        windowHits: null,
        lastUsedAt: null,
        rotatedFrom: null,
        createdBy: null,
      },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["memberships", "permissions", "api-keys"], {
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
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("api-keys over the app's table", BOOT, () => {
  it("creates, verifies, rotates and revokes keys with an enum kind", async () => {
    await expect(
      run(`do $$
declare
  v_key jsonb;
  v_next jsonb;
  v_id uuid;
begin
  ${SERVICE}
  v_key := better_supabase.create_api_key('CI', 'pub1', 'hash1', '${TENANT}', kind => 'live');
  v_id := (v_key ->> 'id')::uuid;
  if (select kind from public.app_tokens where id = v_id) <> 'live' then
    raise exception 'created %', v_key;
  end if;
  if better_supabase.verify_api_key('pub1', 'hash1') ->> 'status' <> 'ok' then
    raise exception 'verify %', better_supabase.verify_api_key('pub1', 'hash1');
  end if;
  if better_supabase.verify_api_key('pub1', 'wrong') ->> 'status' <> 'invalid' then
    raise exception 'verified a wrong secret';
  end if;
  v_next := better_supabase.rotate_api_key(v_id, 'pub2', 'hash2', interval '0');
  if (select kind from public.app_tokens where public_id = 'pub2') <> 'live' then
    raise exception 'rotated %', v_next;
  end if;
  if better_supabase.verify_api_key('pub1', 'hash1') ->> 'status' <> 'invalid' then
    raise exception 'the rotated key still verifies';
  end if;
  perform better_supabase.revoke_api_key((v_next ->> 'id')::uuid);
  if better_supabase.verify_api_key('pub2', 'hash2') ->> 'status' <> 'invalid' then
    raise exception 'the revoked key still verifies';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
