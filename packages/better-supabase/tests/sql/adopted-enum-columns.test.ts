import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../src/config/blocks.ts";

import { renderBlocks } from "../../src/sql/render.ts";
import { liteStack } from "../../src/testing/lite.ts";
import { ownTablesOf } from "../fixtures/own-tables.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const SUBJECT = "22222222-2222-4222-8222-222222222222";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

const APP = `
create type public.subject_type as enum ('invoice', 'quote', 'task');
create type public.tag_kind as enum ('task', 'customer');

create table public.org_sequences (
  organization_id uuid not null,
  entity public.subject_type not null,
  scope text not null default '',
  period text not null default '',
  last_number bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, entity, scope, period)
);

create table public.invoices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  number text
);

create table public.org_tags (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  kind public.tag_kind not null,
  name text not null,
  slug text not null,
  color text,
  description text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.org_taggings (
  organization_id uuid not null,
  tag_id uuid not null references public.org_tags (id) on delete cascade,
  subject_type public.subject_type not null,
  subject_id text not null,
  created_at timestamptz not null default now(),
  primary key (tag_id, subject_type, subject_id)
);
`;

const BLOCKS: AnyBlocksConfig = {
  numbering: {
    tables: { sequences: "public.org_sequences" },
    columns: { sequences: { tenant: "organization_id" } },
    options: {
      entities: {
        invoice: {
          period: "none",
          format: "INV-{n}",
          table: "public.invoices",
          column: "number",
          tenantColumn: "organization_id",
        },
      },
    },
  },
  tags: {
    tables: { tags: "public.org_tags", taggings: "public.org_taggings" },
    columns: {
      tags: { tenant: "organization_id", rank: null },
      taggings: { tenant: "organization_id" },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["numbering", "tags"], {
    modules: BLOCKS,
    ownTables: ownTablesOf(BLOCKS),
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

describe("enum columns on the app's tables", BOOT, () => {
  it("numbers into an enum entity column", async () => {
    await expect(
      run(`do $$
declare
  v_first bigint;
  v_second bigint;
begin
  ${SERVICE}
  v_first := better_supabase.next_number('${TENANT}', 'invoice');
  v_second := better_supabase.next_number('${TENANT}', 'invoice');
  if v_first <> 1 or v_second <> 2 then
    raise exception 'numbered % and %', v_first, v_second;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("syncs an enum entity column from the numbers a table holds", async () => {
    await expect(
      run(`do $$
declare
  v_number text;
begin
  insert into public.invoices (organization_id, number) values ('${TENANT}', 'INV-41');
  perform better_supabase.sync_number_sequences();
  insert into public.invoices (organization_id) values ('${TENANT}') returning number into v_number;
  if v_number <> 'INV-42' then
    raise exception 'numbered %', v_number;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("creates, lists, applies and removes tags with enum kind and subject type columns", async () => {
    await expect(
      run(`do $$
declare
  v_tag uuid;
begin
  ${SERVICE}
  v_tag := (better_supabase.create_tag('${TENANT}', 'task', 'Urgent', null, null) ->> 'id')::uuid;
  if jsonb_array_length(better_supabase.list_tags('${TENANT}', 'task')) <> 1 then
    raise exception 'list_tags missed the tag';
  end if;
  perform better_supabase.tag('${TENANT}', 'task', '${SUBJECT}', v_tag);
  if jsonb_array_length(better_supabase.subject_tags('${TENANT}', 'task', '${SUBJECT}')) <> 1 then
    raise exception 'subject_tags missed the tag';
  end if;
  perform better_supabase.untag('${TENANT}', 'task', '${SUBJECT}', v_tag);
  if exists (select 1 from public.org_taggings) then
    raise exception 'untag left the link';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses a kind the enum lacks", async () => {
    await expect(
      run(`do $$
begin
  ${SERVICE}
  perform better_supabase.create_tag('${TENANT}', 'project', 'Roadmap', null, null);
end;
$$;`),
    ).rejects.toThrow(/invalid input value for enum public\.tag_kind/);
  });
});
