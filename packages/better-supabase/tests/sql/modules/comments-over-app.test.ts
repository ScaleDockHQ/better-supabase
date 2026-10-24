import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";
const DEAL = "44444444-4444-4444-8444-444444444444";
const COPY = "55555555-5555-4555-8555-555555555555";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// The app's own conversation, message and comment link tables: renamed
// columns, enum kinds and access, and no anchor, schedule, resolved, notify
// or link author columns.
const APP = `
create type public.room_kind as enum ('channel', 'dm', 'group_dm', 'subject', 'inbox');
create type public.room_access as enum ('members', 'tenant', 'subject');

create table public.deals (
  id uuid primary key,
  organization_id uuid not null
);

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  kind public.room_kind not null,
  access public.room_access not null default 'members',
  subject_type text,
  subject_id text,
  title text,
  member_key text,
  created_by uuid,
  last_message_at timestamptz,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.room_members (
  room_id uuid not null references public.rooms (id) on delete cascade,
  org_id uuid not null,
  user_id uuid not null,
  role text not null default 'member',
  last_read_at timestamptz
);

create table public.posts (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  room_id uuid not null references public.rooms (id) on delete cascade,
  parent_id uuid references public.posts (id) on delete set null,
  thread_id uuid references public.posts (id) on delete cascade,
  author_id uuid,
  kind text not null default 'message',
  body text not null default '',
  document jsonb,
  mentions uuid[] not null default '{}',
  mention_scope text,
  broadcast boolean not null default false,
  reply_count integer not null default 0,
  last_reply_at timestamptz,
  reply_user_ids uuid[] not null default '{}',
  pinned_at timestamptz,
  pinned_by uuid,
  sent_at timestamptz,
  edited_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.comment_links (
  message_id uuid not null,
  org_id uuid not null,
  task_id uuid not null
);
`;

const OWN_TABLES = {
  "public.rooms": "app.sql",
  "public.room_members": "app.sql",
  "public.posts": "app.sql",
  "public.comment_links": "app.sql",
};

const BLOCKS: AnyBlocksConfig = {
  messaging: {
    tables: {
      conversations: "public.rooms",
      members: "public.room_members",
      messages: "public.posts",
    },
    columns: {
      conversations: { tenant: "org_id" },
      members: {
        conversation: "room_id",
        tenant: "org_id",
        notify: null,
        joinedAt: null,
      },
      messages: {
        tenant: "org_id",
        conversation: "room_id",
        anchor: null,
        scheduledFor: null,
        resolvedAt: null,
        resolvedBy: null,
      },
    },
  },
  comments: {
    tables: { tasks: "public.comment_links" },
    columns: { tasks: { tenant: "org_id", createdBy: null, createdAt: null } },
  },
};

// Everyone may do everything in the tenant: these tests are about the tables.
const ALLOW = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.can_user(member uuid, scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $$ select '${TENANT}'::uuid $$;
insert into public.deals (id, organization_id) values ('${DEAL}', '${TENANT}'), ('${COPY}', '${TENANT}');
`;

const AS_ALICE = `perform set_config('request.jwt.claims', '{"sub":"${ALICE}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${ALICE}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

const AS_SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["comments"], {
    modules: BLOCKS,
    ownTables: OWN_TABLES,
    subjects: { deal: { table: "deals" } },
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

describe("comments over the app's tables", BOOT, () => {
  it("comments on a record, lists, counts and copies the thread", async () => {
    await expect(
      run(`do $$
declare
  v_first jsonb;
  v_counts jsonb;
begin
  ${AS_ALICE}
  v_first := better_supabase.create_comment('${TENANT}', 'deal', '${DEAL}', 'first');
  perform better_supabase.create_comment('${TENANT}', 'deal', '${DEAL}', 'a reply', jsonb_build_object('parentId', v_first ->> 'id'));
  if (select kind from public.rooms where subject_id = '${DEAL}') <> 'subject'
    or (select access from public.rooms where subject_id = '${DEAL}') <> 'subject' then
    raise exception 'room %', (select jsonb_agg(r) from public.rooms r);
  end if;
  if jsonb_array_length(better_supabase.list_comments('${TENANT}', 'deal', '${DEAL}')) <> 2 then
    raise exception 'list_comments %', better_supabase.list_comments('${TENANT}', 'deal', '${DEAL}');
  end if;
  v_counts := better_supabase.comment_counts('${TENANT}', 'deal', array['${DEAL}']);
  if v_counts::text not like '%2%' then
    raise exception 'comment_counts %', v_counts;
  end if;
  if jsonb_array_length(better_supabase.list_file_comments(gen_random_uuid())) <> 0 then
    raise exception 'file comments without an anchor column';
  end if;
  ${AS_SERVICE}
  if better_supabase.copy_comments('${TENANT}', 'deal', '${DEAL}', 'deal', '${COPY}') <> 2 then
    raise exception 'copy_comments copied %', (select count(*) from public.posts);
  end if;
  if (select count(*) from public.posts) <> 4 then
    raise exception 'posts %', (select count(*) from public.posts);
  end if;
  if not exists (
    select 1 from pg_indexes where schemaname = 'public' and tablename = 'comment_links' and indexdef like 'CREATE UNIQUE INDEX%(message_id)'
  ) then
    raise exception 'no unique index on the comment links';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses an anchor the messages table has no column for", async () => {
    await expect(
      run(`do $$
begin
  ${AS_ALICE}
  perform better_supabase.create_comment('${TENANT}', 'deal', '${DEAL}', 'here', '{"anchor": {"kind": "text", "quote": "x"}}');
end;
$$;`),
    ).rejects.toThrow(/no anchor column/);
  });
});
