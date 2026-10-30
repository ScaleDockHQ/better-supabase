import { describe, expect, it } from "vitest";

import { SQL_MODULES } from "../../../src/sql/registry.ts";
import { renderBlocks } from "../../../src/sql/render.ts";
import { upgradePlan } from "../../../src/sql/upgrade.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const INBOX = "22222222-2222-4222-8222-222222222222";
const USER = "33333333-3333-4333-8333-333333333333";
const ADA = "44444444-4444-4444-8444-444444444441";
const BO = "44444444-4444-4444-8444-444444444442";
const CY = "44444444-4444-4444-8444-444444444443";
const ODD = "44444444-4444-4444-8444-444444444444";
const BO_PERSON = "55555555-5555-4555-8555-555555555551";
const CY_PERSON = "55555555-5555-4555-8555-555555555552";

const conversation = (contact: string): string =>
  `66666666-6666-4666-8666-${contact.slice(-12)}`;

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

// The inbox's version 7 contact tables, and the contacts block's link table,
// as 0.46 created them.
const VERSION_7 = `
create table better_supabase.contacts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  user_id uuid references auth.users (id) on delete set null,
  name text,
  email text,
  phone text,
  avatar_url text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table better_supabase.contact_identities (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  contact_id uuid not null references better_supabase.contacts (id) on delete cascade,
  channel text not null,
  external_id text not null,
  created_at timestamptz not null default now(),
  unique (tenant_id, channel, external_id)
);
create table better_supabase.person_inbox_contacts (
  tenant_id uuid not null,
  person_id uuid not null references better_supabase.people (id) on delete cascade,
  contact_id uuid not null unique references better_supabase.contacts (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (person_id, contact_id)
);
alter table better_supabase.inbox_conversations drop constraint inbox_conversations_contact_id_fkey;
alter table better_supabase.inbox_conversations add constraint inbox_conversations_contact_id_fkey
  foreign key (contact_id) references better_supabase.contacts (id) on delete cascade;
alter table better_supabase.identity_links drop constraint identity_links_contact_id_fkey;
alter table better_supabase.identity_links add constraint identity_links_contact_id_fkey
  foreign key (contact_id) references better_supabase.contacts (id) on delete cascade;
`;

const opened = (contact: string): string =>
  `insert into better_supabase.conversations (id, tenant_id, kind, access) values ('${conversation(contact)}', '${TENANT}', 'inbox', 'tenant');
insert into better_supabase.inbox_conversations (id, tenant_id, inbox_id, contact_id) values ('${conversation(contact)}', '${TENANT}', '${INBOX}', '${contact}');`;

// Ada has no person; Bo's email matches an active person; Cy was linked to a
// person; the last contact's email is no email address.
const SEED = `
insert into auth.users (id) values ('${USER}') on conflict do nothing;
insert into better_supabase.inboxes (id, tenant_id, name, channel) values ('${INBOX}', '${TENANT}', 'Support', 'whatsapp');
insert into better_supabase.people (id, tenant_id, name, email, lifecycle) values
  ('${BO_PERSON}', '${TENANT}', 'Bo Person', 'bo@example.com', 'customer'),
  ('${CY_PERSON}', '${TENANT}', 'Cy Person', null, 'lead');
insert into better_supabase.contacts (id, tenant_id, user_id, name, email, phone, avatar_url, metadata) values
  ('${ADA}', '${TENANT}', '${USER}', 'Ada', 'Ada@Example.com', '+31600000001', 'https://example.com/ada.png', '{"plan": "pro"}'),
  ('${BO}', '${TENANT}', null, 'Bo', 'BO@example.com', '+31600000002', null, '{}'),
  ('${CY}', '${TENANT}', null, 'Cy', null, null, null, '{}'),
  ('${ODD}', '${TENANT}', null, null, 'not an email', null, null, '{}');
insert into better_supabase.contact_identities (tenant_id, contact_id, channel, external_id) values
  ('${TENANT}', '${ADA}', 'whatsapp', '+31600000001'),
  ('${TENANT}', '${BO}', 'whatsapp', '+31600000002'),
  ('${TENANT}', '${CY}', 'slack', 'U123');
insert into better_supabase.person_inbox_contacts (tenant_id, person_id, contact_id) values ('${TENANT}', '${CY_PERSON}', '${CY}');
${[ADA, BO, CY, ODD].map(opened).join("\n")}
insert into better_supabase.identity_links (kind, provider, value, contact_id, source) values ('chat', 'slack', 'U123', '${CY}', 'link');
`;

