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

// The app's own components and incidents: enum statuses and severities,
// renamed columns, and no description, group, position, commander or
// timestamp columns.
const APP = `
create type public.service_health as enum ('operational', 'maintenance', 'degraded', 'partial_outage', 'major_outage');
create type public.incident_level as enum ('sev1', 'sev2', 'sev3', 'sev4');
create type public.incident_phase as enum ('investigating', 'identified', 'monitoring', 'resolved');

create table public.services (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  label text not null,
  shown boolean not null default true,
  health public.service_health not null default 'operational'
);

create table public.outages (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  title text not null,
  level public.incident_level not null default 'sev3',
  phase public.incident_phase not null default 'investigating',
  public boolean not null default false,
  started_at timestamptz not null default now(),
  resolved_at timestamptz
);
`;

const BLOCKS: AnyBlocksConfig = {
  incidents: {
    tables: { components: "public.services", incidents: "public.outages" },
    columns: {
      components: {
        tenant: "org_id",
        name: "label",
        public: "shown",
        status: "health",
        description: null,
        group: null,
        position: null,
        createdAt: null,
        updatedAt: null,
      },
      incidents: {
        tenant: "org_id",
        severity: "level",
        status: "phase",
        description: null,
        commander: null,
        createdBy: null,
        createdAt: null,
        updatedAt: null,
      },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["incidents"], {
    modules: BLOCKS,
    ownTables: { "public.services": "app.sql", "public.outages": "app.sql" },
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

describe("incidents over the app's tables", BOOT, () => {
  it("opens, updates and resolves an incident in enum columns", async () => {
    await expect(
      run(`do $$
declare
  v_component jsonb;
  v_incident jsonb;
  v_id uuid;
  v_service uuid;
  v_page jsonb;
begin
  ${SERVICE}
  v_component := better_supabase.save_status_component('${TENANT}', 'API');
  v_service := (v_component ->> 'id')::uuid;
  if v_component ->> 'description' is not null then
    raise exception 'component %', v_component;
  end if;
  v_incident := better_supabase.open_incident('${TENANT}', jsonb_build_object(
    'title', 'API down', 'severity', 'sev1', 'public', true, 'message', 'Looking',
    'impacts', jsonb_build_array(jsonb_build_object('componentId', v_service, 'impact', 'major_outage'))));
  v_id := (v_incident ->> 'id')::uuid;
  if (select level from public.outages where id = v_id) <> 'sev1'
    or (select health from public.services where id = v_service) <> 'major_outage' then
    raise exception 'opened %', v_incident;
  end if;
  perform better_supabase.post_incident_update(v_id, 'resolved', 'Fixed');
  if (select phase from public.outages where id = v_id) <> 'resolved'
    or (select resolved_at from public.outages where id = v_id) is null
    or (select health from public.services where id = v_service) <> 'operational' then
    raise exception 'resolve missed: %', (select to_jsonb(o) from public.outages o where id = v_id);
  end if;
  if jsonb_array_length(better_supabase.list_incidents('${TENANT}', null, 'sev1')) <> 1 then
    raise exception 'severity filter missed';
  end if;
  v_page := better_supabase.save_status_page('${TENANT}', 'acme', 'Acme', null, true);
  if better_supabase.public_status_page('acme') is null then
    raise exception 'page %', v_page;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
