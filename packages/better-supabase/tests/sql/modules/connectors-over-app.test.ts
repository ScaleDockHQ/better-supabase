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

// The app's own MCP server and tool hash tables: renamed columns, enum auth
// and status columns, and none of the transport, scopes, metadata, enabled,
// audit or approval columns.
const APP = `
create type public.mcp_auth as enum ('none', 'oauth', 'header');
create type public.tool_state as enum ('pending', 'approved', 'rejected');

create table public.mcp_servers (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  label text not null,
  endpoint text not null,
  auth_mode public.mcp_auth not null default 'oauth',
  secret_ref jsonb
);

create table public.mcp_tool_hashes (
  server_id uuid not null references public.mcp_servers (id) on delete cascade,
  hash text not null,
  state public.tool_state not null default 'pending'
);
`;

const OWN_TABLES = {
  "public.mcp_servers": "app.sql",
  "public.mcp_tool_hashes": "app.sql",
};

const BLOCKS: AnyBlocksConfig = {
  connectors: {
    tables: {
      servers: "public.mcp_servers",
      fingerprints: "public.mcp_tool_hashes",
    },
    columns: {
      servers: {
        tenant: "org_id",
        name: "label",
        url: "endpoint",
        authType: "auth_mode",
        credentialRef: "secret_ref",
        transport: null,
        scopes: null,
        clientMetadata: null,
        enabled: null,
        createdBy: null,
        createdAt: null,
        updatedAt: null,
      },
      fingerprints: {
        fingerprint: "hash",
        status: "state",
        tools: null,
        approvedBy: null,
        approvedAt: null,
        createdAt: null,
      },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["connectors"], {
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

describe("connectors over the app's tables", BOOT, () => {
  it("saves a server and decides its tool fingerprints in enum columns", async () => {
    await expect(
      run(`do $$
declare
  v_server jsonb;
  v_id uuid;
begin
  ${SERVICE}
  v_server := better_supabase.save_connector_server('${TENANT}', null,
    '{"name": "Docs", "url": "https://mcp.example.com", "auth_type": "none"}'::jsonb);
  v_id := (v_server ->> 'id')::uuid;
  if v_server ->> 'auth_type' <> 'none' or v_server ->> 'transport' <> 'http' or (v_server ->> 'enabled')::boolean is not true then
    raise exception 'saved %', v_server;
  end if;
  v_server := better_supabase.save_connector_server('${TENANT}', v_id, '{"name": "Docs MCP"}'::jsonb);
  if (select label from public.mcp_servers where id = v_id) <> 'Docs MCP' then
    raise exception 'update missed the name: %', v_server;
  end if;
  if better_supabase.check_connector_fingerprint(v_id, 'a1') <> 'approved' then
    raise exception 'the first fingerprint is not trusted';
  end if;
  perform better_supabase.check_connector_fingerprint(v_id, 'a1');
  if (select count(*) from public.mcp_tool_hashes) <> 1 then
    raise exception 'the same fingerprint was recorded twice';
  end if;
  if better_supabase.check_connector_fingerprint(v_id, 'b2') <> 'pending' then
    raise exception 'a changed fingerprint did not wait';
  end if;
  if not better_supabase.decide_connector_fingerprint(v_id, 'b2', false) then
    raise exception 'the decision found no fingerprint';
  end if;
  if (select state from public.mcp_tool_hashes where hash = 'b2') <> 'rejected' then
    raise exception 'the decision missed';
  end if;
  if jsonb_array_length(better_supabase.delete_connector_server(v_id)) <> 0 then
    raise exception 'delete returned grants';
  end if;
  if exists (select 1 from public.mcp_servers) then
    raise exception 'delete missed';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
