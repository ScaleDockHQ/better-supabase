import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const PATIENT = "44444444-4444-4444-8444-444444444444";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

const PATIENTS = `
create table public.patients (
  id uuid primary key,
  organization_id uuid not null,
  name text not null
);
`;

// The app's own vitals table: renamed columns, and no method, device, note
// or reason columns. The renderer adds the columns it needs.
const APP = `${PATIENTS}
create table public.vital_readings (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  definition_id uuid not null,
  subject_type text not null,
  subject_id text not null,
  taken_at timestamptz not null,
  value_number numeric,
  value_text text,
  value_code text,
  components jsonb,
  flag text,
  status text not null default 'final',
  replaces_id uuid,
  source text not null default 'manual',
  external_id text,
  submission_id uuid,
  performer_id uuid,
  created_at timestamptz not null default now()
);
`;

const OWN_TABLES = { "public.vital_readings": "app.sql" };

const BLOCKS: AnyBlocksConfig = {
  observations: {
    options: { defaults: "vitals" },
    tables: { observations: "public.vital_readings" },
    columns: {
      observations: {
        tenant: "org_id",
        observedAt: "taken_at",
        method: null,
        device: null,
        note: null,
        reason: null,
      },
    },
  },
};

const SUBJECTS = {
  patient: { table: "public.patients", idType: "uuid" as const, title: "name" },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  insert into public.patients (id, organization_id, name) values ('${PATIENT}', '${TENANT}', 'Pat');`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

const OVER_APP: Parameters<typeof renderBlocks>[1] = {
  subjects: SUBJECTS,
  modules: BLOCKS,
  ownTables: OWN_TABLES,
};

async function run(check: string, layout = OVER_APP, app = APP): Promise<void> {
  const files = renderBlocks(
    ["memberships", "permissions", "subjects", "observations"],
    layout,
  );

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      app,
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

const LIFECYCLE = `do $$
declare
  v_obs jsonb;
  v_fixed jsonb;
begin
  ${SERVICE}
  v_obs := better_supabase.record_observation('${TENANT}', 'patient', '${PATIENT}', 'heart_rate', '128', now() - interval '1 hour');
  if v_obs ->> 'flag' <> 'high' then
    raise exception 'recorded %', v_obs;
  end if;
  v_fixed := better_supabase.amend_observation((v_obs ->> 'id')::uuid, '{"value": 88}', 'wrong monitor');
  if v_fixed ->> 'flag' <> 'normal' or v_fixed ->> 'replacesId' <> v_obs ->> 'id' then
    raise exception 'amended %', v_fixed;
  end if;
  if jsonb_array_length(better_supabase.list_observations('patient', '${PATIENT}')) <> 1 then
    raise exception 'list %', better_supabase.list_observations('patient', '${PATIENT}');
  end if;
  if (better_supabase.latest_observations('patient', '${PATIENT}') -> 'heart_rate' ->> 'value')::numeric <> 88 then
    raise exception 'latest %', better_supabase.latest_observations('patient', '${PATIENT}');
  end if;
end;
$$;`;

describe("observations over the app's table", BOOT, () => {
  it("records and amends a reading in renamed columns", async () => {
    await expect(run(LIFECYCLE)).resolves.toBeUndefined();
  });

  it("runs the same lifecycle on the module's own tables", async () => {
    await expect(
      run(
        LIFECYCLE,
        {
          subjects: SUBJECTS,
          modules: { observations: { options: { defaults: "vitals" } } },
        },
        PATIENTS,
      ),
    ).resolves.toBeUndefined();
  });

  it("refuses a note the app's table has no column for", async () => {
    await expect(
      run(`do $$
begin
  ${SERVICE}
  perform better_supabase.record_observation('${TENANT}', 'patient', '${PATIENT}', 'heart_rate', '70', null, '{"note": "after a walk"}');
end;
$$;`),
    ).rejects.toThrow(/note/);
  });
});
