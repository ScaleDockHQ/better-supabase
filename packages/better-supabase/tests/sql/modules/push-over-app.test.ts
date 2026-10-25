import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const ALICE = "11111111-1111-4111-8111-111111111111";
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

// The app's device table: renamed columns, an enum platform, no unique token
// and none of the name, version or timestamp columns.
const APP = `
create type public.device_platform as enum ('ios', 'android', 'web');

create table public.devices (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  push_token text not null,
  platform public.device_platform not null,
  provider text not null default 'expo'
);
`;

const BLOCKS: AnyBlocksConfig = {
  push: {
    tables: { devices: "public.devices" },
    columns: {
      devices: {
        user: "owner_id",
        token: "push_token",
        deviceName: null,
        appVersion: null,
        createdAt: null,
        lastSeenAt: null,
      },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config('request.jwt.claim.sub', '', true);`;

const as = (user: string): string =>
  `perform set_config('request.jwt.claims', '{"role":"authenticated","sub":"${user}"}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', '${user}', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["push"], {
    modules: BLOCKS,
    ownTables: { "public.devices": "app.sql" },
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

describe("push over the app's tables", BOOT, () => {
  it("registers, moves, reads and prunes tokens in the app's table", async () => {
    await expect(
      run(`do $$
declare
  v_first uuid;
  v_again uuid;
  v_tokens jsonb;
  v_pruned integer;
begin
  ${as(ALICE)}
  v_first := better_supabase.register_push_device('tok-1', 'ios');
  ${as(BOB)}
  v_again := better_supabase.register_push_device('tok-1', 'android', 'fcm');
  if v_again <> v_first then
    raise exception 'a second register made a new row';
  end if;
  if (select count(*) from public.devices) <> 1
    or (select owner_id from public.devices) <> '${BOB}'
    or (select platform from public.devices) <> 'android'::public.device_platform then
    raise exception 'devices %', (select jsonb_agg(to_jsonb(d)) from public.devices d);
  end if;
  begin
    perform better_supabase.register_push_device('tok-2', 'windows');
    raise exception 'an unknown platform went in';
  exception when invalid_parameter_value then
    null;
  end;
  ${SERVICE}
  v_tokens := better_supabase.push_tokens_for(array['${BOB}'::uuid]);
  if v_tokens <> jsonb_build_array(jsonb_build_object(
    'userId', '${BOB}', 'token', 'tok-1', 'platform', 'android', 'provider', 'fcm'
  )) then
    raise exception 'tokens %', v_tokens;
  end if;
  v_pruned := better_supabase.prune_push_tokens(array['tok-1']);
  if v_pruned <> 1 or exists (select 1 from public.devices) then
    raise exception 'pruned %', v_pruned;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
