-- ==== alone: schema supabase/schemas/900_better_supabase_23_outbox.sql
-- better-supabase module: outbox
-- @bs-module outbox@3 managed
-- Events written in the same transaction as the change, read by named consumers with their own cursor and lease, kept for history and relayed as CloudEvents.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."outbox_events" (
  "id" uuid primary key default gen_random_uuid(),
  "position" bigint generated always as identity unique,
  "type" text not null,
  "source" text,
  "subject" text,
  "organization_id" uuid,
  "key" text,
  "payload" jsonb not null default '{}',
  "actor_id" uuid,
  "created_at" timestamptz not null default now(),
  "xid" xid8 not null default pg_current_xact_id()
);
create unique index if not exists outbox_events_key_idx on "better_supabase"."outbox_events" ("key", "organization_id") nulls not distinct where "key" is not null;
create index if not exists outbox_events_subject_idx on "better_supabase"."outbox_events" ("subject", "position");
create index if not exists outbox_events_type_idx on "better_supabase"."outbox_events" ("type", "position");
create index if not exists outbox_events_created_idx on "better_supabase"."outbox_events" ("created_at");
create index if not exists outbox_events_xid_idx on "better_supabase"."outbox_events" ("xid", "position");
alter table "better_supabase"."outbox_events" enable row level security;
revoke all on "better_supabase"."outbox_events" from anon, authenticated;
grant all on "better_supabase"."outbox_events" to service_role;

create table if not exists "better_supabase"."outbox_consumers" (
  "name" text primary key,
  -- The last event passed, ordered by (transaction id, position). Without
  -- the xid column, cursor_xid stays 0 and the position alone orders.
  "cursor_xid" xid8 not null default '0',
  "cursor_position" bigint not null default 0,
  -- Type patterns ('organization.*', 'invoice.paid'); null takes every event.
  "types" text[],
  "lease_owner" text,
  "lease_until" timestamptz,
  -- Failed claims in a row since the cursor last moved, and when to try again.
  "attempts" integer not null default 0,
  "last_error" text,
  "retry_at" timestamptz,
  "updated_at" timestamptz not null default now()
);
alter table "better_supabase"."outbox_consumers" add column if not exists "attempts" integer not null default 0;
alter table "better_supabase"."outbox_consumers" add column if not exists "last_error" text;
alter table "better_supabase"."outbox_consumers" add column if not exists "retry_at" timestamptz;
alter table "better_supabase"."outbox_consumers" enable row level security;
revoke all on "better_supabase"."outbox_consumers" from anon, authenticated;
grant all on "better_supabase"."outbox_consumers" to service_role;

-- Events a consumer skipped after max_attempts failures, with a copy of the
-- event, so one bad event can't stop the consumer.
create table if not exists "better_supabase"."outbox_dead_letters" (
  "consumer" text not null references "better_supabase"."outbox_consumers" ("name") on delete cascade,
  "position" bigint not null,
  "event_id" text not null,
  "type" text not null,
  "event" jsonb not null,
  "attempts" integer not null,
  "error" text,
  "dead_at" timestamptz not null default now(),
  primary key ("consumer", "position")
);
create index if not exists outbox_dead_letters_dead_at_idx on "better_supabase"."outbox_dead_letters" ("dead_at");
alter table "better_supabase"."outbox_dead_letters" enable row level security;
revoke all on "better_supabase"."outbox_dead_letters" from anon, authenticated;
grant all on "better_supabase"."outbox_dead_letters" to service_role;


