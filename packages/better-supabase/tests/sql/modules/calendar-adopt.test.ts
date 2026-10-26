import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const OWNER = "22222222-2222-4222-8222-222222222222";
const ALICE = "33333333-3333-4333-8333-333333333333";
const BOB = "44444444-4444-4444-8444-444444444444";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// An app's calendar tables: enum visibility and status, a uuid owner, an
// integer position, structured rules and a dates table, attendees without a
// role or a required email, and a shares table with its own access column.
const APP = `
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create type public.calendar_visibility as enum ('team', 'personal');
create type public.event_status as enum ('busy', 'maybe', 'canceled');
create type public.event_visibility as enum ('normal', 'secret');
create type public.repeat_freq as enum ('daily', 'weekly', 'monthly', 'yearly');
create type public.date_kind as enum ('extra', 'skip');

create table public.calendars (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  name text not null,
  timezone text not null default 'UTC',
  owner_user_id uuid,
  visibility public.calendar_visibility not null default 'team',
  is_default boolean not null default false,
  position integer,
  description text,
  created_at timestamptz not null default now()
);

create table public.events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  calendar_id uuid not null references public.calendars (id) on delete cascade,
  uid text not null,
  title text not null default '',
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  all_day boolean not null default false,
  timezone text not null default 'UTC',
  status public.event_status not null default 'busy',
  recurrence_id uuid references public.events (id) on delete cascade,
  original_start timestamptz,
  visibility public.event_visibility not null default 'normal',
  owner_user_id uuid,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.event_rules (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events (id) on delete cascade,
  frequency public.repeat_freq not null,
  every integer,
  occurrences integer,
  ends_at timestamptz,
  weekdays text[],
  month_days integer[]
);

create table public.event_dates (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events (id) on delete cascade,
  kind public.date_kind not null,
  occurs_at timestamptz not null
);

create table public.attendees (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  event_id uuid not null references public.events (id) on delete cascade,
  email text,
  display_name text,
  user_id uuid,
  record_type text,
  record_id text,
  response text not null default 'needs-action',
  is_organizer boolean not null default false,
  is_optional boolean not null default false
);

create table public.calendar_shares (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  calendar_id uuid not null references public.calendars (id) on delete cascade,
  user_id uuid not null,
  access text not null
);

create table public.test_keys (user_id uuid, tenant uuid, key text);
grant select on public.test_keys to authenticated;
`;

const OWN_TABLES = {
  "public.calendars": "app.sql",
  "public.events": "app.sql",
  "public.attendees": "app.sql",
  "public.calendar_shares": "app.sql",
  "public.event_rules": "app.sql",
  "public.event_dates": "app.sql",
};

const CALENDAR: AnyBlocksConfig[string] = {
  tables: {
    calendars: "public.calendars",
    events: "public.events",
    attendees: "public.attendees",
    workingHours: null,
    grants: "public.calendar_shares",
    rules: "public.event_rules",
    recurrenceDates: "public.event_dates",
  },
  columns: {
    calendars: {
      tenant: "organization_id",
      tz: "timezone",
      color: null,
      ownerType: null,
      ownerId: "owner_user_id",
      rank: "position",
    },
    events: {
      tenant: "organization_id",
      tz: "timezone",
      rrule: null,
      exdates: null,
      rdates: null,
      description: null,
      location: null,
      subjectType: null,
      subjectId: null,
      color: null,
      kind: null,
      transparency: null,
      autoDecline: null,
      owner: "owner_user_id",
    },
    attendees: {
      tenant: "organization_id",
      name: "display_name",
      role: null,
      subjectType: "record_type",
      subjectId: "record_id",
      organizer: "is_organizer",
      optional: "is_optional",
    },
    grants: { tenant: "organization_id", role: "access", createdAt: null },
    rules: {
      tenant: null,
      rrule: null,
      freq: "frequency",
      interval: "every",
      count: "occurrences",
      until: "ends_at",
      byDay: "weekdays",
      byMonthDay: "month_days",
      byMonth: null,
      bySetPos: null,
    },
    recurrenceDates: { tenant: null, at: "occurs_at" },
  },
  values: {
    calendars: {
      visibility: { shared: "team", private: "personal" },
      ownerId: {},
    },
    events: {
      status: { confirmed: "busy", tentative: "maybe", cancelled: "canceled" },
      visibility: { public: "normal", private: "secret" },
    },
    rules: {
      freq: {
        DAILY: "daily",
        WEEKLY: "weekly",
        MONTHLY: "monthly",
        YEARLY: "yearly",
      },
    },
    recurrenceDates: { kind: { rdate: "extra", exdate: "skip" } },
  },
  options: {
    access: true,
    recurrence: "table",
    attendeeKey: "any",
    calendarDetails: true,
    userFeed: true,
  },
};

