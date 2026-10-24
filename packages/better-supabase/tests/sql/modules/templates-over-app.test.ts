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

// The module installs pgcrypto into the extensions schema.
const EXTENSIONS = "create schema if not exists extensions;";

// The app's own template tables: renamed columns, an enum scope, and no key,
// default flag, settings, fork origin or author columns.
const APP = `
create type public.template_visibility as enum ('system', 'tenant');

create table public.doc_templates (
  id uuid primary key default gen_random_uuid(),
  org_id uuid,
  kind text not null,
  title text not null,
  locale text not null default 'en',
  visibility public.template_visibility not null default 'tenant',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.doc_template_versions (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.doc_templates (id) on delete cascade,
  version integer not null,
  body jsonb not null,
  hash text not null,
  published_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.doc_template_uses (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.doc_templates (id) on delete cascade,
  version_id uuid not null references public.doc_template_versions (id) on delete cascade,
  org_id uuid not null,
  subject_type text not null,
  subject_id text not null,
  applied_at timestamptz not null default now()
);
`;

const OWN_TABLES = {
  "public.doc_templates": "app.sql",
  "public.doc_template_versions": "app.sql",
  "public.doc_template_uses": "app.sql",
};

const BLOCKS: AnyBlocksConfig = {
  templates: {
    tables: {
      templates: "public.doc_templates",
      versions: "public.doc_template_versions",
      applications: "public.doc_template_uses",
    },
    columns: {
      templates: {
        tenant: "org_id",
        type: "kind",
        name: "title",
        language: "locale",
        scope: "visibility",
        key: null,
        isDefault: null,
        settings: null,
        forkedFrom: null,
        forkedFromVersion: null,
        createdBy: null,
      },
      versions: { createdBy: null },
      applications: { tenant: "org_id", appliedBy: null },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["templates"], {
    modules: BLOCKS,
    ownTables: OWN_TABLES,
  });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      EXTENSIONS,
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

describe("templates over the app's tables", BOOT, () => {
  it("saves, publishes, forks and applies templates with an enum scope", async () => {
    await expect(
      run(`do $$
declare
  v_tpl jsonb;
  v_id uuid;
  v_system uuid;
  v_version jsonb;
  v_fork jsonb;
begin
  ${SERVICE}
  v_tpl := better_supabase.save_template(null, '${TENANT}', 'invoice', 'Invoice', 'en', null);
  v_id := (v_tpl ->> 'id')::uuid;
  if v_tpl ->> 'scope' <> 'tenant' or (v_tpl ->> 'isDefault')::boolean or v_tpl -> 'key' <> 'null'::jsonb then
    raise exception 'created %', v_tpl;
  end if;
  v_tpl := better_supabase.save_template(v_id, '${TENANT}', null, 'Invoice 2', null, null);
  if (select title from public.doc_templates where id = v_id) <> 'Invoice 2' then
    raise exception 'renamed %', v_tpl;
  end if;
  perform better_supabase.save_template_draft(v_id, '{"lines": []}'::jsonb);
  v_version := better_supabase.publish_template_version(v_id);
  if (v_version ->> 'version')::integer <> 1 or v_version ->> 'publishedAt' is null then
    raise exception 'published %', v_version;
  end if;
  if jsonb_array_length(better_supabase.templates_list('${TENANT}', 'invoice', null)) <> 1 then
    raise exception 'list %', better_supabase.templates_list('${TENANT}', 'invoice', null);
  end if;
  perform better_supabase.template_apply_target(v_id, '${TENANT}');
  perform better_supabase.record_template_application(v_id, (v_version ->> 'id')::uuid, '${TENANT}', 'deal', 'd1');
  if jsonb_array_length(better_supabase.template_applications_list('${TENANT}', v_id, null, null)) <> 1 then
    raise exception 'applications missed the application';
  end if;

  v_system := (better_supabase.save_template(null, null, 'invoice', 'Starter', 'en', null) ->> 'id')::uuid;
  if (select visibility from public.doc_templates where id = v_system) <> 'system' then
    raise exception 'system scope is %', (select visibility from public.doc_templates where id = v_system);
  end if;
  perform better_supabase.save_template_draft(v_system, '{"lines": [1]}'::jsonb);
  perform better_supabase.publish_template_version(v_system);
  v_fork := better_supabase.fork_template(v_system, '${TENANT}');
  if v_fork ->> 'scope' <> 'tenant' or v_fork -> 'forkedFrom' <> 'null'::jsonb then
    raise exception 'forked %', v_fork;
  end if;
  if jsonb_array_length(better_supabase.templates_list('${TENANT}', 'invoice', null)) <> 3
    or better_supabase.templates_list('${TENANT}', 'invoice', null) -> 2 ->> 'scope' <> 'system' then
    raise exception 'list with the starter %', better_supabase.templates_list('${TENANT}', 'invoice', null);
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses settings the app's table has no column for", async () => {
    await expect(
      run(`do $$
begin
  ${SERVICE}
  perform better_supabase.save_template(null, '${TENANT}', 'invoice', 'Invoice', 'en', '{"paper": "a4"}'::jsonb);
end;
$$;`),
    ).rejects.toThrow(/no settings column/);
  });
});
