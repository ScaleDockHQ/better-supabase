-- ==== schema supabase/schemas/900_better_supabase_131_timeline.sql
-- better-supabase module: timeline
-- @bsb-block timeline@1 managed
-- @bsb-hash sha256:1412ae213d2df1913b6387372bc064b16835b80442ab87a5a9ed34f59a294be5
-- An activity_entries feed that activitySink() fills from outbox events, filtered by can_subject and joined with the subject's audit entries, notification deliveries and workflow runs when subjects, audit, notifications and workflows are installed.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- The activity feed: one row per outbox event, written by activitySink().
create table if not exists "better_supabase"."activity_entries" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid default auth.uid(),
  "event_id" text not null unique,
  "type" text not null,
  "actor_id" uuid references auth.users (id) on delete set null,
  "subject_type" text,
  "subject_id" text,
  "summary" text,
  "data" jsonb not null default '{}'::jsonb,
  "occurred_at" timestamptz not null default now()
);
create index if not exists activity_entries_feed_idx on "better_supabase"."activity_entries" ("organization_id", "occurred_at" desc, "id" desc);
create index if not exists activity_entries_subject_idx on "better_supabase"."activity_entries" ("organization_id", "subject_type", "subject_id");
create index if not exists activity_entries_actor_idx on "better_supabase"."activity_entries" ("actor_id");
alter table "better_supabase"."activity_entries" enable row level security;
revoke all on "better_supabase"."activity_entries" from public, anon, authenticated;
grant select on "better_supabase"."activity_entries" to authenticated;
grant all on "better_supabase"."activity_entries" to service_role;
drop policy if exists activity_entries_read on "better_supabase"."activity_entries";
create policy activity_entries_read on "better_supabase"."activity_entries"
  for select to authenticated
  using ("organization_id" = (select auth.uid()));
drop function if exists "better_supabase"."activity_subject_readable"(text, text);
drop function if exists "better_supabase"."activity_subject_deliveries"(uuid, text, text, timestamptz, integer);

-- Inserts batch.entries ({ event_id, organization_id, type, actor_id?,
-- subject_type?, subject_id?, summary?, data?, occurred_at? }); a seen
-- event_id is skipped, so a replayed batch writes nothing twice. The list
-- sits in an object so it reaches jsonb the same way over Postgres and the
-- Data API.
create or replace function "better_supabase"."record_activity"(batch jsonb)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  inserted integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role records activity' using errcode = '42501', hint = 'TIMELINE_ENTRY_FORBIDDEN';
  end if;
  insert into "better_supabase"."activity_entries" ("event_id", "organization_id", "type", "actor_id", "subject_type", "subject_id", "summary", "data", "occurred_at")
  select e ->> 'event_id', (e ->> 'organization_id')::uuid, e ->> 'type', nullif(e ->> 'actor_id', '')::uuid,
    e ->> 'subject_type', e ->> 'subject_id', e ->> 'summary', coalesce(e -> 'data', '{}'::jsonb),
    coalesce((e ->> 'occurred_at')::timestamptz, now())
  from jsonb_array_elements(coalesce(batch -> 'entries', '[]'::jsonb)) e
  on conflict ("event_id") do nothing;
  get diagnostics inserted = row_count;
  return inserted;
end;
$$;

-- A tenant's activity, newest first, or one subject's timeline with
-- subject_type and subject_id; before pages back, and sources (null for
-- all) picks the kinds of entry. Runs as the caller, and each entry carries
-- source: event for an activity entry.
create or replace function "better_supabase"."list_activity"(
  tenant uuid,
  subject_type text default null,
  subject_id text default null,
  before timestamptz default null,
  max_rows integer default 50,
  sources text[] default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_limit integer := least(greatest(coalesce(list_activity.max_rows, 50), 1), 500);
  v_rows jsonb;
begin
  select coalesce(jsonb_agg(x.entry order by x.at desc, x.id desc), '[]'::jsonb)
  into v_rows
  from (
    select u.entry, u.at, u.id from (
    (select to_jsonb(y.*) || jsonb_build_object('source', 'event') as entry,
      y."occurred_at" as at, y."id"::text as id
    from "better_supabase"."activity_entries" y
    where y."organization_id" = coalesce(list_activity.tenant, (select auth.uid()))
      and (list_activity.sources is null or 'event' = any (list_activity.sources))
      and (list_activity.subject_type is null or y."subject_type" = list_activity.subject_type)
      and (list_activity.subject_id is null or y."subject_id" = list_activity.subject_id)
      and (list_activity.before is null or y."occurred_at" < list_activity.before)
    order by y."occurred_at" desc, y."id" desc
    limit v_limit)
    ) u
    order by u.at desc, u.id desc
    limit v_limit
  ) x;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_activity"(uuid, text, text, timestamptz, integer, text[]) from public, anon;
revoke execute on function "better_supabase"."record_activity"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."list_activity"(uuid, text, text, timestamptz, integer, text[]) to authenticated, service_role;
grant execute on function "better_supabase"."record_activity"(jsonb) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== data supabase/better-supabase-data/900_better_supabase_131_timeline.sql
-- better-supabase module: timeline
-- @bsb-block-data timeline
-- @bsb-hash sha256:bb23b7cd67670a73cbec8ff09f4097d1e4368fe94954344993bab88288bc8070
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('timeline', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
