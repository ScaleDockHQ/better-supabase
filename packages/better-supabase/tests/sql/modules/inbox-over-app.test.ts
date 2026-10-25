import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role;
  end if;
end;
$$;

create schema if not exists extensions;
create function extensions.gen_random_bytes(n integer) returns bytea
language sql volatile as $$ select decode(md5(random()::text), 'hex') $$;
create function extensions.digest(data text, type text) returns bytea
language sql immutable as $$ select sha256(convert_to(data, 'UTF8')) $$;

-- PGlite has no Storage schema; these are the columns the modules read.
create schema if not exists storage;
create table storage.buckets (
  id text primary key,
  name text not null,
  public boolean default false,
  file_size_limit bigint,
  allowed_mime_types text[]
);
create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets (id),
  name text not null,
  owner uuid,
  metadata jsonb,
  version text
);
alter table storage.objects enable row level security;
`;

// The app's own conversations: renamed columns, enum status and bot mode, and
// no subject, priority, first response, resolved or metadata columns.
const APP = `
create type public.ticket_status as enum ('open', 'pending', 'snoozed', 'resolved');
create type public.ticket_answerer as enum ('bot', 'human', 'paused');

create table public.tickets (
  id uuid primary key,
  org_id uuid not null,
  inbox_id uuid not null,
  customer_id uuid not null,
  state public.ticket_status not null default 'open',
  owner_id uuid,
  team_id uuid,
  answered_by public.ticket_answerer not null default 'human',
  thread_id text,
  snoozed_until timestamptz,
  last_message_at timestamptz not null default now(),
  last_message_preview text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
`;

const BLOCKS: AnyBlocksConfig = {
  inbox: {
    tables: { conversations: "public.tickets" },
    columns: {
      conversations: {
        tenant: "org_id",
        contact: "customer_id",
        status: "state",
        assignee: "owner_id",
        botMode: "answered_by",
        subject: null,
        priority: null,
        firstResponseAt: null,
        resolvedAt: null,
        metadata: null,
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
insert into auth.users (id) values ('${ALICE}') on conflict do nothing;
`;

const AS_ALICE = `perform set_config('request.jwt.claims', '{"sub":"${ALICE}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${ALICE}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

const AS_SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["inbox"], {
    modules: BLOCKS,
    ownTables: { "public.tickets": "app.sql" },
  });

  // The inbox renders before messaging and its PL/pgSQL functions name
  // messaging's tables, so the schema replays as seed SQL in one session with
  // body checks off; earlier files reset the setting.
  await using stack = await liteStack({
    driver: "pglite",
    migrations: [APP],
    seed: [
      [
        ROLES,
        ...files
          .filter((file) => file.kind !== "data")
          .map((file) => `set check_function_bodies = off;\n${file.contents}`),
        "reset check_function_bodies;",
      ].join("\n;\n"),
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      ALLOW,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("inbox over the app's conversations", BOOT, () => {
  it("opens, answers, resolves, reopens and lists a conversation", async () => {
    await expect(
      run(`do $$
declare
  v_inbox jsonb;
  v_conv jsonb;
  v_id uuid;
  v_inbound jsonb;
begin
  ${AS_SERVICE}
  v_inbox := better_supabase.create_inbox('${TENANT}', 'Support', 'whatsapp', '{}'::jsonb, 'human', '+31600000000');
  ${AS_ALICE}
  v_conv := better_supabase.start_conversation((v_inbox ->> 'id')::uuid, jsonb_build_object(
    'contact', jsonb_build_object('name', 'Bob', 'email', 'bob@example.com'),
    'subject', 'Where is my order',
    'priority', 'high',
    'message', 'Hello Bob'
  ));
  v_id := (v_conv ->> 'id')::uuid;
  if v_conv ->> 'status' <> 'open' or v_conv ->> 'bot_mode' <> 'human' or v_conv ->> 'priority' <> 'normal'
    or v_conv ? 'state' or v_conv -> 'contact' ->> 'name' <> 'Bob' then
    raise exception 'start_conversation %', v_conv;
  end if;
  if (select last_message_preview from public.tickets where id = v_id) <> 'Hello Bob' then
    raise exception 'preview %', (select jsonb_agg(t) from public.tickets t);
  end if;
  perform better_supabase.send_inbox_message(v_id, '{"body": "On its way"}');
  v_conv := better_supabase.set_conversation_status(v_id, 'resolved');
  if (select state from public.tickets where id = v_id) <> 'resolved' then
    raise exception 'set_conversation_status %', v_conv;
  end if;
  v_conv := better_supabase.set_bot_mode(v_id, 'bot', 'night');
  if (select answered_by from public.tickets where id = v_id) <> 'bot' then
    raise exception 'set_bot_mode %', v_conv;
  end if;
  ${AS_SERVICE}
  v_inbound := better_supabase.record_inbound(jsonb_build_object(
    'inbox_id', v_inbox ->> 'id',
    'thread_id', (select thread_id from public.tickets where id = v_id),
    'contact', jsonb_build_object('external_id', '+31611111111'),
    'message', jsonb_build_object('body', 'Thanks', 'external_id', 'wamid.1')
  ));
  if (v_inbound ->> 'created')::boolean or (v_inbound ->> 'conversation_id')::uuid <> v_id then
    raise exception 'record_inbound %', v_inbound;
  end if;
  if (select state from public.tickets where id = v_id) <> 'open' then
    raise exception 'reopen %', (select jsonb_agg(t) from public.tickets t);
  end if;
  v_inbound := better_supabase.record_inbound(jsonb_build_object(
    'inbox_id', v_inbox ->> 'id',
    'thread_id', 'whatsapp:+31622222222',
    'contact', jsonb_build_object('external_id', '+31622222222'),
    'message', jsonb_build_object('body', 'New here')
  ));
  if not (v_inbound ->> 'created')::boolean
    or (select answered_by from public.tickets where id = (v_inbound ->> 'conversation_id')::uuid) <> 'human' then
    raise exception 'record_inbound new %', v_inbound;
  end if;
  ${AS_ALICE}
  if jsonb_array_length(better_supabase.list_inbox_conversations('${TENANT}', '{"status": "open"}')) <> 2 then
    raise exception 'list_inbox_conversations %', better_supabase.list_inbox_conversations('${TENANT}', '{"status": "open"}');
  end if;
  if jsonb_array_length(better_supabase.list_inbox_conversations('${TENANT}', '{"search": "Bob"}')) <> 1 then
    raise exception 'search %', better_supabase.list_inbox_conversations('${TENANT}', '{"search": "Bob"}');
  end if;
  if better_supabase.get_conversation(v_id) ->> 'id' <> v_id::text then
    raise exception 'get_conversation %', better_supabase.get_conversation(v_id);
  end if;
  if jsonb_array_length(better_supabase.list_inbox_messages(v_id)) <> 3 then
    raise exception 'list_inbox_messages %', better_supabase.list_inbox_messages(v_id);
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
