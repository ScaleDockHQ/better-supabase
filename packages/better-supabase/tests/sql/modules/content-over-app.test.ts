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

// The app's own pages table: renamed columns, enum type and status, and no
// summary, cover, approval or creator columns.
const APP = `
create type public.page_kind as enum ('page', 'post');
create type public.page_status as enum ('draft', 'scheduled', 'published', 'archived');

create table public.pages (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  kind public.page_kind not null,
  locale text not null default 'en',
  slug text not null,
  title text not null,
  body jsonb not null default '{}'::jsonb,
  status public.page_status not null default 'draft',
  publish_at timestamptz,
  published_at timestamptz,
  author_id uuid,
  translation_group_id uuid not null default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
`;

const OWN_TABLES = { "public.pages": "app.sql" };

const BLOCKS: AnyBlocksConfig = {
  content: {
    tables: { entries: "public.pages" },
    columns: {
      entries: {
        tenant: "org_id",
        type: "kind",
        summary: null,
        cover: null,
        approval: null,
        createdBy: null,
      },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(
    ["memberships", "permissions", "subjects", "content"],
    { modules: BLOCKS, ownTables: OWN_TABLES },
  );

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

describe("content over the app's table", BOOT, () => {
  it("drafts, publishes, lists and archives entries in enum columns", async () => {
    await expect(
      run(`do $$
declare
  v_entry jsonb;
  v_id uuid;
begin
  ${SERVICE}
  v_entry := better_supabase.create_content_entry('${TENANT}', '{"type": "post", "slug": "hello", "title": "Hello"}'::jsonb);
  v_id := (v_entry ->> 'id')::uuid;
  if v_entry ->> 'status' <> 'draft' or v_entry -> 'summary' <> 'null'::jsonb then
    raise exception 'created %', v_entry;
  end if;
  v_entry := better_supabase.update_content_entry(v_id, '{"title": "Hello 2"}'::jsonb);
  v_entry := better_supabase.publish_content_entry(v_id);
  if (select status from public.pages where id = v_id) <> 'published' then
    raise exception 'published %', v_entry;
  end if;
  if better_supabase.public_content_entry('${TENANT}', 'post', 'hello') ->> 'title' <> 'Hello 2' then
    raise exception 'public read %', better_supabase.public_content_entry('${TENANT}', 'post', 'hello');
  end if;
  if jsonb_array_length(better_supabase.list_content_entries('${TENANT}', '{"type": "post", "status": "published"}'::jsonb) -> 'entries') <> 1 then
    raise exception 'list %', better_supabase.list_content_entries('${TENANT}', '{"type": "post", "status": "published"}'::jsonb);
  end if;
  perform better_supabase.archive_content_entry(v_id);
  if (select status from public.pages where id = v_id) <> 'archived' then
    raise exception 'archived';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses a cover the app's table has no column for", async () => {
    await expect(
      run(`do $$
begin
  ${SERVICE}
  perform better_supabase.create_content_entry('${TENANT}', '{"type": "page", "slug": "a", "title": "A", "coverAttachmentId": "${TENANT}"}'::jsonb);
end;
$$;`),
    ).rejects.toThrow(/no cover column/);
  });
});