const CHECK = `
do $$
declare
  v_row better_supabase.people;
begin
  if to_regclass('better_supabase.contacts') is not null
    or to_regclass('better_supabase.contact_identities') is not null
    or to_regclass('better_supabase.person_inbox_contacts') is not null then
    raise exception 'the inbox contact tables still exist';
  end if;
  select * into v_row from better_supabase.people where id = '${ADA}';
  if v_row.name <> 'Ada' or v_row.email <> 'ada@example.com' or v_row.phone <> '+31600000001' or v_row.user_id <> '${USER}'
    or v_row.avatar_url <> 'https://example.com/ada.png' or v_row.metadata <> '{"plan": "pro"}' or v_row.lifecycle <> 'lead' then
    raise exception 'ada %', to_jsonb(v_row);
  end if;
  if exists (select 1 from better_supabase.people where id in ('${BO}', '${CY}')) then
    raise exception 'bo or cy became a second person';
  end if;
  select * into v_row from better_supabase.people where id = '${BO_PERSON}';
  if v_row.name <> 'Bo Person' or v_row.phone <> '+31600000002' then
    raise exception 'bo %', to_jsonb(v_row);
  end if;
  select * into v_row from better_supabase.people where id = '${ODD}';
  if v_row.name <> 'not an email' or v_row.email is not null or v_row.metadata ->> 'email' <> 'not an email' then
    raise exception 'odd %', to_jsonb(v_row);
  end if;
  if (select contact_id from better_supabase.inbox_conversations where id = '${conversation(ADA)}') <> '${ADA}'
    or (select contact_id from better_supabase.inbox_conversations where id = '${conversation(BO)}') <> '${BO_PERSON}'
    or (select contact_id from better_supabase.inbox_conversations where id = '${conversation(CY)}') <> '${CY_PERSON}'
    or (select contact_id from better_supabase.inbox_conversations where id = '${conversation(ODD)}') <> '${ODD}' then
    raise exception 'conversations %', (select jsonb_agg(v) from better_supabase.inbox_conversations v);
  end if;
  if (select contact_id from better_supabase.identity_links where value = 'U123') <> '${CY_PERSON}' then
    raise exception 'identity link %', (select jsonb_agg(l) from better_supabase.identity_links l);
  end if;
  if (select count(*) from better_supabase.person_identities) <> 3
    or (select person_id from better_supabase.person_identities where address = '+31600000001') <> '${ADA}'
    or (select person_id from better_supabase.person_identities where address = '+31600000002') <> '${BO_PERSON}'
    or (select person_id from better_supabase.person_identities where channel = 'slack' and address = 'U123') <> '${CY_PERSON}' then
    raise exception 'identities %', (select jsonb_agg(i) from better_supabase.person_identities i);
  end if;
end;
$$;
`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

describe("inbox version 8 upgrade", BOOT, () => {
  it("moves inbox contacts onto people without losing a row", async () => {
    const files = renderBlocks(["inbox", "identities"]);

    const plan = upgradePlan(
      [
        { module: "inbox", version: 7 },
        { module: "contacts", version: 1 },
        {
          module: "identities",
          version: SQL_MODULES["identities"]?.version ?? 1,
        },
      ],
      { modules: { inbox: {}, identities: {} } },
    ).find((entry) => entry.module === "inbox");

    expect(plan?.to).toBe(8);
    expect(plan?.steps).toHaveLength(1);

    // The inbox renders before messaging and contacts, and its PL/pgSQL names
    // their tables, so the schema replays in one session with body checks off.
    await using stack = await liteStack({
      driver: "pglite",
      migrations: ["select 1;"],
      seed: [
        [
          ROLES,
          ...files
            .filter((file) => file.kind !== "data")
            .map(
              (file) => `set check_function_bodies = off;\n${file.contents}`,
            ),
          "reset check_function_bodies;",
        ].join("\n;\n"),
        ...files
          .filter((file) => file.kind === "data")
          .map((file) => file.contents),
        VERSION_7,
        SEED,
        ...(plan?.steps ?? []).map((step) => step.sql),
        CHECK,
      ],
    });

    expect(stack.url).not.toBe("");
  });
});
