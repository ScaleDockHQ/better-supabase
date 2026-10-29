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

// PGlite has no pgcrypto; versions hashes snapshots with extensions.digest.
const PGCRYPTO = `
create schema if not exists extensions;
create or replace function extensions.digest(data text, kind text) returns bytea
language sql immutable as $$
  select sha256(convert_to(data, 'UTF8'))
$$;
`;

// The app's own risk register: renamed columns, and no description, cause,
// consequence or creator columns. The renderer adds the columns it needs.
const APP = `
create table public.risk_register (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  ref text not null,
  name text not null,
  category text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
`;

const OWN_TABLES = { "public.risk_register": "app.sql" };

const BLOCKS: AnyBlocksConfig = {
  risks: {
    tables: { risks: "public.risk_register" },
    columns: {
      risks: {
        tenant: "org_id",
        number: "ref",
        title: "name",
        description: null,
        cause: null,
        consequence: null,
        createdBy: null,
      },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(
  check: string,
  layout?: Parameters<typeof renderBlocks>[1],
  app = APP,
): Promise<void> {
  const files = renderBlocks(
    ["memberships", "permissions", "subjects", "versions", "risks"],
    layout ?? { modules: BLOCKS, ownTables: OWN_TABLES },
  );

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      PGCRYPTO,
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
  v_risk jsonb;
  v_id uuid;
  v_map jsonb;
begin
  ${SERVICE}
  v_risk := better_supabase.create_risk('${TENANT}', '{"title": "Supplier fails", "category": "operational"}'::jsonb);
  v_id := (v_risk ->> 'id')::uuid;
  if v_risk ->> 'status' <> 'identified' or v_risk ->> 'number' is null or v_risk -> 'inherent' <> 'null'::jsonb then
    raise exception 'created %', v_risk;
  end if;
  v_risk := better_supabase.assess_risk(v_id, 4, 5, 2, 3, 'Two suppliers');
  if v_risk ->> 'status' <> 'assessed'
    or (v_risk -> 'inherent' ->> 'score')::int <> 20 or v_risk -> 'inherent' ->> 'band' <> 'critical'
    or (v_risk -> 'residual' ->> 'score')::int <> 6 or v_risk -> 'residual' ->> 'band' <> 'medium'
    or v_risk ->> 'nextReviewOn' is null then
    raise exception 'assessed %', v_risk;
  end if;
  v_map := better_supabase.risk_heatmap('${TENANT}');
  if jsonb_array_length(v_map -> 'cells') <> 25
    or (select (c ->> 'count')::int from jsonb_array_elements(v_map -> 'cells') c
        where (c ->> 'likelihood')::int = 2 and (c ->> 'impact')::int = 3) <> 1 then
    raise exception 'heatmap %', v_map;
  end if;
  v_risk := better_supabase.set_risk_treatment(v_id, 'mitigate', 'Add a second supplier');
  if v_risk ->> 'status' <> 'treating' then
    raise exception 'treated %', v_risk;
  end if;
  if jsonb_array_length(better_supabase.list_risks('${TENANT}', '{"band": "medium"}'::jsonb)) <> 1 then
    raise exception 'list %', better_supabase.list_risks('${TENANT}', '{"band": "medium"}'::jsonb);
  end if;
  v_risk := better_supabase.get_risk(v_id);
  if jsonb_array_length(v_risk -> 'assessments') <> 1 or v_risk -> 'matrix' ->> 'key' <> 'default' then
    raise exception 'get %', v_risk;
  end if;
  v_risk := better_supabase.close_risk(v_id, 'Supplier replaced');
  if v_risk ->> 'status' <> 'closed' or v_risk ->> 'closedAt' is null then
    raise exception 'closed %', v_risk;
  end if;
end;
$$;`;

describe("risks over the app's table", BOOT, () => {
  it("registers, assesses, treats and closes a risk in renamed columns", async () => {
    await expect(run(LIFECYCLE)).resolves.toBeUndefined();
  });

  it("runs the same lifecycle on the module's own tables", async () => {
    await expect(run(LIFECYCLE, {}, "")).resolves.toBeUndefined();
  });

  it("refuses a description the app's table has no column for", async () => {
    await expect(
      run(`do $$
begin
  ${SERVICE}
  perform better_supabase.create_risk('${TENANT}', '{"title": "A", "category": "quality", "description": "B"}'::jsonb);
end;
$$;`),
    ).rejects.toThrow(/no description column/);
  });

  it("refuses a level outside the matrix and writes to a closed risk", async () => {
    await expect(
      run(`do $$
declare
  v_id uuid;
begin
  ${SERVICE}
  v_id := (better_supabase.create_risk('${TENANT}', '{"title": "A", "category": "quality"}'::jsonb) ->> 'id')::uuid;
  perform better_supabase.assess_risk(v_id, 6, 1, 1, 1);
end;
$$;`),
    ).rejects.toThrow(/likelihood/);

    await expect(
      run(`do $$
declare
  v_id uuid;
begin
  ${SERVICE}
  v_id := (better_supabase.create_risk('${TENANT}', '{"title": "A", "category": "quality"}'::jsonb) ->> 'id')::uuid;
  perform better_supabase.close_risk(v_id, 'Gone');
  perform better_supabase.update_risk(v_id, '{"title": "B"}'::jsonb);
end;
$$;`),
    ).rejects.toThrow(/closed/);
  });
});
