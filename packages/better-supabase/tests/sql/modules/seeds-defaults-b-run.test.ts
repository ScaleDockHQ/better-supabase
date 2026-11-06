import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";

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

-- PGlite has no Realtime schema; block policies are written on its messages table.
create schema if not exists realtime;
create table realtime.messages (
  id bigint generated always as identity primary key,
  topic text not null default '',
  extension text not null default 'broadcast'
);
create function realtime.topic() returns text language sql stable
as $$ select nullif(current_setting('realtime.topic', true), '') $$;
`;

const CHECK = `do $$
declare
  v_count int;
begin
  perform better_supabase.seed_inbox_defaults('${TENANT}');
  perform better_supabase.seed_attachments_defaults('${TENANT}');
  perform better_supabase.seed_calendar_defaults('${TENANT}', null, 'nl');
  perform better_supabase.seed_calendar_defaults('${TENANT}', null, 'en-gb');
  perform better_supabase.seed_calendar_defaults('${TENANT}', null, 'en');
  -- A second run adds nothing.
  perform better_supabase.seed_inbox_defaults('${TENANT}');
  perform better_supabase.seed_attachments_defaults('${TENANT}');
  perform better_supabase.seed_calendar_defaults('${TENANT}', null, 'nl');

  if (select count(*) from better_supabase.inboxes where name = 'Help') <> 1 then
    raise exception 'help inbox';
  end if;
  if (select count(*) from better_supabase.attachment_document_types) <> 6 then
    raise exception 'document types';
  end if;
  if (select count(*) from better_supabase.calendars) <> 2 then
    raise exception 'calendars %', (select count(*) from better_supabase.calendars);
  end if;
  select count(*) into v_count from better_supabase.calendar_events e
    join better_supabase.calendars c on c.id = e.calendar_id where c.name = 'Public holidays (NL)';
  if v_count <> 50 then
    raise exception 'nl holidays %', v_count;
  end if;
  if not exists (select 1 from better_supabase.calendar_events where uid = 'holiday-nl-2026-04-27' and all_day
    and starts_at = '2026-04-26T22:00:00Z' and ends_at = '2026-04-27T22:00:00Z') then
    raise exception 'kings day instant';
  end if;
  if not exists (select 1 from better_supabase.calendar_events where uid = 'holiday-en-gb-2027-12-27') then
    raise exception 'gb substitute day';
  end if;
end;
$$;`;

describe("seeds on a running database", () => {
  it(
    "seeds the Help inbox, document types and holiday calendars once",
    { timeout: 120_000 },
    async () => {
      const files = renderBlocks(["inbox", "attachments", "calendar"], {});

      await using stack = await liteStack({
        driver: "pglite",
        // The inbox renders before messaging and its functions name messaging's
        // tables, so the schema replays as one seed session with body checks off.
        migrations: ["create table public.seeds_probe (id int);"],
        seed: [
          [
            ROLES,
            ...files
              .filter((file) => file.kind === "schema")
              .map(
                (file) => `set check_function_bodies = off;\n${file.contents}`,
              ),
            "reset check_function_bodies;",
          ].join("\n;\n"),
          ...files
            .filter((file) => file.kind === "data")
            .map((file) => file.contents),
          CHECK,
        ],
      });

      expect(stack.url).not.toBe("");
    },
  );
});
