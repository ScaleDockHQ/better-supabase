import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ACCOUNT = "22222222-2222-4222-8222-222222222222";
const OWNER = "33333333-3333-4333-8333-333333333333";
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

// The app's own mail tables: renamed columns, enum share, status, direction
// and kind columns, and none of the optional columns.
const APP = `
create type public.mail_share as enum ('records', 'private');
create type public.mailbox_state as enum ('active', 'paused', 'error', 'disconnected');
create type public.mail_direction as enum ('inbound', 'outbound');
create type public.mail_event_kind as enum ('open', 'click');

create table public.mailboxes (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  owner_id uuid not null,
  provider text not null,
  email text not null,
  credential jsonb not null,
  visibility public.mail_share not null default 'records',
  state public.mailbox_state not null default 'active',
  sync_cursor text,
  last_synced_at timestamptz
);

create table public.mail_conversations (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  mailbox_id uuid not null references public.mailboxes (id) on delete cascade,
  external_id text not null,
  last_message_at timestamptz
);

create table public.mail_items (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  mailbox_id uuid not null references public.mailboxes (id) on delete cascade,
  conversation_id uuid not null references public.mail_conversations (id) on delete cascade,
  external_id text not null,
  direction public.mail_direction not null,
  from_address text,
  to_addresses text[] not null default '{}',
  sent_at timestamptz not null,
  tracking_hash text,
  opened_at timestamptz,
  clicked_at timestamptz,
  unique (mailbox_id, external_id)
);

create table public.mail_link_urls (
  org_id uuid not null,
  message_id uuid not null references public.mail_items (id) on delete cascade,
  position integer not null,
  url text not null,
  click_count integer not null default 0,
  primary key (message_id, position)
);

create table public.mail_events (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  message_id uuid not null references public.mail_items (id) on delete cascade,
  kind public.mail_event_kind not null,
  occurred_at timestamptz not null default now()
);

create table public.mail_conversation_records (
  org_id uuid not null,
  thread_id uuid not null references public.mail_conversations (id) on delete cascade,
  subject_type text not null,
  subject_id text not null
);
`;

const OWN_TABLES = {
  "public.mailboxes": "app.sql",
  "public.mail_conversations": "app.sql",
  "public.mail_items": "app.sql",
  "public.mail_link_urls": "app.sql",
  "public.mail_events": "app.sql",
  "public.mail_conversation_records": "app.sql",
};

const BLOCKS: AnyBlocksConfig = {
  "mail-sync": {
    tables: {
      accounts: "public.mailboxes",
      threads: "public.mail_conversations",
      messages: "public.mail_items",
      trackedLinks: "public.mail_link_urls",
      tracking: "public.mail_events",
      links: "public.mail_conversation_records",
    },
    columns: {
      accounts: {
        tenant: "org_id",
        user: "owner_id",
        address: "email",
        credentialRef: "credential",
        share: "visibility",
        status: "state",
        lastError: null,
        createdAt: null,
        updatedAt: null,
      },
      threads: {
        tenant: "org_id",
        account: "mailbox_id",
        subject: null,
        snippet: null,
        messageCount: null,
        engagement: null,
        createdAt: null,
        updatedAt: null,
      },
      messages: {
        tenant: "org_id",
        account: "mailbox_id",
        thread: "conversation_id",
        rfcId: null,
        fromName: null,
        cc: null,
        subject: null,
        snippet: null,
        bodyText: null,
        bodyHtml: null,
        templateVersion: null,
        openCount: null,
        clickCount: null,
        createdAt: null,
      },
      trackedLinks: { tenant: "org_id", createdAt: null },
      tracking: { tenant: "org_id", position: null, userAgent: null },
      links: { tenant: "org_id", source: null, createdAt: null },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["mail-sync"], {
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
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("mail-sync over the app's tables", BOOT, () => {
  it("ingests messages once, tracks an open and sets the mailbox status", async () => {
    await expect(
      run(`do $$
declare
  v_result jsonb;
  v_batch jsonb := jsonb_build_array(
    jsonb_build_object('externalId', 'm1', 'threadId', 't1', 'from', jsonb_build_object('address', 'ann@example.com'),
      'to', jsonb_build_array('me@example.com'), 'subject', 'Hello', 'sentAt', '2026-01-01T10:00:00Z'),
    jsonb_build_object('externalId', 'm2', 'threadId', 't1', 'from', 'me@example.com',
      'to', jsonb_build_array('ann@example.com'), 'sentAt', '2026-01-01T11:00:00Z', 'trackingHash', '${HASH}'));
begin
  ${SERVICE}
  insert into public.mailboxes (id, org_id, owner_id, provider, email, credential)
  values ('${ACCOUNT}', '${TENANT}', '${OWNER}', 'gmail', 'me@example.com', '{"ref": "grant"}');
  v_result := better_supabase.ingest_mail('${ACCOUNT}', v_batch, 'c1');
  if (v_result ->> 'stored')::integer <> 2 or (v_result ->> 'threads')::integer <> 1 then
    raise exception 'ingested %', v_result;
  end if;
  v_result := better_supabase.ingest_mail('${ACCOUNT}', v_batch, 'c2');
  if (v_result ->> 'stored')::integer <> 0 then
    raise exception 'stored a message twice: %', v_result;
  end if;
  if (select count(*) from public.mail_items) <> 2
    or (select direction from public.mail_items where external_id = 'm2') <> 'outbound'
    or (select last_message_at from public.mail_conversations) <> '2026-01-01T11:00:00Z'
    or (select sync_cursor from public.mailboxes) <> 'c2' then
    raise exception 'stored %', (select jsonb_agg(y) from public.mail_items y);
  end if;
  v_result := better_supabase.track_mail('${HASH}', 'open', null, 'agent');
  if v_result ->> 'messageId' is null
    or (select kind from public.mail_events) <> 'open'
    or (select opened_at from public.mail_items where external_id = 'm2') is null then
    raise exception 'tracked %', v_result;
  end if;
  if not better_supabase.set_mail_account_status('${ACCOUNT}', 'paused', 'quota') then
    raise exception 'no mailbox to pause';
  end if;
  if (select state from public.mailboxes) <> 'paused' then
    raise exception 'not paused %', (select jsonb_agg(k) from public.mailboxes k);
  end if;
  if better_supabase.due_mail_accounts(10, null) <> '[]'::jsonb then
    raise exception 'a paused mailbox is due: %', better_supabase.due_mail_accounts(10, null);
  end if;
  perform better_supabase.set_mail_account_status('${ACCOUNT}', 'active', null);
  update public.mailboxes set last_synced_at = null;
  v_result := better_supabase.due_mail_accounts(10, null);
  if jsonb_array_length(v_result) <> 1 or v_result -> 0 ->> 'share' <> 'records'
    or v_result -> 0 -> 'last_error' <> 'null'::jsonb or v_result -> 0 ->> 'address' <> 'me@example.com' then
    raise exception 'due %', v_result;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