-- create or replace can't change the return type of an earlier install.
drop function if exists "better_supabase"."emit_event"(text, jsonb, text, text, text, text);
-- Appends an event in the caller's transaction, so it exists only if the
-- transaction commits, and returns its id. A repeated key (per tenant)
-- returns the first event's id.
create or replace function "better_supabase"."emit_event"(
  event_type text,
  payload jsonb default '{}',
  subject text default null,
  tenant text default null,
  key text default null,
  source text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  found_id text;
begin
  if event_type is null or btrim(event_type) = '' then
    raise exception 'An event needs a type' using errcode = '22023', hint = 'OUTBOX_TYPE_REQUIRED';
  end if;
  if key is not null then
    select e."id"::text into found_id from "better_supabase"."outbox_events" e
    where e."key" = key and e."organization_id" is not distinct from tenant::uuid;
    if found_id is not null then
      return found_id;
    end if;
  end if;
  insert into "better_supabase"."outbox_events" ("type", "payload", "source", "subject", "organization_id", "key", "actor_id")
  values (event_type, coalesce(payload, '{}'), source, coalesce(subject, payload ->> 'subject'), tenant::uuid, key, auth.uid())
  on conflict do nothing
  returning "id"::text into found_id;
  if found_id is null then
    -- Another transaction emitted the same key first.
    select e."id"::text into found_id from "better_supabase"."outbox_events" e
    where e."key" = key and e."organization_id" is not distinct from tenant::uuid;
  end if;
  return found_id;
end;
$$;
revoke execute on function "better_supabase"."emit_event"(text, jsonb, text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."emit_event"(text, jsonb, text, text, text, text) to service_role;

drop function if exists "better_supabase"."purge_outbox"(interval);
-- The signature before purge_outbox could pass over idle consumers.
drop function if exists "better_supabase"."purge_outbox"(interval, integer);

-- Registers a consumer. A new one starts after the latest event, or at the
-- first with from_start. Registering again changes only its types.
create or replace function "better_supabase"."outbox_register"(consumer text, types text[] default null, from_start boolean default false)
returns bigint
language sql
security definer
set search_path = ''
as $$
  insert into "better_supabase"."outbox_consumers" ("name", "cursor_xid", "cursor_position", "types")
  select consumer, coalesce(latest.xid, '0'), coalesce(latest.position, 0), types
  from (select 1) one
  left join lateral (
    select e."xid" as xid, e."position" as position from "better_supabase"."outbox_events" e
    where not from_start
    order by e."xid" desc, e."position" desc
    limit 1
  ) latest on true
  on conflict ("name") do update set "types" = excluded."types", "updated_at" = now()
  returning "cursor_position"
$$;

-- Deletes a consumer and its cursor, so purge_outbox no longer waits for it.
create or replace function "better_supabase"."outbox_unregister"(consumer text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  delete from "better_supabase"."outbox_consumers" k where k."name" = consumer;
  return found;
end;
$$;

-- Leases the consumer to owner and returns its next events after the
-- cursor. Events of transactions still running are held back, and
-- events sort by (xid, position), so a transaction that commits late sorts
-- after the cursor and is never skipped. When no event matches the consumer's types,
-- the cursor moves past the settled events it scanned. After a failure
-- (outbox_fail) the consumer waits until retry_at, then claims one event at
-- a time, so the next failure belongs to that event.
create or replace function "better_supabase"."outbox_claim"(consumer text, owner text, max_events integer default 100, lease interval default '1 minute')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  c "better_supabase"."outbox_consumers";
  events jsonb;
begin
  update "better_supabase"."outbox_consumers" k
  set "lease_owner" = owner, "lease_until" = now() + lease, "updated_at" = now()
  where k."name" = consumer
    and (k."lease_until" is null or k."lease_until" < now() or k."lease_owner" = owner)
    and (k."retry_at" is null or k."retry_at" <= now())
  returning k.* into c;
  if not found then
    if not exists (select 1 from "better_supabase"."outbox_consumers" k where k."name" = consumer) then
      raise exception 'Unknown outbox consumer %', consumer using errcode = 'P0002', hint = 'OUTBOX_UNKNOWN_CONSUMER';
    end if;
    return '[]';
  end if;
  select jsonb_agg(x.event order by x.n) into events
  from (
    select jsonb_build_object(
    'position', e."position",
    'id', e."id",
    'type', e."type",
    'payload', e."payload",
    'created_at', e."created_at",
    'source', e."source",
    'subject', e."subject",
    'tenant', e."organization_id",
    'key', e."key",
    'actor_id', e."actor_id"
  ) as event, row_number() over (order by e."xid", e."position") as n
    from "better_supabase"."outbox_events" e
    where (e."xid", e."position") > (c."cursor_xid", c."cursor_position")
      and e."xid" < pg_snapshot_xmin(pg_current_snapshot())
      and (c."types" is null or exists (
        select 1 from unnest(c."types") p
        where p = '*' or p = e."type"
          or (right(p, 2) = '.*' and starts_with(e."type", left(p, -1)))
      ))
    order by e."xid", e."position"
    limit case when c."attempts" > 0 then 1 else max_events end
  ) x;
  if events is null then
    update "better_supabase"."outbox_consumers" k
    set ("cursor_xid", "cursor_position") = (
      select e."xid", e."position" from "better_supabase"."outbox_events" e
      where (e."xid", e."position") > (c."cursor_xid", c."cursor_position") and e."xid" < pg_snapshot_xmin(pg_current_snapshot())
      order by e."xid" desc, e."position" desc
      limit 1
    )
    where k."name" = consumer
      and exists (select 1 from "better_supabase"."outbox_events" e where (e."xid", e."position") > (c."cursor_xid", c."cursor_position") and e."xid" < pg_snapshot_xmin(pg_current_snapshot()));
  end if;
  return coalesce(events, '[]');
end;
$$;

-- Moves the cursor to the event at position upto (when given), clears the
-- failure count and releases the lease. False when owner no longer holds it.
create or replace function "better_supabase"."outbox_ack"(consumer text, owner text, upto bigint default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  update "better_supabase"."outbox_consumers" k
  set ("cursor_xid", "cursor_position") = (
      select e."xid", e."position" from "better_supabase"."outbox_events" e where e."position" = upto
    ),
    "attempts" = 0, "last_error" = null, "retry_at" = null,
    "lease_owner" = null, "lease_until" = null, "updated_at" = now()
  where k."name" = consumer and k."lease_owner" = owner
    and upto is not null
    and exists (select 1 from "better_supabase"."outbox_events" e where e."position" = upto and (e."xid", e."position") > (k."cursor_xid", k."cursor_position"));
  if found then
    return true;
  end if;
  update "better_supabase"."outbox_consumers" k
  set "lease_owner" = null, "lease_until" = null, "updated_at" = now()
  where k."name" = consumer and k."lease_owner" = owner;
  return found;
end;
$$;

-- Records a failed claim and releases the lease. The consumer waits
-- 2^attempts seconds (at most max_backoff) before its next claim. When the
-- claim held the one event at position failed and the consumer has failed
-- max_attempts times, the event goes to the dead letters and the cursor
-- moves past it. Returns 'retrying', 'dead', or null when owner no longer
-- holds the lease.
create or replace function "better_supabase"."outbox_fail"(
  consumer text,
  owner text,
  failed bigint default null,
  error text default null,
  max_attempts integer default 10,
  max_backoff interval default '10 minutes'
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  c "better_supabase"."outbox_consumers";
begin
  update "better_supabase"."outbox_consumers" k
  set "attempts" = k."attempts" + 1, "last_error" = left(error, 4000),
    "lease_owner" = null, "lease_until" = null, "updated_at" = now()
  where k."name" = consumer and k."lease_owner" = owner
  returning k.* into c;
  if not found then
    return null;
  end if;
  if failed is not null and c."attempts" >= greatest(coalesce(max_attempts, 10), 1) then
    insert into "better_supabase"."outbox_dead_letters" ("consumer", "position", "event_id", "type", "event", "attempts", "error")
    select consumer, e."position", e."id"::text, e."type", jsonb_build_object(
    'position', e."position",
    'id', e."id",
    'type', e."type",
    'payload', e."payload",
    'created_at', e."created_at",
    'source', e."source",
    'subject', e."subject",
    'tenant', e."organization_id",
    'key', e."key",
    'actor_id', e."actor_id"
  ), c."attempts", c."last_error"
    from "better_supabase"."outbox_events" e
    where e."position" = failed and (e."xid", e."position") > (c."cursor_xid", c."cursor_position")
    on conflict do nothing;
    update "better_supabase"."outbox_consumers" k
    set ("cursor_xid", "cursor_position") = (
        select e."xid", e."position" from "better_supabase"."outbox_events" e where e."position" = failed
      ),
      "attempts" = 0, "retry_at" = null
    where k."name" = consumer
      and exists (select 1 from "better_supabase"."outbox_events" e where e."position" = failed and (e."xid", e."position") > (k."cursor_xid", k."cursor_position"));
    if found then
      return 'dead';
    end if;
  end if;
  update "better_supabase"."outbox_consumers" k
  set "retry_at" = now() + least(
    coalesce(max_backoff, '10 minutes'),
    interval '1 second' * power(2, least(c."attempts", 20))
  )
  where k."name" = consumer;
  return 'retrying';
end;
$$;

-- A consumer's dead letters, newest first.
create or replace function "better_supabase"."outbox_dead_letters"(consumer text, max_rows integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'consumer', x."consumer",
    'position', x."position",
    'event', x."event",
    'attempts', x."attempts",
    'error', x."error",
    'dead_at', x."dead_at"
  ) order by x."dead_at" desc, x."position" desc), '[]')
  from (
    select * from "better_supabase"."outbox_dead_letters" d
    where d."consumer" = outbox_dead_letters.consumer
    order by d."dead_at" desc, d."position" desc
    limit least(greatest(coalesce(max_rows, 100), 1), 1000)
  ) x
$$;

-- Kept events, by subject and type, oldest first.
create or replace function "better_supabase"."outbox_history"(subject text default null, event_type text default null, after bigint default 0, max_events integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.event order by x.position), '[]')
  from (
    select jsonb_build_object(
    'position', e."position",
    'id', e."id",
    'type', e."type",
    'payload', e."payload",
    'created_at', e."created_at",
    'source', e."source",
    'subject', e."subject",
    'tenant', e."organization_id",
    'key', e."key",
    'actor_id', e."actor_id"
  ) as event, e."position" as position
    from "better_supabase"."outbox_events" e
    where e."position" > "outbox_history".after
      and ("outbox_history".subject is null or e."subject" = "outbox_history".subject)
      and ("outbox_history".event_type is null or e."type" = "outbox_history".event_type)
    order by e."position"
    limit "outbox_history".max_events
  ) x
$$;

-- Deletes up to batch events older than older_than that every consumer has
-- passed, and returns how many, along with dead letters older than
-- older_than. With ignore_idle, a consumer that hasn't claimed for that long
-- no longer holds events back. Run it until it returns less than batch.
-- A null older_than or batch takes its default.
create or replace function "better_supabase"."purge_outbox"(older_than interval default '30 days', batch integer default 10000, ignore_idle interval default null)
returns integer
language sql
security definer
set search_path = ''
as $$
  with active as (
    select k."cursor_xid", k."cursor_position" from "better_supabase"."outbox_consumers" k
    where ignore_idle is null or k."updated_at" >= now() - ignore_idle
  ),
  letters as (
    delete from "better_supabase"."outbox_dead_letters" x
    where x."dead_at" < now() - coalesce(older_than, '30 days'::interval)
  ),
  gone as (
    delete from "better_supabase"."outbox_events" e
    where e."id" in (
      select d."id" from "better_supabase"."outbox_events" d
      where d."created_at" < now() - coalesce(older_than, '30 days'::interval)
        and (
          not exists (select 1 from active)
          or (d."xid", d."position") <= (
            select a."cursor_xid", a."cursor_position" from active a
            order by a."cursor_xid", a."cursor_position"
            limit 1
          )
        )
      order by d."created_at"
      limit coalesce(batch, 10000)
    )
    returning 1
  )
  select count(*)::integer from gone
$$;
revoke execute on function "better_supabase"."outbox_register"(text, text[], boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."outbox_register"(text, text[], boolean) to service_role;
revoke execute on function "better_supabase"."outbox_unregister"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."outbox_unregister"(text) to service_role;
revoke execute on function "better_supabase"."outbox_claim"(text, text, integer, interval) from public, anon, authenticated;
grant execute on function "better_supabase"."outbox_claim"(text, text, integer, interval) to service_role;
revoke execute on function "better_supabase"."outbox_ack"(text, text, bigint) from public, anon, authenticated;
grant execute on function "better_supabase"."outbox_ack"(text, text, bigint) to service_role;
revoke execute on function "better_supabase"."outbox_fail"(text, text, bigint, text, integer, interval) from public, anon, authenticated;
grant execute on function "better_supabase"."outbox_fail"(text, text, bigint, text, integer, interval) to service_role;
revoke execute on function "better_supabase"."outbox_dead_letters"(text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."outbox_dead_letters"(text, integer) to service_role;
revoke execute on function "better_supabase"."outbox_history"(text, text, bigint, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."outbox_history"(text, text, bigint, integer) to service_role;
revoke execute on function "better_supabase"."purge_outbox"(interval, integer, interval) from public, anon, authenticated;
grant execute on function "better_supabase"."purge_outbox"(interval, integer, interval) to service_role;

-- A row trigger that emits <prefix>.created, .updated and .deleted with the
-- row as payload. prefix defaults to the table name.
create or replace function "better_supabase"."outbox_row_event"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_data jsonb := to_jsonb(case when tg_op = 'DELETE' then old else new end);
  prefix text := coalesce(nullif(tg_argv[0], ''), tg_table_name);
  tenant_column text := nullif(tg_argv[1], '');
begin
  perform "better_supabase"."emit_event"(
    prefix || '.' || case tg_op when 'INSERT' then 'created' when 'UPDATE' then 'updated' else 'deleted' end,
    jsonb_build_object('table', tg_table_schema || '.' || tg_table_name, 'row', row_data),
    tg_table_name || '/' || coalesce(row_data ->> 'id', ''),
    case when tenant_column is null then null else row_data ->> tenant_column end,
    null,
    'better-supabase/track_events'
  );
  return null;
end;
$$;

create or replace function "better_supabase"."track_events"(target regclass, type_prefix text default null, tenant_column text default null)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists "bs_outbox_events" on %s', target);
  execute format('drop trigger if exists "bs_outbox_events_update" on %s', target);
  execute format(
    'create trigger "bs_outbox_events" after insert or delete on %s for each row execute function "better_supabase"."outbox_row_event"(%L, %L)',
    target, coalesce(type_prefix, ''), coalesce(tenant_column, '')
  );
  -- jsonb, not the row: a row comparison fails on columns without equality (json).
  execute format(
    'create trigger "bs_outbox_events_update" after update on %s for each row when (to_jsonb(old) is distinct from to_jsonb(new)) execute function "better_supabase"."outbox_row_event"(%L, %L)',
    target, coalesce(type_prefix, ''), coalesce(tenant_column, '')
  );
end;
$$;
revoke execute on function "better_supabase"."track_events"(regclass, text, text) from public, anon, authenticated;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_23_outbox.sql
-- better-supabase module: outbox
-- @bs-module-data outbox
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('outbox', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_23_outbox.sql
-- better-supabase module: outbox
-- @bs-module outbox@3 managed
-- Events written in the same transaction as the change, read by named consumers with their own cursor and lease, kept for history and relayed as CloudEvents.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."outbox_events" (
  "id" uuid primary key default gen_random_uuid(),
  "position" bigint generated always as identity unique,
  "type" text not null,
  "source" text,
  "subject" text,
  "organization_id" uuid,
  "key" text,
  "payload" jsonb not null default '{}',
  "actor_id" uuid,
  "created_at" timestamptz not null default now(),
  "xid" xid8 not null default pg_current_xact_id()
);
create unique index if not exists outbox_events_key_idx on "better_supabase"."outbox_events" ("key", "organization_id") nulls not distinct where "key" is not null;
create index if not exists outbox_events_subject_idx on "better_supabase"."outbox_events" ("subject", "position");
create index if not exists outbox_events_type_idx on "better_supabase"."outbox_events" ("type", "position");
create index if not exists outbox_events_created_idx on "better_supabase"."outbox_events" ("created_at");
create index if not exists outbox_events_xid_idx on "better_supabase"."outbox_events" ("xid", "position");
alter table "better_supabase"."outbox_events" enable row level security;
revoke all on "better_supabase"."outbox_events" from anon, authenticated;
grant all on "better_supabase"."outbox_events" to service_role;

create table if not exists "better_supabase"."outbox_consumers" (
  "name" text primary key,
  -- The last event passed, ordered by (transaction id, position). Without
  -- the xid column, cursor_xid stays 0 and the position alone orders.
  "cursor_xid" xid8 not null default '0',
  "cursor_position" bigint not null default 0,
  -- Type patterns ('organization.*', 'invoice.paid'); null takes every event.
  "types" text[],
  "lease_owner" text,
  "lease_until" timestamptz,
  -- Failed claims in a row since the cursor last moved, and when to try again.
  "attempts" integer not null default 0,
  "last_error" text,
  "retry_at" timestamptz,
  "updated_at" timestamptz not null default now()
);
alter table "better_supabase"."outbox_consumers" add column if not exists "attempts" integer not null default 0;
alter table "better_supabase"."outbox_consumers" add column if not exists "last_error" text;
alter table "better_supabase"."outbox_consumers" add column if not exists "retry_at" timestamptz;
alter table "better_supabase"."outbox_consumers" enable row level security;
revoke all on "better_supabase"."outbox_consumers" from anon, authenticated;
grant all on "better_supabase"."outbox_consumers" to service_role;

-- Events a consumer skipped after max_attempts failures, with a copy of the
-- event, so one bad event can't stop the consumer.
create table if not exists "better_supabase"."outbox_dead_letters" (
  "consumer" text not null references "better_supabase"."outbox_consumers" ("name") on delete cascade,
  "position" bigint not null,
  "event_id" text not null,
  "type" text not null,
  "event" jsonb not null,
  "attempts" integer not null,
  "error" text,
  "dead_at" timestamptz not null default now(),
  primary key ("consumer", "position")
);
create index if not exists outbox_dead_letters_dead_at_idx on "better_supabase"."outbox_dead_letters" ("dead_at");
alter table "better_supabase"."outbox_dead_letters" enable row level security;
revoke all on "better_supabase"."outbox_dead_letters" from anon, authenticated;
grant all on "better_supabase"."outbox_dead_letters" to service_role;


-- create or replace can't change the return type of an earlier install.
drop function if exists "better_supabase"."emit_event"(text, jsonb, text, text, text, text);
-- Appends an event in the caller's transaction, so it exists only if the
-- transaction commits, and returns its id. A repeated key (per tenant)
-- returns the first event's id.
create or replace function "better_supabase"."emit_event"(
  event_type text,
  payload jsonb default '{}',
  subject text default null,
  tenant text default null,
  key text default null,
  source text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  found_id text;
begin
  if event_type is null or btrim(event_type) = '' then
    raise exception 'An event needs a type' using errcode = '22023', hint = 'OUTBOX_TYPE_REQUIRED';
  end if;
  if key is not null then
    select e."id"::text into found_id from "better_supabase"."outbox_events" e
    where e."key" = key and e."organization_id" is not distinct from tenant::uuid;
    if found_id is not null then
      return found_id;
    end if;
  end if;
  insert into "better_supabase"."outbox_events" ("type", "payload", "source", "subject", "organization_id", "key", "actor_id")
  values (event_type, coalesce(payload, '{}'), source, coalesce(subject, payload ->> 'subject'), tenant::uuid, key, auth.uid())
  on conflict do nothing
  returning "id"::text into found_id;
  if found_id is null then
    -- Another transaction emitted the same key first.
    select e."id"::text into found_id from "better_supabase"."outbox_events" e
    where e."key" = key and e."organization_id" is not distinct from tenant::uuid;
  end if;
  return found_id;
end;
$$;
revoke execute on function "better_supabase"."emit_event"(text, jsonb, text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."emit_event"(text, jsonb, text, text, text, text) to service_role;

drop function if exists "better_supabase"."purge_outbox"(interval);
-- The signature before purge_outbox could pass over idle consumers.
drop function if exists "better_supabase"."purge_outbox"(interval, integer);

-- Registers a consumer. A new one starts after the latest event, or at the
-- first with from_start. Registering again changes only its types.
create or replace function "better_supabase"."outbox_register"(consumer text, types text[] default null, from_start boolean default false)
returns bigint
language sql
security definer
set search_path = ''
as $$
  insert into "better_supabase"."outbox_consumers" ("name", "cursor_xid", "cursor_position", "types")
  select consumer, coalesce(latest.xid, '0'), coalesce(latest.position, 0), types
  from (select 1) one
  left join lateral (
    select e."xid" as xid, e."position" as position from "better_supabase"."outbox_events" e
    where not from_start
    order by e."xid" desc, e."position" desc
    limit 1
  ) latest on true
  on conflict ("name") do update set "types" = excluded."types", "updated_at" = now()
  returning "cursor_position"
$$;

-- Deletes a consumer and its cursor, so purge_outbox no longer waits for it.
create or replace function "better_supabase"."outbox_unregister"(consumer text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  delete from "better_supabase"."outbox_consumers" k where k."name" = consumer;
  return found;
end;
$$;

-- Leases the consumer to owner and returns its next events after the
-- cursor. Events of transactions still running are held back, and
-- events sort by (xid, position), so a transaction that commits late sorts
-- after the cursor and is never skipped. When no event matches the consumer's types,
-- the cursor moves past the settled events it scanned. After a failure
-- (outbox_fail) the consumer waits until retry_at, then claims one event at
-- a time, so the next failure belongs to that event.
create or replace function "better_supabase"."outbox_claim"(consumer text, owner text, max_events integer default 100, lease interval default '1 minute')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  c "better_supabase"."outbox_consumers";
  events jsonb;
begin
  update "better_supabase"."outbox_consumers" k
  set "lease_owner" = owner, "lease_until" = now() + lease, "updated_at" = now()
  where k."name" = consumer
    and (k."lease_until" is null or k."lease_until" < now() or k."lease_owner" = owner)
    and (k."retry_at" is null or k."retry_at" <= now())
  returning k.* into c;
  if not found then
    if not exists (select 1 from "better_supabase"."outbox_consumers" k where k."name" = consumer) then
      raise exception 'Unknown outbox consumer %', consumer using errcode = 'P0002', hint = 'OUTBOX_UNKNOWN_CONSUMER';
    end if;
    return '[]';
  end if;
  select jsonb_agg(x.event order by x.n) into events
  from (
    select jsonb_build_object(
    'position', e."position",
    'id', e."id",
    'type', e."type",
    'payload', e."payload",
    'created_at', e."created_at",
    'source', e."source",
    'subject', e."subject",
    'tenant', e."organization_id",
    'key', e."key",
    'actor_id', e."actor_id"
  ) as event, row_number() over (order by e."xid", e."position") as n
    from "better_supabase"."outbox_events" e
    where (e."xid", e."position") > (c."cursor_xid", c."cursor_position")
      and e."xid" < pg_snapshot_xmin(pg_current_snapshot())
      and (c."types" is null or exists (
        select 1 from unnest(c."types") p
        where p = '*' or p = e."type"
          or (right(p, 2) = '.*' and starts_with(e."type", left(p, -1)))
      ))
    order by e."xid", e."position"
    limit case when c."attempts" > 0 then 1 else max_events end
  ) x;
  if events is null then
    update "better_supabase"."outbox_consumers" k
    set ("cursor_xid", "cursor_position") = (
      select e."xid", e."position" from "better_supabase"."outbox_events" e
      where (e."xid", e."position") > (c."cursor_xid", c."cursor_position") and e."xid" < pg_snapshot_xmin(pg_current_snapshot())
      order by e."xid" desc, e."position" desc
      limit 1
    )
    where k."name" = consumer
      and exists (select 1 from "better_supabase"."outbox_events" e where (e."xid", e."position") > (c."cursor_xid", c."cursor_position") and e."xid" < pg_snapshot_xmin(pg_current_snapshot()));
  end if;
  return coalesce(events, '[]');
end;
$$;

-- Moves the cursor to the event at position upto (when given), clears the
-- failure count and releases the lease. False when owner no longer holds it.
create or replace function "better_supabase"."outbox_ack"(consumer text, owner text, upto bigint default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  update "better_supabase"."outbox_consumers" k
  set ("cursor_xid", "cursor_position") = (
      select e."xid", e."position" from "better_supabase"."outbox_events" e where e."position" = upto
    ),
    "attempts" = 0, "last_error" = null, "retry_at" = null,
    "lease_owner" = null, "lease_until" = null, "updated_at" = now()
  where k."name" = consumer and k."lease_owner" = owner
    and upto is not null
    and exists (select 1 from "better_supabase"."outbox_events" e where e."position" = upto and (e."xid", e."position") > (k."cursor_xid", k."cursor_position"));
  if found then
    return true;
  end if;
  update "better_supabase"."outbox_consumers" k
  set "lease_owner" = null, "lease_until" = null, "updated_at" = now()
  where k."name" = consumer and k."lease_owner" = owner;
  return found;
end;
$$;

-- Records a failed claim and releases the lease. The consumer waits
-- 2^attempts seconds (at most max_backoff) before its next claim. When the
-- claim held the one event at position failed and the consumer has failed
-- max_attempts times, the event goes to the dead letters and the cursor
-- moves past it. Returns 'retrying', 'dead', or null when owner no longer
-- holds the lease.
create or replace function "better_supabase"."outbox_fail"(
  consumer text,
  owner text,
  failed bigint default null,
  error text default null,
  max_attempts integer default 10,
  max_backoff interval default '10 minutes'
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  c "better_supabase"."outbox_consumers";
begin
  update "better_supabase"."outbox_consumers" k
  set "attempts" = k."attempts" + 1, "last_error" = left(error, 4000),
    "lease_owner" = null, "lease_until" = null, "updated_at" = now()
  where k."name" = consumer and k."lease_owner" = owner
  returning k.* into c;
  if not found then
    return null;
  end if;
  if failed is not null and c."attempts" >= greatest(coalesce(max_attempts, 10), 1) then
    insert into "better_supabase"."outbox_dead_letters" ("consumer", "position", "event_id", "type", "event", "attempts", "error")
    select consumer, e."position", e."id"::text, e."type", jsonb_build_object(
    'position', e."position",
    'id', e."id",
    'type', e."type",
    'payload', e."payload",
    'created_at', e."created_at",
    'source', e."source",
    'subject', e."subject",
    'tenant', e."organization_id",
    'key', e."key",
    'actor_id', e."actor_id"
  ), c."attempts", c."last_error"
    from "better_supabase"."outbox_events" e
    where e."position" = failed and (e."xid", e."position") > (c."cursor_xid", c."cursor_position")
    on conflict do nothing;
    update "better_supabase"."outbox_consumers" k
    set ("cursor_xid", "cursor_position") = (
        select e."xid", e."position" from "better_supabase"."outbox_events" e where e."position" = failed
      ),
      "attempts" = 0, "retry_at" = null
    where k."name" = consumer
      and exists (select 1 from "better_supabase"."outbox_events" e where e."position" = failed and (e."xid", e."position") > (k."cursor_xid", k."cursor_position"));
    if found then
      return 'dead';
    end if;
  end if;
  update "better_supabase"."outbox_consumers" k
  set "retry_at" = now() + least(
    coalesce(max_backoff, '10 minutes'),
    interval '1 second' * power(2, least(c."attempts", 20))
  )
  where k."name" = consumer;
  return 'retrying';
end;
$$;

-- A consumer's dead letters, newest first.
create or replace function "better_supabase"."outbox_dead_letters"(consumer text, max_rows integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'consumer', x."consumer",
    'position', x."position",
    'event', x."event",
    'attempts', x."attempts",
    'error', x."error",
    'dead_at', x."dead_at"
  ) order by x."dead_at" desc, x."position" desc), '[]')
  from (
    select * from "better_supabase"."outbox_dead_letters" d
    where d."consumer" = outbox_dead_letters.consumer
    order by d."dead_at" desc, d."position" desc
    limit least(greatest(coalesce(max_rows, 100), 1), 1000)
  ) x
$$;

-- Kept events, by subject and type, oldest first.
create or replace function "better_supabase"."outbox_history"(subject text default null, event_type text default null, after bigint default 0, max_events integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.event order by x.position), '[]')
  from (
    select jsonb_build_object(
    'position', e."position",
    'id', e."id",
    'type', e."type",
    'payload', e."payload",
    'created_at', e."created_at",
    'source', e."source",
    'subject', e."subject",
    'tenant', e."organization_id",
    'key', e."key",
    'actor_id', e."actor_id"
  ) as event, e."position" as position
    from "better_supabase"."outbox_events" e
    where e."position" > "outbox_history".after
      and ("outbox_history".subject is null or e."subject" = "outbox_history".subject)
      and ("outbox_history".event_type is null or e."type" = "outbox_history".event_type)
    order by e."position"
    limit "outbox_history".max_events
  ) x
$$;

-- Deletes up to batch events older than older_than that every consumer has
-- passed, and returns how many, along with dead letters older than
-- older_than. With ignore_idle, a consumer that hasn't claimed for that long
-- no longer holds events back. Run it until it returns less than batch.
-- A null older_than or batch takes its default.
create or replace function "better_supabase"."purge_outbox"(older_than interval default '30 days', batch integer default 10000, ignore_idle interval default null)
returns integer
language sql
security definer
set search_path = ''
as $$
  with active as (
    select k."cursor_xid", k."cursor_position" from "better_supabase"."outbox_consumers" k
    where ignore_idle is null or k."updated_at" >= now() - ignore_idle
  ),
  letters as (
    delete from "better_supabase"."outbox_dead_letters" x
    where x."dead_at" < now() - coalesce(older_than, '30 days'::interval)
  ),
  gone as (
    delete from "better_supabase"."outbox_events" e
    where e."id" in (
      select d."id" from "better_supabase"."outbox_events" d
      where d."created_at" < now() - coalesce(older_than, '30 days'::interval)
        and (
          not exists (select 1 from active)
          or (d."xid", d."position") <= (
            select a."cursor_xid", a."cursor_position" from active a
            order by a."cursor_xid", a."cursor_position"
            limit 1
          )
        )
      order by d."created_at"
      limit coalesce(batch, 10000)
    )
    returning 1
  )
  select count(*)::integer from gone
$$;
revoke execute on function "better_supabase"."outbox_register"(text, text[], boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."outbox_register"(text, text[], boolean) to service_role;
revoke execute on function "better_supabase"."outbox_unregister"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."outbox_unregister"(text) to service_role;
revoke execute on function "better_supabase"."outbox_claim"(text, text, integer, interval) from public, anon, authenticated;
grant execute on function "better_supabase"."outbox_claim"(text, text, integer, interval) to service_role;
revoke execute on function "better_supabase"."outbox_ack"(text, text, bigint) from public, anon, authenticated;
grant execute on function "better_supabase"."outbox_ack"(text, text, bigint) to service_role;
revoke execute on function "better_supabase"."outbox_fail"(text, text, bigint, text, integer, interval) from public, anon, authenticated;
grant execute on function "better_supabase"."outbox_fail"(text, text, bigint, text, integer, interval) to service_role;
revoke execute on function "better_supabase"."outbox_dead_letters"(text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."outbox_dead_letters"(text, integer) to service_role;
revoke execute on function "better_supabase"."outbox_history"(text, text, bigint, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."outbox_history"(text, text, bigint, integer) to service_role;
revoke execute on function "better_supabase"."purge_outbox"(interval, integer, interval) from public, anon, authenticated;
grant execute on function "better_supabase"."purge_outbox"(interval, integer, interval) to service_role;

-- A row trigger that emits <prefix>.created, .updated and .deleted with the
-- row as payload. prefix defaults to the table name.
create or replace function "better_supabase"."outbox_row_event"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_data jsonb := to_jsonb(case when tg_op = 'DELETE' then old else new end);
  prefix text := coalesce(nullif(tg_argv[0], ''), tg_table_name);
  tenant_column text := nullif(tg_argv[1], '');
begin
  perform "better_supabase"."emit_event"(
    prefix || '.' || case tg_op when 'INSERT' then 'created' when 'UPDATE' then 'updated' else 'deleted' end,
    jsonb_build_object('table', tg_table_schema || '.' || tg_table_name, 'row', row_data),
    tg_table_name || '/' || coalesce(row_data ->> 'id', ''),
    case when tenant_column is null then null else row_data ->> tenant_column end,
    null,
    'better-supabase/track_events'
  );
  return null;
end;
$$;

create or replace function "better_supabase"."track_events"(target regclass, type_prefix text default null, tenant_column text default null)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists "bs_outbox_events" on %s', target);
  execute format('drop trigger if exists "bs_outbox_events_update" on %s', target);
  execute format(
    'create trigger "bs_outbox_events" after insert or delete on %s for each row execute function "better_supabase"."outbox_row_event"(%L, %L)',
    target, coalesce(type_prefix, ''), coalesce(tenant_column, '')
  );
  -- jsonb, not the row: a row comparison fails on columns without equality (json).
  execute format(
    'create trigger "bs_outbox_events_update" after update on %s for each row when (to_jsonb(old) is distinct from to_jsonb(new)) execute function "better_supabase"."outbox_row_event"(%L, %L)',
    target, coalesce(type_prefix, ''), coalesce(tenant_column, '')
  );
end;
$$;
revoke execute on function "better_supabase"."track_events"(regclass, text, text) from public, anon, authenticated;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_23_outbox.sql
-- better-supabase module: outbox
-- @bs-module-data outbox
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('outbox', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_23_outbox.sql
-- better-supabase module: outbox
-- @bs-module outbox@3 managed
-- Events written in the same transaction as the change, read by named consumers with their own cursor and lease, kept for history and relayed as CloudEvents.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
create table if not exists "app_private"."outbox_events" (
  "id" uuid primary key default gen_random_uuid(),
  "position" bigint generated always as identity unique,
  "type" text not null,
  "source" text,
  "subject" text,
  "organization_id" uuid,
  "key" text,
  "payload" jsonb not null default '{}',
  "actor_id" uuid,
  "created_at" timestamptz not null default now(),
  "xid" xid8 not null default pg_current_xact_id()
);
create unique index if not exists outbox_events_key_idx on "app_private"."outbox_events" ("key", "organization_id") nulls not distinct where "key" is not null;
create index if not exists outbox_events_subject_idx on "app_private"."outbox_events" ("subject", "position");
create index if not exists outbox_events_type_idx on "app_private"."outbox_events" ("type", "position");
create index if not exists outbox_events_created_idx on "app_private"."outbox_events" ("created_at");
create index if not exists outbox_events_xid_idx on "app_private"."outbox_events" ("xid", "position");
alter table "app_private"."outbox_events" enable row level security;
revoke all on "app_private"."outbox_events" from anon, authenticated;
grant all on "app_private"."outbox_events" to service_role;

create table if not exists "app_private"."outbox_consumers" (
  "name" text primary key,
  -- The last event passed, ordered by (transaction id, position). Without
  -- the xid column, cursor_xid stays 0 and the position alone orders.
  "cursor_xid" xid8 not null default '0',
  "cursor_position" bigint not null default 0,
  -- Type patterns ('organization.*', 'invoice.paid'); null takes every event.
  "types" text[],
  "lease_owner" text,
  "lease_until" timestamptz,
  -- Failed claims in a row since the cursor last moved, and when to try again.
  "attempts" integer not null default 0,
  "last_error" text,
  "retry_at" timestamptz,
  "updated_at" timestamptz not null default now()
);
alter table "app_private"."outbox_consumers" add column if not exists "attempts" integer not null default 0;
alter table "app_private"."outbox_consumers" add column if not exists "last_error" text;
alter table "app_private"."outbox_consumers" add column if not exists "retry_at" timestamptz;
alter table "app_private"."outbox_consumers" enable row level security;
revoke all on "app_private"."outbox_consumers" from anon, authenticated;
grant all on "app_private"."outbox_consumers" to service_role;

-- Events a consumer skipped after max_attempts failures, with a copy of the
-- event, so one bad event can't stop the consumer.
create table if not exists "app_private"."outbox_dead_letters" (
  "consumer" text not null references "app_private"."outbox_consumers" ("name") on delete cascade,
  "position" bigint not null,
  "event_id" text not null,
  "type" text not null,
  "event" jsonb not null,
  "attempts" integer not null,
  "error" text,
  "dead_at" timestamptz not null default now(),
  primary key ("consumer", "position")
);
create index if not exists outbox_dead_letters_dead_at_idx on "app_private"."outbox_dead_letters" ("dead_at");
alter table "app_private"."outbox_dead_letters" enable row level security;
revoke all on "app_private"."outbox_dead_letters" from anon, authenticated;
grant all on "app_private"."outbox_dead_letters" to service_role;


-- create or replace can't change the return type of an earlier install.
drop function if exists "app_private"."emit_event"(text, jsonb, text, text, text, text);
-- Appends an event in the caller's transaction, so it exists only if the
-- transaction commits, and returns its id. A repeated key (per tenant)
-- returns the first event's id.
create or replace function "app_private"."emit_event"(
  event_type text,
  payload jsonb default '{}',
  subject text default null,
  tenant text default null,
  key text default null,
  source text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  found_id text;
begin
  if event_type is null or btrim(event_type) = '' then
    raise exception 'An event needs a type' using errcode = '22023', hint = 'OUTBOX_TYPE_REQUIRED';
  end if;
  if key is not null then
    select e."id"::text into found_id from "app_private"."outbox_events" e
    where e."key" = key and e."organization_id" is not distinct from tenant::uuid;
    if found_id is not null then
      return found_id;
    end if;
  end if;
  insert into "app_private"."outbox_events" ("type", "payload", "source", "subject", "organization_id", "key", "actor_id")
  values (event_type, coalesce(payload, '{}'), source, coalesce(subject, payload ->> 'subject'), tenant::uuid, key, auth.uid())
  on conflict do nothing
  returning "id"::text into found_id;
  if found_id is null then
    -- Another transaction emitted the same key first.
    select e."id"::text into found_id from "app_private"."outbox_events" e
    where e."key" = key and e."organization_id" is not distinct from tenant::uuid;
  end if;
  return found_id;
end;
$$;
revoke execute on function "app_private"."emit_event"(text, jsonb, text, text, text, text) from public, anon, authenticated;
grant execute on function "app_private"."emit_event"(text, jsonb, text, text, text, text) to service_role;

drop function if exists "app_private"."purge_outbox"(interval);
-- The signature before purge_outbox could pass over idle consumers.
drop function if exists "app_private"."purge_outbox"(interval, integer);

-- Registers a consumer. A new one starts after the latest event, or at the
-- first with from_start. Registering again changes only its types.
create or replace function "app_private"."outbox_register"(consumer text, types text[] default null, from_start boolean default false)
returns bigint
language sql
security definer
set search_path = ''
as $$
  insert into "app_private"."outbox_consumers" ("name", "cursor_xid", "cursor_position", "types")
  select consumer, coalesce(latest.xid, '0'), coalesce(latest.position, 0), types
  from (select 1) one
  left join lateral (
    select e."xid" as xid, e."position" as position from "app_private"."outbox_events" e
    where not from_start
    order by e."xid" desc, e."position" desc
    limit 1
  ) latest on true
  on conflict ("name") do update set "types" = excluded."types", "updated_at" = now()
  returning "cursor_position"
$$;

-- Deletes a consumer and its cursor, so purge_outbox no longer waits for it.
create or replace function "app_private"."outbox_unregister"(consumer text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  delete from "app_private"."outbox_consumers" k where k."name" = consumer;
  return found;
end;
$$;

-- Leases the consumer to owner and returns its next events after the
-- cursor. Events of transactions still running are held back, and
-- events sort by (xid, position), so a transaction that commits late sorts
-- after the cursor and is never skipped. When no event matches the consumer's types,
-- the cursor moves past the settled events it scanned. After a failure
-- (outbox_fail) the consumer waits until retry_at, then claims one event at
-- a time, so the next failure belongs to that event.
create or replace function "app_private"."outbox_claim"(consumer text, owner text, max_events integer default 100, lease interval default '1 minute')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  c "app_private"."outbox_consumers";
  events jsonb;
begin
  update "app_private"."outbox_consumers" k
  set "lease_owner" = owner, "lease_until" = now() + lease, "updated_at" = now()
  where k."name" = consumer
    and (k."lease_until" is null or k."lease_until" < now() or k."lease_owner" = owner)
    and (k."retry_at" is null or k."retry_at" <= now())
  returning k.* into c;
  if not found then
    if not exists (select 1 from "app_private"."outbox_consumers" k where k."name" = consumer) then
      raise exception 'Unknown outbox consumer %', consumer using errcode = 'P0002', hint = 'OUTBOX_UNKNOWN_CONSUMER';
    end if;
    return '[]';
  end if;
  select jsonb_agg(x.event order by x.n) into events
  from (
    select jsonb_build_object(
    'position', e."position",
    'id', e."id",
    'type', e."type",
    'payload', e."payload",
    'created_at', e."created_at",
    'source', e."source",
    'subject', e."subject",
    'tenant', e."organization_id",
    'key', e."key",
    'actor_id', e."actor_id"
  ) as event, row_number() over (order by e."xid", e."position") as n
    from "app_private"."outbox_events" e
    where (e."xid", e."position") > (c."cursor_xid", c."cursor_position")
      and e."xid" < pg_snapshot_xmin(pg_current_snapshot())
      and (c."types" is null or exists (
        select 1 from unnest(c."types") p
        where p = '*' or p = e."type"
          or (right(p, 2) = '.*' and starts_with(e."type", left(p, -1)))
      ))
    order by e."xid", e."position"
    limit case when c."attempts" > 0 then 1 else max_events end
  ) x;
  if events is null then
    update "app_private"."outbox_consumers" k
    set ("cursor_xid", "cursor_position") = (
      select e."xid", e."position" from "app_private"."outbox_events" e
      where (e."xid", e."position") > (c."cursor_xid", c."cursor_position") and e."xid" < pg_snapshot_xmin(pg_current_snapshot())
      order by e."xid" desc, e."position" desc
      limit 1
    )
    where k."name" = consumer
      and exists (select 1 from "app_private"."outbox_events" e where (e."xid", e."position") > (c."cursor_xid", c."cursor_position") and e."xid" < pg_snapshot_xmin(pg_current_snapshot()));
  end if;
  return coalesce(events, '[]');
end;
$$;

-- Moves the cursor to the event at position upto (when given), clears the
-- failure count and releases the lease. False when owner no longer holds it.
create or replace function "app_private"."outbox_ack"(consumer text, owner text, upto bigint default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  update "app_private"."outbox_consumers" k
  set ("cursor_xid", "cursor_position") = (
      select e."xid", e."position" from "app_private"."outbox_events" e where e."position" = upto
    ),
    "attempts" = 0, "last_error" = null, "retry_at" = null,
    "lease_owner" = null, "lease_until" = null, "updated_at" = now()
  where k."name" = consumer and k."lease_owner" = owner
    and upto is not null
    and exists (select 1 from "app_private"."outbox_events" e where e."position" = upto and (e."xid", e."position") > (k."cursor_xid", k."cursor_position"));
  if found then
    return true;
  end if;
  update "app_private"."outbox_consumers" k
  set "lease_owner" = null, "lease_until" = null, "updated_at" = now()
  where k."name" = consumer and k."lease_owner" = owner;
  return found;
end;
$$;

-- Records a failed claim and releases the lease. The consumer waits
-- 2^attempts seconds (at most max_backoff) before its next claim. When the
-- claim held the one event at position failed and the consumer has failed
-- max_attempts times, the event goes to the dead letters and the cursor
-- moves past it. Returns 'retrying', 'dead', or null when owner no longer
-- holds the lease.
create or replace function "app_private"."outbox_fail"(
  consumer text,
  owner text,
  failed bigint default null,
  error text default null,
  max_attempts integer default 10,
  max_backoff interval default '10 minutes'
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  c "app_private"."outbox_consumers";
begin
  update "app_private"."outbox_consumers" k
  set "attempts" = k."attempts" + 1, "last_error" = left(error, 4000),
    "lease_owner" = null, "lease_until" = null, "updated_at" = now()
  where k."name" = consumer and k."lease_owner" = owner
  returning k.* into c;
  if not found then
    return null;
  end if;
  if failed is not null and c."attempts" >= greatest(coalesce(max_attempts, 10), 1) then
    insert into "app_private"."outbox_dead_letters" ("consumer", "position", "event_id", "type", "event", "attempts", "error")
    select consumer, e."position", e."id"::text, e."type", jsonb_build_object(
    'position', e."position",
    'id', e."id",
    'type', e."type",
    'payload', e."payload",
    'created_at', e."created_at",
    'source', e."source",
    'subject', e."subject",
    'tenant', e."organization_id",
    'key', e."key",
    'actor_id', e."actor_id"
  ), c."attempts", c."last_error"
    from "app_private"."outbox_events" e
    where e."position" = failed and (e."xid", e."position") > (c."cursor_xid", c."cursor_position")
    on conflict do nothing;
    update "app_private"."outbox_consumers" k
    set ("cursor_xid", "cursor_position") = (
        select e."xid", e."position" from "app_private"."outbox_events" e where e."position" = failed
      ),
      "attempts" = 0, "retry_at" = null
    where k."name" = consumer
      and exists (select 1 from "app_private"."outbox_events" e where e."position" = failed and (e."xid", e."position") > (k."cursor_xid", k."cursor_position"));
    if found then
      return 'dead';
    end if;
  end if;
  update "app_private"."outbox_consumers" k
  set "retry_at" = now() + least(
    coalesce(max_backoff, '10 minutes'),
    interval '1 second' * power(2, least(c."attempts", 20))
  )
  where k."name" = consumer;
  return 'retrying';
end;
$$;

-- A consumer's dead letters, newest first.
create or replace function "app_private"."outbox_dead_letters"(consumer text, max_rows integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'consumer', x."consumer",
    'position', x."position",
    'event', x."event",
    'attempts', x."attempts",
    'error', x."error",
    'dead_at', x."dead_at"
  ) order by x."dead_at" desc, x."position" desc), '[]')
  from (
    select * from "app_private"."outbox_dead_letters" d
    where d."consumer" = outbox_dead_letters.consumer
    order by d."dead_at" desc, d."position" desc
    limit least(greatest(coalesce(max_rows, 100), 1), 1000)
  ) x
$$;

-- Kept events, by subject and type, oldest first.
create or replace function "app_private"."outbox_history"(subject text default null, event_type text default null, after bigint default 0, max_events integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.event order by x.position), '[]')
  from (
    select jsonb_build_object(
    'position', e."position",
    'id', e."id",
    'type', e."type",
    'payload', e."payload",
    'created_at', e."created_at",
    'source', e."source",
    'subject', e."subject",
    'tenant', e."organization_id",
    'key', e."key",
    'actor_id', e."actor_id"
  ) as event, e."position" as position
    from "app_private"."outbox_events" e
    where e."position" > "outbox_history".after
      and ("outbox_history".subject is null or e."subject" = "outbox_history".subject)
      and ("outbox_history".event_type is null or e."type" = "outbox_history".event_type)
    order by e."position"
    limit "outbox_history".max_events
  ) x
$$;

-- Deletes up to batch events older than older_than that every consumer has
-- passed, and returns how many, along with dead letters older than
-- older_than. With ignore_idle, a consumer that hasn't claimed for that long
-- no longer holds events back. Run it until it returns less than batch.
-- A null older_than or batch takes its default.
create or replace function "app_private"."purge_outbox"(older_than interval default '30 days', batch integer default 10000, ignore_idle interval default null)
returns integer
language sql
security definer
set search_path = ''
as $$
  with active as (
    select k."cursor_xid", k."cursor_position" from "app_private"."outbox_consumers" k
    where ignore_idle is null or k."updated_at" >= now() - ignore_idle
  ),
  letters as (
    delete from "app_private"."outbox_dead_letters" x
    where x."dead_at" < now() - coalesce(older_than, '30 days'::interval)
  ),
  gone as (
    delete from "app_private"."outbox_events" e
    where e."id" in (
      select d."id" from "app_private"."outbox_events" d
      where d."created_at" < now() - coalesce(older_than, '30 days'::interval)
        and (
          not exists (select 1 from active)
          or (d."xid", d."position") <= (
            select a."cursor_xid", a."cursor_position" from active a
            order by a."cursor_xid", a."cursor_position"
            limit 1
          )
        )
      order by d."created_at"
      limit coalesce(batch, 10000)
    )
    returning 1
  )
  select count(*)::integer from gone
$$;
revoke execute on function "app_private"."outbox_register"(text, text[], boolean) from public, anon, authenticated;
grant execute on function "app_private"."outbox_register"(text, text[], boolean) to service_role;
revoke execute on function "app_private"."outbox_unregister"(text) from public, anon, authenticated;
grant execute on function "app_private"."outbox_unregister"(text) to service_role;
revoke execute on function "app_private"."outbox_claim"(text, text, integer, interval) from public, anon, authenticated;
grant execute on function "app_private"."outbox_claim"(text, text, integer, interval) to service_role;
revoke execute on function "app_private"."outbox_ack"(text, text, bigint) from public, anon, authenticated;
grant execute on function "app_private"."outbox_ack"(text, text, bigint) to service_role;
revoke execute on function "app_private"."outbox_fail"(text, text, bigint, text, integer, interval) from public, anon, authenticated;
grant execute on function "app_private"."outbox_fail"(text, text, bigint, text, integer, interval) to service_role;
revoke execute on function "app_private"."outbox_dead_letters"(text, integer) from public, anon, authenticated;
grant execute on function "app_private"."outbox_dead_letters"(text, integer) to service_role;
revoke execute on function "app_private"."outbox_history"(text, text, bigint, integer) from public, anon, authenticated;
grant execute on function "app_private"."outbox_history"(text, text, bigint, integer) to service_role;
revoke execute on function "app_private"."purge_outbox"(interval, integer, interval) from public, anon, authenticated;
grant execute on function "app_private"."purge_outbox"(interval, integer, interval) to service_role;

-- A row trigger that emits <prefix>.created, .updated and .deleted with the
-- row as payload. prefix defaults to the table name.
create or replace function "app_private"."outbox_row_event"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_data jsonb := to_jsonb(case when tg_op = 'DELETE' then old else new end);
  prefix text := coalesce(nullif(tg_argv[0], ''), tg_table_name);
  tenant_column text := nullif(tg_argv[1], '');
begin
  perform "app_private"."emit_event"(
    prefix || '.' || case tg_op when 'INSERT' then 'created' when 'UPDATE' then 'updated' else 'deleted' end,
    jsonb_build_object('table', tg_table_schema || '.' || tg_table_name, 'row', row_data),
    tg_table_name || '/' || coalesce(row_data ->> 'id', ''),
    case when tenant_column is null then null else row_data ->> tenant_column end,
    null,
    'better-supabase/track_events'
  );
  return null;
end;
$$;

create or replace function "app_private"."track_events"(target regclass, type_prefix text default null, tenant_column text default null)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists "bs_outbox_events" on %s', target);
  execute format('drop trigger if exists "bs_outbox_events_update" on %s', target);
  execute format(
    'create trigger "bs_outbox_events" after insert or delete on %s for each row execute function "app_private"."outbox_row_event"(%L, %L)',
    target, coalesce(type_prefix, ''), coalesce(tenant_column, '')
  );
  -- jsonb, not the row: a row comparison fails on columns without equality (json).
  execute format(
    'create trigger "bs_outbox_events_update" after update on %s for each row when (to_jsonb(old) is distinct from to_jsonb(new)) execute function "app_private"."outbox_row_event"(%L, %L)',
    target, coalesce(type_prefix, ''), coalesce(tenant_column, '')
  );
end;
$$;
revoke execute on function "app_private"."track_events"(regclass, text, text) from public, anon, authenticated;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_23_outbox.sql
-- better-supabase module: outbox
-- @bs-module-data outbox
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('outbox', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_23_outbox.sql
-- better-supabase module: outbox
-- @bs-module outbox@3 managed
-- Events written in the same transaction as the change, read by named consumers with their own cursor and lease, kept for history and relayed as CloudEvents.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."outbox_events" (
  "id" uuid primary key default gen_random_uuid(),
  "position" bigint generated always as identity unique,
  "type" text not null,
  "source" text,
  "subject" text,
  "organization_id" uuid,
  "key" text,
  "payload" jsonb not null default '{}',
  "actor_id" uuid,
  "created_at" timestamptz not null default now(),
  "xid" xid8 not null default pg_current_xact_id()
);
create unique index if not exists outbox_events_key_idx on "better_supabase"."outbox_events" ("key", "organization_id") nulls not distinct where "key" is not null;
create index if not exists outbox_events_subject_idx on "better_supabase"."outbox_events" ("subject", "position");
create index if not exists outbox_events_type_idx on "better_supabase"."outbox_events" ("type", "position");
create index if not exists outbox_events_created_idx on "better_supabase"."outbox_events" ("created_at");
create index if not exists outbox_events_xid_idx on "better_supabase"."outbox_events" ("xid", "position");
alter table "better_supabase"."outbox_events" enable row level security;
revoke all on "better_supabase"."outbox_events" from anon, authenticated;
grant all on "better_supabase"."outbox_events" to service_role;

create table if not exists "better_supabase"."outbox_consumers" (
  "name" text primary key,
  -- The last event passed, ordered by (transaction id, position). Without
  -- the xid column, cursor_xid stays 0 and the position alone orders.
  "cursor_xid" xid8 not null default '0',
  "cursor_position" bigint not null default 0,
  -- Type patterns ('organization.*', 'invoice.paid'); null takes every event.
  "types" text[],
  "lease_owner" text,
  "lease_until" timestamptz,
  -- Failed claims in a row since the cursor last moved, and when to try again.
  "attempts" integer not null default 0,
  "last_error" text,
  "retry_at" timestamptz,
  "updated_at" timestamptz not null default now()
);
alter table "better_supabase"."outbox_consumers" add column if not exists "attempts" integer not null default 0;
alter table "better_supabase"."outbox_consumers" add column if not exists "last_error" text;
alter table "better_supabase"."outbox_consumers" add column if not exists "retry_at" timestamptz;
alter table "better_supabase"."outbox_consumers" enable row level security;
revoke all on "better_supabase"."outbox_consumers" from anon, authenticated;
grant all on "better_supabase"."outbox_consumers" to service_role;

-- Events a consumer skipped after max_attempts failures, with a copy of the
-- event, so one bad event can't stop the consumer.
create table if not exists "better_supabase"."outbox_dead_letters" (
  "consumer" text not null references "better_supabase"."outbox_consumers" ("name") on delete cascade,
  "position" bigint not null,
  "event_id" text not null,
  "type" text not null,
  "event" jsonb not null,
  "attempts" integer not null,
  "error" text,
  "dead_at" timestamptz not null default now(),
  primary key ("consumer", "position")
);
create index if not exists outbox_dead_letters_dead_at_idx on "better_supabase"."outbox_dead_letters" ("dead_at");
alter table "better_supabase"."outbox_dead_letters" enable row level security;
revoke all on "better_supabase"."outbox_dead_letters" from anon, authenticated;
grant all on "better_supabase"."outbox_dead_letters" to service_role;


-- create or replace can't change the return type of an earlier install.
drop function if exists "better_supabase"."emit_event"(text, jsonb, text, text, text, text);
-- Appends an event in the caller's transaction, so it exists only if the
-- transaction commits, and returns its id. A repeated key (per tenant)
-- returns the first event's id.
create or replace function "better_supabase"."emit_event"(
  event_type text,
  payload jsonb default '{}',
  subject text default null,
  tenant text default null,
  key text default null,
  source text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  found_id text;
begin
  if event_type is null or btrim(event_type) = '' then
    raise exception 'An event needs a type' using errcode = '22023', hint = 'OUTBOX_TYPE_REQUIRED';
  end if;
  if key is not null then
    select e."id"::text into found_id from "better_supabase"."outbox_events" e
    where e."key" = key and e."organization_id" is not distinct from tenant::uuid;
    if found_id is not null then
      return found_id;
    end if;
  end if;
  insert into "better_supabase"."outbox_events" ("type", "payload", "source", "subject", "organization_id", "key", "actor_id")
  values (event_type, coalesce(payload, '{}'), source, coalesce(subject, payload ->> 'subject'), tenant::uuid, key, auth.uid())
  on conflict do nothing
  returning "id"::text into found_id;
  if found_id is null then
    -- Another transaction emitted the same key first.
    select e."id"::text into found_id from "better_supabase"."outbox_events" e
    where e."key" = key and e."organization_id" is not distinct from tenant::uuid;
  end if;
  return found_id;
end;
$$;
revoke execute on function "better_supabase"."emit_event"(text, jsonb, text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."emit_event"(text, jsonb, text, text, text, text) to service_role;

drop function if exists "better_supabase"."purge_outbox"(interval);
-- The signature before purge_outbox could pass over idle consumers.
drop function if exists "better_supabase"."purge_outbox"(interval, integer);

-- Registers a consumer. A new one starts after the latest event, or at the
-- first with from_start. Registering again changes only its types.
create or replace function "better_supabase"."outbox_register"(consumer text, types text[] default null, from_start boolean default false)
returns bigint
language sql
security definer
set search_path = ''
as $$
  insert into "better_supabase"."outbox_consumers" ("name", "cursor_xid", "cursor_position", "types")
  select consumer, coalesce(latest.xid, '0'), coalesce(latest.position, 0), types
  from (select 1) one
  left join lateral (
    select e."xid" as xid, e."position" as position from "better_supabase"."outbox_events" e
    where not from_start
    order by e."xid" desc, e."position" desc
    limit 1
  ) latest on true
  on conflict ("name") do update set "types" = excluded."types", "updated_at" = now()
  returning "cursor_position"
$$;

-- Deletes a consumer and its cursor, so purge_outbox no longer waits for it.
create or replace function "better_supabase"."outbox_unregister"(consumer text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  delete from "better_supabase"."outbox_consumers" k where k."name" = consumer;
  return found;
end;
$$;

-- Leases the consumer to owner and returns its next events after the
-- cursor. Events of transactions still running are held back, and
-- events sort by (xid, position), so a transaction that commits late sorts
-- after the cursor and is never skipped. When no event matches the consumer's types,
-- the cursor moves past the settled events it scanned. After a failure
-- (outbox_fail) the consumer waits until retry_at, then claims one event at
-- a time, so the next failure belongs to that event.
create or replace function "better_supabase"."outbox_claim"(consumer text, owner text, max_events integer default 100, lease interval default '1 minute')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  c "better_supabase"."outbox_consumers";
  events jsonb;
begin
  update "better_supabase"."outbox_consumers" k
  set "lease_owner" = owner, "lease_until" = now() + lease, "updated_at" = now()
  where k."name" = consumer
    and (k."lease_until" is null or k."lease_until" < now() or k."lease_owner" = owner)
    and (k."retry_at" is null or k."retry_at" <= now())
  returning k.* into c;
  if not found then
    if not exists (select 1 from "better_supabase"."outbox_consumers" k where k."name" = consumer) then
      raise exception 'Unknown outbox consumer %', consumer using errcode = 'P0002', hint = 'OUTBOX_UNKNOWN_CONSUMER';
    end if;
    return '[]';
  end if;
  select jsonb_agg(x.event order by x.n) into events
  from (
    select jsonb_build_object(
    'position', e."position",
    'id', e."id",
    'type', e."type",
    'payload', e."payload",
    'created_at', e."created_at",
    'source', e."source",
    'subject', e."subject",
    'tenant', e."organization_id",
    'key', e."key",
    'actor_id', e."actor_id"
  ) as event, row_number() over (order by e."xid", e."position") as n
    from "better_supabase"."outbox_events" e
    where (e."xid", e."position") > (c."cursor_xid", c."cursor_position")
      and e."xid" < pg_snapshot_xmin(pg_current_snapshot())
      and (c."types" is null or exists (
        select 1 from unnest(c."types") p
        where p = '*' or p = e."type"
          or (right(p, 2) = '.*' and starts_with(e."type", left(p, -1)))
      ))
    order by e."xid", e."position"
    limit case when c."attempts" > 0 then 1 else max_events end
  ) x;
  if events is null then
    update "better_supabase"."outbox_consumers" k
    set ("cursor_xid", "cursor_position") = (
      select e."xid", e."position" from "better_supabase"."outbox_events" e
      where (e."xid", e."position") > (c."cursor_xid", c."cursor_position") and e."xid" < pg_snapshot_xmin(pg_current_snapshot())
      order by e."xid" desc, e."position" desc
      limit 1
    )
    where k."name" = consumer
      and exists (select 1 from "better_supabase"."outbox_events" e where (e."xid", e."position") > (c."cursor_xid", c."cursor_position") and e."xid" < pg_snapshot_xmin(pg_current_snapshot()));
  end if;
  return coalesce(events, '[]');
end;
$$;

-- Moves the cursor to the event at position upto (when given), clears the
-- failure count and releases the lease. False when owner no longer holds it.
create or replace function "better_supabase"."outbox_ack"(consumer text, owner text, upto bigint default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  update "better_supabase"."outbox_consumers" k
  set ("cursor_xid", "cursor_position") = (
      select e."xid", e."position" from "better_supabase"."outbox_events" e where e."position" = upto
    ),
    "attempts" = 0, "last_error" = null, "retry_at" = null,
    "lease_owner" = null, "lease_until" = null, "updated_at" = now()
  where k."name" = consumer and k."lease_owner" = owner
    and upto is not null
    and exists (select 1 from "better_supabase"."outbox_events" e where e."position" = upto and (e."xid", e."position") > (k."cursor_xid", k."cursor_position"));
  if found then
    return true;
  end if;
  update "better_supabase"."outbox_consumers" k
  set "lease_owner" = null, "lease_until" = null, "updated_at" = now()
  where k."name" = consumer and k."lease_owner" = owner;
  return found;
end;
$$;

-- Records a failed claim and releases the lease. The consumer waits
-- 2^attempts seconds (at most max_backoff) before its next claim. When the
-- claim held the one event at position failed and the consumer has failed
-- max_attempts times, the event goes to the dead letters and the cursor
-- moves past it. Returns 'retrying', 'dead', or null when owner no longer
-- holds the lease.
create or replace function "better_supabase"."outbox_fail"(
  consumer text,
  owner text,
  failed bigint default null,
  error text default null,
  max_attempts integer default 10,
  max_backoff interval default '10 minutes'
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  c "better_supabase"."outbox_consumers";
begin
  update "better_supabase"."outbox_consumers" k
  set "attempts" = k."attempts" + 1, "last_error" = left(error, 4000),
    "lease_owner" = null, "lease_until" = null, "updated_at" = now()
  where k."name" = consumer and k."lease_owner" = owner
  returning k.* into c;
  if not found then
    return null;
  end if;
  if failed is not null and c."attempts" >= greatest(coalesce(max_attempts, 10), 1) then
    insert into "better_supabase"."outbox_dead_letters" ("consumer", "position", "event_id", "type", "event", "attempts", "error")
    select consumer, e."position", e."id"::text, e."type", jsonb_build_object(
    'position', e."position",
    'id', e."id",
    'type', e."type",
    'payload', e."payload",
    'created_at', e."created_at",
    'source', e."source",
    'subject', e."subject",
    'tenant', e."organization_id",
    'key', e."key",
    'actor_id', e."actor_id"
  ), c."attempts", c."last_error"
    from "better_supabase"."outbox_events" e
    where e."position" = failed and (e."xid", e."position") > (c."cursor_xid", c."cursor_position")
    on conflict do nothing;
    update "better_supabase"."outbox_consumers" k
    set ("cursor_xid", "cursor_position") = (
        select e."xid", e."position" from "better_supabase"."outbox_events" e where e."position" = failed
      ),
      "attempts" = 0, "retry_at" = null
    where k."name" = consumer
      and exists (select 1 from "better_supabase"."outbox_events" e where e."position" = failed and (e."xid", e."position") > (k."cursor_xid", k."cursor_position"));
    if found then
      return 'dead';
    end if;
  end if;
  update "better_supabase"."outbox_consumers" k
  set "retry_at" = now() + least(
    coalesce(max_backoff, '10 minutes'),
    interval '1 second' * power(2, least(c."attempts", 20))
  )
  where k."name" = consumer;
  return 'retrying';
end;
$$;

-- A consumer's dead letters, newest first.
create or replace function "better_supabase"."outbox_dead_letters"(consumer text, max_rows integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'consumer', x."consumer",
    'position', x."position",
    'event', x."event",
    'attempts', x."attempts",
    'error', x."error",
    'dead_at', x."dead_at"
  ) order by x."dead_at" desc, x."position" desc), '[]')
  from (
    select * from "better_supabase"."outbox_dead_letters" d
    where d."consumer" = outbox_dead_letters.consumer
    order by d."dead_at" desc, d."position" desc
    limit least(greatest(coalesce(max_rows, 100), 1), 1000)
  ) x
$$;

-- Kept events, by subject and type, oldest first.
create or replace function "better_supabase"."outbox_history"(subject text default null, event_type text default null, after bigint default 0, max_events integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.event order by x.position), '[]')
  from (
    select jsonb_build_object(
    'position', e."position",
    'id', e."id",
    'type', e."type",
    'payload', e."payload",
    'created_at', e."created_at",
    'source', e."source",
    'subject', e."subject",
    'tenant', e."organization_id",
    'key', e."key",
    'actor_id', e."actor_id"
  ) as event, e."position" as position
    from "better_supabase"."outbox_events" e
    where e."position" > "outbox_history".after
      and ("outbox_history".subject is null or e."subject" = "outbox_history".subject)
      and ("outbox_history".event_type is null or e."type" = "outbox_history".event_type)
    order by e."position"
    limit "outbox_history".max_events
  ) x
$$;

-- Deletes up to batch events older than older_than that every consumer has
-- passed, and returns how many, along with dead letters older than
-- older_than. With ignore_idle, a consumer that hasn't claimed for that long
-- no longer holds events back. Run it until it returns less than batch.
-- A null older_than or batch takes its default.
create or replace function "better_supabase"."purge_outbox"(older_than interval default '30 days', batch integer default 10000, ignore_idle interval default null)
returns integer
language sql
security definer
set search_path = ''
as $$
  with active as (
    select k."cursor_xid", k."cursor_position" from "better_supabase"."outbox_consumers" k
    where ignore_idle is null or k."updated_at" >= now() - ignore_idle
  ),
  letters as (
    delete from "better_supabase"."outbox_dead_letters" x
    where x."dead_at" < now() - coalesce(older_than, '30 days'::interval)
  ),
  gone as (
    delete from "better_supabase"."outbox_events" e
    where e."id" in (
      select d."id" from "better_supabase"."outbox_events" d
      where d."created_at" < now() - coalesce(older_than, '30 days'::interval)
        and (
          not exists (select 1 from active)
          or (d."xid", d."position") <= (
            select a."cursor_xid", a."cursor_position" from active a
            order by a."cursor_xid", a."cursor_position"
            limit 1
          )
        )
      order by d."created_at"
      limit coalesce(batch, 10000)
    )
    returning 1
  )
  select count(*)::integer from gone
$$;
revoke execute on function "better_supabase"."outbox_register"(text, text[], boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."outbox_register"(text, text[], boolean) to service_role;
revoke execute on function "better_supabase"."outbox_unregister"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."outbox_unregister"(text) to service_role;
revoke execute on function "better_supabase"."outbox_claim"(text, text, integer, interval) from public, anon, authenticated;
grant execute on function "better_supabase"."outbox_claim"(text, text, integer, interval) to service_role;
revoke execute on function "better_supabase"."outbox_ack"(text, text, bigint) from public, anon, authenticated;
grant execute on function "better_supabase"."outbox_ack"(text, text, bigint) to service_role;
revoke execute on function "better_supabase"."outbox_fail"(text, text, bigint, text, integer, interval) from public, anon, authenticated;
grant execute on function "better_supabase"."outbox_fail"(text, text, bigint, text, integer, interval) to service_role;
revoke execute on function "better_supabase"."outbox_dead_letters"(text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."outbox_dead_letters"(text, integer) to service_role;
revoke execute on function "better_supabase"."outbox_history"(text, text, bigint, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."outbox_history"(text, text, bigint, integer) to service_role;
revoke execute on function "better_supabase"."purge_outbox"(interval, integer, interval) from public, anon, authenticated;
grant execute on function "better_supabase"."purge_outbox"(interval, integer, interval) to service_role;

-- A row trigger that emits <prefix>.created, .updated and .deleted with the
-- row as payload. prefix defaults to the table name.
create or replace function "better_supabase"."outbox_row_event"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_data jsonb := to_jsonb(case when tg_op = 'DELETE' then old else new end);
  prefix text := coalesce(nullif(tg_argv[0], ''), tg_table_name);
  tenant_column text := nullif(tg_argv[1], '');
begin
  perform "better_supabase"."emit_event"(
    prefix || '.' || case tg_op when 'INSERT' then 'created' when 'UPDATE' then 'updated' else 'deleted' end,
    jsonb_build_object('table', tg_table_schema || '.' || tg_table_name, 'row', row_data),
    tg_table_name || '/' || coalesce(row_data ->> 'id', ''),
    case when tenant_column is null then null else row_data ->> tenant_column end,
    null,
    'better-supabase/track_events'
  );
  return null;
end;
$$;

create or replace function "better_supabase"."track_events"(target regclass, type_prefix text default null, tenant_column text default null)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists "bs_outbox_events" on %s', target);
  execute format('drop trigger if exists "bs_outbox_events_update" on %s', target);
  execute format(
    'create trigger "bs_outbox_events" after insert or delete on %s for each row execute function "better_supabase"."outbox_row_event"(%L, %L)',
    target, coalesce(type_prefix, ''), coalesce(tenant_column, '')
  );
  -- jsonb, not the row: a row comparison fails on columns without equality (json).
  execute format(
    'create trigger "bs_outbox_events_update" after update on %s for each row when (to_jsonb(old) is distinct from to_jsonb(new)) execute function "better_supabase"."outbox_row_event"(%L, %L)',
    target, coalesce(type_prefix, ''), coalesce(tenant_column, '')
  );
end;
$$;
revoke execute on function "better_supabase"."track_events"(regclass, text, text) from public, anon, authenticated;

-- sql.modules.outbox.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."emit_event"(text, jsonb, text, text, text, text);
drop function if exists "api"."purge_outbox"(interval);
drop function if exists "api"."purge_outbox"(interval, integer);

create or replace function "api"."emit_event"(event_type text, payload jsonb default '{}', subject text default null, tenant text default null, key text default null, source text default null)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."emit_event"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."emit_event"(text, jsonb, text, text, text, text) from public, anon, authenticated;
grant execute on function "api"."emit_event"(text, jsonb, text, text, text, text) to service_role;

create or replace function "api"."outbox_register"(consumer text, types text[] default null, from_start boolean default false)
returns bigint
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."outbox_register"($1, $2, $3) $$;
revoke execute on function "api"."outbox_register"(text, text[], boolean) from public, anon, authenticated;
grant execute on function "api"."outbox_register"(text, text[], boolean) to service_role;

create or replace function "api"."outbox_unregister"(consumer text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."outbox_unregister"($1) $$;
revoke execute on function "api"."outbox_unregister"(text) from public, anon, authenticated;
grant execute on function "api"."outbox_unregister"(text) to service_role;

create or replace function "api"."outbox_claim"(consumer text, owner text, max_events integer default 100, lease interval default '1 minute')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."outbox_claim"($1, $2, $3, $4) $$;
revoke execute on function "api"."outbox_claim"(text, text, integer, interval) from public, anon, authenticated;
grant execute on function "api"."outbox_claim"(text, text, integer, interval) to service_role;

create or replace function "api"."outbox_ack"(consumer text, owner text, upto bigint default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."outbox_ack"($1, $2, $3) $$;
revoke execute on function "api"."outbox_ack"(text, text, bigint) from public, anon, authenticated;
grant execute on function "api"."outbox_ack"(text, text, bigint) to service_role;

create or replace function "api"."outbox_fail"(consumer text, owner text, failed bigint default null, error text default null, max_attempts integer default 10, max_backoff interval default '10 minutes')
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."outbox_fail"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."outbox_fail"(text, text, bigint, text, integer, interval) from public, anon, authenticated;
grant execute on function "api"."outbox_fail"(text, text, bigint, text, integer, interval) to service_role;

create or replace function "api"."outbox_dead_letters"(consumer text, max_rows integer default 100)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."outbox_dead_letters"($1, $2) $$;
revoke execute on function "api"."outbox_dead_letters"(text, integer) from public, anon, authenticated;
grant execute on function "api"."outbox_dead_letters"(text, integer) to service_role;

create or replace function "api"."outbox_history"(subject text default null, event_type text default null, after bigint default 0, max_events integer default 100)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."outbox_history"($1, $2, $3, $4) $$;
revoke execute on function "api"."outbox_history"(text, text, bigint, integer) from public, anon, authenticated;
grant execute on function "api"."outbox_history"(text, text, bigint, integer) to service_role;

create or replace function "api"."purge_outbox"(older_than interval default '30 days', batch integer default 10000, ignore_idle interval default null)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."purge_outbox"($1, $2, $3) $$;
revoke execute on function "api"."purge_outbox"(interval, integer, interval) from public, anon, authenticated;
grant execute on function "api"."purge_outbox"(interval, integer, interval) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_23_outbox.sql
-- better-supabase module: outbox
-- @bs-module-data outbox
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('outbox', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== adopt: schema supabase/schemas/900_better_supabase_23_outbox.sql
-- better-supabase module: outbox
-- @bs-module outbox@3 adopt
-- Events written in the same transaction as the change, read by named consumers with their own cursor and lease, kept for history and relayed as CloudEvents.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
alter table "better_supabase"."outbox_events" add column if not exists "xid" xid8 not null default pg_current_xact_id();
create index if not exists outbox_events_xid_idx on "better_supabase"."outbox_events" ("xid", "position");
create table if not exists "better_supabase"."outbox_consumers" (
  "name" text primary key,
  -- The last event passed, ordered by (transaction id, position). Without
  -- the xid column, cursor_xid stays 0 and the position alone orders.
  "cursor_xid" xid8 not null default '0',
  "cursor_position" bigint not null default 0,
  -- Type patterns ('organization.*', 'invoice.paid'); null takes every event.
  "types" text[],
  "lease_owner" text,
  "lease_until" timestamptz,
  -- Failed claims in a row since the cursor last moved, and when to try again.
  "attempts" integer not null default 0,
  "last_error" text,
  "retry_at" timestamptz,
  "updated_at" timestamptz not null default now()
);
alter table "better_supabase"."outbox_consumers" add column if not exists "attempts" integer not null default 0;
alter table "better_supabase"."outbox_consumers" add column if not exists "last_error" text;
alter table "better_supabase"."outbox_consumers" add column if not exists "retry_at" timestamptz;
alter table "better_supabase"."outbox_consumers" enable row level security;
revoke all on "better_supabase"."outbox_consumers" from anon, authenticated;
grant all on "better_supabase"."outbox_consumers" to service_role;

-- Events a consumer skipped after max_attempts failures, with a copy of the
-- event, so one bad event can't stop the consumer.
create table if not exists "better_supabase"."outbox_dead_letters" (
  "consumer" text not null references "better_supabase"."outbox_consumers" ("name") on delete cascade,
  "position" bigint not null,
  "event_id" text not null,
  "type" text not null,
  "event" jsonb not null,
  "attempts" integer not null,
  "error" text,
  "dead_at" timestamptz not null default now(),
  primary key ("consumer", "position")
);
create index if not exists outbox_dead_letters_dead_at_idx on "better_supabase"."outbox_dead_letters" ("dead_at");
alter table "better_supabase"."outbox_dead_letters" enable row level security;
revoke all on "better_supabase"."outbox_dead_letters" from anon, authenticated;
grant all on "better_supabase"."outbox_dead_letters" to service_role;


-- create or replace can't change the return type of an earlier install.
drop function if exists "better_supabase"."emit_event"(text, jsonb, text, text, text, text);
-- Appends an event in the caller's transaction, so it exists only if the
-- transaction commits, and returns its id. A repeated key (per tenant)
-- returns the first event's id.
create or replace function "better_supabase"."emit_event"(
  event_type text,
  payload jsonb default '{}',
  subject text default null,
  tenant text default null,
  key text default null,
  source text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  found_id text;
begin
  if event_type is null or btrim(event_type) = '' then
    raise exception 'An event needs a type' using errcode = '22023', hint = 'OUTBOX_TYPE_REQUIRED';
  end if;
  if key is not null then
    select e."id"::text into found_id from "better_supabase"."outbox_events" e
    where e."key" = key and e."organization_id" is not distinct from tenant::uuid;
    if found_id is not null then
      return found_id;
    end if;
  end if;
  insert into "better_supabase"."outbox_events" ("type", "payload", "source", "subject", "organization_id", "key", "actor_id")
  values (event_type, coalesce(payload, '{}'), source, coalesce(subject, payload ->> 'subject'), tenant::uuid, key, auth.uid())
  on conflict do nothing
  returning "id"::text into found_id;
  if found_id is null then
    -- Another transaction emitted the same key first.
    select e."id"::text into found_id from "better_supabase"."outbox_events" e
    where e."key" = key and e."organization_id" is not distinct from tenant::uuid;
  end if;
  return found_id;
end;
$$;
revoke execute on function "better_supabase"."emit_event"(text, jsonb, text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."emit_event"(text, jsonb, text, text, text, text) to service_role;

drop function if exists "better_supabase"."purge_outbox"(interval);
-- The signature before purge_outbox could pass over idle consumers.
drop function if exists "better_supabase"."purge_outbox"(interval, integer);

-- Registers a consumer. A new one starts after the latest event, or at the
-- first with from_start. Registering again changes only its types.
create or replace function "better_supabase"."outbox_register"(consumer text, types text[] default null, from_start boolean default false)
returns bigint
language sql
security definer
set search_path = ''
as $$
  insert into "better_supabase"."outbox_consumers" ("name", "cursor_xid", "cursor_position", "types")
  select consumer, coalesce(latest.xid, '0'), coalesce(latest.position, 0), types
  from (select 1) one
  left join lateral (
    select e."xid" as xid, e."position" as position from "better_supabase"."outbox_events" e
    where not from_start
    order by e."xid" desc, e."position" desc
    limit 1
  ) latest on true
  on conflict ("name") do update set "types" = excluded."types", "updated_at" = now()
  returning "cursor_position"
$$;

-- Deletes a consumer and its cursor, so purge_outbox no longer waits for it.
create or replace function "better_supabase"."outbox_unregister"(consumer text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  delete from "better_supabase"."outbox_consumers" k where k."name" = consumer;
  return found;
end;
$$;

-- Leases the consumer to owner and returns its next events after the
-- cursor. Events of transactions still running are held back, and
-- events sort by (xid, position), so a transaction that commits late sorts
-- after the cursor and is never skipped. When no event matches the consumer's types,
-- the cursor moves past the settled events it scanned. After a failure
-- (outbox_fail) the consumer waits until retry_at, then claims one event at
-- a time, so the next failure belongs to that event.
create or replace function "better_supabase"."outbox_claim"(consumer text, owner text, max_events integer default 100, lease interval default '1 minute')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  c "better_supabase"."outbox_consumers";
  events jsonb;
begin
  update "better_supabase"."outbox_consumers" k
  set "lease_owner" = owner, "lease_until" = now() + lease, "updated_at" = now()
  where k."name" = consumer
    and (k."lease_until" is null or k."lease_until" < now() or k."lease_owner" = owner)
    and (k."retry_at" is null or k."retry_at" <= now())
  returning k.* into c;
  if not found then
    if not exists (select 1 from "better_supabase"."outbox_consumers" k where k."name" = consumer) then
      raise exception 'Unknown outbox consumer %', consumer using errcode = 'P0002', hint = 'OUTBOX_UNKNOWN_CONSUMER';
    end if;
    return '[]';
  end if;
  select jsonb_agg(x.event order by x.n) into events
  from (
    select jsonb_build_object(
    'position', e."position",
    'id', e."id",
    'type', e."type",
    'payload', e."payload",
    'created_at', e."created_at",
    'source', e."source",
    'subject', e."subject",
    'tenant', e."organization_id",
    'key', e."key",
    'actor_id', e."actor_id"
  ) as event, row_number() over (order by e."xid", e."position") as n
    from "better_supabase"."outbox_events" e
    where (e."xid", e."position") > (c."cursor_xid", c."cursor_position")
      and e."xid" < pg_snapshot_xmin(pg_current_snapshot())
      and (c."types" is null or exists (
        select 1 from unnest(c."types") p
        where p = '*' or p = e."type"
          or (right(p, 2) = '.*' and starts_with(e."type", left(p, -1)))
      ))
    order by e."xid", e."position"
    limit case when c."attempts" > 0 then 1 else max_events end
  ) x;
  if events is null then
    update "better_supabase"."outbox_consumers" k
    set ("cursor_xid", "cursor_position") = (
      select e."xid", e."position" from "better_supabase"."outbox_events" e
      where (e."xid", e."position") > (c."cursor_xid", c."cursor_position") and e."xid" < pg_snapshot_xmin(pg_current_snapshot())
      order by e."xid" desc, e."position" desc
      limit 1
    )
    where k."name" = consumer
      and exists (select 1 from "better_supabase"."outbox_events" e where (e."xid", e."position") > (c."cursor_xid", c."cursor_position") and e."xid" < pg_snapshot_xmin(pg_current_snapshot()));
  end if;
  return coalesce(events, '[]');
end;
$$;

-- Moves the cursor to the event at position upto (when given), clears the
-- failure count and releases the lease. False when owner no longer holds it.
create or replace function "better_supabase"."outbox_ack"(consumer text, owner text, upto bigint default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  update "better_supabase"."outbox_consumers" k
  set ("cursor_xid", "cursor_position") = (
      select e."xid", e."position" from "better_supabase"."outbox_events" e where e."position" = upto
    ),
    "attempts" = 0, "last_error" = null, "retry_at" = null,
    "lease_owner" = null, "lease_until" = null, "updated_at" = now()
  where k."name" = consumer and k."lease_owner" = owner
    and upto is not null
    and exists (select 1 from "better_supabase"."outbox_events" e where e."position" = upto and (e."xid", e."position") > (k."cursor_xid", k."cursor_position"));
  if found then
    return true;
  end if;
  update "better_supabase"."outbox_consumers" k
  set "lease_owner" = null, "lease_until" = null, "updated_at" = now()
  where k."name" = consumer and k."lease_owner" = owner;
  return found;
end;
$$;

-- Records a failed claim and releases the lease. The consumer waits
-- 2^attempts seconds (at most max_backoff) before its next claim. When the
-- claim held the one event at position failed and the consumer has failed
-- max_attempts times, the event goes to the dead letters and the cursor
-- moves past it. Returns 'retrying', 'dead', or null when owner no longer
-- holds the lease.
create or replace function "better_supabase"."outbox_fail"(
  consumer text,
  owner text,
  failed bigint default null,
  error text default null,
  max_attempts integer default 10,
  max_backoff interval default '10 minutes'
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  c "better_supabase"."outbox_consumers";
begin
  update "better_supabase"."outbox_consumers" k
  set "attempts" = k."attempts" + 1, "last_error" = left(error, 4000),
    "lease_owner" = null, "lease_until" = null, "updated_at" = now()
  where k."name" = consumer and k."lease_owner" = owner
  returning k.* into c;
  if not found then
    return null;
  end if;
  if failed is not null and c."attempts" >= greatest(coalesce(max_attempts, 10), 1) then
    insert into "better_supabase"."outbox_dead_letters" ("consumer", "position", "event_id", "type", "event", "attempts", "error")
    select consumer, e."position", e."id"::text, e."type", jsonb_build_object(
    'position', e."position",
    'id', e."id",
    'type', e."type",
    'payload', e."payload",
    'created_at', e."created_at",
    'source', e."source",
    'subject', e."subject",
    'tenant', e."organization_id",
    'key', e."key",
    'actor_id', e."actor_id"
  ), c."attempts", c."last_error"
    from "better_supabase"."outbox_events" e
    where e."position" = failed and (e."xid", e."position") > (c."cursor_xid", c."cursor_position")
    on conflict do nothing;
    update "better_supabase"."outbox_consumers" k
    set ("cursor_xid", "cursor_position") = (
        select e."xid", e."position" from "better_supabase"."outbox_events" e where e."position" = failed
      ),
      "attempts" = 0, "retry_at" = null
    where k."name" = consumer
      and exists (select 1 from "better_supabase"."outbox_events" e where e."position" = failed and (e."xid", e."position") > (k."cursor_xid", k."cursor_position"));
    if found then
      return 'dead';
    end if;
  end if;
  update "better_supabase"."outbox_consumers" k
  set "retry_at" = now() + least(
    coalesce(max_backoff, '10 minutes'),
    interval '1 second' * power(2, least(c."attempts", 20))
  )
  where k."name" = consumer;
  return 'retrying';
end;
$$;

-- A consumer's dead letters, newest first.
create or replace function "better_supabase"."outbox_dead_letters"(consumer text, max_rows integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'consumer', x."consumer",
    'position', x."position",
    'event', x."event",
    'attempts', x."attempts",
    'error', x."error",
    'dead_at', x."dead_at"
  ) order by x."dead_at" desc, x."position" desc), '[]')
  from (
    select * from "better_supabase"."outbox_dead_letters" d
    where d."consumer" = outbox_dead_letters.consumer
    order by d."dead_at" desc, d."position" desc
    limit least(greatest(coalesce(max_rows, 100), 1), 1000)
  ) x
$$;

-- Kept events, by subject and type, oldest first.
create or replace function "better_supabase"."outbox_history"(subject text default null, event_type text default null, after bigint default 0, max_events integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.event order by x.position), '[]')
  from (
    select jsonb_build_object(
    'position', e."position",
    'id', e."id",
    'type', e."type",
    'payload', e."payload",
    'created_at', e."created_at",
    'source', e."source",
    'subject', e."subject",
    'tenant', e."organization_id",
    'key', e."key",
    'actor_id', e."actor_id"
  ) as event, e."position" as position
    from "better_supabase"."outbox_events" e
    where e."position" > "outbox_history".after
      and ("outbox_history".subject is null or e."subject" = "outbox_history".subject)
      and ("outbox_history".event_type is null or e."type" = "outbox_history".event_type)
    order by e."position"
    limit "outbox_history".max_events
  ) x
$$;

-- Deletes up to batch events older than older_than that every consumer has
-- passed, and returns how many, along with dead letters older than
-- older_than. With ignore_idle, a consumer that hasn't claimed for that long
-- no longer holds events back. Run it until it returns less than batch.
-- A null older_than or batch takes its default.
create or replace function "better_supabase"."purge_outbox"(older_than interval default '30 days', batch integer default 10000, ignore_idle interval default null)
returns integer
language sql
security definer
set search_path = ''
as $$
  with active as (
    select k."cursor_xid", k."cursor_position" from "better_supabase"."outbox_consumers" k
    where ignore_idle is null or k."updated_at" >= now() - ignore_idle
  ),
  letters as (
    delete from "better_supabase"."outbox_dead_letters" x
    where x."dead_at" < now() - coalesce(older_than, '30 days'::interval)
  ),
  gone as (
    delete from "better_supabase"."outbox_events" e
    where e."id" in (
      select d."id" from "better_supabase"."outbox_events" d
      where d."created_at" < now() - coalesce(older_than, '30 days'::interval)
        and (
          not exists (select 1 from active)
          or (d."xid", d."position") <= (
            select a."cursor_xid", a."cursor_position" from active a
            order by a."cursor_xid", a."cursor_position"
            limit 1
          )
        )
      order by d."created_at"
      limit coalesce(batch, 10000)
    )
    returning 1
  )
  select count(*)::integer from gone
$$;
revoke execute on function "better_supabase"."outbox_register"(text, text[], boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."outbox_register"(text, text[], boolean) to service_role;
revoke execute on function "better_supabase"."outbox_unregister"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."outbox_unregister"(text) to service_role;
revoke execute on function "better_supabase"."outbox_claim"(text, text, integer, interval) from public, anon, authenticated;
grant execute on function "better_supabase"."outbox_claim"(text, text, integer, interval) to service_role;
revoke execute on function "better_supabase"."outbox_ack"(text, text, bigint) from public, anon, authenticated;
grant execute on function "better_supabase"."outbox_ack"(text, text, bigint) to service_role;
revoke execute on function "better_supabase"."outbox_fail"(text, text, bigint, text, integer, interval) from public, anon, authenticated;
grant execute on function "better_supabase"."outbox_fail"(text, text, bigint, text, integer, interval) to service_role;
revoke execute on function "better_supabase"."outbox_dead_letters"(text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."outbox_dead_letters"(text, integer) to service_role;
revoke execute on function "better_supabase"."outbox_history"(text, text, bigint, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."outbox_history"(text, text, bigint, integer) to service_role;
revoke execute on function "better_supabase"."purge_outbox"(interval, integer, interval) from public, anon, authenticated;
grant execute on function "better_supabase"."purge_outbox"(interval, integer, interval) to service_role;

-- A row trigger that emits <prefix>.created, .updated and .deleted with the
-- row as payload. prefix defaults to the table name.
create or replace function "better_supabase"."outbox_row_event"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_data jsonb := to_jsonb(case when tg_op = 'DELETE' then old else new end);
  prefix text := coalesce(nullif(tg_argv[0], ''), tg_table_name);
  tenant_column text := nullif(tg_argv[1], '');
begin
  perform "better_supabase"."emit_event"(
    prefix || '.' || case tg_op when 'INSERT' then 'created' when 'UPDATE' then 'updated' else 'deleted' end,
    jsonb_build_object('table', tg_table_schema || '.' || tg_table_name, 'row', row_data),
    tg_table_name || '/' || coalesce(row_data ->> 'id', ''),
    case when tenant_column is null then null else row_data ->> tenant_column end,
    null,
    'better-supabase/track_events'
  );
  return null;
end;
$$;

create or replace function "better_supabase"."track_events"(target regclass, type_prefix text default null, tenant_column text default null)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists "bs_outbox_events" on %s', target);
  execute format('drop trigger if exists "bs_outbox_events_update" on %s', target);
  execute format(
    'create trigger "bs_outbox_events" after insert or delete on %s for each row execute function "better_supabase"."outbox_row_event"(%L, %L)',
    target, coalesce(type_prefix, ''), coalesce(tenant_column, '')
  );
  -- jsonb, not the row: a row comparison fails on columns without equality (json).
  execute format(
    'create trigger "bs_outbox_events_update" after update on %s for each row when (to_jsonb(old) is distinct from to_jsonb(new)) execute function "better_supabase"."outbox_row_event"(%L, %L)',
    target, coalesce(type_prefix, ''), coalesce(tenant_column, '')
  );
end;
$$;
revoke execute on function "better_supabase"."track_events"(regclass, text, text) from public, anon, authenticated;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;

-- ==== adopt: data supabase/better-supabase-data/900_better_supabase_23_outbox.sql
-- better-supabase module: outbox
-- @bs-module-data outbox
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('outbox', 3, 'adopt')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
