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

// The app's own asset tables: renamed columns, an enum status, and no code,
// address, coordinate, metadata, serial number, note or author columns.
const APP = `
create type public.equipment_condition as enum ('active', 'maintenance', 'retired');

create table public.sites (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  parent_id uuid references public.sites (id),
  category text not null,
  label text not null,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.equipment (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  site_id uuid references public.sites (id),
  category text not null,
  label text not null,
  asset_tag text,
  condition public.equipment_condition not null default 'active',
  holder_type text,
  holder_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.equipment_loans (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  equipment_id uuid not null references public.equipment (id) on delete cascade,
  holder_type text not null,
  holder_id text not null,
  assigned_at timestamptz not null default now(),
  released_at timestamptz
);
`;

const OWN_TABLES = {
  "public.sites": "app.sql",
  "public.equipment": "app.sql",
  "public.equipment_loans": "app.sql",
};

const BLOCKS: AnyBlocksConfig = {
  assets: {
    tables: {
      locations: "public.sites",
      assets: "public.equipment",
      assignments: "public.equipment_loans",
    },
    columns: {
      locations: {
        tenant: "org_id",
        kind: "category",
        name: "label",
        code: null,
        address: null,
        latitude: null,
        longitude: null,
        metadata: null,
      },
      assets: {
        tenant: "org_id",
        location: "site_id",
        kind: "category",
        name: "label",
        tag: "asset_tag",
        status: "condition",
        assigneeType: "holder_type",
        assigneeId: "holder_id",
        serial: null,
        latitude: null,
        longitude: null,
        metadata: null,
        retiredAt: null,
        createdBy: null,
      },
      assignments: {
        tenant: "org_id",
        asset: "equipment_id",
        assigneeType: "holder_type",
        assigneeId: "holder_id",
        note: null,
        assignedBy: null,
      },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["assets"], {
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

describe("assets over the app's tables", BOOT, () => {
  it("creates, assigns and retires an asset in an enum status column", async () => {
    await expect(
      run(`do $$
declare
  v_site uuid;
  v_asset jsonb;
  v_id uuid;
begin
  ${SERVICE}
  v_site := (better_supabase.create_asset_location('${TENANT}', 'site', 'HQ') ->> 'id')::uuid;
  v_asset := better_supabase.create_asset('${TENANT}', 'laptop', 'MacBook', v_site, 'TAG-1');
  v_id := (v_asset ->> 'id')::uuid;
  if v_asset ->> 'status' <> 'active' or v_asset -> 'serialNumber' <> 'null'::jsonb then
    raise exception 'created %', v_asset;
  end if;
  perform better_supabase.assign_asset(v_id, 'party', 'p1');
  if (select holder_id from public.equipment where id = v_id) <> 'p1' then
    raise exception 'holder is %', (select holder_id from public.equipment where id = v_id);
  end if;
  perform better_supabase.update_asset(v_id, '{"status": "maintenance", "name": "MacBook Pro"}'::jsonb);
  if (select condition from public.equipment where id = v_id) <> 'maintenance' then
    raise exception 'status is %', (select condition from public.equipment where id = v_id);
  end if;
  if jsonb_array_length(better_supabase.list_assets('${TENANT}', status => 'maintenance', query => 'TAG-1')) <> 1 then
    raise exception 'list %', better_supabase.list_assets('${TENANT}', status => 'maintenance', query => 'TAG-1');
  end if;
  perform better_supabase.update_asset(v_id, '{"status": "retired"}'::jsonb);
  if (select holder_id from public.equipment where id = v_id) is not null
    or (select released_at from public.equipment_loans where equipment_id = v_id) is null then
    raise exception 'retiring kept the assignment';
  end if;
  if jsonb_array_length(better_supabase.asset_assignment_history(v_id)) <> 1 then
    raise exception 'history %', better_supabase.asset_assignment_history(v_id);
  end if;
  perform better_supabase.assets_near('${TENANT}', 52.1, 5.1, 1000);
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses a serial number the app's table has no column for", async () => {
    await expect(
      run(`do $$
begin
  ${SERVICE}
  perform better_supabase.create_asset('${TENANT}', 'laptop', 'MacBook', serial_number => 'SN-1');
end;
$$;`),
    ).rejects.toThrow(/no serial number column/);
  });
});
