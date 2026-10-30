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

// PGlite has no pgcrypto; versions hash the published content.
const PGCRYPTO = `
create schema if not exists extensions;
create or replace function extensions.digest(data text, kind text) returns bytea
language sql immutable as $$
  select sha256(convert_to(data, 'UTF8'))
$$;
`;

// The app's own frameworks, controls and policies: renamed columns and no
// version, description, owner or timestamp columns. The module adds the
// publishing columns the policies table is missing.
const APP = `
create table public.standards (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  slug text not null,
  title text not null
);

create table public.requirements (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  standard_id uuid not null references public.standards (id) on delete cascade,
  ref text not null,
  title text not null,
  in_scope boolean not null default true
);

create table public.rulebooks (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  slug text not null,
  title text not null,
  requires_acknowledgement boolean not null default true
);
`;

const BLOCKS: AnyBlocksConfig = {
  compliance: {
    tables: {
      frameworks: "public.standards",
      controls: "public.requirements",
      policies: "public.rulebooks",
    },
    columns: {
      frameworks: {
        tenant: "org_id",
        key: "slug",
        name: "title",
        version: null,
        description: null,
        createdAt: null,
        updatedAt: null,
      },
      controls: {
        tenant: "org_id",
        framework: "standard_id",
        code: "ref",
        applicable: "in_scope",
        description: null,
        owner: null,
        createdAt: null,
        updatedAt: null,
      },
      policies: {
        tenant: "org_id",
        key: "slug",
        owner: null,
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
  const files = renderBlocks(["compliance"], {
    modules: BLOCKS,
    ownTables: {
      "public.standards": "app.sql",
      "public.requirements": "app.sql",
      "public.rulebooks": "app.sql",
    },
  });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      PGCRYPTO,
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

describe("compliance over the app's tables", BOOT, () => {
  it("saves frameworks, controls, evidence and policies without the optional columns", async () => {
    await expect(
      run(`do $$
declare
  v_framework jsonb;
  v_control jsonb;
  v_again jsonb;
  v_policy jsonb;
  v_posture jsonb;
begin
  ${SERVICE}
  v_framework := better_supabase.save_control_framework('${TENANT}', 'soc2', 'SOC 2', '2017', 'Trust');
  perform better_supabase.save_control_framework('${TENANT}', 'soc2', 'SOC 2 Type II');
  if (select count(*) from public.standards) <> 1
    or (select title from public.standards) <> 'SOC 2 Type II'
    or v_framework ->> 'version' is not null then
    raise exception 'framework %', v_framework;
  end if;
  v_control := better_supabase.save_control((v_framework ->> 'id')::uuid, 'CC1.1', 'Integrity');
  v_again := better_supabase.save_control((v_framework ->> 'id')::uuid, 'CC1.1', 'Integrity and ethics');
  if v_again ->> 'id' <> v_control ->> 'id' or v_again ->> 'ownerId' is not null then
    raise exception 'control %', v_again;
  end if;
  perform better_supabase.add_control_evidence((v_control ->> 'id')::uuid, null, 'Signed code of conduct', current_date + 30);
  v_posture := better_supabase.control_posture('${TENANT}');
  if v_posture::text not like '%passing%' then
    raise exception 'posture %', v_posture;
  end if;
  v_policy := better_supabase.save_compliance_policy('${TENANT}', 'security', 'Security policy');
  perform better_supabase.save_compliance_policy('${TENANT}', 'security', 'Information security policy');
  if (select count(*) from public.rulebooks) <> 1 then
    raise exception 'policy %', v_policy;
  end if;
  v_policy := better_supabase.publish_compliance_policy((v_policy ->> 'id')::uuid, '{"body": "Be careful"}'::jsonb);
  if (select version_number from public.rulebooks) <> 1 then
    raise exception 'published %', v_policy;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
