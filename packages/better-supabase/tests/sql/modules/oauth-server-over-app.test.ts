import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const ADA = "33333333-3333-4333-8333-333333333333";
const SECRET = "a".repeat(64);
const TOKEN = "b".repeat(64);
const CODE = "c".repeat(64);
const DEVICE = "d".repeat(64);
const CHALLENGE = "E".repeat(43);

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// The app's own OAuth tables: enum auth methods and device statuses, a
// private column on clients, none of the optional columns, and no primary
// key on the revocation list.
const APP = `
create type public.client_auth as enum ('none', 'client_secret_basic', 'client_secret_post');
create type public.device_state as enum ('pending', 'approved', 'denied');

create table public.apps (
  id uuid primary key default gen_random_uuid(),
  client_id text not null unique,
  secret_hash text,
  registration_token_hash text,
  redirect_uris text[] not null default '{}',
  grant_types text[] not null default '{authorization_code}',
  auth_method public.client_auth not null default 'client_secret_basic',
  scope text,
  created_at timestamptz not null default now(),
  note text default 'private'
);

create table public.app_grants (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  client_id text not null,
  scopes text[] not null default '{}',
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);

create table public.app_codes (
  code_hash text primary key,
  client_id text not null,
  user_id uuid not null,
  grant_id uuid not null,
  redirect_uri text,
  scope text not null default '',
  resource text[] not null default '{}',
  code_challenge text not null,
  expires_at timestamptz not null,
  consumed_at timestamptz
);

create table public.app_devices (
  device_code_hash text primary key,
  user_code text not null,
  client_id text not null,
  scope text not null default '',
  resource text[] not null default '{}',
  status public.device_state not null default 'pending',
  user_id uuid,
  grant_id uuid,
  poll_interval integer not null default 5,
  last_polled_at timestamptz,
  expires_at timestamptz not null,
  consumed_at timestamptz
);

create table public.app_revocations (
  jti text not null,
  expires_at timestamptz not null
);
`;

const OWN_TABLES = {
  "public.apps": "app.sql",
  "public.app_grants": "app.sql",
  "public.app_codes": "app.sql",
  "public.app_devices": "app.sql",
  "public.app_revocations": "app.sql",
};

const BLOCKS: AnyBlocksConfig = {
  "oauth-server": {
    tables: {
      clients: "public.apps",
      grants: "public.app_grants",
      codes: "public.app_codes",
      devices: "public.app_devices",
      revocations: "public.app_revocations",
    },
    columns: {
      clients: {
        authMethod: "auth_method",
        name: null,
        metadata: null,
        createdBy: null,
        updatedAt: null,
      },
      grants: { resource: null, updatedAt: null },
      codes: { nonce: null, createdAt: null },
      devices: { createdAt: null },
      revocations: { grantId: null, createdAt: null },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["oauth-server"], {
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
      `insert into auth.users (id) values ('${ADA}');`,
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("oauth-server over the app's tables", BOOT, () => {
  it("registers clients and redeems codes without exposing hashes", async () => {
    await expect(
      run(`do $$
declare
  v_client jsonb;
  v_code jsonb;
  v_grants jsonb;
begin
  ${SERVICE}
  v_client := better_supabase.register_oauth_client('cli', '${SECRET}', '${TOKEN}', 'CLI',
    array['https://app.test/cb'], null, 'client_secret_post', 'read', null);
  if (select auth_method from public.apps) <> 'client_secret_post' then
    raise exception 'auth method %', v_client;
  end if;
  if v_client::text like '%${SECRET}%' or v_client::text like '%${TOKEN}%' or v_client::text like '%private%' then
    raise exception 'leaked %', v_client;
  end if;
  if better_supabase.verify_oauth_client('cli', '${SECRET}') is null
    or not better_supabase.verify_oauth_registration_token('cli', '${TOKEN}') then
    raise exception 'verify';
  end if;
  perform better_supabase.update_oauth_client('cli', 'Renamed', null, null, 'read write', null);
  perform better_supabase.create_oauth_authorization_code('${CODE}', 'cli', '${ADA}',
    'https://app.test/cb', 'read', '${CHALLENGE}', interval '5 minutes', 'nonce-1');
  v_code := better_supabase.redeem_oauth_authorization_code('${CODE}', 'cli', 'https://app.test/cb', '${CHALLENGE}');
  if v_code ->> 'status' <> 'ok' or v_code ->> 'nonce' is not null then
    raise exception 'redeemed %', v_code;
  end if;
  if better_supabase.redeem_oauth_authorization_code('${CODE}', 'cli', 'https://app.test/cb', '${CHALLENGE}') ->> 'replayed' <> 'true' then
    raise exception 'replay';
  end if;
  v_grants := better_supabase.list_oauth_grants('${ADA}', true);
  if jsonb_array_length(v_grants) <> 1 or v_grants::text like '%${SECRET}%' then
    raise exception 'grants %', v_grants;
  end if;
  perform better_supabase.revoke_oauth_token('jti-1', now() + interval '1 hour');
  perform better_supabase.revoke_oauth_token('jti-1', now() + interval '1 hour');
  if not better_supabase.is_oauth_token_revoked('jti-1') then
    raise exception 'not revoked';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("approves device codes into an enum status", async () => {
    await expect(
      run(`do $$
declare
  v_poll jsonb;
begin
  ${SERVICE}
  perform better_supabase.register_oauth_client('tv', null, null, 'TV', '{}',
    array['urn:ietf:params:oauth:grant-type:device_code'], 'none', 'read', null);
  perform better_supabase.create_oauth_device_code('${DEVICE}', 'ABCDEF', 'tv', 'read', interval '10 minutes');
  if not better_supabase.decide_oauth_device_code('ABCDEF', '${ADA}', true) then
    raise exception 'decide';
  end if;
  if (select status from public.app_devices) <> 'approved' then
    raise exception 'status';
  end if;
  v_poll := better_supabase.poll_oauth_device_code('${DEVICE}', 'tv');
  if v_poll ->> 'status' <> 'ok' then
    raise exception 'poll %', v_poll;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
