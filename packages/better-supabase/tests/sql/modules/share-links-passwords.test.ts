import { describe, expect, it } from "vitest";

import type { SubjectsConfig } from "../../../src/config/index.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";
const MINE = "44444444-4444-4444-8444-444444444444";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticator') then
    create role authenticator;
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

const ALLOW = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $$ select '${TENANT}'::uuid $$;
insert into public.threads (id, organization_id, owner_id) values ('${MINE}', '${TENANT}', '${ALICE}');
`;

const AS_ALICE = `perform set_config('request.jwt.claims', '{"sub":"${ALICE}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${ALICE}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

const hintOf = (statement: string, hint: string) => `begin
    ${statement};
    v_hint := 'none';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
  end;
  if v_hint <> '${hint}' then
    raise exception 'expected ${hint}, got %', v_hint;
  end if;`;

async function run(modules: readonly string[], check: string): Promise<void> {
  const files = renderBlocks(["subjects", ...modules, "share-links"], {
    modules: {},
    subjects: SUBJECTS,
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
      ALLOW,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("share link passwords", { timeout: 60_000 }, () => {
  it("needs the password, keeps the download flag and counts no use while locked", async () => {
    await expect(
      run(
        [],
        `do $$
declare
  v_hint text;
  v_token text;
  v_link jsonb;
begin
  ${AS_ALICE}
  ${hintOf(`perform better_supabase.create_share_link('${TENANT}', 'thread', '${MINE}', 'view', password => 'short')`, "SHARE_LINK_PASSWORD_INVALID")}
  v_token := better_supabase.create_share_link('${TENANT}', 'thread', '${MINE}', 'view', password => 'correct horse', download_allowed => false) ->> 'token';
  v_link := better_supabase.resolve_share_link(v_token);
  if v_link <> '{"passwordRequired": true}'::jsonb then
    raise exception 'resolved without a password: %', v_link;
  end if;
  v_link := better_supabase.resolve_share_link(v_token, 'wrong horse');
  if v_link ? 'id' then
    raise exception 'resolved with a wrong password: %', v_link;
  end if;
  if (select use_count from better_supabase.share_links) <> 0 then
    raise exception 'a locked resolve counted a use';
  end if;
  v_link := better_supabase.resolve_share_link(v_token, 'correct horse');
  if v_link ->> 'subjectId' <> '${MINE}' or (v_link ->> 'downloadAllowed')::boolean or not (v_link ->> 'passwordRequired')::boolean then
    raise exception 'resolved %', v_link;
  end if;
  if (select password_hash from better_supabase.share_links) = 'correct horse' then
    raise exception 'stored the password in plain text';
  end if;
  if better_supabase.list_share_links('thread', '${MINE}') -> 0 ->> 'passwordRequired' <> 'true' then
    raise exception 'listed %', better_supabase.list_share_links('thread', '${MINE}');
  end if;
end;
$$;`,
      ),
    ).resolves.toBeUndefined();
  });

  it("locks a link after 10 wrong passwords when rate-limit is installed", async () => {
    await expect(
      run(
        ["rate-limit"],
        `do $$
declare
  v_hint text;
  v_token text;
  v_open text;
begin
  ${AS_ALICE}
  v_token := better_supabase.create_share_link('${TENANT}', 'thread', '${MINE}', 'view', password => 'correct horse') ->> 'token';
  v_open := better_supabase.create_share_link('${TENANT}', 'thread', '${MINE}', 'view') ->> 'token';
  for i in 1..10 loop
    if better_supabase.resolve_share_link(v_token, 'wrong horse') ? 'id' then
      raise exception 'resolved with a wrong password';
    end if;
  end loop;
  ${hintOf(`perform better_supabase.resolve_share_link(v_token, 'correct horse')`, "SHARE_LINK_RATE_LIMITED")}
  if not (better_supabase.resolve_share_link(v_open) ? 'id') then
    raise exception 'locked a link without a password';
  end if;
end;
$$;`,
      ),
    ).resolves.toBeUndefined();
  });
});
