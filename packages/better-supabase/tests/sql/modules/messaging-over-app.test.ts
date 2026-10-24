import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";
const BOB = "33333333-3333-4333-8333-333333333333";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
create schema if not exists realtime;
create or replace function realtime.send(payload jsonb, event text, topic text, private boolean default true)
returns void language plpgsql as $$ begin end $$;
`;

// The app's own chat tables: renamed columns, enum kinds, access, roles and
// mention scopes, and no notify level, join time, anchor, schedule or
// resolved columns.
const APP = `
create type public.room_kind as enum ('channel', 'dm', 'group_dm', 'subject', 'inbox');
create type public.room_access as enum ('members', 'tenant', 'subject');
create type public.room_role as enum ('owner', 'member');
create type public.post_kind as enum ('message', 'note');
create type public.post_scope as enum ('channel', 'here');

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  kind public.room_kind not null,
  access public.room_access not null default 'members',
  subject_type text,
  subject_id text,
  name text,
  member_key text,
  created_by uuid,
  last_message_at timestamptz,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  topic text
);

create table public.room_members (
  room_id uuid not null references public.rooms (id) on delete cascade,
  org_id uuid not null,
  user_id uuid not null,
  role public.room_role not null default 'member',
  last_read_at timestamptz,
  primary key (room_id, user_id)
);

create table public.posts (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  room_id uuid not null references public.rooms (id) on delete cascade,
  parent_id uuid references public.posts (id) on delete set null,
  thread_id uuid references public.posts (id) on delete cascade,
  author_id uuid,
  kind public.post_kind not null default 'message',
  body text not null default '',
  document jsonb,
  mentions uuid[] not null default '{}',
  scope public.post_scope,
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
`;

const OWN_TABLES = {
  "public.rooms": "app.sql",
  "public.room_members": "app.sql",
  "public.posts": "app.sql",
};

const BLOCKS: AnyBlocksConfig = {
  messaging: {
    tables: {
      conversations: "public.rooms",
      members: "public.room_members",
      messages: "public.posts",
    },
    columns: {
      conversations: { tenant: "org_id", title: "name" },
      members: {
        conversation: "room_id",
        tenant: "org_id",
        notify: null,
        joinedAt: null,
      },
      messages: {
        tenant: "org_id",
        conversation: "room_id",
        mentionScope: "scope",
        anchor: null,
        scheduledFor: null,
        resolvedAt: null,
        resolvedBy: null,
      },
    },
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
insert into auth.users (id) values ('${ALICE}'), ('${BOB}');
insert into better_supabase.memberships (organization_id, user_id) values ('${TENANT}', '${ALICE}'), ('${TENANT}', '${BOB}');
`;

const as = (user: string): string =>
  `perform set_config('request.jwt.claims', '{"sub":"${user}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${user}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["messaging", "notifications"], {
    modules: BLOCKS,
    ownTables: OWN_TABLES,
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

describe("messaging over the app's tables", BOOT, () => {
  it("opens, sends, edits, pins, lists and reads in enum columns", async () => {
    await expect(
      run(`do $$
declare
  v_dm jsonb;
  v_room uuid;
  v_msg jsonb;
  v_reply jsonb;
  v_list jsonb;
begin
  ${as(ALICE)}
  v_dm := better_supabase.open_conversation('${TENANT}', 'dm', '{}', array['${BOB}'::uuid]);
  v_room := (v_dm ->> 'id')::uuid;
  if (select kind from public.rooms where id = v_room) <> 'dm' or (select access from public.rooms where id = v_room) <> 'members' then
    raise exception 'opened %', v_dm;
  end if;
  if (select count(*) from public.room_members where room_id = v_room) <> 2
    or (select role from public.room_members where room_id = v_room and user_id = '${ALICE}') <> 'owner' then
    raise exception 'members %', (select jsonb_agg(m) from public.room_members m);
  end if;
  if (better_supabase.open_conversation('${TENANT}', 'dm', '{}', array['${BOB}'::uuid]) ->> 'id')::uuid <> v_room then
    raise exception 'a second open made another room';
  end if;
  v_msg := better_supabase.send_message(v_room, 'hello @channel');
  if (select scope from public.posts where id = (v_msg ->> 'id')::uuid) is distinct from 'channel' then
    raise exception 'sent %', v_msg;
  end if;
  -- Without a notify column every member hears of a mention of the room.
  if not exists (select 1 from better_supabase.notification_recipients r where r.user_id = '${BOB}') then
    raise exception 'no notification for the other member';
  end if;
  v_reply := better_supabase.send_message(v_room, 'a reply', jsonb_build_object('parentId', v_msg ->> 'id'));
  if (select reply_count from public.posts where id = (v_msg ->> 'id')::uuid) <> 1 then
    raise exception 'replies %', (select reply_count from public.posts where id = (v_msg ->> 'id')::uuid);
  end if;
  perform better_supabase.edit_message((v_msg ->> 'id')::uuid, 'hello again');
  perform better_supabase.pin_message((v_msg ->> 'id')::uuid);
  if (select body from public.posts where id = (v_msg ->> 'id')::uuid) <> 'hello again'
    or (select pinned_at from public.posts where id = (v_msg ->> 'id')::uuid) is null then
    raise exception 'edit or pin missed';
  end if;
  v_list := better_supabase.list_messages(v_room);
  if jsonb_array_length(v_list) <> 1 then
    raise exception 'list_messages %', v_list;
  end if;
  if jsonb_array_length(better_supabase.list_conversations('${TENANT}', array['dm'])) <> 1 then
    raise exception 'list_conversations %', better_supabase.list_conversations('${TENANT}', array['dm']);
  end if;
  ${as(BOB)}
  if better_supabase.unread_counts('${TENANT}') is null then
    raise exception 'unread_counts is null';
  end if;
  perform better_supabase.mark_read(v_room);
  if (select last_read_at from public.room_members where room_id = v_room and user_id = '${BOB}') is null then
    raise exception 'mark_read missed';
  end if;
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  if better_supabase.publish_due_messages() <> 0 then
    raise exception 'published without a schedule column';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses a notify level the members table has no column for", async () => {
    await expect(
      run(`do $$
declare
  v_room uuid;
begin
  ${as(ALICE)}
  v_room := (better_supabase.open_conversation('${TENANT}', 'dm', '{}', array['${BOB}'::uuid]) ->> 'id')::uuid;
  perform better_supabase.set_conversation_notify(v_room, 'mentions');
end;
$$;`),
    ).rejects.toThrow(/no notify column/);
  });

  it("refuses a schedule, an anchor and resolving without their columns", async () => {
    for (const [call, message] of [
      [
        `perform better_supabase.send_message(v_room, 'later', jsonb_build_object('scheduledFor', now() + interval '1 day'));`,
        /no scheduledFor column/,
      ],
      [
        `perform better_supabase.send_message(v_room, 'here', '{"anchor": {"kind": "text", "quote": "x"}}');`,
        /no anchor column/,
      ],
      [
        `perform better_supabase.resolve_message((better_supabase.send_message(v_room, 'done?') ->> 'id')::uuid);`,
        /no resolvedAt column/,
      ],
    ] as const) {
      await expect(
        run(`do $$
declare
  v_room uuid;
begin
  ${as(ALICE)}
  v_room := (better_supabase.open_conversation('${TENANT}', 'dm', '{}', array['${BOB}'::uuid]) ->> 'id')::uuid;
  ${call}
end;
$$;`),
      ).rejects.toThrow(message);
    }
  });
});
