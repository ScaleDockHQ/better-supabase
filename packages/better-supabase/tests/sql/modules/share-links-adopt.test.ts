import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";
import type { SubjectsConfig } from "../../../src/config/index.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";
const BOB = "33333333-3333-4333-8333-333333333333";
const MINE = "44444444-4444-4444-8444-444444444444";
const THEIRS = "55555555-5555-4555-8555-555555555555";
const HASH = "a".repeat(64);

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
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create table public.threads (
  id uuid primary key,
  organization_id uuid not null,
  owner_id uuid not null
);
`;

const SUBJECTS: SubjectsConfig = {
  thread: {
    table: "public.threads",
    idType: "uuid",
    permissions: { share: { owner: "owner_id" } },
  },
};

const BLOCKS: AnyBlocksConfig = {
  "share-links": { options: { tokenHash: true, fullRows: true } },
};

const ALLOW = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $$ select '${TENANT}'::uuid $$;
insert into public.threads (id, organization_id, owner_id) values ('${MINE}', '${TENANT}', '${ALICE}'), ('${THEIRS}', '${TENANT}', '${BOB}');
`;

const as = (
  user: string,
) => `perform set_config('request.jwt.claims', '{"sub":"${user}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${user}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

const AS_SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

const BOOT = { timeout: 60_000 };

const render = (
  modules: AnyBlocksConfig = BLOCKS,
  subjects: SubjectsConfig = SUBJECTS,
) => renderBlocks(["subjects", "share-links"], { modules, subjects });

async function run(
  check: string,
  subjects: SubjectsConfig = SUBJECTS,
  allow = ALLOW,
  modules: AnyBlocksConfig = BLOCKS,
): Promise<void> {
  const files = render(modules, subjects);

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
      allow,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("share links checked per record", BOOT, () => {
  it("shares only records the caller may share, with a caller-made hash and full rows", async () => {
    await expect(
      run(`do $$
declare
  v_link jsonb;
  v_hint text;
  v_list jsonb;
begin
  ${as(ALICE)}
  v_link := better_supabase.create_share_link('${TENANT}', 'thread', '${MINE}', 'view', null, null, null, '${HASH}');
  if v_link ->> 'token' is not null then
    raise exception 'token for a caller hash %', v_link;
  end if;
  begin
    perform better_supabase.create_share_link('${TENANT}', 'thread', '${THEIRS}', 'view');
    v_hint := 'none';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
  end;
  if v_hint <> 'SHARE_SUBJECT_NOT_FOUND' then
    raise exception 'shared another owner''s thread: %', v_hint;
  end if;
  begin
    perform better_supabase.create_share_link('${TENANT}', 'thread', '${MINE}', 'view', null, null, null, 'NOT-HEX');
    v_hint := 'none';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
  end;
  if v_hint <> 'SHARE_TOKEN_HASH_INVALID' then
    raise exception 'bad hash %', v_hint;
  end if;
  v_list := better_supabase.list_share_links('thread', '${MINE}');
  if v_list -> 0 ->> 'createdBy' <> '${ALICE}' or v_list -> 0 ->> 'subjectId' <> '${MINE}' or v_list -> 0 ->> 'createdAt' is null then
    raise exception 'full rows %', v_list;
  end if;
  ${as(BOB)}
  if jsonb_array_length(better_supabase.list_share_links('thread', '${MINE}')) <> 0 then
    raise exception 'listed for a caller who may not share';
  end if;
  ${AS_SERVICE}
  if (better_supabase.find_share_link('${HASH}') ->> 'subjectId') <> '${MINE}' then
    raise exception 'find %', better_supabase.find_share_link('${HASH}');
  end if;
  perform better_supabase.revoke_share_link((v_link ->> 'id')::uuid);
  if better_supabase.find_share_link('${HASH}') is not null then
    raise exception 'found a revoked link';
  end if;
  if jsonb_array_length(better_supabase.list_share_links('thread', '${MINE}', false)) <> 0 then
    raise exception 'include_revoked';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("renders the last release's functions without the options", () => {
    const sql = render({})
      .filter((file) => file.module === "share-links")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).not.toContain("find_share_link");
    expect(sql).not.toContain("token_hash text default null");
    expect(sql).toContain(
      `coalesce("better_supabase"."can_subject"(create_share_link.subject_type, create_share_link.subject_id, 'share'), false)`,
    );
  });

  it("reads a record through its owner when nobody holds the read key", async () => {
    const subjects: SubjectsConfig = {
      thread: {
        table: "public.threads",
        idType: "uuid",
        permissions: { read: { key: "thread.read", owner: "owner_id" } },
      },
    };

    const allow = ALLOW.replace(
      "as $$ select true $$;",
      () => "as $$ select permission <> 'thread.read' $$;",
    );

    await expect(
      run(
        `do $$
declare
  v_hint text;
begin
  ${as(ALICE)}
  perform better_supabase.create_share_link('${TENANT}', 'thread', '${MINE}', 'view');
  begin
    perform better_supabase.create_share_link('${TENANT}', 'thread', '${THEIRS}', 'view');
    v_hint := 'none';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
  end;
  if v_hint <> 'SHARE_SUBJECT_NOT_FOUND' then
    raise exception 'shared a thread the caller neither owns nor reads: %', v_hint;
  end if;
end;
$$;`,
        subjects,
        allow,
      ),
    ).resolves.toBeUndefined();
  });

  it("installs without the optional views and state tables", async () => {
    const sql = render({
      "share-links": { tables: { views: null, state: null } },
    })
      .map((file) => file.contents)
      .join("\n");

    expect(sql).not.toContain("subject_views");
    expect(sql).not.toContain("subject_user_state");

    await expect(
      run(
        `do $$
begin
  ${as(ALICE)}
  perform better_supabase.create_share_link('${TENANT}', 'thread', '${MINE}', 'view');
  perform better_supabase.set_user_state('thread', '${MINE}', true);
  ${AS_SERVICE}
  perform better_supabase.record_view('${TENANT}', 'thread', '${MINE}', 'user', '${ALICE}');
end;
$$;`,
        SUBJECTS,
        ALLOW,
        { "share-links": { tables: { views: null, state: null } } },
      ),
    ).resolves.toBeUndefined();
  });
});
