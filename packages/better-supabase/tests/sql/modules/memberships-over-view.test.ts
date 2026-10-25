import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const ORG = "11111111-1111-4111-8111-111111111111";
const MEMBER = "22222222-2222-4222-8222-222222222222";
const OUTSIDER = "33333333-3333-4333-8333-333333333333";
const DOC = "44444444-4444-4444-8444-444444444444";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;

-- PGlite loads no pgcrypto here; share tokens need random bytes and sha256.
create schema if not exists extensions;
create function extensions.gen_random_bytes(n integer) returns bytea
language sql volatile as $$ select decode(md5(random()::text), 'hex') $$;
create function extensions.digest(data bytea, type text) returns bytea
language sql immutable as $$ select sha256(data) $$;
`;

// The app keeps memberships of every scope in one table and shows the
// organization ones to the block through a view Postgres can't write through.
const APP = `
create table public.memberships (
  scope text not null,
  scope_id uuid not null,
  user_id uuid not null,
  role text not null,
  created_at timestamptz not null default now()
);

create view public.organization_memberships with (security_invoker = true) as
select distinct on (scope_id, user_id) scope_id as organization_id, user_id, role, created_at
from public.memberships where scope = 'organization'
order by scope_id, user_id, created_at, role;

create table public.docs (
  id uuid primary key,
  organization_id uuid not null
);
`;

const ROWS = `insert into public.memberships (scope, scope_id, user_id, role) values
  ('organization', '${ORG}', '${MEMBER}', 'owner'),
  ('team', '${ORG}', '${OUTSIDER}', 'owner');
insert into public.docs (id, organization_id) values ('${DOC}', '${ORG}');
`;

const VIEW = "public.organization_memberships";

const BLOCKS: AnyBlocksConfig = {
  memberships: {
    tables: { memberships: VIEW },
    columns: { memberships: { updatedAt: null, lastUsedAt: null } },
  },
  "share-links": { on: { doc: { table: "docs" } } },
};

const LAYOUT = {
  modules: BLOCKS,
  ownTables: { [VIEW]: "app.sql", "public.memberships": "app.sql" },
  ownViews: { [VIEW]: { updatable: false } },
  ownColumns: {
    [VIEW]: ["organization_id", "user_id", "role", "created_at"],
    "public.memberships": [
      "scope",
      "scope_id",
      "user_id",
      "role",
      "created_at",
    ],
  },
};

const as = (user: string) =>
  `perform set_config('request.jwt.claims', '{"role":"authenticated","sub":"${user}"}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', '${user}', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["memberships", "share-links"], LAYOUT);

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
      ROWS,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("memberships over the app's view", BOOT, () => {
  it("creates and resolves a share link for a member the view lists", async () => {
    await expect(
      run(`do $$
declare
  v_link jsonb;
  v_resolved jsonb;
begin
  ${as(MEMBER)}
  v_link := better_supabase.create_share_link('${ORG}', 'doc', '${DOC}', 'view');
  v_resolved := better_supabase.resolve_share_link(v_link ->> 'token');
  if v_resolved ->> 'organizationId' <> '${ORG}' or v_resolved ->> 'subjectId' <> '${DOC}' then
    raise exception 'resolved %', v_resolved;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses a user the view leaves out", async () => {
    await expect(
      run(`do $$
begin
  ${as(OUTSIDER)}
  perform better_supabase.create_share_link('${ORG}', 'doc', '${DOC}', 'view');
end;
$$;`),
    ).rejects.toThrow(/not allowed to share/);
  });
});