const KEYS = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$
  select exists (select 1 from public.test_keys k where k.user_id = auth.uid() and k.tenant = scope_id and k.key = permission)
$$;
create or replace function better_supabase.can_user(member uuid, scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$
  select exists (select 1 from public.test_keys k where k.user_id = member and k.tenant = scope_id and k.key = permission)
$$;
insert into public.test_keys (user_id, tenant, key)
select u, '${TENANT}'::uuid, k
from (values ('${OWNER}'::uuid), ('${ALICE}'::uuid), ('${BOB}'::uuid)) users (u)
cross join (values ('calendar.read'), ('calendar.write'), ('share_links.create')) keys (k)
union all select '${OWNER}'::uuid, '${TENANT}'::uuid, 'calendar.manage';
`;

const as = (user: string): string =>
  `perform set_config('request.jwt.claims', '{"role":"authenticated","sub":"${user}"}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', '${user}', true);`;

const ANON = `perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('request.jwt.claim.role', 'anon', true);
  perform set_config('request.jwt.claim.sub', '', true);`;

const MANAGED_CHECK = `do $$
declare
  v_private uuid;
  v_series uuid;
  v_hint text;
  v_feed jsonb;
begin
  ${as(ALICE)}
  v_private := (better_supabase.create_calendar('${TENANT}', 'Alice', 'UTC', 'user', '${ALICE}', '{"visibility": "private", "description": "Mine"}') ->> 'id')::uuid;
  v_series := (better_supabase.save_calendar_event(v_private, '{"title": "Run", "visibility": "private", "startsAt": "2026-03-02T07:00:00Z", "endsAt": "2026-03-02T08:00:00Z", "rrule": "FREQ=WEEKLY;COUNT=2", "rdates": ["2026-03-04T07:00:00Z"]}') ->> 'id')::uuid;
  if (select cardinality(rdates) from better_supabase.calendar_events where id = v_series) <> 1 then
    raise exception 'rdates %', (select to_jsonb(e) from better_supabase.calendar_events e where id = v_series);
  end if;
  perform better_supabase.set_calendar_attendee(v_series, '{"subjectType": "contact", "subjectId": "c-9"}');
  perform better_supabase.set_calendar_attendee(v_series, 'ada@example.com', 'Ada', null, 'optional');
  v_feed := better_supabase.list_calendars('${TENANT}');
  if v_feed -> 0 ->> 'visibility' <> 'private' or v_feed -> 0 ->> 'description' <> 'Mine' then
    raise exception 'calendars %', v_feed;
  end if;
  v_feed := better_supabase.list_calendar_events(array[v_private], '2026-03-01T00:00:00Z', '2026-04-01T00:00:00Z');
  if jsonb_array_length(v_feed -> 0 -> 'rdates') <> 1 or jsonb_array_length(v_feed -> 0 -> 'attendees') <> 2 then
    raise exception 'events %', v_feed;
  end if;

  ${as(BOB)}
  begin
    perform better_supabase.delete_calendar_event(v_series);
    raise exception 'bob deleted alice''s event';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint <> 'CALENDAR_FORBIDDEN' then raise; end if;
  end;
  v_feed := better_supabase.calendar_free_busy('${TENANT}', array['${ALICE}'::uuid], '2026-03-01T00:00:00Z', '2026-03-08T00:00:00Z');
  if jsonb_array_length(v_feed -> 0 -> 'busy') <> 2 or v_feed::text like '%Run%' then
    raise exception 'free/busy %', v_feed;
  end if;
  execute 'set local role authenticated';
  if (select count(*) from better_supabase.calendar_events) <> 0 or (select count(*) from better_supabase.calendars) <> 0 then
    raise exception 'bob reads alice''s private rows';
  end if;
  execute 'reset role';
end;
$$;`;

const CHECK = `do $$
declare
  v_private uuid;
  v_team uuid;
  v_series uuid;
  v_secret uuid;
  v_attendee uuid;
  v_saved jsonb;
  v_token text;
  v_feed jsonb;
  v_hint text;
begin
  ${as(ALICE)}
  v_private := (better_supabase.create_calendar('${TENANT}', 'Alice', 'UTC', null, '${ALICE}', '{"visibility": "private"}') ->> 'id')::uuid;
  if (select visibility::text from public.calendars where id = v_private) <> 'personal' then
    raise exception 'visibility %', (select to_jsonb(c) from public.calendars c where id = v_private);
  end if;
  begin
    perform better_supabase.create_calendar('${TENANT}', 'Not mine', 'UTC', null, '${BOB}', null);
    raise exception 'a member created a calendar for someone else';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint <> 'CALENDAR_FORBIDDEN' then raise; end if;
  end;

  ${as(OWNER)}
  v_team := (better_supabase.create_calendar('${TENANT}', 'Team', 'UTC', null, null, '{"rank": "2", "isDefault": true, "description": "Everyone"}') ->> 'id')::uuid;
  if (select position from public.calendars where id = v_team) <> 2
    or not (select is_default from public.calendars where id = v_team) then
    raise exception 'details %', (select to_jsonb(c) from public.calendars c where id = v_team);
  end if;
  begin
    perform better_supabase.save_calendar_event(v_private, '{"title": "Peek", "startsAt": "2026-03-02T09:00:00Z", "endsAt": "2026-03-02T10:00:00Z"}');
    raise exception 'a manager wrote to a private calendar';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint <> 'CALENDAR_FORBIDDEN' then raise; end if;
  end;

  ${as(ALICE)}
  v_saved := better_supabase.save_calendar_event(v_private, '{"title": "Therapy", "startsAt": "2026-03-02T09:00:00Z", "endsAt": "2026-03-02T10:00:00Z", "rrule": "FREQ=WEEKLY;BYDAY=MO;COUNT=4", "exdates": ["2026-03-09T09:00:00Z"], "rdates": ["2026-03-05T09:00:00Z"]}');
  v_series := (v_saved ->> 'id')::uuid;
  if (select frequency::text || '/' || occurrences || '/' || weekdays::text from public.event_rules where event_id = v_series) <> 'weekly/4/{MO}' then
    raise exception 'rule %', (select jsonb_agg(r) from public.event_rules r);
  end if;
  if (select string_agg(kind::text || '@' || to_char(occurs_at at time zone 'UTC', 'MM-DD'), ',' order by kind) from public.event_dates where event_id = v_series) <> 'extra@03-05,skip@03-09' then
    raise exception 'dates %', (select jsonb_agg(d) from public.event_dates d);
  end if;
  v_feed := better_supabase.list_calendar_events(array[v_private], '2026-03-01T00:00:00Z', '2026-04-01T00:00:00Z');
  if v_feed -> 0 ->> 'rrule' <> 'FREQ=WEEKLY;COUNT=4;BYDAY=MO'
    or (v_feed -> 0 -> 'exdates' ->> 0)::timestamptz <> '2026-03-09T09:00:00Z'
    or (v_feed -> 0 -> 'rdates' ->> 0)::timestamptz <> '2026-03-05T09:00:00Z'
    or v_feed -> 0 ->> 'visibility' <> 'public' then
    raise exception 'listed %', v_feed;
  end if;
  perform better_supabase.cancel_calendar_occurrence(v_series, '2026-03-16T09:00:00Z');
  if (select count(*) from public.event_dates where event_id = v_series and kind = 'skip') <> 2 then
    raise exception 'cancel %', (select jsonb_agg(d) from public.event_dates d);
  end if;

  v_saved := better_supabase.set_calendar_attendee(v_series, '{"subjectType": "contact", "subjectId": "c-1", "optional": true}');
  v_attendee := (v_saved ->> 'id')::uuid;
  if not (v_saved ->> 'created')::boolean
    or (better_supabase.set_calendar_attendee(v_series, '{"subjectType": "contact", "subjectId": "c-1", "name": "Ada"}') ->> 'created')::boolean then
    raise exception 'subject attendee %', (select jsonb_agg(a) from public.attendees a);
  end if;
  if (select display_name || '/' || is_optional::text || '/' || coalesce(email, '-') from public.attendees where id = v_attendee) <> 'Ada/true/-' then
    raise exception 'attendee row %', (select to_jsonb(a) from public.attendees a where id = v_attendee);
  end if;
  perform better_supabase.set_calendar_attendee(v_series, '{"userId": "${BOB}", "organizer": true}');
  v_feed := better_supabase.list_calendar_events(array[v_private], '2026-03-01T00:00:00Z', '2026-04-01T00:00:00Z');
  if jsonb_array_length(v_feed -> 0 -> 'attendees') <> 2
    or not exists (select 1 from jsonb_array_elements(v_feed -> 0 -> 'attendees') x where x ->> 'role' = 'chair' and x ->> 'userId' = '${BOB}') then
    raise exception 'attendees %', v_feed -> 0 -> 'attendees';
  end if;
  if not better_supabase.remove_calendar_attendee(v_attendee) then
    raise exception 'remove by id';
  end if;

  ${as(BOB)}
  if better_supabase.calendar_access(v_private, '${BOB}', 'read') then
    raise exception 'bob reads alice''s private calendar';
  end if;
  v_secret := (better_supabase.save_calendar_event(v_team, '{"title": "Interview", "visibility": "private", "startsAt": "2026-03-03T09:00:00Z", "endsAt": "2026-03-03T10:00:00Z"}') ->> 'id')::uuid;
  if (select visibility::text || '/' || owner_user_id::text from public.events where id = v_secret) <> 'secret/${BOB}' then
    raise exception 'secret %', (select to_jsonb(e) from public.events e where id = v_secret);
  end if;
  execute 'set local role authenticated';
  if (select count(*) from public.events where calendar_id = v_private) <> 0
    or (select count(*) from public.calendars) <> 1
    or (select count(*) from public.event_rules) <> 0
    or (select count(*) from public.events where id = v_secret) <> 1 then
    raise exception 'bob reads % events, % calendars', (select count(*) from public.events), (select count(*) from public.calendars);
  end if;
  execute 'reset role';
  v_feed := better_supabase.calendar_free_busy('${TENANT}', array['${ALICE}'::uuid], '2026-03-01T00:00:00Z', '2026-03-08T00:00:00Z');
  if jsonb_array_length(v_feed -> 0 -> 'busy') <> 2 or v_feed::text like '%Therapy%' then
    raise exception 'free/busy %', v_feed;
  end if;

  ${as(ALICE)}
  execute 'set local role authenticated';
  if (select count(*) from public.events where id = v_secret) <> 0 or (select count(*) from public.events) <> 1 then
    raise exception 'alice reads bob''s private event';
  end if;
  execute 'reset role';
  if better_supabase.calendar_event_access(v_secret, '${ALICE}', 'read') then
    raise exception 'alice sees bob''s private event';
  end if;
  begin
    perform better_supabase.delete_calendar_event(v_secret);
    raise exception 'alice deleted bob''s private event';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint <> 'CALENDAR_FORBIDDEN' then raise; end if;
  end;
  v_token := better_supabase.create_share_link('${TENANT}', 'calendar_user', '${ALICE}', 'view') ->> 'token';

  ${ANON}
  v_feed := better_supabase.calendar_user_feed(v_token);
  if jsonb_array_length(v_feed -> 'calendars') <> 2 or v_feed::text like '%Interview%' or v_feed::text not like '%Therapy%' then
    raise exception 'user feed %', v_feed;
  end if;

  ${as(BOB)}
  begin
    perform better_supabase.create_share_link('${TENANT}', 'calendar_user', '${ALICE}', 'view');
    raise exception 'bob shared alice''s feed';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint <> 'SHARE_SUBJECT_NOT_FOUND' then raise; end if;
  end;
  begin
    perform better_supabase.create_share_link('${TENANT}', 'calendar', v_private::text, 'view');
    raise exception 'bob shared alice''s private calendar';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint <> 'SHARE_SUBJECT_NOT_FOUND' then raise; end if;
  end;
  v_token := better_supabase.create_share_link('${TENANT}', 'calendar', v_team::text, 'view') ->> 'token';

  ${as(OWNER)}
  v_token := better_supabase.create_share_link('${TENANT}', 'calendar', v_team::text, 'view') ->> 'token';
  ${ANON}
  v_feed := better_supabase.calendar_feed(v_token);
  if v_feed::text like '%Interview%' then
    raise exception 'team feed leaks a private event %', v_feed;
  end if;

  ${as(ALICE)}
  perform better_supabase.set_calendar_grant(v_private, '${BOB}', 'editor');
  perform better_supabase.update_calendar(v_private, '{"name": "Alice (personal)", "isDefault": true, "rank": "1"}');
  if (select name || '/' || position from public.calendars where id = v_private) <> 'Alice (personal)/1' then
    raise exception 'update %', (select to_jsonb(c) from public.calendars c where id = v_private);
  end if;

  ${as(BOB)}
  if not better_supabase.calendar_access(v_private, '${BOB}', 'private') then
    raise exception 'an editor grant does not see private events';
  end if;
  perform better_supabase.save_calendar_event(v_private, '{"title": "Booked by Bob", "startsAt": "2026-03-04T09:00:00Z", "endsAt": "2026-03-04T10:00:00Z"}');
  begin
    perform better_supabase.update_calendar(v_private, '{"name": "Bob was here"}');
    raise exception 'an editor managed the calendar';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint <> 'CALENDAR_FORBIDDEN' then raise; end if;
  end;

  ${as(ALICE)}
  perform better_supabase.split_calendar_event(v_series, '2026-03-23T09:00:00Z', 'FREQ=WEEKLY;BYDAY=MO;UNTIL=20260323T085959Z', '{"title": "Therapy (new)", "startsAt": "2026-03-23T09:00:00Z", "endsAt": "2026-03-23T10:00:00Z", "rrule": "FREQ=WEEKLY;BYDAY=MO;COUNT=1"}');
  if (select to_char(ends_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS') from public.event_rules where event_id = v_series) <> '2026-03-23 08:59:59' then
    raise exception 'split rule %', (select jsonb_agg(r) from public.event_rules r);
  end if;
end;
$$;`;

describe("calendar over an app's tables with per-calendar access", () => {
  it(
    "keeps private calendars and events private and stores recurrence in tables",
    { timeout: 60_000 },
    async () => {
      const files = renderBlocks(["calendar", "share-links"], {
        modules: { calendar: CALENDAR },
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
          KEYS,
          CHECK,
        ],
      });

      expect(stack.url).not.toBe("");
    },
  );

  it(
    "runs on the block's own tables with inline rdates and attendees without email",
    { timeout: 60_000 },
    async () => {
      const files = renderBlocks(["calendar", "share-links"], {
        modules: {
          calendar: {
            options: {
              access: true,
              rdates: true,
              attendeeKey: "any",
              calendarDetails: true,
            },
          },
        },
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
          KEYS,
          MANAGED_CHECK,
        ],
      });

      expect(stack.url).not.toBe("");
    },
  );

  it(
    "stores structured rules keyed by event in the app's rule dialect",
    { timeout: 60_000 },
    async () => {
      const app = APP.replace(
        `create table public.event_rules (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events (id) on delete cascade,
  frequency public.repeat_freq not null,
  every integer,
  occurrences integer,
  ends_at timestamptz,
  weekdays text[],
  month_days integer[]
);`,
        `create table public.event_rules (
  event_id uuid primary key references public.events (id) on delete cascade,
  frequency public.repeat_freq not null,
  every integer,
  occurrences integer,
  ends_at timestamptz,
  weekdays text[],
  month_day integer,
  month_weekday text,
  month_ordinal integer
);`,
      );

      const files = renderBlocks(["calendar", "share-links"], {
        modules: {
          calendar: {
            ...CALENDAR,
            columns: {
              ...CALENDAR.columns,
              rules: {
                ...CALENDAR.columns?.["rules"],
                id: null,
                byMonthDay: "month_day",
              },
            },
            options: {
              ...CALENDAR.options,
              ruleDialect: {
                weekdays: "lower",
                monthDay: "scalar",
                ordinal: {
                  weekday: "month_weekday",
                  position: "month_ordinal",
                },
              },
            },
          },
        },
        ownTables: OWN_TABLES,
      });

      await using stack = await liteStack({
        driver: "pglite",
        migrations: [
          ROLES,
          app,
          ...files
            .filter((file) => file.kind !== "data")
            .map((file) => file.contents),
        ],
        seed: [
          ...files
            .filter((file) => file.kind === "data")
            .map((file) => file.contents),
          KEYS,
          `do $$
declare
  v_calendar uuid;
  v_weekly uuid;
  v_ordinal uuid;
  v_day uuid;
  v_feed jsonb;
begin
  ${as(ALICE)}
  v_calendar := (better_supabase.create_calendar('${TENANT}', 'Alice', 'UTC', null, '${ALICE}', null) ->> 'id')::uuid;
  v_weekly := (better_supabase.save_calendar_event(v_calendar, '{"title": "Gym", "startsAt": "2026-03-02T07:00:00Z", "endsAt": "2026-03-02T08:00:00Z", "rrule": "FREQ=WEEKLY;BYDAY=MO,WE"}') ->> 'id')::uuid;
  v_ordinal := (better_supabase.save_calendar_event(v_calendar, '{"title": "Board", "startsAt": "2026-03-10T09:00:00Z", "endsAt": "2026-03-10T10:00:00Z", "rrule": "FREQ=MONTHLY;BYDAY=2TU"}') ->> 'id')::uuid;
  v_day := (better_supabase.save_calendar_event(v_calendar, '{"title": "Rent", "startsAt": "2026-03-15T09:00:00Z", "endsAt": "2026-03-15T10:00:00Z", "rrule": "FREQ=MONTHLY;BYMONTHDAY=15"}') ->> 'id')::uuid;
  if (select weekdays::text from public.event_rules where event_id = v_weekly) <> '{mo,we}'
    or (select month_ordinal || month_weekday from public.event_rules where event_id = v_ordinal) <> '2tu'
    or (select weekdays from public.event_rules where event_id = v_ordinal) is not null
    or (select month_day from public.event_rules where event_id = v_day) <> 15 then
    raise exception 'rules %', (select jsonb_agg(r) from public.event_rules r);
  end if;
  v_feed := better_supabase.list_calendar_events(array[v_calendar], '2026-03-01T00:00:00Z', '2026-03-31T00:00:00Z');
  if (select string_agg(e ->> 'rrule', ' | ' order by e ->> 'title') from jsonb_array_elements(v_feed) e)
    <> 'FREQ=MONTHLY;BYDAY=2TU | FREQ=WEEKLY;BYDAY=MO,WE | FREQ=MONTHLY;BYMONTHDAY=15' then
    raise exception 'listed %', v_feed;
  end if;
end;
$$;`,
        ],
      });

      expect(stack.url).not.toBe("");
    },
  );

  it("refuses a rule dialect over a raw rule column", () => {
    expect(() =>
      renderBlocks(["calendar"], {
        modules: {
          calendar: {
            ...CALENDAR,
            columns: {
              ...CALENDAR.columns,
              rules: { tenant: null, rrule: "rrule" },
            },
            options: {
              ...CALENDAR.options,
              ruleDialect: { weekdays: "lower" },
            },
          },
        },
        ownTables: OWN_TABLES,
      }),
    ).toThrow(/ruleDialect/);
  });

  it("hides another member's private rows from direct reads", () => {
    const sql = renderBlocks(["calendar"], {
      modules: { calendar: CALENDAR },
      ownTables: OWN_TABLES,
    })
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain(
      `create policy bsb_calendars_select on "public"."calendars"\n  for select to authenticated\n  using ("better_supabase"."calendar_access"("id", (select auth.uid()), 'read'));`,
    );
    expect(sql).toContain(
      `using ("better_supabase"."calendar_event_access"("id", (select auth.uid()), 'read'));`,
    );
  });
});
