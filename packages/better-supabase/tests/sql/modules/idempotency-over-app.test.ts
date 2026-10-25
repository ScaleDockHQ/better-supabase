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

// The app's own request keys and locks: renamed columns, an enum status, no
// created_at and no primary keys.
const APP = `
create type public.request_state as enum ('running', 'completed');

create table public.request_keys (
  tenant_scope text not null default '',
  request_key text not null,
  body_hash text not null,
  state public.request_state not null default 'running',
  code integer,
  body jsonb,
  locked_until timestamptz,
  expires_at timestamptz not null,
  owner uuid
);

create table public.locks (
  lock_scope text not null default '',
  lock_key text not null,
  owner uuid,
  expires_at timestamptz not null
);
`;

const BLOCKS: AnyBlocksConfig = {
  idempotency: {
    tables: { keys: "public.request_keys", leases: "public.locks" },
    columns: {
      keys: {
        scope: "tenant_scope",
        key: "request_key",
        requestHash: "body_hash",
        status: "state",
        statusCode: "code",
        response: "body",
        holder: "owner",
        createdAt: null,
      },
      leases: { scope: "lock_scope", key: "lock_key", holder: "owner" },
    },
  },
};

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["idempotency"], {
    modules: BLOCKS,
    ownTables: { "public.request_keys": "app.sql", "public.locks": "app.sql" },
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

describe("idempotency over the app's tables", BOOT, () => {
  it("begins, completes and replays a key, and holds one lease", async () => {
    await expect(
      run(`do $$
declare
  v_begin record;
  v_lease uuid;
begin
  select * into v_begin from better_supabase.begin_idempotent('api', 'k1', 'h1');
  if v_begin.state <> 'started' then
    raise exception 'first begin %', v_begin.state;
  end if;
  if (select b.state from better_supabase.begin_idempotent('api', 'k1', 'h1') b) <> 'running' then
    raise exception 'second begin is not running';
  end if;
  if not better_supabase.complete_idempotent('api', 'k1', v_begin.holder, 201, '{"ok":true}') then
    raise exception 'complete failed';
  end if;
  if (select r.state::text || r.code from public.request_keys r) <> 'completed201' then
    raise exception 'row %', (select jsonb_agg(r) from public.request_keys r);
  end if;
  if (select b.state || b.status_code from better_supabase.begin_idempotent('api', 'k1', 'h1') b) <> 'replay201' then
    raise exception 'no replay';
  end if;
  if (select b.state from better_supabase.begin_idempotent('api', 'k1', 'other') b) <> 'mismatch' then
    raise exception 'no mismatch';
  end if;

  v_lease := better_supabase.acquire_lease('job', 60, 'conv');
  if v_lease is null or better_supabase.acquire_lease('job', 60, 'conv') is not null then
    raise exception 'lease %', (select jsonb_agg(l) from public.locks l);
  end if;
  if not better_supabase.release_lease('job', v_lease, 'conv')
    or better_supabase.acquire_lease('job', 60, 'conv') is null then
    raise exception 'release did not free the lease';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
