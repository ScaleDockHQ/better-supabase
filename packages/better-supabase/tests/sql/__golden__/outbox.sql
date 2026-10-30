-- ==== alone: schema supabase/schemas/900_better_supabase_023_outbox.sql
-- better-supabase module: outbox
-- @bsb-block outbox@5 managed
-- @bsb-hash sha256:a1d3344e66eb4042d246243941f52ec45eb8c35c07716087f2f368db0af046c7
-- Events written in the same transaction as the change, read by named consumers with their own cursor and lease, kept for history and relayed as CloudEvents.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."outbox_events";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."outbox_events";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."outbox_events";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."outbox_events";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."outbox_events";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

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
revoke all on "better_supabase"."outbox_events" from public, anon, authenticated;
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
revoke all on "better_supabase"."outbox_consumers" from public, anon, authenticated;
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
revoke all on "better_supabase"."outbox_dead_letters" from public, anon, authenticated;
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
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_purged integer;
begin
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
  select count(*)::integer into v_purged from gone;
  return v_purged;
end;
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
revoke execute on function "better_supabase"."outbox_row_event"() from public, anon, authenticated;

create or replace function "better_supabase"."track_events"(target regclass, type_prefix text default null, tenant_column text default null)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists "bsb_outbox_events" on %s', target);
  execute format('drop trigger if exists "bsb_outbox_events_update" on %s', target);
  execute format(
    'create trigger "bsb_outbox_events" after insert or delete on %s for each row execute function "better_supabase"."outbox_row_event"(%L, %L)',
    target, coalesce(type_prefix, ''), coalesce(tenant_column, '')
  );
  -- jsonb, not the row: a row comparison fails on columns without equality (json).
  execute format(
    'create trigger "bsb_outbox_events_update" after update on %s for each row when (to_jsonb(old) is distinct from to_jsonb(new)) execute function "better_supabase"."outbox_row_event"(%L, %L)',
    target, coalesce(type_prefix, ''), coalesce(tenant_column, '')
  );
end;
$$;
revoke execute on function "better_supabase"."track_events"(regclass, text, text) from public, anon, authenticated;

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_023_outbox.sql
-- better-supabase module: outbox
-- @bsb-block-data outbox
-- @bsb-hash sha256:5acf345602c65fa5d8b14b27584db06d6781e8b7baa395bf3edb3a329343acee
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Event types renamed by the 0.47 naming convention (ADR 0130).
update "better_supabase"."outbox_events" t set "type" = m.next_type
from (values
  ('access.ended', 'access_request.ended'),
  ('access.request_approved', 'access_request.approved'),
  ('access.requested', 'access_request.requested'),
  ('ai_tool_policy.set', 'ai_tool_policy.updated'),
  ('approval_policy.removed', 'approval_policy.deleted'),
  ('compliance_policy.acknowledged', 'acknowledgement.created'),
  ('credential.set', 'credential.updated'),
  ('custom_field.deleted', 'field_definition.deleted'),
  ('drive.node_created', 'drive_node.created'),
  ('drive.node_document_saved', 'drive_node.document_saved'),
  ('drive.node_download_blocked_changed', 'drive_node.download_blocked_changed'),
  ('drive.node_hold_placed', 'drive_node.hold_placed'),
  ('drive.node_hold_released', 'drive_node.hold_released'),
  ('drive.node_locked', 'drive_node.locked'),
  ('drive.node_moved', 'drive_node.moved'),
  ('drive.node_obsoleted', 'drive_node.obsoleted'),
  ('drive.node_ownership_transferred', 'drive_node.ownership_transferred'),
  ('drive.node_purged', 'drive_node.purged'),
  ('drive.node_released', 'drive_node.released'),
  ('drive.node_renamed', 'drive_node.renamed'),
  ('drive.node_review_requested', 'drive_node.review_requested'),
  ('drive.node_reviewed', 'drive_node.reviewed'),
  ('drive.node_shared', 'drive_node.shared'),
  ('drive.node_submitted', 'drive_node.submitted'),
  ('drive.node_unlocked', 'drive_node.unlocked'),
  ('drive.node_unshared', 'drive_node.unshared'),
  ('engagement.amended', 'activity.amended'),
  ('engagement.completed', 'activity.completed'),
  ('engagement.deleted', 'activity.deleted'),
  ('engagement.error_marked', 'activity.error_marked'),
  ('engagement.logged', 'activity.logged'),
  ('engagement.recorded', 'activity.recorded'),
  ('engagement.summarized', 'activity.summarized'),
  ('engagement.transcribed', 'activity.transcribed'),
  ('engagement.updated', 'activity.updated'),
  ('flag.override_set', 'flag.override_changed'),
  ('forecast.snapshotted', 'forecast_snapshot.created'),
  ('hostname.primary_set', 'hostname.primary_changed'),
  ('hostname.removed', 'hostname.deleted'),
  ('incoming_webhook.enabled_set', 'incoming_webhook.enabled_changed'),
  ('job.closed', 'job_opening.closed'),
  ('job.opened', 'job_opening.opened'),
  ('leave.adjusted', 'leave_balance.adjusted'),
  ('leave.approved', 'leave_request.approved'),
  ('leave.cancelled', 'leave_request.cancelled'),
  ('leave.rejected', 'leave_request.rejected'),
  ('leave.requested', 'leave_request.requested'),
  ('leave.split', 'leave_request.split'),
  ('leave.updated', 'leave_request.updated'),
  ('marketplace_installation.removed', 'marketplace_installation.deleted'),
  ('marketplace_invoice.state_changed', 'marketplace_invoice.status_changed'),
  ('obligation.status_changed', 'contract_obligation.status_changed'),
  ('organization.domain_added', 'sso_domain.created'),
  ('organization.domain_removed', 'sso_domain.deleted'),
  ('organization.domain_updated', 'sso_domain.updated'),
  ('organization.domain_verified', 'sso_domain.verified'),
  ('policy.acknowledged', 'acknowledgement.created'),
  ('policy.published', 'compliance_policy.published'),
  ('postmortem.published', 'incident_postmortem.published'),
  ('rule.disabled', 'automation.disabled'),
  ('rule.enabled', 'automation.enabled'),
  ('rule.matched', 'automation.matched'),
  ('rule.removed', 'automation.deleted'),
  ('segment.removed', 'segment.deleted'),
  ('sequence_enrollment.completed', 'enrollment.completed'),
  ('sequence_enrollment.created', 'enrollment.created'),
  ('sequence_enrollment.exited', 'enrollment.cancelled'),
  ('sequence_enrollment.paused', 'enrollment.paused'),
  ('sequence_enrollment.resumed', 'enrollment.resumed'),
  ('sequence_enrollment.step_completed', 'enrollment.step_completed'),
  ('signature.cancelled', 'signature_request.cancelled'),
  ('signature.completed', 'signature_request.completed'),
  ('signature.declined', 'signature_request.declined'),
  ('signature.requested', 'signature_request.requested'),
  ('signature.signed', 'signature_request.signed'),
  ('support.denied', 'support_session.denied'),
  ('support.ended', 'support_session.ended'),
  ('support.started', 'support_session.started'),
  ('time.invoiced', 'time_entry.invoiced'),
  ('variant.created', 'product_variant.created'),
  ('variant.deleted', 'product_variant.deleted'),
  ('variant.updated', 'product_variant.updated'),
  ('waitlist.approved', 'waitlist_entry.approved'),
  ('waitlist.rejected', 'waitlist_entry.rejected'),
  ('webhook.delivered', 'webhook_endpoint.delivered'),
  ('webhook.disabled', 'webhook_endpoint.disabled'),
  ('webhook.failed', 'webhook_endpoint.failed'),
  ('webhook.secret_rotated', 'webhook_endpoint.secret_rotated'),
  ('work_item.archived', 'task.archived'),
  ('work_item.assigned', 'task.assigned'),
  ('work_item.closed', 'task.closed'),
  ('work_item.created', 'task.created'),
  ('work_item.deleted', 'task.deleted'),
  ('work_item.reopened', 'task.reopened'),
  ('work_item.updated', 'task.updated'),
  ('workflow.published', 'workflow_definition.published')
) as m(old_type, next_type)
where t."type" = m.old_type;

update "better_supabase"."outbox_dead_letters" t set "type" = m.next_type
from (values
  ('access.ended', 'access_request.ended'),
  ('access.request_approved', 'access_request.approved'),
  ('access.requested', 'access_request.requested'),
  ('ai_tool_policy.set', 'ai_tool_policy.updated'),
  ('approval_policy.removed', 'approval_policy.deleted'),
  ('compliance_policy.acknowledged', 'acknowledgement.created'),
  ('credential.set', 'credential.updated'),
  ('custom_field.deleted', 'field_definition.deleted'),
  ('drive.node_created', 'drive_node.created'),
  ('drive.node_document_saved', 'drive_node.document_saved'),
  ('drive.node_download_blocked_changed', 'drive_node.download_blocked_changed'),
  ('drive.node_hold_placed', 'drive_node.hold_placed'),
  ('drive.node_hold_released', 'drive_node.hold_released'),
  ('drive.node_locked', 'drive_node.locked'),
  ('drive.node_moved', 'drive_node.moved'),
  ('drive.node_obsoleted', 'drive_node.obsoleted'),
  ('drive.node_ownership_transferred', 'drive_node.ownership_transferred'),
  ('drive.node_purged', 'drive_node.purged'),
  ('drive.node_released', 'drive_node.released'),
  ('drive.node_renamed', 'drive_node.renamed'),
  ('drive.node_review_requested', 'drive_node.review_requested'),
  ('drive.node_reviewed', 'drive_node.reviewed'),
  ('drive.node_shared', 'drive_node.shared'),
  ('drive.node_submitted', 'drive_node.submitted'),
  ('drive.node_unlocked', 'drive_node.unlocked'),
  ('drive.node_unshared', 'drive_node.unshared'),
  ('engagement.amended', 'activity.amended'),
  ('engagement.completed', 'activity.completed'),
  ('engagement.deleted', 'activity.deleted'),
  ('engagement.error_marked', 'activity.error_marked'),
  ('engagement.logged', 'activity.logged'),
  ('engagement.recorded', 'activity.recorded'),
  ('engagement.summarized', 'activity.summarized'),
  ('engagement.transcribed', 'activity.transcribed'),
  ('engagement.updated', 'activity.updated'),
  ('flag.override_set', 'flag.override_changed'),
  ('forecast.snapshotted', 'forecast_snapshot.created'),
  ('hostname.primary_set', 'hostname.primary_changed'),
  ('hostname.removed', 'hostname.deleted'),
  ('incoming_webhook.enabled_set', 'incoming_webhook.enabled_changed'),
  ('job.closed', 'job_opening.closed'),
  ('job.opened', 'job_opening.opened'),
  ('leave.adjusted', 'leave_balance.adjusted'),
  ('leave.approved', 'leave_request.approved'),
  ('leave.cancelled', 'leave_request.cancelled'),
  ('leave.rejected', 'leave_request.rejected'),
  ('leave.requested', 'leave_request.requested'),
  ('leave.split', 'leave_request.split'),
  ('leave.updated', 'leave_request.updated'),
  ('marketplace_installation.removed', 'marketplace_installation.deleted'),
  ('marketplace_invoice.state_changed', 'marketplace_invoice.status_changed'),
  ('obligation.status_changed', 'contract_obligation.status_changed'),
  ('organization.domain_added', 'sso_domain.created'),
  ('organization.domain_removed', 'sso_domain.deleted'),
  ('organization.domain_updated', 'sso_domain.updated'),
  ('organization.domain_verified', 'sso_domain.verified'),
  ('policy.acknowledged', 'acknowledgement.created'),
  ('policy.published', 'compliance_policy.published'),
  ('postmortem.published', 'incident_postmortem.published'),
  ('rule.disabled', 'automation.disabled'),
  ('rule.enabled', 'automation.enabled'),
  ('rule.matched', 'automation.matched'),
  ('rule.removed', 'automation.deleted'),
  ('segment.removed', 'segment.deleted'),
  ('sequence_enrollment.completed', 'enrollment.completed'),
  ('sequence_enrollment.created', 'enrollment.created'),
  ('sequence_enrollment.exited', 'enrollment.cancelled'),
  ('sequence_enrollment.paused', 'enrollment.paused'),
  ('sequence_enrollment.resumed', 'enrollment.resumed'),
  ('sequence_enrollment.step_completed', 'enrollment.step_completed'),
  ('signature.cancelled', 'signature_request.cancelled'),
  ('signature.completed', 'signature_request.completed'),
  ('signature.declined', 'signature_request.declined'),
  ('signature.requested', 'signature_request.requested'),
  ('signature.signed', 'signature_request.signed'),
  ('support.denied', 'support_session.denied'),
  ('support.ended', 'support_session.ended'),
  ('support.started', 'support_session.started'),
  ('time.invoiced', 'time_entry.invoiced'),
  ('variant.created', 'product_variant.created'),
  ('variant.deleted', 'product_variant.deleted'),
  ('variant.updated', 'product_variant.updated'),
  ('waitlist.approved', 'waitlist_entry.approved'),
  ('waitlist.rejected', 'waitlist_entry.rejected'),
  ('webhook.delivered', 'webhook_endpoint.delivered'),
  ('webhook.disabled', 'webhook_endpoint.disabled'),
  ('webhook.failed', 'webhook_endpoint.failed'),
  ('webhook.secret_rotated', 'webhook_endpoint.secret_rotated'),
  ('work_item.archived', 'task.archived'),
  ('work_item.assigned', 'task.assigned'),
  ('work_item.closed', 'task.closed'),
  ('work_item.created', 'task.created'),
  ('work_item.deleted', 'task.deleted'),
  ('work_item.reopened', 'task.reopened'),
  ('work_item.updated', 'task.updated'),
  ('workflow.published', 'workflow_definition.published')
) as m(old_type, next_type)
where t."type" = m.old_type;

with m(old_type, next_types) as (values
  ('access.*', array['access_request.*']::text[]),
  ('access.ended', array['access_request.ended']::text[]),
  ('access.request_approved', array['access_request.approved']::text[]),
  ('access.requested', array['access_request.requested']::text[]),
  ('agent.saved', array['agent.created', 'agent.updated']::text[]),
  ('ai_provider_key.saved', array['ai_provider_key.created', 'ai_provider_key.updated']::text[]),
  ('ai_tool_policy.set', array['ai_tool_policy.updated']::text[]),
  ('announcement.saved', array['announcement.created', 'announcement.updated']::text[]),
  ('approval_policy.removed', array['approval_policy.deleted']::text[]),
  ('approval_policy.saved', array['approval_policy.created', 'approval_policy.updated']::text[]),
  ('compliance_policy.acknowledged', array['acknowledgement.created']::text[]),
  ('connector.saved', array['connector.created', 'connector.updated']::text[]),
  ('control.saved', array['control.created', 'control.updated']::text[]),
  ('course.saved', array['course.created', 'course.updated']::text[]),
  ('credential.set', array['credential.updated']::text[]),
  ('custom_field.*', array['field_definition.*']::text[]),
  ('custom_field.deleted', array['field_definition.deleted']::text[]),
  ('custom_field.saved', array['field_definition.created', 'field_definition.updated']::text[]),
  ('drive.*', array['drive_node.*']::text[]),
  ('drive.node_created', array['drive_node.created']::text[]),
  ('drive.node_document_saved', array['drive_node.document_saved']::text[]),
  ('drive.node_download_blocked_changed', array['drive_node.download_blocked_changed']::text[]),
  ('drive.node_hold_placed', array['drive_node.hold_placed']::text[]),
  ('drive.node_hold_released', array['drive_node.hold_released']::text[]),
  ('drive.node_locked', array['drive_node.locked']::text[]),
  ('drive.node_moved', array['drive_node.moved']::text[]),
  ('drive.node_obsoleted', array['drive_node.obsoleted']::text[]),
  ('drive.node_ownership_transferred', array['drive_node.ownership_transferred']::text[]),
  ('drive.node_purged', array['drive_node.purged']::text[]),
  ('drive.node_released', array['drive_node.released']::text[]),
  ('drive.node_renamed', array['drive_node.renamed']::text[]),
  ('drive.node_review_requested', array['drive_node.review_requested']::text[]),
  ('drive.node_reviewed', array['drive_node.reviewed']::text[]),
  ('drive.node_shared', array['drive_node.shared']::text[]),
  ('drive.node_submitted', array['drive_node.submitted']::text[]),
  ('drive.node_unlocked', array['drive_node.unlocked']::text[]),
  ('drive.node_unshared', array['drive_node.unshared']::text[]),
  ('engagement.*', array['activity.*']::text[]),
  ('engagement.amended', array['activity.amended']::text[]),
  ('engagement.completed', array['activity.completed']::text[]),
  ('engagement.deleted', array['activity.deleted']::text[]),
  ('engagement.error_marked', array['activity.error_marked']::text[]),
  ('engagement.logged', array['activity.logged']::text[]),
  ('engagement.recorded', array['activity.recorded']::text[]),
  ('engagement.summarized', array['activity.summarized']::text[]),
  ('engagement.transcribed', array['activity.transcribed']::text[]),
  ('engagement.updated', array['activity.updated']::text[]),
  ('enrollment_program.saved', array['enrollment_program.created', 'enrollment_program.updated']::text[]),
  ('flag.override_set', array['flag.override_changed']::text[]),
  ('flag.saved', array['flag.created', 'flag.updated']::text[]),
  ('forecast.*', array['forecast_snapshot.*']::text[]),
  ('forecast.snapshotted', array['forecast_snapshot.created']::text[]),
  ('hostname.primary_set', array['hostname.primary_changed']::text[]),
  ('hostname.removed', array['hostname.deleted']::text[]),
  ('incoming_webhook.enabled_set', array['incoming_webhook.enabled_changed']::text[]),
  ('job.*', array['job_opening.*']::text[]),
  ('job.closed', array['job_opening.closed']::text[]),
  ('job.opened', array['job_opening.opened']::text[]),
  ('leave.*', array['leave_request.*', 'leave_balance.*']::text[]),
  ('leave.adjusted', array['leave_balance.adjusted']::text[]),
  ('leave.approved', array['leave_request.approved']::text[]),
  ('leave.cancelled', array['leave_request.cancelled']::text[]),
  ('leave.rejected', array['leave_request.rejected']::text[]),
  ('leave.requested', array['leave_request.requested']::text[]),
  ('leave.split', array['leave_request.split']::text[]),
  ('leave.updated', array['leave_request.updated']::text[]),
  ('marketplace_installation.removed', array['marketplace_installation.deleted']::text[]),
  ('marketplace_installation.upserted', array['marketplace_installation.created', 'marketplace_installation.updated']::text[]),
  ('marketplace_invoice.state_changed', array['marketplace_invoice.status_changed']::text[]),
  ('obligation.*', array['contract_obligation.*']::text[]),
  ('obligation.saved', array['contract_obligation.created', 'contract_obligation.updated']::text[]),
  ('obligation.status_changed', array['contract_obligation.status_changed']::text[]),
  ('organization.*', array['sso_domain.*']::text[]),
  ('organization.domain_added', array['sso_domain.created']::text[]),
  ('organization.domain_removed', array['sso_domain.deleted']::text[]),
  ('organization.domain_updated', array['sso_domain.updated']::text[]),
  ('organization.domain_verified', array['sso_domain.verified']::text[]),
  ('party.*', array['company.enriched', 'person.enriched']::text[]),
  ('party.enriched', array['company.enriched', 'person.enriched']::text[]),
  ('pipeline_stage.saved', array['pipeline_stage.created', 'pipeline_stage.updated']::text[]),
  ('policy.*', array['compliance_policy.*']::text[]),
  ('policy.acknowledged', array['acknowledgement.created']::text[]),
  ('policy.published', array['compliance_policy.published']::text[]),
  ('post_board.saved', array['post_board.created', 'post_board.updated']::text[]),
  ('postmortem.*', array['incident_postmortem.*']::text[]),
  ('postmortem.published', array['incident_postmortem.published']::text[]),
  ('rule.*', array['automation.*']::text[]),
  ('rule.disabled', array['automation.disabled']::text[]),
  ('rule.enabled', array['automation.enabled']::text[]),
  ('rule.matched', array['automation.matched']::text[]),
  ('rule.removed', array['automation.deleted']::text[]),
  ('rule.saved', array['automation.created', 'automation.updated']::text[]),
  ('saved_view.saved', array['saved_view.created', 'saved_view.updated']::text[]),
  ('scim_group.saved', array['scim_group.created', 'scim_group.updated']::text[]),
  ('scim_user.saved', array['scim_user.created', 'scim_user.updated']::text[]),
  ('score_model.saved', array['score_model.created', 'score_model.updated']::text[]),
  ('segment.removed', array['segment.deleted']::text[]),
  ('segment.saved', array['segment.created', 'segment.updated']::text[]),
  ('sequence.saved', array['sequence.created', 'sequence.updated']::text[]),
  ('sequence_enrollment.*', array['enrollment.*']::text[]),
  ('sequence_enrollment.completed', array['enrollment.completed']::text[]),
  ('sequence_enrollment.created', array['enrollment.created']::text[]),
  ('sequence_enrollment.exited', array['enrollment.cancelled']::text[]),
  ('sequence_enrollment.paused', array['enrollment.paused']::text[]),
  ('sequence_enrollment.resumed', array['enrollment.resumed']::text[]),
  ('sequence_enrollment.step_completed', array['enrollment.step_completed']::text[]),
  ('signature.*', array['signature_request.*']::text[]),
  ('signature.cancelled', array['signature_request.cancelled']::text[]),
  ('signature.completed', array['signature_request.completed']::text[]),
  ('signature.declined', array['signature_request.declined']::text[]),
  ('signature.requested', array['signature_request.requested']::text[]),
  ('signature.signed', array['signature_request.signed']::text[]),
  ('support.*', array['support_session.*']::text[]),
  ('support.denied', array['support_session.denied']::text[]),
  ('support.ended', array['support_session.ended']::text[]),
  ('support.started', array['support_session.started']::text[]),
  ('time.*', array['time_entry.*']::text[]),
  ('time.invoiced', array['time_entry.invoiced']::text[]),
  ('variant.*', array['product_variant.*']::text[]),
  ('variant.created', array['product_variant.created']::text[]),
  ('variant.deleted', array['product_variant.deleted']::text[]),
  ('variant.updated', array['product_variant.updated']::text[]),
  ('waitlist.*', array['waitlist_entry.*']::text[]),
  ('waitlist.approved', array['waitlist_entry.approved']::text[]),
  ('waitlist.rejected', array['waitlist_entry.rejected']::text[]),
  ('webhook.*', array['webhook_endpoint.*']::text[]),
  ('webhook.delivered', array['webhook_endpoint.delivered']::text[]),
  ('webhook.disabled', array['webhook_endpoint.disabled']::text[]),
  ('webhook.failed', array['webhook_endpoint.failed']::text[]),
  ('webhook.secret_rotated', array['webhook_endpoint.secret_rotated']::text[]),
  ('work_item.*', array['task.*']::text[]),
  ('work_item.archived', array['task.archived']::text[]),
  ('work_item.assigned', array['task.assigned']::text[]),
  ('work_item.closed', array['task.closed']::text[]),
  ('work_item.created', array['task.created']::text[]),
  ('work_item.deleted', array['task.deleted']::text[]),
  ('work_item.reopened', array['task.reopened']::text[]),
  ('work_item.updated', array['task.updated']::text[]),
  ('workflow.*', array['workflow_definition.*']::text[]),
  ('workflow.published', array['workflow_definition.published']::text[])
)
update "better_supabase"."outbox_consumers" t set "types" = array(
  select distinct x from unnest(t."types" || array(
    select n from unnest(t."types") o join m on m.old_type = o
    cross join unnest(m.next_types) n
  )) x order by x
)
where t."types" && array(select old_type from m);

insert into better_supabase.blocks (name, version, mode)
values ('outbox', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_023_outbox.sql
-- better-supabase module: outbox
-- @bsb-block outbox@5 managed
-- @bsb-hash sha256:5651ad428234fb6c40d0517ec57e239e1a25bf90ac1935a26c7062c51755cd3f
-- Events written in the same transaction as the change, read by named consumers with their own cursor and lease, kept for history and relayed as CloudEvents.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."outbox_events";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."outbox_events";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."outbox_events";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."outbox_events";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."outbox_events";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

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
revoke all on "better_supabase"."outbox_events" from public, anon, authenticated;
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
revoke all on "better_supabase"."outbox_consumers" from public, anon, authenticated;
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
revoke all on "better_supabase"."outbox_dead_letters" from public, anon, authenticated;
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
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_purged integer;
begin
  with active as (
    select k."cursor_xid", k."cursor_position" from "better_supabase"."outbox_consumers" k
    where ignore_idle is null or k."updated_at" >= now() - ignore_idle
  ),
  letters as (
    delete from "better_supabase"."outbox_dead_letters" x
    where (x."dead_at" < now() - least(coalesce(older_than, '30 days'::interval), "better_supabase"."retention_floor"('outbox'))
      and x."dead_at" < now() - coalesce("better_supabase"."retention_for"('outbox', (null)::text), coalesce(older_than, '30 days'::interval))
      and not "better_supabase"."is_held"('outbox', (null)::text))
  ),
  gone as (
    delete from "better_supabase"."outbox_events" e
    where e."id" in (
      select d."id" from "better_supabase"."outbox_events" d
      where (d."created_at" < now() - least(coalesce(older_than, '30 days'::interval), "better_supabase"."retention_floor"('outbox'))
      and d."created_at" < now() - coalesce("better_supabase"."retention_for"('outbox', (d."organization_id")::text), coalesce(older_than, '30 days'::interval))
      and not "better_supabase"."is_held"('outbox', (d."organization_id")::text))
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
  select count(*)::integer into v_purged from gone;
  return v_purged;
end;
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
revoke execute on function "better_supabase"."outbox_row_event"() from public, anon, authenticated;

create or replace function "better_supabase"."track_events"(target regclass, type_prefix text default null, tenant_column text default null)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists "bsb_outbox_events" on %s', target);
  execute format('drop trigger if exists "bsb_outbox_events_update" on %s', target);
  execute format(
    'create trigger "bsb_outbox_events" after insert or delete on %s for each row execute function "better_supabase"."outbox_row_event"(%L, %L)',
    target, coalesce(type_prefix, ''), coalesce(tenant_column, '')
  );
  -- jsonb, not the row: a row comparison fails on columns without equality (json).
  execute format(
    'create trigger "bsb_outbox_events_update" after update on %s for each row when (to_jsonb(old) is distinct from to_jsonb(new)) execute function "better_supabase"."outbox_row_event"(%L, %L)',
    target, coalesce(type_prefix, ''), coalesce(tenant_column, '')
  );
end;
$$;
revoke execute on function "better_supabase"."track_events"(regclass, text, text) from public, anon, authenticated;

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_023_outbox.sql
-- better-supabase module: outbox
-- @bsb-block-data outbox
-- @bsb-hash sha256:5acf345602c65fa5d8b14b27584db06d6781e8b7baa395bf3edb3a329343acee
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Event types renamed by the 0.47 naming convention (ADR 0130).
update "better_supabase"."outbox_events" t set "type" = m.next_type
from (values
  ('access.ended', 'access_request.ended'),
  ('access.request_approved', 'access_request.approved'),
  ('access.requested', 'access_request.requested'),
  ('ai_tool_policy.set', 'ai_tool_policy.updated'),
  ('approval_policy.removed', 'approval_policy.deleted'),
  ('compliance_policy.acknowledged', 'acknowledgement.created'),
  ('credential.set', 'credential.updated'),
  ('custom_field.deleted', 'field_definition.deleted'),
  ('drive.node_created', 'drive_node.created'),
  ('drive.node_document_saved', 'drive_node.document_saved'),
  ('drive.node_download_blocked_changed', 'drive_node.download_blocked_changed'),
  ('drive.node_hold_placed', 'drive_node.hold_placed'),
  ('drive.node_hold_released', 'drive_node.hold_released'),
  ('drive.node_locked', 'drive_node.locked'),
  ('drive.node_moved', 'drive_node.moved'),
  ('drive.node_obsoleted', 'drive_node.obsoleted'),
  ('drive.node_ownership_transferred', 'drive_node.ownership_transferred'),
  ('drive.node_purged', 'drive_node.purged'),
  ('drive.node_released', 'drive_node.released'),
  ('drive.node_renamed', 'drive_node.renamed'),
  ('drive.node_review_requested', 'drive_node.review_requested'),
  ('drive.node_reviewed', 'drive_node.reviewed'),
  ('drive.node_shared', 'drive_node.shared'),
  ('drive.node_submitted', 'drive_node.submitted'),
  ('drive.node_unlocked', 'drive_node.unlocked'),
  ('drive.node_unshared', 'drive_node.unshared'),
  ('engagement.amended', 'activity.amended'),
  ('engagement.completed', 'activity.completed'),
  ('engagement.deleted', 'activity.deleted'),
  ('engagement.error_marked', 'activity.error_marked'),
  ('engagement.logged', 'activity.logged'),
  ('engagement.recorded', 'activity.recorded'),
  ('engagement.summarized', 'activity.summarized'),
  ('engagement.transcribed', 'activity.transcribed'),
  ('engagement.updated', 'activity.updated'),
  ('flag.override_set', 'flag.override_changed'),
  ('forecast.snapshotted', 'forecast_snapshot.created'),
  ('hostname.primary_set', 'hostname.primary_changed'),
  ('hostname.removed', 'hostname.deleted'),
  ('incoming_webhook.enabled_set', 'incoming_webhook.enabled_changed'),
  ('job.closed', 'job_opening.closed'),
  ('job.opened', 'job_opening.opened'),
  ('leave.adjusted', 'leave_balance.adjusted'),
  ('leave.approved', 'leave_request.approved'),
  ('leave.cancelled', 'leave_request.cancelled'),
  ('leave.rejected', 'leave_request.rejected'),
  ('leave.requested', 'leave_request.requested'),
  ('leave.split', 'leave_request.split'),
  ('leave.updated', 'leave_request.updated'),
  ('marketplace_installation.removed', 'marketplace_installation.deleted'),
  ('marketplace_invoice.state_changed', 'marketplace_invoice.status_changed'),
  ('obligation.status_changed', 'contract_obligation.status_changed'),
  ('organization.domain_added', 'sso_domain.created'),
  ('organization.domain_removed', 'sso_domain.deleted'),
  ('organization.domain_updated', 'sso_domain.updated'),
  ('organization.domain_verified', 'sso_domain.verified'),
  ('policy.acknowledged', 'acknowledgement.created'),
  ('policy.published', 'compliance_policy.published'),
  ('postmortem.published', 'incident_postmortem.published'),
  ('rule.disabled', 'automation.disabled'),
  ('rule.enabled', 'automation.enabled'),
  ('rule.matched', 'automation.matched'),
  ('rule.removed', 'automation.deleted'),
  ('segment.removed', 'segment.deleted'),
  ('sequence_enrollment.completed', 'enrollment.completed'),
  ('sequence_enrollment.created', 'enrollment.created'),
  ('sequence_enrollment.exited', 'enrollment.cancelled'),
  ('sequence_enrollment.paused', 'enrollment.paused'),
  ('sequence_enrollment.resumed', 'enrollment.resumed'),
  ('sequence_enrollment.step_completed', 'enrollment.step_completed'),
  ('signature.cancelled', 'signature_request.cancelled'),
  ('signature.completed', 'signature_request.completed'),
  ('signature.declined', 'signature_request.declined'),
  ('signature.requested', 'signature_request.requested'),
  ('signature.signed', 'signature_request.signed'),
  ('support.denied', 'support_session.denied'),
  ('support.ended', 'support_session.ended'),
  ('support.started', 'support_session.started'),
  ('time.invoiced', 'time_entry.invoiced'),
  ('variant.created', 'product_variant.created'),
  ('variant.deleted', 'product_variant.deleted'),
  ('variant.updated', 'product_variant.updated'),
  ('waitlist.approved', 'waitlist_entry.approved'),
  ('waitlist.rejected', 'waitlist_entry.rejected'),
  ('webhook.delivered', 'webhook_endpoint.delivered'),
  ('webhook.disabled', 'webhook_endpoint.disabled'),
  ('webhook.failed', 'webhook_endpoint.failed'),
  ('webhook.secret_rotated', 'webhook_endpoint.secret_rotated'),
  ('work_item.archived', 'task.archived'),
  ('work_item.assigned', 'task.assigned'),
  ('work_item.closed', 'task.closed'),
  ('work_item.created', 'task.created'),
  ('work_item.deleted', 'task.deleted'),
  ('work_item.reopened', 'task.reopened'),
  ('work_item.updated', 'task.updated'),
  ('workflow.published', 'workflow_definition.published')
) as m(old_type, next_type)
where t."type" = m.old_type;

update "better_supabase"."outbox_dead_letters" t set "type" = m.next_type
from (values
  ('access.ended', 'access_request.ended'),
  ('access.request_approved', 'access_request.approved'),
  ('access.requested', 'access_request.requested'),
  ('ai_tool_policy.set', 'ai_tool_policy.updated'),
  ('approval_policy.removed', 'approval_policy.deleted'),
  ('compliance_policy.acknowledged', 'acknowledgement.created'),
  ('credential.set', 'credential.updated'),
  ('custom_field.deleted', 'field_definition.deleted'),
  ('drive.node_created', 'drive_node.created'),
  ('drive.node_document_saved', 'drive_node.document_saved'),
  ('drive.node_download_blocked_changed', 'drive_node.download_blocked_changed'),
  ('drive.node_hold_placed', 'drive_node.hold_placed'),
  ('drive.node_hold_released', 'drive_node.hold_released'),
  ('drive.node_locked', 'drive_node.locked'),
  ('drive.node_moved', 'drive_node.moved'),
  ('drive.node_obsoleted', 'drive_node.obsoleted'),
  ('drive.node_ownership_transferred', 'drive_node.ownership_transferred'),
  ('drive.node_purged', 'drive_node.purged'),
  ('drive.node_released', 'drive_node.released'),
  ('drive.node_renamed', 'drive_node.renamed'),
  ('drive.node_review_requested', 'drive_node.review_requested'),
  ('drive.node_reviewed', 'drive_node.reviewed'),
  ('drive.node_shared', 'drive_node.shared'),
  ('drive.node_submitted', 'drive_node.submitted'),
  ('drive.node_unlocked', 'drive_node.unlocked'),
  ('drive.node_unshared', 'drive_node.unshared'),
  ('engagement.amended', 'activity.amended'),
  ('engagement.completed', 'activity.completed'),
  ('engagement.deleted', 'activity.deleted'),
  ('engagement.error_marked', 'activity.error_marked'),
  ('engagement.logged', 'activity.logged'),
  ('engagement.recorded', 'activity.recorded'),
  ('engagement.summarized', 'activity.summarized'),
  ('engagement.transcribed', 'activity.transcribed'),
  ('engagement.updated', 'activity.updated'),
  ('flag.override_set', 'flag.override_changed'),
  ('forecast.snapshotted', 'forecast_snapshot.created'),
  ('hostname.primary_set', 'hostname.primary_changed'),
  ('hostname.removed', 'hostname.deleted'),
  ('incoming_webhook.enabled_set', 'incoming_webhook.enabled_changed'),
  ('job.closed', 'job_opening.closed'),
  ('job.opened', 'job_opening.opened'),
  ('leave.adjusted', 'leave_balance.adjusted'),
  ('leave.approved', 'leave_request.approved'),
  ('leave.cancelled', 'leave_request.cancelled'),
  ('leave.rejected', 'leave_request.rejected'),
  ('leave.requested', 'leave_request.requested'),
  ('leave.split', 'leave_request.split'),
  ('leave.updated', 'leave_request.updated'),
  ('marketplace_installation.removed', 'marketplace_installation.deleted'),
  ('marketplace_invoice.state_changed', 'marketplace_invoice.status_changed'),
  ('obligation.status_changed', 'contract_obligation.status_changed'),
  ('organization.domain_added', 'sso_domain.created'),
  ('organization.domain_removed', 'sso_domain.deleted'),
  ('organization.domain_updated', 'sso_domain.updated'),
  ('organization.domain_verified', 'sso_domain.verified'),
  ('policy.acknowledged', 'acknowledgement.created'),
  ('policy.published', 'compliance_policy.published'),
  ('postmortem.published', 'incident_postmortem.published'),
  ('rule.disabled', 'automation.disabled'),
  ('rule.enabled', 'automation.enabled'),
  ('rule.matched', 'automation.matched'),
  ('rule.removed', 'automation.deleted'),
  ('segment.removed', 'segment.deleted'),
  ('sequence_enrollment.completed', 'enrollment.completed'),
  ('sequence_enrollment.created', 'enrollment.created'),
  ('sequence_enrollment.exited', 'enrollment.cancelled'),
  ('sequence_enrollment.paused', 'enrollment.paused'),
  ('sequence_enrollment.resumed', 'enrollment.resumed'),
  ('sequence_enrollment.step_completed', 'enrollment.step_completed'),
  ('signature.cancelled', 'signature_request.cancelled'),
  ('signature.completed', 'signature_request.completed'),
  ('signature.declined', 'signature_request.declined'),
  ('signature.requested', 'signature_request.requested'),
  ('signature.signed', 'signature_request.signed'),
  ('support.denied', 'support_session.denied'),
  ('support.ended', 'support_session.ended'),
  ('support.started', 'support_session.started'),
  ('time.invoiced', 'time_entry.invoiced'),
  ('variant.created', 'product_variant.created'),
  ('variant.deleted', 'product_variant.deleted'),
  ('variant.updated', 'product_variant.updated'),
  ('waitlist.approved', 'waitlist_entry.approved'),
  ('waitlist.rejected', 'waitlist_entry.rejected'),
  ('webhook.delivered', 'webhook_endpoint.delivered'),
  ('webhook.disabled', 'webhook_endpoint.disabled'),
  ('webhook.failed', 'webhook_endpoint.failed'),
  ('webhook.secret_rotated', 'webhook_endpoint.secret_rotated'),
  ('work_item.archived', 'task.archived'),
  ('work_item.assigned', 'task.assigned'),
  ('work_item.closed', 'task.closed'),
  ('work_item.created', 'task.created'),
  ('work_item.deleted', 'task.deleted'),
  ('work_item.reopened', 'task.reopened'),
  ('work_item.updated', 'task.updated'),
  ('workflow.published', 'workflow_definition.published')
) as m(old_type, next_type)
where t."type" = m.old_type;

with m(old_type, next_types) as (values
  ('access.*', array['access_request.*']::text[]),
  ('access.ended', array['access_request.ended']::text[]),
  ('access.request_approved', array['access_request.approved']::text[]),
  ('access.requested', array['access_request.requested']::text[]),
  ('agent.saved', array['agent.created', 'agent.updated']::text[]),
  ('ai_provider_key.saved', array['ai_provider_key.created', 'ai_provider_key.updated']::text[]),
  ('ai_tool_policy.set', array['ai_tool_policy.updated']::text[]),
  ('announcement.saved', array['announcement.created', 'announcement.updated']::text[]),
  ('approval_policy.removed', array['approval_policy.deleted']::text[]),
  ('approval_policy.saved', array['approval_policy.created', 'approval_policy.updated']::text[]),
  ('compliance_policy.acknowledged', array['acknowledgement.created']::text[]),
  ('connector.saved', array['connector.created', 'connector.updated']::text[]),
  ('control.saved', array['control.created', 'control.updated']::text[]),
  ('course.saved', array['course.created', 'course.updated']::text[]),
  ('credential.set', array['credential.updated']::text[]),
  ('custom_field.*', array['field_definition.*']::text[]),
  ('custom_field.deleted', array['field_definition.deleted']::text[]),
  ('custom_field.saved', array['field_definition.created', 'field_definition.updated']::text[]),
  ('drive.*', array['drive_node.*']::text[]),
  ('drive.node_created', array['drive_node.created']::text[]),
  ('drive.node_document_saved', array['drive_node.document_saved']::text[]),
  ('drive.node_download_blocked_changed', array['drive_node.download_blocked_changed']::text[]),
  ('drive.node_hold_placed', array['drive_node.hold_placed']::text[]),
  ('drive.node_hold_released', array['drive_node.hold_released']::text[]),
  ('drive.node_locked', array['drive_node.locked']::text[]),
  ('drive.node_moved', array['drive_node.moved']::text[]),
  ('drive.node_obsoleted', array['drive_node.obsoleted']::text[]),
  ('drive.node_ownership_transferred', array['drive_node.ownership_transferred']::text[]),
  ('drive.node_purged', array['drive_node.purged']::text[]),
  ('drive.node_released', array['drive_node.released']::text[]),
  ('drive.node_renamed', array['drive_node.renamed']::text[]),
  ('drive.node_review_requested', array['drive_node.review_requested']::text[]),
  ('drive.node_reviewed', array['drive_node.reviewed']::text[]),
  ('drive.node_shared', array['drive_node.shared']::text[]),
  ('drive.node_submitted', array['drive_node.submitted']::text[]),
  ('drive.node_unlocked', array['drive_node.unlocked']::text[]),
  ('drive.node_unshared', array['drive_node.unshared']::text[]),
  ('engagement.*', array['activity.*']::text[]),
  ('engagement.amended', array['activity.amended']::text[]),
  ('engagement.completed', array['activity.completed']::text[]),
  ('engagement.deleted', array['activity.deleted']::text[]),
  ('engagement.error_marked', array['activity.error_marked']::text[]),
  ('engagement.logged', array['activity.logged']::text[]),
  ('engagement.recorded', array['activity.recorded']::text[]),
  ('engagement.summarized', array['activity.summarized']::text[]),
  ('engagement.transcribed', array['activity.transcribed']::text[]),
  ('engagement.updated', array['activity.updated']::text[]),
  ('enrollment_program.saved', array['enrollment_program.created', 'enrollment_program.updated']::text[]),
  ('flag.override_set', array['flag.override_changed']::text[]),
  ('flag.saved', array['flag.created', 'flag.updated']::text[]),
  ('forecast.*', array['forecast_snapshot.*']::text[]),
  ('forecast.snapshotted', array['forecast_snapshot.created']::text[]),
  ('hostname.primary_set', array['hostname.primary_changed']::text[]),
  ('hostname.removed', array['hostname.deleted']::text[]),
  ('incoming_webhook.enabled_set', array['incoming_webhook.enabled_changed']::text[]),
  ('job.*', array['job_opening.*']::text[]),
  ('job.closed', array['job_opening.closed']::text[]),
  ('job.opened', array['job_opening.opened']::text[]),
  ('leave.*', array['leave_request.*', 'leave_balance.*']::text[]),
  ('leave.adjusted', array['leave_balance.adjusted']::text[]),
  ('leave.approved', array['leave_request.approved']::text[]),
  ('leave.cancelled', array['leave_request.cancelled']::text[]),
  ('leave.rejected', array['leave_request.rejected']::text[]),
  ('leave.requested', array['leave_request.requested']::text[]),
  ('leave.split', array['leave_request.split']::text[]),
  ('leave.updated', array['leave_request.updated']::text[]),
  ('marketplace_installation.removed', array['marketplace_installation.deleted']::text[]),
  ('marketplace_installation.upserted', array['marketplace_installation.created', 'marketplace_installation.updated']::text[]),
  ('marketplace_invoice.state_changed', array['marketplace_invoice.status_changed']::text[]),
  ('obligation.*', array['contract_obligation.*']::text[]),
  ('obligation.saved', array['contract_obligation.created', 'contract_obligation.updated']::text[]),
  ('obligation.status_changed', array['contract_obligation.status_changed']::text[]),
  ('organization.*', array['sso_domain.*']::text[]),
  ('organization.domain_added', array['sso_domain.created']::text[]),
  ('organization.domain_removed', array['sso_domain.deleted']::text[]),
  ('organization.domain_updated', array['sso_domain.updated']::text[]),
  ('organization.domain_verified', array['sso_domain.verified']::text[]),
  ('party.*', array['company.enriched', 'person.enriched']::text[]),
  ('party.enriched', array['company.enriched', 'person.enriched']::text[]),
  ('pipeline_stage.saved', array['pipeline_stage.created', 'pipeline_stage.updated']::text[]),
  ('policy.*', array['compliance_policy.*']::text[]),
  ('policy.acknowledged', array['acknowledgement.created']::text[]),
  ('policy.published', array['compliance_policy.published']::text[]),
  ('post_board.saved', array['post_board.created', 'post_board.updated']::text[]),
  ('postmortem.*', array['incident_postmortem.*']::text[]),
  ('postmortem.published', array['incident_postmortem.published']::text[]),
  ('rule.*', array['automation.*']::text[]),
  ('rule.disabled', array['automation.disabled']::text[]),
  ('rule.enabled', array['automation.enabled']::text[]),
  ('rule.matched', array['automation.matched']::text[]),
  ('rule.removed', array['automation.deleted']::text[]),
  ('rule.saved', array['automation.created', 'automation.updated']::text[]),
  ('saved_view.saved', array['saved_view.created', 'saved_view.updated']::text[]),
  ('scim_group.saved', array['scim_group.created', 'scim_group.updated']::text[]),
  ('scim_user.saved', array['scim_user.created', 'scim_user.updated']::text[]),
  ('score_model.saved', array['score_model.created', 'score_model.updated']::text[]),
  ('segment.removed', array['segment.deleted']::text[]),
  ('segment.saved', array['segment.created', 'segment.updated']::text[]),
  ('sequence.saved', array['sequence.created', 'sequence.updated']::text[]),
  ('sequence_enrollment.*', array['enrollment.*']::text[]),
  ('sequence_enrollment.completed', array['enrollment.completed']::text[]),
  ('sequence_enrollment.created', array['enrollment.created']::text[]),
  ('sequence_enrollment.exited', array['enrollment.cancelled']::text[]),
  ('sequence_enrollment.paused', array['enrollment.paused']::text[]),
  ('sequence_enrollment.resumed', array['enrollment.resumed']::text[]),
  ('sequence_enrollment.step_completed', array['enrollment.step_completed']::text[]),
  ('signature.*', array['signature_request.*']::text[]),
  ('signature.cancelled', array['signature_request.cancelled']::text[]),
  ('signature.completed', array['signature_request.completed']::text[]),
  ('signature.declined', array['signature_request.declined']::text[]),
  ('signature.requested', array['signature_request.requested']::text[]),
  ('signature.signed', array['signature_request.signed']::text[]),
  ('support.*', array['support_session.*']::text[]),
  ('support.denied', array['support_session.denied']::text[]),
  ('support.ended', array['support_session.ended']::text[]),
  ('support.started', array['support_session.started']::text[]),
  ('time.*', array['time_entry.*']::text[]),
  ('time.invoiced', array['time_entry.invoiced']::text[]),
  ('variant.*', array['product_variant.*']::text[]),
  ('variant.created', array['product_variant.created']::text[]),
  ('variant.deleted', array['product_variant.deleted']::text[]),
  ('variant.updated', array['product_variant.updated']::text[]),
  ('waitlist.*', array['waitlist_entry.*']::text[]),
  ('waitlist.approved', array['waitlist_entry.approved']::text[]),
  ('waitlist.rejected', array['waitlist_entry.rejected']::text[]),
  ('webhook.*', array['webhook_endpoint.*']::text[]),
  ('webhook.delivered', array['webhook_endpoint.delivered']::text[]),
  ('webhook.disabled', array['webhook_endpoint.disabled']::text[]),
  ('webhook.failed', array['webhook_endpoint.failed']::text[]),
  ('webhook.secret_rotated', array['webhook_endpoint.secret_rotated']::text[]),
  ('work_item.*', array['task.*']::text[]),
  ('work_item.archived', array['task.archived']::text[]),
  ('work_item.assigned', array['task.assigned']::text[]),
  ('work_item.closed', array['task.closed']::text[]),
  ('work_item.created', array['task.created']::text[]),
  ('work_item.deleted', array['task.deleted']::text[]),
  ('work_item.reopened', array['task.reopened']::text[]),
  ('work_item.updated', array['task.updated']::text[]),
  ('workflow.*', array['workflow_definition.*']::text[]),
  ('workflow.published', array['workflow_definition.published']::text[])
)
update "better_supabase"."outbox_consumers" t set "types" = array(
  select distinct x from unnest(t."types" || array(
    select n from unnest(t."types") o join m on m.old_type = o
    cross join unnest(m.next_types) n
  )) x order by x
)
where t."types" && array(select old_type from m);

insert into better_supabase.blocks (name, version, mode)
values ('outbox', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_023_outbox.sql
-- better-supabase module: outbox
-- @bsb-block outbox@5 managed
-- @bsb-hash sha256:ca0799e4a1e82c8044a2e8f53296e85e3e6e6d114aed5657aba3ee6255bc079d
-- Events written in the same transaction as the change, read by named consumers with their own cursor and lease, kept for history and relayed as CloudEvents.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."outbox_events";
    drop policy if exists bsb_tenant_scope_select on "app_private"."outbox_events";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."outbox_events";
    drop policy if exists bsb_tenant_scope_update on "app_private"."outbox_events";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."outbox_events";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
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
revoke all on "app_private"."outbox_events" from public, anon, authenticated;
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
revoke all on "app_private"."outbox_consumers" from public, anon, authenticated;
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
revoke all on "app_private"."outbox_dead_letters" from public, anon, authenticated;
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
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_purged integer;
begin
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
  select count(*)::integer into v_purged from gone;
  return v_purged;
end;
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
revoke execute on function "app_private"."outbox_row_event"() from public, anon, authenticated;

create or replace function "app_private"."track_events"(target regclass, type_prefix text default null, tenant_column text default null)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists "bsb_outbox_events" on %s', target);
  execute format('drop trigger if exists "bsb_outbox_events_update" on %s', target);
  execute format(
    'create trigger "bsb_outbox_events" after insert or delete on %s for each row execute function "app_private"."outbox_row_event"(%L, %L)',
    target, coalesce(type_prefix, ''), coalesce(tenant_column, '')
  );
  -- jsonb, not the row: a row comparison fails on columns without equality (json).
  execute format(
    'create trigger "bsb_outbox_events_update" after update on %s for each row when (to_jsonb(old) is distinct from to_jsonb(new)) execute function "app_private"."outbox_row_event"(%L, %L)',
    target, coalesce(type_prefix, ''), coalesce(tenant_column, '')
  );
end;
$$;
revoke execute on function "app_private"."track_events"(regclass, text, text) from public, anon, authenticated;

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_023_outbox.sql
-- better-supabase module: outbox
-- @bsb-block-data outbox
-- @bsb-hash sha256:5534162a04667e4ba3b3dc783cd84702845415884621ec2c9437f25351f7f615
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Event types renamed by the 0.47 naming convention (ADR 0130).
update "app_private"."outbox_events" t set "type" = m.next_type
from (values
  ('access.ended', 'access_request.ended'),
  ('access.request_approved', 'access_request.approved'),
  ('access.requested', 'access_request.requested'),
  ('ai_tool_policy.set', 'ai_tool_policy.updated'),
  ('approval_policy.removed', 'approval_policy.deleted'),
  ('compliance_policy.acknowledged', 'acknowledgement.created'),
  ('credential.set', 'credential.updated'),
  ('custom_field.deleted', 'field_definition.deleted'),
  ('drive.node_created', 'drive_node.created'),
  ('drive.node_document_saved', 'drive_node.document_saved'),
  ('drive.node_download_blocked_changed', 'drive_node.download_blocked_changed'),
  ('drive.node_hold_placed', 'drive_node.hold_placed'),
  ('drive.node_hold_released', 'drive_node.hold_released'),
  ('drive.node_locked', 'drive_node.locked'),
  ('drive.node_moved', 'drive_node.moved'),
  ('drive.node_obsoleted', 'drive_node.obsoleted'),
  ('drive.node_ownership_transferred', 'drive_node.ownership_transferred'),
  ('drive.node_purged', 'drive_node.purged'),
  ('drive.node_released', 'drive_node.released'),
  ('drive.node_renamed', 'drive_node.renamed'),
  ('drive.node_review_requested', 'drive_node.review_requested'),
  ('drive.node_reviewed', 'drive_node.reviewed'),
  ('drive.node_shared', 'drive_node.shared'),
  ('drive.node_submitted', 'drive_node.submitted'),
  ('drive.node_unlocked', 'drive_node.unlocked'),
  ('drive.node_unshared', 'drive_node.unshared'),
  ('engagement.amended', 'activity.amended'),
  ('engagement.completed', 'activity.completed'),
  ('engagement.deleted', 'activity.deleted'),
  ('engagement.error_marked', 'activity.error_marked'),
  ('engagement.logged', 'activity.logged'),
  ('engagement.recorded', 'activity.recorded'),
  ('engagement.summarized', 'activity.summarized'),
  ('engagement.transcribed', 'activity.transcribed'),
  ('engagement.updated', 'activity.updated'),
  ('flag.override_set', 'flag.override_changed'),
  ('forecast.snapshotted', 'forecast_snapshot.created'),
  ('hostname.primary_set', 'hostname.primary_changed'),
  ('hostname.removed', 'hostname.deleted'),
  ('incoming_webhook.enabled_set', 'incoming_webhook.enabled_changed'),
  ('job.closed', 'job_opening.closed'),
  ('job.opened', 'job_opening.opened'),
  ('leave.adjusted', 'leave_balance.adjusted'),
  ('leave.approved', 'leave_request.approved'),
  ('leave.cancelled', 'leave_request.cancelled'),
  ('leave.rejected', 'leave_request.rejected'),
  ('leave.requested', 'leave_request.requested'),
  ('leave.split', 'leave_request.split'),
  ('leave.updated', 'leave_request.updated'),
  ('marketplace_installation.removed', 'marketplace_installation.deleted'),
  ('marketplace_invoice.state_changed', 'marketplace_invoice.status_changed'),
  ('obligation.status_changed', 'contract_obligation.status_changed'),
  ('organization.domain_added', 'sso_domain.created'),
  ('organization.domain_removed', 'sso_domain.deleted'),
  ('organization.domain_updated', 'sso_domain.updated'),
  ('organization.domain_verified', 'sso_domain.verified'),
  ('policy.acknowledged', 'acknowledgement.created'),
  ('policy.published', 'compliance_policy.published'),
  ('postmortem.published', 'incident_postmortem.published'),
  ('rule.disabled', 'automation.disabled'),
  ('rule.enabled', 'automation.enabled'),
  ('rule.matched', 'automation.matched'),
  ('rule.removed', 'automation.deleted'),
  ('segment.removed', 'segment.deleted'),
  ('sequence_enrollment.completed', 'enrollment.completed'),
  ('sequence_enrollment.created', 'enrollment.created'),
  ('sequence_enrollment.exited', 'enrollment.cancelled'),
  ('sequence_enrollment.paused', 'enrollment.paused'),
  ('sequence_enrollment.resumed', 'enrollment.resumed'),
  ('sequence_enrollment.step_completed', 'enrollment.step_completed'),
  ('signature.cancelled', 'signature_request.cancelled'),
  ('signature.completed', 'signature_request.completed'),
  ('signature.declined', 'signature_request.declined'),
  ('signature.requested', 'signature_request.requested'),
  ('signature.signed', 'signature_request.signed'),
  ('support.denied', 'support_session.denied'),
  ('support.ended', 'support_session.ended'),
  ('support.started', 'support_session.started'),
  ('time.invoiced', 'time_entry.invoiced'),
  ('variant.created', 'product_variant.created'),
  ('variant.deleted', 'product_variant.deleted'),
  ('variant.updated', 'product_variant.updated'),
  ('waitlist.approved', 'waitlist_entry.approved'),
  ('waitlist.rejected', 'waitlist_entry.rejected'),
  ('webhook.delivered', 'webhook_endpoint.delivered'),
  ('webhook.disabled', 'webhook_endpoint.disabled'),
  ('webhook.failed', 'webhook_endpoint.failed'),
  ('webhook.secret_rotated', 'webhook_endpoint.secret_rotated'),
  ('work_item.archived', 'task.archived'),
  ('work_item.assigned', 'task.assigned'),
  ('work_item.closed', 'task.closed'),
  ('work_item.created', 'task.created'),
  ('work_item.deleted', 'task.deleted'),
  ('work_item.reopened', 'task.reopened'),
  ('work_item.updated', 'task.updated'),
  ('workflow.published', 'workflow_definition.published')
) as m(old_type, next_type)
where t."type" = m.old_type;

update "app_private"."outbox_dead_letters" t set "type" = m.next_type
from (values
  ('access.ended', 'access_request.ended'),
  ('access.request_approved', 'access_request.approved'),
  ('access.requested', 'access_request.requested'),
  ('ai_tool_policy.set', 'ai_tool_policy.updated'),
  ('approval_policy.removed', 'approval_policy.deleted'),
  ('compliance_policy.acknowledged', 'acknowledgement.created'),
  ('credential.set', 'credential.updated'),
  ('custom_field.deleted', 'field_definition.deleted'),
  ('drive.node_created', 'drive_node.created'),
  ('drive.node_document_saved', 'drive_node.document_saved'),
  ('drive.node_download_blocked_changed', 'drive_node.download_blocked_changed'),
  ('drive.node_hold_placed', 'drive_node.hold_placed'),
  ('drive.node_hold_released', 'drive_node.hold_released'),
  ('drive.node_locked', 'drive_node.locked'),
  ('drive.node_moved', 'drive_node.moved'),
  ('drive.node_obsoleted', 'drive_node.obsoleted'),
  ('drive.node_ownership_transferred', 'drive_node.ownership_transferred'),
  ('drive.node_purged', 'drive_node.purged'),
  ('drive.node_released', 'drive_node.released'),
  ('drive.node_renamed', 'drive_node.renamed'),
  ('drive.node_review_requested', 'drive_node.review_requested'),
  ('drive.node_reviewed', 'drive_node.reviewed'),
  ('drive.node_shared', 'drive_node.shared'),
  ('drive.node_submitted', 'drive_node.submitted'),
  ('drive.node_unlocked', 'drive_node.unlocked'),
  ('drive.node_unshared', 'drive_node.unshared'),
  ('engagement.amended', 'activity.amended'),
  ('engagement.completed', 'activity.completed'),
  ('engagement.deleted', 'activity.deleted'),
  ('engagement.error_marked', 'activity.error_marked'),
  ('engagement.logged', 'activity.logged'),
  ('engagement.recorded', 'activity.recorded'),
  ('engagement.summarized', 'activity.summarized'),
  ('engagement.transcribed', 'activity.transcribed'),
  ('engagement.updated', 'activity.updated'),
  ('flag.override_set', 'flag.override_changed'),
  ('forecast.snapshotted', 'forecast_snapshot.created'),
  ('hostname.primary_set', 'hostname.primary_changed'),
  ('hostname.removed', 'hostname.deleted'),
  ('incoming_webhook.enabled_set', 'incoming_webhook.enabled_changed'),
  ('job.closed', 'job_opening.closed'),
  ('job.opened', 'job_opening.opened'),
  ('leave.adjusted', 'leave_balance.adjusted'),
  ('leave.approved', 'leave_request.approved'),
  ('leave.cancelled', 'leave_request.cancelled'),
  ('leave.rejected', 'leave_request.rejected'),
  ('leave.requested', 'leave_request.requested'),
  ('leave.split', 'leave_request.split'),
  ('leave.updated', 'leave_request.updated'),
  ('marketplace_installation.removed', 'marketplace_installation.deleted'),
  ('marketplace_invoice.state_changed', 'marketplace_invoice.status_changed'),
  ('obligation.status_changed', 'contract_obligation.status_changed'),
  ('organization.domain_added', 'sso_domain.created'),
  ('organization.domain_removed', 'sso_domain.deleted'),
  ('organization.domain_updated', 'sso_domain.updated'),
  ('organization.domain_verified', 'sso_domain.verified'),
  ('policy.acknowledged', 'acknowledgement.created'),
  ('policy.published', 'compliance_policy.published'),
  ('postmortem.published', 'incident_postmortem.published'),
  ('rule.disabled', 'automation.disabled'),
  ('rule.enabled', 'automation.enabled'),
  ('rule.matched', 'automation.matched'),
  ('rule.removed', 'automation.deleted'),
  ('segment.removed', 'segment.deleted'),
  ('sequence_enrollment.completed', 'enrollment.completed'),
  ('sequence_enrollment.created', 'enrollment.created'),
  ('sequence_enrollment.exited', 'enrollment.cancelled'),
  ('sequence_enrollment.paused', 'enrollment.paused'),
  ('sequence_enrollment.resumed', 'enrollment.resumed'),
  ('sequence_enrollment.step_completed', 'enrollment.step_completed'),
  ('signature.cancelled', 'signature_request.cancelled'),
  ('signature.completed', 'signature_request.completed'),
  ('signature.declined', 'signature_request.declined'),
  ('signature.requested', 'signature_request.requested'),
  ('signature.signed', 'signature_request.signed'),
  ('support.denied', 'support_session.denied'),
  ('support.ended', 'support_session.ended'),
  ('support.started', 'support_session.started'),
  ('time.invoiced', 'time_entry.invoiced'),
  ('variant.created', 'product_variant.created'),
  ('variant.deleted', 'product_variant.deleted'),
  ('variant.updated', 'product_variant.updated'),
  ('waitlist.approved', 'waitlist_entry.approved'),
  ('waitlist.rejected', 'waitlist_entry.rejected'),
  ('webhook.delivered', 'webhook_endpoint.delivered'),
  ('webhook.disabled', 'webhook_endpoint.disabled'),
  ('webhook.failed', 'webhook_endpoint.failed'),
  ('webhook.secret_rotated', 'webhook_endpoint.secret_rotated'),
  ('work_item.archived', 'task.archived'),
  ('work_item.assigned', 'task.assigned'),
  ('work_item.closed', 'task.closed'),
  ('work_item.created', 'task.created'),
  ('work_item.deleted', 'task.deleted'),
  ('work_item.reopened', 'task.reopened'),
  ('work_item.updated', 'task.updated'),
  ('workflow.published', 'workflow_definition.published')
) as m(old_type, next_type)
where t."type" = m.old_type;

with m(old_type, next_types) as (values
  ('access.*', array['access_request.*']::text[]),
  ('access.ended', array['access_request.ended']::text[]),
  ('access.request_approved', array['access_request.approved']::text[]),
  ('access.requested', array['access_request.requested']::text[]),
  ('agent.saved', array['agent.created', 'agent.updated']::text[]),
  ('ai_provider_key.saved', array['ai_provider_key.created', 'ai_provider_key.updated']::text[]),
  ('ai_tool_policy.set', array['ai_tool_policy.updated']::text[]),
  ('announcement.saved', array['announcement.created', 'announcement.updated']::text[]),
  ('approval_policy.removed', array['approval_policy.deleted']::text[]),
  ('approval_policy.saved', array['approval_policy.created', 'approval_policy.updated']::text[]),
  ('compliance_policy.acknowledged', array['acknowledgement.created']::text[]),
  ('connector.saved', array['connector.created', 'connector.updated']::text[]),
  ('control.saved', array['control.created', 'control.updated']::text[]),
  ('course.saved', array['course.created', 'course.updated']::text[]),
  ('credential.set', array['credential.updated']::text[]),
  ('custom_field.*', array['field_definition.*']::text[]),
  ('custom_field.deleted', array['field_definition.deleted']::text[]),
  ('custom_field.saved', array['field_definition.created', 'field_definition.updated']::text[]),
  ('drive.*', array['drive_node.*']::text[]),
  ('drive.node_created', array['drive_node.created']::text[]),
  ('drive.node_document_saved', array['drive_node.document_saved']::text[]),
  ('drive.node_download_blocked_changed', array['drive_node.download_blocked_changed']::text[]),
  ('drive.node_hold_placed', array['drive_node.hold_placed']::text[]),
  ('drive.node_hold_released', array['drive_node.hold_released']::text[]),
  ('drive.node_locked', array['drive_node.locked']::text[]),
  ('drive.node_moved', array['drive_node.moved']::text[]),
  ('drive.node_obsoleted', array['drive_node.obsoleted']::text[]),
  ('drive.node_ownership_transferred', array['drive_node.ownership_transferred']::text[]),
  ('drive.node_purged', array['drive_node.purged']::text[]),
  ('drive.node_released', array['drive_node.released']::text[]),
  ('drive.node_renamed', array['drive_node.renamed']::text[]),
  ('drive.node_review_requested', array['drive_node.review_requested']::text[]),
  ('drive.node_reviewed', array['drive_node.reviewed']::text[]),
  ('drive.node_shared', array['drive_node.shared']::text[]),
  ('drive.node_submitted', array['drive_node.submitted']::text[]),
  ('drive.node_unlocked', array['drive_node.unlocked']::text[]),
  ('drive.node_unshared', array['drive_node.unshared']::text[]),
  ('engagement.*', array['activity.*']::text[]),
  ('engagement.amended', array['activity.amended']::text[]),
  ('engagement.completed', array['activity.completed']::text[]),
  ('engagement.deleted', array['activity.deleted']::text[]),
  ('engagement.error_marked', array['activity.error_marked']::text[]),
  ('engagement.logged', array['activity.logged']::text[]),
  ('engagement.recorded', array['activity.recorded']::text[]),
  ('engagement.summarized', array['activity.summarized']::text[]),
  ('engagement.transcribed', array['activity.transcribed']::text[]),
  ('engagement.updated', array['activity.updated']::text[]),
  ('enrollment_program.saved', array['enrollment_program.created', 'enrollment_program.updated']::text[]),
  ('flag.override_set', array['flag.override_changed']::text[]),
  ('flag.saved', array['flag.created', 'flag.updated']::text[]),
  ('forecast.*', array['forecast_snapshot.*']::text[]),
  ('forecast.snapshotted', array['forecast_snapshot.created']::text[]),
  ('hostname.primary_set', array['hostname.primary_changed']::text[]),
  ('hostname.removed', array['hostname.deleted']::text[]),
  ('incoming_webhook.enabled_set', array['incoming_webhook.enabled_changed']::text[]),
  ('job.*', array['job_opening.*']::text[]),
  ('job.closed', array['job_opening.closed']::text[]),
  ('job.opened', array['job_opening.opened']::text[]),
  ('leave.*', array['leave_request.*', 'leave_balance.*']::text[]),
  ('leave.adjusted', array['leave_balance.adjusted']::text[]),
  ('leave.approved', array['leave_request.approved']::text[]),
  ('leave.cancelled', array['leave_request.cancelled']::text[]),
  ('leave.rejected', array['leave_request.rejected']::text[]),
  ('leave.requested', array['leave_request.requested']::text[]),
  ('leave.split', array['leave_request.split']::text[]),
  ('leave.updated', array['leave_request.updated']::text[]),
  ('marketplace_installation.removed', array['marketplace_installation.deleted']::text[]),
  ('marketplace_installation.upserted', array['marketplace_installation.created', 'marketplace_installation.updated']::text[]),
  ('marketplace_invoice.state_changed', array['marketplace_invoice.status_changed']::text[]),
  ('obligation.*', array['contract_obligation.*']::text[]),
  ('obligation.saved', array['contract_obligation.created', 'contract_obligation.updated']::text[]),
  ('obligation.status_changed', array['contract_obligation.status_changed']::text[]),
  ('organization.*', array['sso_domain.*']::text[]),
  ('organization.domain_added', array['sso_domain.created']::text[]),
  ('organization.domain_removed', array['sso_domain.deleted']::text[]),
  ('organization.domain_updated', array['sso_domain.updated']::text[]),
  ('organization.domain_verified', array['sso_domain.verified']::text[]),
  ('party.*', array['company.enriched', 'person.enriched']::text[]),
  ('party.enriched', array['company.enriched', 'person.enriched']::text[]),
  ('pipeline_stage.saved', array['pipeline_stage.created', 'pipeline_stage.updated']::text[]),
  ('policy.*', array['compliance_policy.*']::text[]),
  ('policy.acknowledged', array['acknowledgement.created']::text[]),
  ('policy.published', array['compliance_policy.published']::text[]),
  ('post_board.saved', array['post_board.created', 'post_board.updated']::text[]),
  ('postmortem.*', array['incident_postmortem.*']::text[]),
  ('postmortem.published', array['incident_postmortem.published']::text[]),
  ('rule.*', array['automation.*']::text[]),
  ('rule.disabled', array['automation.disabled']::text[]),
  ('rule.enabled', array['automation.enabled']::text[]),
  ('rule.matched', array['automation.matched']::text[]),
  ('rule.removed', array['automation.deleted']::text[]),
  ('rule.saved', array['automation.created', 'automation.updated']::text[]),
  ('saved_view.saved', array['saved_view.created', 'saved_view.updated']::text[]),
  ('scim_group.saved', array['scim_group.created', 'scim_group.updated']::text[]),
  ('scim_user.saved', array['scim_user.created', 'scim_user.updated']::text[]),
  ('score_model.saved', array['score_model.created', 'score_model.updated']::text[]),
  ('segment.removed', array['segment.deleted']::text[]),
  ('segment.saved', array['segment.created', 'segment.updated']::text[]),
  ('sequence.saved', array['sequence.created', 'sequence.updated']::text[]),
  ('sequence_enrollment.*', array['enrollment.*']::text[]),
  ('sequence_enrollment.completed', array['enrollment.completed']::text[]),
  ('sequence_enrollment.created', array['enrollment.created']::text[]),
  ('sequence_enrollment.exited', array['enrollment.cancelled']::text[]),
  ('sequence_enrollment.paused', array['enrollment.paused']::text[]),
  ('sequence_enrollment.resumed', array['enrollment.resumed']::text[]),
  ('sequence_enrollment.step_completed', array['enrollment.step_completed']::text[]),
  ('signature.*', array['signature_request.*']::text[]),
  ('signature.cancelled', array['signature_request.cancelled']::text[]),
  ('signature.completed', array['signature_request.completed']::text[]),
  ('signature.declined', array['signature_request.declined']::text[]),
  ('signature.requested', array['signature_request.requested']::text[]),
  ('signature.signed', array['signature_request.signed']::text[]),
  ('support.*', array['support_session.*']::text[]),
  ('support.denied', array['support_session.denied']::text[]),
  ('support.ended', array['support_session.ended']::text[]),
  ('support.started', array['support_session.started']::text[]),
  ('time.*', array['time_entry.*']::text[]),
  ('time.invoiced', array['time_entry.invoiced']::text[]),
  ('variant.*', array['product_variant.*']::text[]),
  ('variant.created', array['product_variant.created']::text[]),
  ('variant.deleted', array['product_variant.deleted']::text[]),
  ('variant.updated', array['product_variant.updated']::text[]),
  ('waitlist.*', array['waitlist_entry.*']::text[]),
  ('waitlist.approved', array['waitlist_entry.approved']::text[]),
  ('waitlist.rejected', array['waitlist_entry.rejected']::text[]),
  ('webhook.*', array['webhook_endpoint.*']::text[]),
  ('webhook.delivered', array['webhook_endpoint.delivered']::text[]),
  ('webhook.disabled', array['webhook_endpoint.disabled']::text[]),
  ('webhook.failed', array['webhook_endpoint.failed']::text[]),
  ('webhook.secret_rotated', array['webhook_endpoint.secret_rotated']::text[]),
  ('work_item.*', array['task.*']::text[]),
  ('work_item.archived', array['task.archived']::text[]),
  ('work_item.assigned', array['task.assigned']::text[]),
  ('work_item.closed', array['task.closed']::text[]),
  ('work_item.created', array['task.created']::text[]),
  ('work_item.deleted', array['task.deleted']::text[]),
  ('work_item.reopened', array['task.reopened']::text[]),
  ('work_item.updated', array['task.updated']::text[]),
  ('workflow.*', array['workflow_definition.*']::text[]),
  ('workflow.published', array['workflow_definition.published']::text[])
)
update "app_private"."outbox_consumers" t set "types" = array(
  select distinct x from unnest(t."types" || array(
    select n from unnest(t."types") o join m on m.old_type = o
    cross join unnest(m.next_types) n
  )) x order by x
)
where t."types" && array(select old_type from m);

insert into better_supabase.blocks (name, version, mode)
values ('outbox', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_023_outbox.sql
-- better-supabase module: outbox
-- @bsb-block outbox@5 managed
-- @bsb-hash sha256:a64b6f52847b0a1ab9285189fc4a8523ba3379d9bf44f785e7c0a5cf1dd5e1e4
-- Events written in the same transaction as the change, read by named consumers with their own cursor and lease, kept for history and relayed as CloudEvents.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."outbox_events";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."outbox_events";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."outbox_events";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."outbox_events";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."outbox_events";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

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
revoke all on "better_supabase"."outbox_events" from public, anon, authenticated;
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
revoke all on "better_supabase"."outbox_consumers" from public, anon, authenticated;
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
revoke all on "better_supabase"."outbox_dead_letters" from public, anon, authenticated;
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
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_purged integer;
begin
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
  select count(*)::integer into v_purged from gone;
  return v_purged;
end;
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
revoke execute on function "better_supabase"."outbox_row_event"() from public, anon, authenticated;

create or replace function "better_supabase"."track_events"(target regclass, type_prefix text default null, tenant_column text default null)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists "bsb_outbox_events" on %s', target);
  execute format('drop trigger if exists "bsb_outbox_events_update" on %s', target);
  execute format(
    'create trigger "bsb_outbox_events" after insert or delete on %s for each row execute function "better_supabase"."outbox_row_event"(%L, %L)',
    target, coalesce(type_prefix, ''), coalesce(tenant_column, '')
  );
  -- jsonb, not the row: a row comparison fails on columns without equality (json).
  execute format(
    'create trigger "bsb_outbox_events_update" after update on %s for each row when (to_jsonb(old) is distinct from to_jsonb(new)) execute function "better_supabase"."outbox_row_event"(%L, %L)',
    target, coalesce(type_prefix, ''), coalesce(tenant_column, '')
  );
end;
$$;
revoke execute on function "better_supabase"."track_events"(regclass, text, text) from public, anon, authenticated;

-- blocks.outbox.api: entry points for the Data API.
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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_023_outbox.sql
-- better-supabase module: outbox
-- @bsb-block-data outbox
-- @bsb-hash sha256:5acf345602c65fa5d8b14b27584db06d6781e8b7baa395bf3edb3a329343acee
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Event types renamed by the 0.47 naming convention (ADR 0130).
update "better_supabase"."outbox_events" t set "type" = m.next_type
from (values
  ('access.ended', 'access_request.ended'),
  ('access.request_approved', 'access_request.approved'),
  ('access.requested', 'access_request.requested'),
  ('ai_tool_policy.set', 'ai_tool_policy.updated'),
  ('approval_policy.removed', 'approval_policy.deleted'),
  ('compliance_policy.acknowledged', 'acknowledgement.created'),
  ('credential.set', 'credential.updated'),
  ('custom_field.deleted', 'field_definition.deleted'),
  ('drive.node_created', 'drive_node.created'),
  ('drive.node_document_saved', 'drive_node.document_saved'),
  ('drive.node_download_blocked_changed', 'drive_node.download_blocked_changed'),
  ('drive.node_hold_placed', 'drive_node.hold_placed'),
  ('drive.node_hold_released', 'drive_node.hold_released'),
  ('drive.node_locked', 'drive_node.locked'),
  ('drive.node_moved', 'drive_node.moved'),
  ('drive.node_obsoleted', 'drive_node.obsoleted'),
  ('drive.node_ownership_transferred', 'drive_node.ownership_transferred'),
  ('drive.node_purged', 'drive_node.purged'),
  ('drive.node_released', 'drive_node.released'),
  ('drive.node_renamed', 'drive_node.renamed'),
  ('drive.node_review_requested', 'drive_node.review_requested'),
  ('drive.node_reviewed', 'drive_node.reviewed'),
  ('drive.node_shared', 'drive_node.shared'),
  ('drive.node_submitted', 'drive_node.submitted'),
  ('drive.node_unlocked', 'drive_node.unlocked'),
  ('drive.node_unshared', 'drive_node.unshared'),
  ('engagement.amended', 'activity.amended'),
  ('engagement.completed', 'activity.completed'),
  ('engagement.deleted', 'activity.deleted'),
  ('engagement.error_marked', 'activity.error_marked'),
  ('engagement.logged', 'activity.logged'),
  ('engagement.recorded', 'activity.recorded'),
  ('engagement.summarized', 'activity.summarized'),
  ('engagement.transcribed', 'activity.transcribed'),
  ('engagement.updated', 'activity.updated'),
  ('flag.override_set', 'flag.override_changed'),
  ('forecast.snapshotted', 'forecast_snapshot.created'),
  ('hostname.primary_set', 'hostname.primary_changed'),
  ('hostname.removed', 'hostname.deleted'),
  ('incoming_webhook.enabled_set', 'incoming_webhook.enabled_changed'),
  ('job.closed', 'job_opening.closed'),
  ('job.opened', 'job_opening.opened'),
  ('leave.adjusted', 'leave_balance.adjusted'),
  ('leave.approved', 'leave_request.approved'),
  ('leave.cancelled', 'leave_request.cancelled'),
  ('leave.rejected', 'leave_request.rejected'),
  ('leave.requested', 'leave_request.requested'),
  ('leave.split', 'leave_request.split'),
  ('leave.updated', 'leave_request.updated'),
  ('marketplace_installation.removed', 'marketplace_installation.deleted'),
  ('marketplace_invoice.state_changed', 'marketplace_invoice.status_changed'),
  ('obligation.status_changed', 'contract_obligation.status_changed'),
  ('organization.domain_added', 'sso_domain.created'),
  ('organization.domain_removed', 'sso_domain.deleted'),
  ('organization.domain_updated', 'sso_domain.updated'),
  ('organization.domain_verified', 'sso_domain.verified'),
  ('policy.acknowledged', 'acknowledgement.created'),
  ('policy.published', 'compliance_policy.published'),
  ('postmortem.published', 'incident_postmortem.published'),
  ('rule.disabled', 'automation.disabled'),
  ('rule.enabled', 'automation.enabled'),
  ('rule.matched', 'automation.matched'),
  ('rule.removed', 'automation.deleted'),
  ('segment.removed', 'segment.deleted'),
  ('sequence_enrollment.completed', 'enrollment.completed'),
  ('sequence_enrollment.created', 'enrollment.created'),
  ('sequence_enrollment.exited', 'enrollment.cancelled'),
  ('sequence_enrollment.paused', 'enrollment.paused'),
  ('sequence_enrollment.resumed', 'enrollment.resumed'),
  ('sequence_enrollment.step_completed', 'enrollment.step_completed'),
  ('signature.cancelled', 'signature_request.cancelled'),
  ('signature.completed', 'signature_request.completed'),
  ('signature.declined', 'signature_request.declined'),
  ('signature.requested', 'signature_request.requested'),
  ('signature.signed', 'signature_request.signed'),
  ('support.denied', 'support_session.denied'),
  ('support.ended', 'support_session.ended'),
  ('support.started', 'support_session.started'),
  ('time.invoiced', 'time_entry.invoiced'),
  ('variant.created', 'product_variant.created'),
  ('variant.deleted', 'product_variant.deleted'),
  ('variant.updated', 'product_variant.updated'),
  ('waitlist.approved', 'waitlist_entry.approved'),
  ('waitlist.rejected', 'waitlist_entry.rejected'),
  ('webhook.delivered', 'webhook_endpoint.delivered'),
  ('webhook.disabled', 'webhook_endpoint.disabled'),
  ('webhook.failed', 'webhook_endpoint.failed'),
  ('webhook.secret_rotated', 'webhook_endpoint.secret_rotated'),
  ('work_item.archived', 'task.archived'),
  ('work_item.assigned', 'task.assigned'),
  ('work_item.closed', 'task.closed'),
  ('work_item.created', 'task.created'),
  ('work_item.deleted', 'task.deleted'),
  ('work_item.reopened', 'task.reopened'),
  ('work_item.updated', 'task.updated'),
  ('workflow.published', 'workflow_definition.published')
) as m(old_type, next_type)
where t."type" = m.old_type;

update "better_supabase"."outbox_dead_letters" t set "type" = m.next_type
from (values
  ('access.ended', 'access_request.ended'),
  ('access.request_approved', 'access_request.approved'),
  ('access.requested', 'access_request.requested'),
  ('ai_tool_policy.set', 'ai_tool_policy.updated'),
  ('approval_policy.removed', 'approval_policy.deleted'),
  ('compliance_policy.acknowledged', 'acknowledgement.created'),
  ('credential.set', 'credential.updated'),
  ('custom_field.deleted', 'field_definition.deleted'),
  ('drive.node_created', 'drive_node.created'),
  ('drive.node_document_saved', 'drive_node.document_saved'),
  ('drive.node_download_blocked_changed', 'drive_node.download_blocked_changed'),
  ('drive.node_hold_placed', 'drive_node.hold_placed'),
  ('drive.node_hold_released', 'drive_node.hold_released'),
  ('drive.node_locked', 'drive_node.locked'),
  ('drive.node_moved', 'drive_node.moved'),
  ('drive.node_obsoleted', 'drive_node.obsoleted'),
  ('drive.node_ownership_transferred', 'drive_node.ownership_transferred'),
  ('drive.node_purged', 'drive_node.purged'),
  ('drive.node_released', 'drive_node.released'),
  ('drive.node_renamed', 'drive_node.renamed'),
  ('drive.node_review_requested', 'drive_node.review_requested'),
  ('drive.node_reviewed', 'drive_node.reviewed'),
  ('drive.node_shared', 'drive_node.shared'),
  ('drive.node_submitted', 'drive_node.submitted'),
  ('drive.node_unlocked', 'drive_node.unlocked'),
  ('drive.node_unshared', 'drive_node.unshared'),
  ('engagement.amended', 'activity.amended'),
  ('engagement.completed', 'activity.completed'),
  ('engagement.deleted', 'activity.deleted'),
  ('engagement.error_marked', 'activity.error_marked'),
  ('engagement.logged', 'activity.logged'),
  ('engagement.recorded', 'activity.recorded'),
  ('engagement.summarized', 'activity.summarized'),
  ('engagement.transcribed', 'activity.transcribed'),
  ('engagement.updated', 'activity.updated'),
  ('flag.override_set', 'flag.override_changed'),
  ('forecast.snapshotted', 'forecast_snapshot.created'),
  ('hostname.primary_set', 'hostname.primary_changed'),
  ('hostname.removed', 'hostname.deleted'),
  ('incoming_webhook.enabled_set', 'incoming_webhook.enabled_changed'),
  ('job.closed', 'job_opening.closed'),
  ('job.opened', 'job_opening.opened'),
  ('leave.adjusted', 'leave_balance.adjusted'),
  ('leave.approved', 'leave_request.approved'),
  ('leave.cancelled', 'leave_request.cancelled'),
  ('leave.rejected', 'leave_request.rejected'),
  ('leave.requested', 'leave_request.requested'),
  ('leave.split', 'leave_request.split'),
  ('leave.updated', 'leave_request.updated'),
  ('marketplace_installation.removed', 'marketplace_installation.deleted'),
  ('marketplace_invoice.state_changed', 'marketplace_invoice.status_changed'),
  ('obligation.status_changed', 'contract_obligation.status_changed'),
  ('organization.domain_added', 'sso_domain.created'),
  ('organization.domain_removed', 'sso_domain.deleted'),
  ('organization.domain_updated', 'sso_domain.updated'),
  ('organization.domain_verified', 'sso_domain.verified'),
  ('policy.acknowledged', 'acknowledgement.created'),
  ('policy.published', 'compliance_policy.published'),
  ('postmortem.published', 'incident_postmortem.published'),
  ('rule.disabled', 'automation.disabled'),
  ('rule.enabled', 'automation.enabled'),
  ('rule.matched', 'automation.matched'),
  ('rule.removed', 'automation.deleted'),
  ('segment.removed', 'segment.deleted'),
  ('sequence_enrollment.completed', 'enrollment.completed'),
  ('sequence_enrollment.created', 'enrollment.created'),
  ('sequence_enrollment.exited', 'enrollment.cancelled'),
  ('sequence_enrollment.paused', 'enrollment.paused'),
  ('sequence_enrollment.resumed', 'enrollment.resumed'),
  ('sequence_enrollment.step_completed', 'enrollment.step_completed'),
  ('signature.cancelled', 'signature_request.cancelled'),
  ('signature.completed', 'signature_request.completed'),
  ('signature.declined', 'signature_request.declined'),
  ('signature.requested', 'signature_request.requested'),
  ('signature.signed', 'signature_request.signed'),
  ('support.denied', 'support_session.denied'),
  ('support.ended', 'support_session.ended'),
  ('support.started', 'support_session.started'),
  ('time.invoiced', 'time_entry.invoiced'),
  ('variant.created', 'product_variant.created'),
  ('variant.deleted', 'product_variant.deleted'),
  ('variant.updated', 'product_variant.updated'),
  ('waitlist.approved', 'waitlist_entry.approved'),
  ('waitlist.rejected', 'waitlist_entry.rejected'),
  ('webhook.delivered', 'webhook_endpoint.delivered'),
  ('webhook.disabled', 'webhook_endpoint.disabled'),
  ('webhook.failed', 'webhook_endpoint.failed'),
  ('webhook.secret_rotated', 'webhook_endpoint.secret_rotated'),
  ('work_item.archived', 'task.archived'),
  ('work_item.assigned', 'task.assigned'),
  ('work_item.closed', 'task.closed'),
  ('work_item.created', 'task.created'),
  ('work_item.deleted', 'task.deleted'),
  ('work_item.reopened', 'task.reopened'),
  ('work_item.updated', 'task.updated'),
  ('workflow.published', 'workflow_definition.published')
) as m(old_type, next_type)
where t."type" = m.old_type;

with m(old_type, next_types) as (values
  ('access.*', array['access_request.*']::text[]),
  ('access.ended', array['access_request.ended']::text[]),
  ('access.request_approved', array['access_request.approved']::text[]),
  ('access.requested', array['access_request.requested']::text[]),
  ('agent.saved', array['agent.created', 'agent.updated']::text[]),
  ('ai_provider_key.saved', array['ai_provider_key.created', 'ai_provider_key.updated']::text[]),
  ('ai_tool_policy.set', array['ai_tool_policy.updated']::text[]),
  ('announcement.saved', array['announcement.created', 'announcement.updated']::text[]),
  ('approval_policy.removed', array['approval_policy.deleted']::text[]),
  ('approval_policy.saved', array['approval_policy.created', 'approval_policy.updated']::text[]),
  ('compliance_policy.acknowledged', array['acknowledgement.created']::text[]),
  ('connector.saved', array['connector.created', 'connector.updated']::text[]),
  ('control.saved', array['control.created', 'control.updated']::text[]),
  ('course.saved', array['course.created', 'course.updated']::text[]),
  ('credential.set', array['credential.updated']::text[]),
  ('custom_field.*', array['field_definition.*']::text[]),
  ('custom_field.deleted', array['field_definition.deleted']::text[]),
  ('custom_field.saved', array['field_definition.created', 'field_definition.updated']::text[]),
  ('drive.*', array['drive_node.*']::text[]),
  ('drive.node_created', array['drive_node.created']::text[]),
  ('drive.node_document_saved', array['drive_node.document_saved']::text[]),
  ('drive.node_download_blocked_changed', array['drive_node.download_blocked_changed']::text[]),
  ('drive.node_hold_placed', array['drive_node.hold_placed']::text[]),
  ('drive.node_hold_released', array['drive_node.hold_released']::text[]),
  ('drive.node_locked', array['drive_node.locked']::text[]),
  ('drive.node_moved', array['drive_node.moved']::text[]),
  ('drive.node_obsoleted', array['drive_node.obsoleted']::text[]),
  ('drive.node_ownership_transferred', array['drive_node.ownership_transferred']::text[]),
  ('drive.node_purged', array['drive_node.purged']::text[]),
  ('drive.node_released', array['drive_node.released']::text[]),
  ('drive.node_renamed', array['drive_node.renamed']::text[]),
  ('drive.node_review_requested', array['drive_node.review_requested']::text[]),
  ('drive.node_reviewed', array['drive_node.reviewed']::text[]),
  ('drive.node_shared', array['drive_node.shared']::text[]),
  ('drive.node_submitted', array['drive_node.submitted']::text[]),
  ('drive.node_unlocked', array['drive_node.unlocked']::text[]),
  ('drive.node_unshared', array['drive_node.unshared']::text[]),
  ('engagement.*', array['activity.*']::text[]),
  ('engagement.amended', array['activity.amended']::text[]),
  ('engagement.completed', array['activity.completed']::text[]),
  ('engagement.deleted', array['activity.deleted']::text[]),
  ('engagement.error_marked', array['activity.error_marked']::text[]),
  ('engagement.logged', array['activity.logged']::text[]),
  ('engagement.recorded', array['activity.recorded']::text[]),
  ('engagement.summarized', array['activity.summarized']::text[]),
  ('engagement.transcribed', array['activity.transcribed']::text[]),
  ('engagement.updated', array['activity.updated']::text[]),
  ('enrollment_program.saved', array['enrollment_program.created', 'enrollment_program.updated']::text[]),
  ('flag.override_set', array['flag.override_changed']::text[]),
  ('flag.saved', array['flag.created', 'flag.updated']::text[]),
  ('forecast.*', array['forecast_snapshot.*']::text[]),
  ('forecast.snapshotted', array['forecast_snapshot.created']::text[]),
  ('hostname.primary_set', array['hostname.primary_changed']::text[]),
  ('hostname.removed', array['hostname.deleted']::text[]),
  ('incoming_webhook.enabled_set', array['incoming_webhook.enabled_changed']::text[]),
  ('job.*', array['job_opening.*']::text[]),
  ('job.closed', array['job_opening.closed']::text[]),
  ('job.opened', array['job_opening.opened']::text[]),
  ('leave.*', array['leave_request.*', 'leave_balance.*']::text[]),
  ('leave.adjusted', array['leave_balance.adjusted']::text[]),
  ('leave.approved', array['leave_request.approved']::text[]),
  ('leave.cancelled', array['leave_request.cancelled']::text[]),
  ('leave.rejected', array['leave_request.rejected']::text[]),
  ('leave.requested', array['leave_request.requested']::text[]),
  ('leave.split', array['leave_request.split']::text[]),
  ('leave.updated', array['leave_request.updated']::text[]),
  ('marketplace_installation.removed', array['marketplace_installation.deleted']::text[]),
  ('marketplace_installation.upserted', array['marketplace_installation.created', 'marketplace_installation.updated']::text[]),
  ('marketplace_invoice.state_changed', array['marketplace_invoice.status_changed']::text[]),
  ('obligation.*', array['contract_obligation.*']::text[]),
  ('obligation.saved', array['contract_obligation.created', 'contract_obligation.updated']::text[]),
  ('obligation.status_changed', array['contract_obligation.status_changed']::text[]),
  ('organization.*', array['sso_domain.*']::text[]),
  ('organization.domain_added', array['sso_domain.created']::text[]),
  ('organization.domain_removed', array['sso_domain.deleted']::text[]),
  ('organization.domain_updated', array['sso_domain.updated']::text[]),
  ('organization.domain_verified', array['sso_domain.verified']::text[]),
  ('party.*', array['company.enriched', 'person.enriched']::text[]),
  ('party.enriched', array['company.enriched', 'person.enriched']::text[]),
  ('pipeline_stage.saved', array['pipeline_stage.created', 'pipeline_stage.updated']::text[]),
  ('policy.*', array['compliance_policy.*']::text[]),
  ('policy.acknowledged', array['acknowledgement.created']::text[]),
  ('policy.published', array['compliance_policy.published']::text[]),
  ('post_board.saved', array['post_board.created', 'post_board.updated']::text[]),
  ('postmortem.*', array['incident_postmortem.*']::text[]),
  ('postmortem.published', array['incident_postmortem.published']::text[]),
  ('rule.*', array['automation.*']::text[]),
  ('rule.disabled', array['automation.disabled']::text[]),
  ('rule.enabled', array['automation.enabled']::text[]),
  ('rule.matched', array['automation.matched']::text[]),
  ('rule.removed', array['automation.deleted']::text[]),
  ('rule.saved', array['automation.created', 'automation.updated']::text[]),
  ('saved_view.saved', array['saved_view.created', 'saved_view.updated']::text[]),
  ('scim_group.saved', array['scim_group.created', 'scim_group.updated']::text[]),
  ('scim_user.saved', array['scim_user.created', 'scim_user.updated']::text[]),
  ('score_model.saved', array['score_model.created', 'score_model.updated']::text[]),
  ('segment.removed', array['segment.deleted']::text[]),
  ('segment.saved', array['segment.created', 'segment.updated']::text[]),
  ('sequence.saved', array['sequence.created', 'sequence.updated']::text[]),
  ('sequence_enrollment.*', array['enrollment.*']::text[]),
  ('sequence_enrollment.completed', array['enrollment.completed']::text[]),
  ('sequence_enrollment.created', array['enrollment.created']::text[]),
  ('sequence_enrollment.exited', array['enrollment.cancelled']::text[]),
  ('sequence_enrollment.paused', array['enrollment.paused']::text[]),
  ('sequence_enrollment.resumed', array['enrollment.resumed']::text[]),
  ('sequence_enrollment.step_completed', array['enrollment.step_completed']::text[]),
  ('signature.*', array['signature_request.*']::text[]),
  ('signature.cancelled', array['signature_request.cancelled']::text[]),
  ('signature.completed', array['signature_request.completed']::text[]),
  ('signature.declined', array['signature_request.declined']::text[]),
  ('signature.requested', array['signature_request.requested']::text[]),
  ('signature.signed', array['signature_request.signed']::text[]),
  ('support.*', array['support_session.*']::text[]),
  ('support.denied', array['support_session.denied']::text[]),
  ('support.ended', array['support_session.ended']::text[]),
  ('support.started', array['support_session.started']::text[]),
  ('time.*', array['time_entry.*']::text[]),
  ('time.invoiced', array['time_entry.invoiced']::text[]),
  ('variant.*', array['product_variant.*']::text[]),
  ('variant.created', array['product_variant.created']::text[]),
  ('variant.deleted', array['product_variant.deleted']::text[]),
  ('variant.updated', array['product_variant.updated']::text[]),
  ('waitlist.*', array['waitlist_entry.*']::text[]),
  ('waitlist.approved', array['waitlist_entry.approved']::text[]),
  ('waitlist.rejected', array['waitlist_entry.rejected']::text[]),
  ('webhook.*', array['webhook_endpoint.*']::text[]),
  ('webhook.delivered', array['webhook_endpoint.delivered']::text[]),
  ('webhook.disabled', array['webhook_endpoint.disabled']::text[]),
  ('webhook.failed', array['webhook_endpoint.failed']::text[]),
  ('webhook.secret_rotated', array['webhook_endpoint.secret_rotated']::text[]),
  ('work_item.*', array['task.*']::text[]),
  ('work_item.archived', array['task.archived']::text[]),
  ('work_item.assigned', array['task.assigned']::text[]),
  ('work_item.closed', array['task.closed']::text[]),
  ('work_item.created', array['task.created']::text[]),
  ('work_item.deleted', array['task.deleted']::text[]),
  ('work_item.reopened', array['task.reopened']::text[]),
  ('work_item.updated', array['task.updated']::text[]),
  ('workflow.*', array['workflow_definition.*']::text[]),
  ('workflow.published', array['workflow_definition.published']::text[])
)
update "better_supabase"."outbox_consumers" t set "types" = array(
  select distinct x from unnest(t."types" || array(
    select n from unnest(t."types") o join m on m.old_type = o
    cross join unnest(m.next_types) n
  )) x order by x
)
where t."types" && array(select old_type from m);

insert into better_supabase.blocks (name, version, mode)
values ('outbox', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_023_outbox.sql
-- better-supabase module: outbox
-- @bsb-block outbox@5 managed
-- @bsb-hash sha256:a01ca1acc5083a923f5895dba667f4ae24496e1e0464e575d3db40df654dbdd6
-- Events written in the same transaction as the change, read by named consumers with their own cursor and lease, kept for history and relayed as CloudEvents.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."outbox_events";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."outbox_events";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."outbox_events";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."outbox_events";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."outbox_events";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
alter table "better_supabase"."outbox_events" add column if not exists "xid" xid8 not null default pg_current_xact_id();
create index if not exists outbox_events_xid_idx on "better_supabase"."outbox_events" ("xid", "position");
-- better_supabase.outbox_consumers is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."outbox_consumers" add column if not exists "name" text;
alter table "better_supabase"."outbox_consumers" add column if not exists "cursor_xid" xid8 not null default '0';
alter table "better_supabase"."outbox_consumers" add column if not exists "cursor_position" bigint not null default 0;
alter table "better_supabase"."outbox_consumers" add column if not exists "types" text[];
alter table "better_supabase"."outbox_consumers" add column if not exists "lease_owner" text;
alter table "better_supabase"."outbox_consumers" add column if not exists "lease_until" timestamptz;
alter table "better_supabase"."outbox_consumers" add column if not exists "attempts" integer not null default 0;
alter table "better_supabase"."outbox_consumers" add column if not exists "last_error" text;
alter table "better_supabase"."outbox_consumers" add column if not exists "retry_at" timestamptz;
alter table "better_supabase"."outbox_consumers" add column if not exists "updated_at" timestamptz not null default now();
alter table "better_supabase"."outbox_consumers" add column if not exists "attempts" integer not null default 0;
alter table "better_supabase"."outbox_consumers" add column if not exists "last_error" text;
alter table "better_supabase"."outbox_consumers" add column if not exists "retry_at" timestamptz;
alter table "better_supabase"."outbox_consumers" enable row level security;
grant all on "better_supabase"."outbox_consumers" to service_role;

-- Events a consumer skipped after max_attempts failures, with a copy of the
-- event, so one bad event can't stop the consumer.
-- better_supabase.outbox_dead_letters is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."outbox_dead_letters" add column if not exists "consumer" text references "better_supabase"."outbox_consumers" ("name") on delete cascade;
alter table "better_supabase"."outbox_dead_letters" add column if not exists "position" bigint;
alter table "better_supabase"."outbox_dead_letters" add column if not exists "event_id" text;
alter table "better_supabase"."outbox_dead_letters" add column if not exists "type" text;
alter table "better_supabase"."outbox_dead_letters" add column if not exists "event" jsonb;
alter table "better_supabase"."outbox_dead_letters" add column if not exists "attempts" integer;
alter table "better_supabase"."outbox_dead_letters" add column if not exists "error" text;
alter table "better_supabase"."outbox_dead_letters" add column if not exists "dead_at" timestamptz not null default now();
create index if not exists outbox_dead_letters_dead_at_idx on "better_supabase"."outbox_dead_letters" ("dead_at");
alter table "better_supabase"."outbox_dead_letters" enable row level security;
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
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_purged integer;
begin
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
  select count(*)::integer into v_purged from gone;
  return v_purged;
end;
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
revoke execute on function "better_supabase"."outbox_row_event"() from public, anon, authenticated;

create or replace function "better_supabase"."track_events"(target regclass, type_prefix text default null, tenant_column text default null)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists "bsb_outbox_events" on %s', target);
  execute format('drop trigger if exists "bsb_outbox_events_update" on %s', target);
  execute format(
    'create trigger "bsb_outbox_events" after insert or delete on %s for each row execute function "better_supabase"."outbox_row_event"(%L, %L)',
    target, coalesce(type_prefix, ''), coalesce(tenant_column, '')
  );
  -- jsonb, not the row: a row comparison fails on columns without equality (json).
  execute format(
    'create trigger "bsb_outbox_events_update" after update on %s for each row when (to_jsonb(old) is distinct from to_jsonb(new)) execute function "better_supabase"."outbox_row_event"(%L, %L)',
    target, coalesce(type_prefix, ''), coalesce(tenant_column, '')
  );
end;
$$;
revoke execute on function "better_supabase"."track_events"(regclass, text, text) from public, anon, authenticated;

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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_023_outbox.sql
-- better-supabase module: outbox
-- @bsb-block-data outbox
-- @bsb-hash sha256:5acf345602c65fa5d8b14b27584db06d6781e8b7baa395bf3edb3a329343acee
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Event types renamed by the 0.47 naming convention (ADR 0130).
update "better_supabase"."outbox_events" t set "type" = m.next_type
from (values
  ('access.ended', 'access_request.ended'),
  ('access.request_approved', 'access_request.approved'),
  ('access.requested', 'access_request.requested'),
  ('ai_tool_policy.set', 'ai_tool_policy.updated'),
  ('approval_policy.removed', 'approval_policy.deleted'),
  ('compliance_policy.acknowledged', 'acknowledgement.created'),
  ('credential.set', 'credential.updated'),
  ('custom_field.deleted', 'field_definition.deleted'),
  ('drive.node_created', 'drive_node.created'),
  ('drive.node_document_saved', 'drive_node.document_saved'),
  ('drive.node_download_blocked_changed', 'drive_node.download_blocked_changed'),
  ('drive.node_hold_placed', 'drive_node.hold_placed'),
  ('drive.node_hold_released', 'drive_node.hold_released'),
  ('drive.node_locked', 'drive_node.locked'),
  ('drive.node_moved', 'drive_node.moved'),
  ('drive.node_obsoleted', 'drive_node.obsoleted'),
  ('drive.node_ownership_transferred', 'drive_node.ownership_transferred'),
  ('drive.node_purged', 'drive_node.purged'),
  ('drive.node_released', 'drive_node.released'),
  ('drive.node_renamed', 'drive_node.renamed'),
  ('drive.node_review_requested', 'drive_node.review_requested'),
  ('drive.node_reviewed', 'drive_node.reviewed'),
  ('drive.node_shared', 'drive_node.shared'),
  ('drive.node_submitted', 'drive_node.submitted'),
  ('drive.node_unlocked', 'drive_node.unlocked'),
  ('drive.node_unshared', 'drive_node.unshared'),
  ('engagement.amended', 'activity.amended'),
  ('engagement.completed', 'activity.completed'),
  ('engagement.deleted', 'activity.deleted'),
  ('engagement.error_marked', 'activity.error_marked'),
  ('engagement.logged', 'activity.logged'),
  ('engagement.recorded', 'activity.recorded'),
  ('engagement.summarized', 'activity.summarized'),
  ('engagement.transcribed', 'activity.transcribed'),
  ('engagement.updated', 'activity.updated'),
  ('flag.override_set', 'flag.override_changed'),
  ('forecast.snapshotted', 'forecast_snapshot.created'),
  ('hostname.primary_set', 'hostname.primary_changed'),
  ('hostname.removed', 'hostname.deleted'),
  ('incoming_webhook.enabled_set', 'incoming_webhook.enabled_changed'),
  ('job.closed', 'job_opening.closed'),
  ('job.opened', 'job_opening.opened'),
  ('leave.adjusted', 'leave_balance.adjusted'),
  ('leave.approved', 'leave_request.approved'),
  ('leave.cancelled', 'leave_request.cancelled'),
  ('leave.rejected', 'leave_request.rejected'),
  ('leave.requested', 'leave_request.requested'),
  ('leave.split', 'leave_request.split'),
  ('leave.updated', 'leave_request.updated'),
  ('marketplace_installation.removed', 'marketplace_installation.deleted'),
  ('marketplace_invoice.state_changed', 'marketplace_invoice.status_changed'),
  ('obligation.status_changed', 'contract_obligation.status_changed'),
  ('organization.domain_added', 'sso_domain.created'),
  ('organization.domain_removed', 'sso_domain.deleted'),
  ('organization.domain_updated', 'sso_domain.updated'),
  ('organization.domain_verified', 'sso_domain.verified'),
  ('policy.acknowledged', 'acknowledgement.created'),
  ('policy.published', 'compliance_policy.published'),
  ('postmortem.published', 'incident_postmortem.published'),
  ('rule.disabled', 'automation.disabled'),
  ('rule.enabled', 'automation.enabled'),
  ('rule.matched', 'automation.matched'),
  ('rule.removed', 'automation.deleted'),
  ('segment.removed', 'segment.deleted'),
  ('sequence_enrollment.completed', 'enrollment.completed'),
  ('sequence_enrollment.created', 'enrollment.created'),
  ('sequence_enrollment.exited', 'enrollment.cancelled'),
  ('sequence_enrollment.paused', 'enrollment.paused'),
  ('sequence_enrollment.resumed', 'enrollment.resumed'),
  ('sequence_enrollment.step_completed', 'enrollment.step_completed'),
  ('signature.cancelled', 'signature_request.cancelled'),
  ('signature.completed', 'signature_request.completed'),
  ('signature.declined', 'signature_request.declined'),
  ('signature.requested', 'signature_request.requested'),
  ('signature.signed', 'signature_request.signed'),
  ('support.denied', 'support_session.denied'),
  ('support.ended', 'support_session.ended'),
  ('support.started', 'support_session.started'),
  ('time.invoiced', 'time_entry.invoiced'),
  ('variant.created', 'product_variant.created'),
  ('variant.deleted', 'product_variant.deleted'),
  ('variant.updated', 'product_variant.updated'),
  ('waitlist.approved', 'waitlist_entry.approved'),
  ('waitlist.rejected', 'waitlist_entry.rejected'),
  ('webhook.delivered', 'webhook_endpoint.delivered'),
  ('webhook.disabled', 'webhook_endpoint.disabled'),
  ('webhook.failed', 'webhook_endpoint.failed'),
  ('webhook.secret_rotated', 'webhook_endpoint.secret_rotated'),
  ('work_item.archived', 'task.archived'),
  ('work_item.assigned', 'task.assigned'),
  ('work_item.closed', 'task.closed'),
  ('work_item.created', 'task.created'),
  ('work_item.deleted', 'task.deleted'),
  ('work_item.reopened', 'task.reopened'),
  ('work_item.updated', 'task.updated'),
  ('workflow.published', 'workflow_definition.published')
) as m(old_type, next_type)
where t."type" = m.old_type;

update "better_supabase"."outbox_dead_letters" t set "type" = m.next_type
from (values
  ('access.ended', 'access_request.ended'),
  ('access.request_approved', 'access_request.approved'),
  ('access.requested', 'access_request.requested'),
  ('ai_tool_policy.set', 'ai_tool_policy.updated'),
  ('approval_policy.removed', 'approval_policy.deleted'),
  ('compliance_policy.acknowledged', 'acknowledgement.created'),
  ('credential.set', 'credential.updated'),
  ('custom_field.deleted', 'field_definition.deleted'),
  ('drive.node_created', 'drive_node.created'),
  ('drive.node_document_saved', 'drive_node.document_saved'),
  ('drive.node_download_blocked_changed', 'drive_node.download_blocked_changed'),
  ('drive.node_hold_placed', 'drive_node.hold_placed'),
  ('drive.node_hold_released', 'drive_node.hold_released'),
  ('drive.node_locked', 'drive_node.locked'),
  ('drive.node_moved', 'drive_node.moved'),
  ('drive.node_obsoleted', 'drive_node.obsoleted'),
  ('drive.node_ownership_transferred', 'drive_node.ownership_transferred'),
  ('drive.node_purged', 'drive_node.purged'),
  ('drive.node_released', 'drive_node.released'),
  ('drive.node_renamed', 'drive_node.renamed'),
  ('drive.node_review_requested', 'drive_node.review_requested'),
  ('drive.node_reviewed', 'drive_node.reviewed'),
  ('drive.node_shared', 'drive_node.shared'),
  ('drive.node_submitted', 'drive_node.submitted'),
  ('drive.node_unlocked', 'drive_node.unlocked'),
  ('drive.node_unshared', 'drive_node.unshared'),
  ('engagement.amended', 'activity.amended'),
  ('engagement.completed', 'activity.completed'),
  ('engagement.deleted', 'activity.deleted'),
  ('engagement.error_marked', 'activity.error_marked'),
  ('engagement.logged', 'activity.logged'),
  ('engagement.recorded', 'activity.recorded'),
  ('engagement.summarized', 'activity.summarized'),
  ('engagement.transcribed', 'activity.transcribed'),
  ('engagement.updated', 'activity.updated'),
  ('flag.override_set', 'flag.override_changed'),
  ('forecast.snapshotted', 'forecast_snapshot.created'),
  ('hostname.primary_set', 'hostname.primary_changed'),
  ('hostname.removed', 'hostname.deleted'),
  ('incoming_webhook.enabled_set', 'incoming_webhook.enabled_changed'),
  ('job.closed', 'job_opening.closed'),
  ('job.opened', 'job_opening.opened'),
  ('leave.adjusted', 'leave_balance.adjusted'),
  ('leave.approved', 'leave_request.approved'),
  ('leave.cancelled', 'leave_request.cancelled'),
  ('leave.rejected', 'leave_request.rejected'),
  ('leave.requested', 'leave_request.requested'),
  ('leave.split', 'leave_request.split'),
  ('leave.updated', 'leave_request.updated'),
  ('marketplace_installation.removed', 'marketplace_installation.deleted'),
  ('marketplace_invoice.state_changed', 'marketplace_invoice.status_changed'),
  ('obligation.status_changed', 'contract_obligation.status_changed'),
  ('organization.domain_added', 'sso_domain.created'),
  ('organization.domain_removed', 'sso_domain.deleted'),
  ('organization.domain_updated', 'sso_domain.updated'),
  ('organization.domain_verified', 'sso_domain.verified'),
  ('policy.acknowledged', 'acknowledgement.created'),
  ('policy.published', 'compliance_policy.published'),
  ('postmortem.published', 'incident_postmortem.published'),
  ('rule.disabled', 'automation.disabled'),
  ('rule.enabled', 'automation.enabled'),
  ('rule.matched', 'automation.matched'),
  ('rule.removed', 'automation.deleted'),
  ('segment.removed', 'segment.deleted'),
  ('sequence_enrollment.completed', 'enrollment.completed'),
  ('sequence_enrollment.created', 'enrollment.created'),
  ('sequence_enrollment.exited', 'enrollment.cancelled'),
  ('sequence_enrollment.paused', 'enrollment.paused'),
  ('sequence_enrollment.resumed', 'enrollment.resumed'),
  ('sequence_enrollment.step_completed', 'enrollment.step_completed'),
  ('signature.cancelled', 'signature_request.cancelled'),
  ('signature.completed', 'signature_request.completed'),
  ('signature.declined', 'signature_request.declined'),
  ('signature.requested', 'signature_request.requested'),
  ('signature.signed', 'signature_request.signed'),
  ('support.denied', 'support_session.denied'),
  ('support.ended', 'support_session.ended'),
  ('support.started', 'support_session.started'),
  ('time.invoiced', 'time_entry.invoiced'),
  ('variant.created', 'product_variant.created'),
  ('variant.deleted', 'product_variant.deleted'),
  ('variant.updated', 'product_variant.updated'),
  ('waitlist.approved', 'waitlist_entry.approved'),
  ('waitlist.rejected', 'waitlist_entry.rejected'),
  ('webhook.delivered', 'webhook_endpoint.delivered'),
  ('webhook.disabled', 'webhook_endpoint.disabled'),
  ('webhook.failed', 'webhook_endpoint.failed'),
  ('webhook.secret_rotated', 'webhook_endpoint.secret_rotated'),
  ('work_item.archived', 'task.archived'),
  ('work_item.assigned', 'task.assigned'),
  ('work_item.closed', 'task.closed'),
  ('work_item.created', 'task.created'),
  ('work_item.deleted', 'task.deleted'),
  ('work_item.reopened', 'task.reopened'),
  ('work_item.updated', 'task.updated'),
  ('workflow.published', 'workflow_definition.published')
) as m(old_type, next_type)
where t."type" = m.old_type;

with m(old_type, next_types) as (values
  ('access.*', array['access_request.*']::text[]),
  ('access.ended', array['access_request.ended']::text[]),
  ('access.request_approved', array['access_request.approved']::text[]),
  ('access.requested', array['access_request.requested']::text[]),
  ('agent.saved', array['agent.created', 'agent.updated']::text[]),
  ('ai_provider_key.saved', array['ai_provider_key.created', 'ai_provider_key.updated']::text[]),
  ('ai_tool_policy.set', array['ai_tool_policy.updated']::text[]),
  ('announcement.saved', array['announcement.created', 'announcement.updated']::text[]),
  ('approval_policy.removed', array['approval_policy.deleted']::text[]),
  ('approval_policy.saved', array['approval_policy.created', 'approval_policy.updated']::text[]),
  ('compliance_policy.acknowledged', array['acknowledgement.created']::text[]),
  ('connector.saved', array['connector.created', 'connector.updated']::text[]),
  ('control.saved', array['control.created', 'control.updated']::text[]),
  ('course.saved', array['course.created', 'course.updated']::text[]),
  ('credential.set', array['credential.updated']::text[]),
  ('custom_field.*', array['field_definition.*']::text[]),
  ('custom_field.deleted', array['field_definition.deleted']::text[]),
  ('custom_field.saved', array['field_definition.created', 'field_definition.updated']::text[]),
  ('drive.*', array['drive_node.*']::text[]),
  ('drive.node_created', array['drive_node.created']::text[]),
  ('drive.node_document_saved', array['drive_node.document_saved']::text[]),
  ('drive.node_download_blocked_changed', array['drive_node.download_blocked_changed']::text[]),
  ('drive.node_hold_placed', array['drive_node.hold_placed']::text[]),
  ('drive.node_hold_released', array['drive_node.hold_released']::text[]),
  ('drive.node_locked', array['drive_node.locked']::text[]),
  ('drive.node_moved', array['drive_node.moved']::text[]),
  ('drive.node_obsoleted', array['drive_node.obsoleted']::text[]),
  ('drive.node_ownership_transferred', array['drive_node.ownership_transferred']::text[]),
  ('drive.node_purged', array['drive_node.purged']::text[]),
  ('drive.node_released', array['drive_node.released']::text[]),
  ('drive.node_renamed', array['drive_node.renamed']::text[]),
  ('drive.node_review_requested', array['drive_node.review_requested']::text[]),
  ('drive.node_reviewed', array['drive_node.reviewed']::text[]),
  ('drive.node_shared', array['drive_node.shared']::text[]),
  ('drive.node_submitted', array['drive_node.submitted']::text[]),
  ('drive.node_unlocked', array['drive_node.unlocked']::text[]),
  ('drive.node_unshared', array['drive_node.unshared']::text[]),
  ('engagement.*', array['activity.*']::text[]),
  ('engagement.amended', array['activity.amended']::text[]),
  ('engagement.completed', array['activity.completed']::text[]),
  ('engagement.deleted', array['activity.deleted']::text[]),
  ('engagement.error_marked', array['activity.error_marked']::text[]),
  ('engagement.logged', array['activity.logged']::text[]),
  ('engagement.recorded', array['activity.recorded']::text[]),
  ('engagement.summarized', array['activity.summarized']::text[]),
  ('engagement.transcribed', array['activity.transcribed']::text[]),
  ('engagement.updated', array['activity.updated']::text[]),
  ('enrollment_program.saved', array['enrollment_program.created', 'enrollment_program.updated']::text[]),
  ('flag.override_set', array['flag.override_changed']::text[]),
  ('flag.saved', array['flag.created', 'flag.updated']::text[]),
  ('forecast.*', array['forecast_snapshot.*']::text[]),
  ('forecast.snapshotted', array['forecast_snapshot.created']::text[]),
  ('hostname.primary_set', array['hostname.primary_changed']::text[]),
  ('hostname.removed', array['hostname.deleted']::text[]),
  ('incoming_webhook.enabled_set', array['incoming_webhook.enabled_changed']::text[]),
  ('job.*', array['job_opening.*']::text[]),
  ('job.closed', array['job_opening.closed']::text[]),
  ('job.opened', array['job_opening.opened']::text[]),
  ('leave.*', array['leave_request.*', 'leave_balance.*']::text[]),
  ('leave.adjusted', array['leave_balance.adjusted']::text[]),
  ('leave.approved', array['leave_request.approved']::text[]),
  ('leave.cancelled', array['leave_request.cancelled']::text[]),
  ('leave.rejected', array['leave_request.rejected']::text[]),
  ('leave.requested', array['leave_request.requested']::text[]),
  ('leave.split', array['leave_request.split']::text[]),
  ('leave.updated', array['leave_request.updated']::text[]),
  ('marketplace_installation.removed', array['marketplace_installation.deleted']::text[]),
  ('marketplace_installation.upserted', array['marketplace_installation.created', 'marketplace_installation.updated']::text[]),
  ('marketplace_invoice.state_changed', array['marketplace_invoice.status_changed']::text[]),
  ('obligation.*', array['contract_obligation.*']::text[]),
  ('obligation.saved', array['contract_obligation.created', 'contract_obligation.updated']::text[]),
  ('obligation.status_changed', array['contract_obligation.status_changed']::text[]),
  ('organization.*', array['sso_domain.*']::text[]),
  ('organization.domain_added', array['sso_domain.created']::text[]),
  ('organization.domain_removed', array['sso_domain.deleted']::text[]),
  ('organization.domain_updated', array['sso_domain.updated']::text[]),
  ('organization.domain_verified', array['sso_domain.verified']::text[]),
  ('party.*', array['company.enriched', 'person.enriched']::text[]),
  ('party.enriched', array['company.enriched', 'person.enriched']::text[]),
  ('pipeline_stage.saved', array['pipeline_stage.created', 'pipeline_stage.updated']::text[]),
  ('policy.*', array['compliance_policy.*']::text[]),
  ('policy.acknowledged', array['acknowledgement.created']::text[]),
  ('policy.published', array['compliance_policy.published']::text[]),
  ('post_board.saved', array['post_board.created', 'post_board.updated']::text[]),
  ('postmortem.*', array['incident_postmortem.*']::text[]),
  ('postmortem.published', array['incident_postmortem.published']::text[]),
  ('rule.*', array['automation.*']::text[]),
  ('rule.disabled', array['automation.disabled']::text[]),
  ('rule.enabled', array['automation.enabled']::text[]),
  ('rule.matched', array['automation.matched']::text[]),
  ('rule.removed', array['automation.deleted']::text[]),
  ('rule.saved', array['automation.created', 'automation.updated']::text[]),
  ('saved_view.saved', array['saved_view.created', 'saved_view.updated']::text[]),
  ('scim_group.saved', array['scim_group.created', 'scim_group.updated']::text[]),
  ('scim_user.saved', array['scim_user.created', 'scim_user.updated']::text[]),
  ('score_model.saved', array['score_model.created', 'score_model.updated']::text[]),
  ('segment.removed', array['segment.deleted']::text[]),
  ('segment.saved', array['segment.created', 'segment.updated']::text[]),
  ('sequence.saved', array['sequence.created', 'sequence.updated']::text[]),
  ('sequence_enrollment.*', array['enrollment.*']::text[]),
  ('sequence_enrollment.completed', array['enrollment.completed']::text[]),
  ('sequence_enrollment.created', array['enrollment.created']::text[]),
  ('sequence_enrollment.exited', array['enrollment.cancelled']::text[]),
  ('sequence_enrollment.paused', array['enrollment.paused']::text[]),
  ('sequence_enrollment.resumed', array['enrollment.resumed']::text[]),
  ('sequence_enrollment.step_completed', array['enrollment.step_completed']::text[]),
  ('signature.*', array['signature_request.*']::text[]),
  ('signature.cancelled', array['signature_request.cancelled']::text[]),
  ('signature.completed', array['signature_request.completed']::text[]),
  ('signature.declined', array['signature_request.declined']::text[]),
  ('signature.requested', array['signature_request.requested']::text[]),
  ('signature.signed', array['signature_request.signed']::text[]),
  ('support.*', array['support_session.*']::text[]),
  ('support.denied', array['support_session.denied']::text[]),
  ('support.ended', array['support_session.ended']::text[]),
  ('support.started', array['support_session.started']::text[]),
  ('time.*', array['time_entry.*']::text[]),
  ('time.invoiced', array['time_entry.invoiced']::text[]),
  ('variant.*', array['product_variant.*']::text[]),
  ('variant.created', array['product_variant.created']::text[]),
  ('variant.deleted', array['product_variant.deleted']::text[]),
  ('variant.updated', array['product_variant.updated']::text[]),
  ('waitlist.*', array['waitlist_entry.*']::text[]),
  ('waitlist.approved', array['waitlist_entry.approved']::text[]),
  ('waitlist.rejected', array['waitlist_entry.rejected']::text[]),
  ('webhook.*', array['webhook_endpoint.*']::text[]),
  ('webhook.delivered', array['webhook_endpoint.delivered']::text[]),
  ('webhook.disabled', array['webhook_endpoint.disabled']::text[]),
  ('webhook.failed', array['webhook_endpoint.failed']::text[]),
  ('webhook.secret_rotated', array['webhook_endpoint.secret_rotated']::text[]),
  ('work_item.*', array['task.*']::text[]),
  ('work_item.archived', array['task.archived']::text[]),
  ('work_item.assigned', array['task.assigned']::text[]),
  ('work_item.closed', array['task.closed']::text[]),
  ('work_item.created', array['task.created']::text[]),
  ('work_item.deleted', array['task.deleted']::text[]),
  ('work_item.reopened', array['task.reopened']::text[]),
  ('work_item.updated', array['task.updated']::text[]),
  ('workflow.*', array['workflow_definition.*']::text[]),
  ('workflow.published', array['workflow_definition.published']::text[])
)
update "better_supabase"."outbox_consumers" t set "types" = array(
  select distinct x from unnest(t."types" || array(
    select n from unnest(t."types") o join m on m.old_type = o
    cross join unnest(m.next_types) n
  )) x order by x
)
where t."types" && array(select old_type from m);

insert into better_supabase.blocks (name, version, mode)
values ('outbox', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_023_outbox.sql
-- better-supabase module: outbox
-- @bsb-block outbox@5 managed
-- @bsb-hash sha256:b020878ab1451605fcc4f46920ba55bf8330d7e59950074cba1330d3bce52573
-- Events written in the same transaction as the change, read by named consumers with their own cursor and lease, kept for history and relayed as CloudEvents.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."outbox_events";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."outbox_events";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."outbox_events";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."outbox_events";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."outbox_events";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."outbox_events" (
  "id" uuid primary key default gen_random_uuid(),
  "position" bigint generated always as identity unique,
  "type" text not null,
  "source" text,
  "subject" text,
  "org_id" uuid,
  "key" text,
  "payload" jsonb not null default '{}',
  "actor_id" uuid,
  "created_at" timestamptz not null default now(),
  "xid" xid8 not null default pg_current_xact_id()
);
create unique index if not exists outbox_events_key_idx on "better_supabase"."outbox_events" ("key", "org_id") nulls not distinct where "key" is not null;
create index if not exists outbox_events_subject_idx on "better_supabase"."outbox_events" ("subject", "position");
create index if not exists outbox_events_type_idx on "better_supabase"."outbox_events" ("type", "position");
create index if not exists outbox_events_created_idx on "better_supabase"."outbox_events" ("created_at");
create index if not exists outbox_events_xid_idx on "better_supabase"."outbox_events" ("xid", "position");
alter table "better_supabase"."outbox_events" enable row level security;
revoke all on "better_supabase"."outbox_events" from public, anon, authenticated;
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
revoke all on "better_supabase"."outbox_consumers" from public, anon, authenticated;
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
revoke all on "better_supabase"."outbox_dead_letters" from public, anon, authenticated;
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
    where e."key" = key and e."org_id" is not distinct from tenant::uuid;
    if found_id is not null then
      return found_id;
    end if;
  end if;
  insert into "better_supabase"."outbox_events" ("type", "payload", "source", "subject", "org_id", "key", "actor_id")
  values (event_type, coalesce(payload, '{}'), source, coalesce(subject, payload ->> 'subject'), tenant::uuid, key, auth.uid())
  on conflict do nothing
  returning "id"::text into found_id;
  if found_id is null then
    -- Another transaction emitted the same key first.
    select e."id"::text into found_id from "better_supabase"."outbox_events" e
    where e."key" = key and e."org_id" is not distinct from tenant::uuid;
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
    'tenant', e."org_id",
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
    'tenant', e."org_id",
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
    'tenant', e."org_id",
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
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_purged integer;
begin
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
  select count(*)::integer into v_purged from gone;
  return v_purged;
end;
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
revoke execute on function "better_supabase"."outbox_row_event"() from public, anon, authenticated;

create or replace function "better_supabase"."track_events"(target regclass, type_prefix text default null, tenant_column text default null)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists "bsb_outbox_events" on %s', target);
  execute format('drop trigger if exists "bsb_outbox_events_update" on %s', target);
  execute format(
    'create trigger "bsb_outbox_events" after insert or delete on %s for each row execute function "better_supabase"."outbox_row_event"(%L, %L)',
    target, coalesce(type_prefix, ''), coalesce(tenant_column, '')
  );
  -- jsonb, not the row: a row comparison fails on columns without equality (json).
  execute format(
    'create trigger "bsb_outbox_events_update" after update on %s for each row when (to_jsonb(old) is distinct from to_jsonb(new)) execute function "better_supabase"."outbox_row_event"(%L, %L)',
    target, coalesce(type_prefix, ''), coalesce(tenant_column, '')
  );
end;
$$;
revoke execute on function "better_supabase"."track_events"(regclass, text, text) from public, anon, authenticated;

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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_023_outbox.sql
-- better-supabase module: outbox
-- @bsb-block-data outbox
-- @bsb-hash sha256:5acf345602c65fa5d8b14b27584db06d6781e8b7baa395bf3edb3a329343acee
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Event types renamed by the 0.47 naming convention (ADR 0130).
update "better_supabase"."outbox_events" t set "type" = m.next_type
from (values
  ('access.ended', 'access_request.ended'),
  ('access.request_approved', 'access_request.approved'),
  ('access.requested', 'access_request.requested'),
  ('ai_tool_policy.set', 'ai_tool_policy.updated'),
  ('approval_policy.removed', 'approval_policy.deleted'),
  ('compliance_policy.acknowledged', 'acknowledgement.created'),
  ('credential.set', 'credential.updated'),
  ('custom_field.deleted', 'field_definition.deleted'),
  ('drive.node_created', 'drive_node.created'),
  ('drive.node_document_saved', 'drive_node.document_saved'),
  ('drive.node_download_blocked_changed', 'drive_node.download_blocked_changed'),
  ('drive.node_hold_placed', 'drive_node.hold_placed'),
  ('drive.node_hold_released', 'drive_node.hold_released'),
  ('drive.node_locked', 'drive_node.locked'),
  ('drive.node_moved', 'drive_node.moved'),
  ('drive.node_obsoleted', 'drive_node.obsoleted'),
  ('drive.node_ownership_transferred', 'drive_node.ownership_transferred'),
  ('drive.node_purged', 'drive_node.purged'),
  ('drive.node_released', 'drive_node.released'),
  ('drive.node_renamed', 'drive_node.renamed'),
  ('drive.node_review_requested', 'drive_node.review_requested'),
  ('drive.node_reviewed', 'drive_node.reviewed'),
  ('drive.node_shared', 'drive_node.shared'),
  ('drive.node_submitted', 'drive_node.submitted'),
  ('drive.node_unlocked', 'drive_node.unlocked'),
  ('drive.node_unshared', 'drive_node.unshared'),
  ('engagement.amended', 'activity.amended'),
  ('engagement.completed', 'activity.completed'),
  ('engagement.deleted', 'activity.deleted'),
  ('engagement.error_marked', 'activity.error_marked'),
  ('engagement.logged', 'activity.logged'),
  ('engagement.recorded', 'activity.recorded'),
  ('engagement.summarized', 'activity.summarized'),
  ('engagement.transcribed', 'activity.transcribed'),
  ('engagement.updated', 'activity.updated'),
  ('flag.override_set', 'flag.override_changed'),
  ('forecast.snapshotted', 'forecast_snapshot.created'),
  ('hostname.primary_set', 'hostname.primary_changed'),
  ('hostname.removed', 'hostname.deleted'),
  ('incoming_webhook.enabled_set', 'incoming_webhook.enabled_changed'),
  ('job.closed', 'job_opening.closed'),
  ('job.opened', 'job_opening.opened'),
  ('leave.adjusted', 'leave_balance.adjusted'),
  ('leave.approved', 'leave_request.approved'),
  ('leave.cancelled', 'leave_request.cancelled'),
  ('leave.rejected', 'leave_request.rejected'),
  ('leave.requested', 'leave_request.requested'),
  ('leave.split', 'leave_request.split'),
  ('leave.updated', 'leave_request.updated'),
  ('marketplace_installation.removed', 'marketplace_installation.deleted'),
  ('marketplace_invoice.state_changed', 'marketplace_invoice.status_changed'),
  ('obligation.status_changed', 'contract_obligation.status_changed'),
  ('organization.domain_added', 'sso_domain.created'),
  ('organization.domain_removed', 'sso_domain.deleted'),
  ('organization.domain_updated', 'sso_domain.updated'),
  ('organization.domain_verified', 'sso_domain.verified'),
  ('policy.acknowledged', 'acknowledgement.created'),
  ('policy.published', 'compliance_policy.published'),
  ('postmortem.published', 'incident_postmortem.published'),
  ('rule.disabled', 'automation.disabled'),
  ('rule.enabled', 'automation.enabled'),
  ('rule.matched', 'automation.matched'),
  ('rule.removed', 'automation.deleted'),
  ('segment.removed', 'segment.deleted'),
  ('sequence_enrollment.completed', 'enrollment.completed'),
  ('sequence_enrollment.created', 'enrollment.created'),
  ('sequence_enrollment.exited', 'enrollment.cancelled'),
  ('sequence_enrollment.paused', 'enrollment.paused'),
  ('sequence_enrollment.resumed', 'enrollment.resumed'),
  ('sequence_enrollment.step_completed', 'enrollment.step_completed'),
  ('signature.cancelled', 'signature_request.cancelled'),
  ('signature.completed', 'signature_request.completed'),
  ('signature.declined', 'signature_request.declined'),
  ('signature.requested', 'signature_request.requested'),
  ('signature.signed', 'signature_request.signed'),
  ('support.denied', 'support_session.denied'),
  ('support.ended', 'support_session.ended'),
  ('support.started', 'support_session.started'),
  ('time.invoiced', 'time_entry.invoiced'),
  ('variant.created', 'product_variant.created'),
  ('variant.deleted', 'product_variant.deleted'),
  ('variant.updated', 'product_variant.updated'),
  ('waitlist.approved', 'waitlist_entry.approved'),
  ('waitlist.rejected', 'waitlist_entry.rejected'),
  ('webhook.delivered', 'webhook_endpoint.delivered'),
  ('webhook.disabled', 'webhook_endpoint.disabled'),
  ('webhook.failed', 'webhook_endpoint.failed'),
  ('webhook.secret_rotated', 'webhook_endpoint.secret_rotated'),
  ('work_item.archived', 'task.archived'),
  ('work_item.assigned', 'task.assigned'),
  ('work_item.closed', 'task.closed'),
  ('work_item.created', 'task.created'),
  ('work_item.deleted', 'task.deleted'),
  ('work_item.reopened', 'task.reopened'),
  ('work_item.updated', 'task.updated'),
  ('workflow.published', 'workflow_definition.published')
) as m(old_type, next_type)
where t."type" = m.old_type;

update "better_supabase"."outbox_dead_letters" t set "type" = m.next_type
from (values
  ('access.ended', 'access_request.ended'),
  ('access.request_approved', 'access_request.approved'),
  ('access.requested', 'access_request.requested'),
  ('ai_tool_policy.set', 'ai_tool_policy.updated'),
  ('approval_policy.removed', 'approval_policy.deleted'),
  ('compliance_policy.acknowledged', 'acknowledgement.created'),
  ('credential.set', 'credential.updated'),
  ('custom_field.deleted', 'field_definition.deleted'),
  ('drive.node_created', 'drive_node.created'),
  ('drive.node_document_saved', 'drive_node.document_saved'),
  ('drive.node_download_blocked_changed', 'drive_node.download_blocked_changed'),
  ('drive.node_hold_placed', 'drive_node.hold_placed'),
  ('drive.node_hold_released', 'drive_node.hold_released'),
  ('drive.node_locked', 'drive_node.locked'),
  ('drive.node_moved', 'drive_node.moved'),
  ('drive.node_obsoleted', 'drive_node.obsoleted'),
  ('drive.node_ownership_transferred', 'drive_node.ownership_transferred'),
  ('drive.node_purged', 'drive_node.purged'),
  ('drive.node_released', 'drive_node.released'),
  ('drive.node_renamed', 'drive_node.renamed'),
  ('drive.node_review_requested', 'drive_node.review_requested'),
  ('drive.node_reviewed', 'drive_node.reviewed'),
  ('drive.node_shared', 'drive_node.shared'),
  ('drive.node_submitted', 'drive_node.submitted'),
  ('drive.node_unlocked', 'drive_node.unlocked'),
  ('drive.node_unshared', 'drive_node.unshared'),
  ('engagement.amended', 'activity.amended'),
  ('engagement.completed', 'activity.completed'),
  ('engagement.deleted', 'activity.deleted'),
  ('engagement.error_marked', 'activity.error_marked'),
  ('engagement.logged', 'activity.logged'),
  ('engagement.recorded', 'activity.recorded'),
  ('engagement.summarized', 'activity.summarized'),
  ('engagement.transcribed', 'activity.transcribed'),
  ('engagement.updated', 'activity.updated'),
  ('flag.override_set', 'flag.override_changed'),
  ('forecast.snapshotted', 'forecast_snapshot.created'),
  ('hostname.primary_set', 'hostname.primary_changed'),
  ('hostname.removed', 'hostname.deleted'),
  ('incoming_webhook.enabled_set', 'incoming_webhook.enabled_changed'),
  ('job.closed', 'job_opening.closed'),
  ('job.opened', 'job_opening.opened'),
  ('leave.adjusted', 'leave_balance.adjusted'),
  ('leave.approved', 'leave_request.approved'),
  ('leave.cancelled', 'leave_request.cancelled'),
  ('leave.rejected', 'leave_request.rejected'),
  ('leave.requested', 'leave_request.requested'),
  ('leave.split', 'leave_request.split'),
  ('leave.updated', 'leave_request.updated'),
  ('marketplace_installation.removed', 'marketplace_installation.deleted'),
  ('marketplace_invoice.state_changed', 'marketplace_invoice.status_changed'),
  ('obligation.status_changed', 'contract_obligation.status_changed'),
  ('organization.domain_added', 'sso_domain.created'),
  ('organization.domain_removed', 'sso_domain.deleted'),
  ('organization.domain_updated', 'sso_domain.updated'),
  ('organization.domain_verified', 'sso_domain.verified'),
  ('policy.acknowledged', 'acknowledgement.created'),
  ('policy.published', 'compliance_policy.published'),
  ('postmortem.published', 'incident_postmortem.published'),
  ('rule.disabled', 'automation.disabled'),
  ('rule.enabled', 'automation.enabled'),
  ('rule.matched', 'automation.matched'),
  ('rule.removed', 'automation.deleted'),
  ('segment.removed', 'segment.deleted'),
  ('sequence_enrollment.completed', 'enrollment.completed'),
  ('sequence_enrollment.created', 'enrollment.created'),
  ('sequence_enrollment.exited', 'enrollment.cancelled'),
  ('sequence_enrollment.paused', 'enrollment.paused'),
  ('sequence_enrollment.resumed', 'enrollment.resumed'),
  ('sequence_enrollment.step_completed', 'enrollment.step_completed'),
  ('signature.cancelled', 'signature_request.cancelled'),
  ('signature.completed', 'signature_request.completed'),
  ('signature.declined', 'signature_request.declined'),
  ('signature.requested', 'signature_request.requested'),
  ('signature.signed', 'signature_request.signed'),
  ('support.denied', 'support_session.denied'),
  ('support.ended', 'support_session.ended'),
  ('support.started', 'support_session.started'),
  ('time.invoiced', 'time_entry.invoiced'),
  ('variant.created', 'product_variant.created'),
  ('variant.deleted', 'product_variant.deleted'),
  ('variant.updated', 'product_variant.updated'),
  ('waitlist.approved', 'waitlist_entry.approved'),
  ('waitlist.rejected', 'waitlist_entry.rejected'),
  ('webhook.delivered', 'webhook_endpoint.delivered'),
  ('webhook.disabled', 'webhook_endpoint.disabled'),
  ('webhook.failed', 'webhook_endpoint.failed'),
  ('webhook.secret_rotated', 'webhook_endpoint.secret_rotated'),
  ('work_item.archived', 'task.archived'),
  ('work_item.assigned', 'task.assigned'),
  ('work_item.closed', 'task.closed'),
  ('work_item.created', 'task.created'),
  ('work_item.deleted', 'task.deleted'),
  ('work_item.reopened', 'task.reopened'),
  ('work_item.updated', 'task.updated'),
  ('workflow.published', 'workflow_definition.published')
) as m(old_type, next_type)
where t."type" = m.old_type;

with m(old_type, next_types) as (values
  ('access.*', array['access_request.*']::text[]),
  ('access.ended', array['access_request.ended']::text[]),
  ('access.request_approved', array['access_request.approved']::text[]),
  ('access.requested', array['access_request.requested']::text[]),
  ('agent.saved', array['agent.created', 'agent.updated']::text[]),
  ('ai_provider_key.saved', array['ai_provider_key.created', 'ai_provider_key.updated']::text[]),
  ('ai_tool_policy.set', array['ai_tool_policy.updated']::text[]),
  ('announcement.saved', array['announcement.created', 'announcement.updated']::text[]),
  ('approval_policy.removed', array['approval_policy.deleted']::text[]),
  ('approval_policy.saved', array['approval_policy.created', 'approval_policy.updated']::text[]),
  ('compliance_policy.acknowledged', array['acknowledgement.created']::text[]),
  ('connector.saved', array['connector.created', 'connector.updated']::text[]),
  ('control.saved', array['control.created', 'control.updated']::text[]),
  ('course.saved', array['course.created', 'course.updated']::text[]),
  ('credential.set', array['credential.updated']::text[]),
  ('custom_field.*', array['field_definition.*']::text[]),
  ('custom_field.deleted', array['field_definition.deleted']::text[]),
  ('custom_field.saved', array['field_definition.created', 'field_definition.updated']::text[]),
  ('drive.*', array['drive_node.*']::text[]),
  ('drive.node_created', array['drive_node.created']::text[]),
  ('drive.node_document_saved', array['drive_node.document_saved']::text[]),
  ('drive.node_download_blocked_changed', array['drive_node.download_blocked_changed']::text[]),
  ('drive.node_hold_placed', array['drive_node.hold_placed']::text[]),
  ('drive.node_hold_released', array['drive_node.hold_released']::text[]),
  ('drive.node_locked', array['drive_node.locked']::text[]),
  ('drive.node_moved', array['drive_node.moved']::text[]),
  ('drive.node_obsoleted', array['drive_node.obsoleted']::text[]),
  ('drive.node_ownership_transferred', array['drive_node.ownership_transferred']::text[]),
  ('drive.node_purged', array['drive_node.purged']::text[]),
  ('drive.node_released', array['drive_node.released']::text[]),
  ('drive.node_renamed', array['drive_node.renamed']::text[]),
  ('drive.node_review_requested', array['drive_node.review_requested']::text[]),
  ('drive.node_reviewed', array['drive_node.reviewed']::text[]),
  ('drive.node_shared', array['drive_node.shared']::text[]),
  ('drive.node_submitted', array['drive_node.submitted']::text[]),
  ('drive.node_unlocked', array['drive_node.unlocked']::text[]),
  ('drive.node_unshared', array['drive_node.unshared']::text[]),
  ('engagement.*', array['activity.*']::text[]),
  ('engagement.amended', array['activity.amended']::text[]),
  ('engagement.completed', array['activity.completed']::text[]),
  ('engagement.deleted', array['activity.deleted']::text[]),
  ('engagement.error_marked', array['activity.error_marked']::text[]),
  ('engagement.logged', array['activity.logged']::text[]),
  ('engagement.recorded', array['activity.recorded']::text[]),
  ('engagement.summarized', array['activity.summarized']::text[]),
  ('engagement.transcribed', array['activity.transcribed']::text[]),
  ('engagement.updated', array['activity.updated']::text[]),
  ('enrollment_program.saved', array['enrollment_program.created', 'enrollment_program.updated']::text[]),
  ('flag.override_set', array['flag.override_changed']::text[]),
  ('flag.saved', array['flag.created', 'flag.updated']::text[]),
  ('forecast.*', array['forecast_snapshot.*']::text[]),
  ('forecast.snapshotted', array['forecast_snapshot.created']::text[]),
  ('hostname.primary_set', array['hostname.primary_changed']::text[]),
  ('hostname.removed', array['hostname.deleted']::text[]),
  ('incoming_webhook.enabled_set', array['incoming_webhook.enabled_changed']::text[]),
  ('job.*', array['job_opening.*']::text[]),
  ('job.closed', array['job_opening.closed']::text[]),
  ('job.opened', array['job_opening.opened']::text[]),
  ('leave.*', array['leave_request.*', 'leave_balance.*']::text[]),
  ('leave.adjusted', array['leave_balance.adjusted']::text[]),
  ('leave.approved', array['leave_request.approved']::text[]),
  ('leave.cancelled', array['leave_request.cancelled']::text[]),
  ('leave.rejected', array['leave_request.rejected']::text[]),
  ('leave.requested', array['leave_request.requested']::text[]),
  ('leave.split', array['leave_request.split']::text[]),
  ('leave.updated', array['leave_request.updated']::text[]),
  ('marketplace_installation.removed', array['marketplace_installation.deleted']::text[]),
  ('marketplace_installation.upserted', array['marketplace_installation.created', 'marketplace_installation.updated']::text[]),
  ('marketplace_invoice.state_changed', array['marketplace_invoice.status_changed']::text[]),
  ('obligation.*', array['contract_obligation.*']::text[]),
  ('obligation.saved', array['contract_obligation.created', 'contract_obligation.updated']::text[]),
  ('obligation.status_changed', array['contract_obligation.status_changed']::text[]),
  ('organization.*', array['sso_domain.*']::text[]),
  ('organization.domain_added', array['sso_domain.created']::text[]),
  ('organization.domain_removed', array['sso_domain.deleted']::text[]),
  ('organization.domain_updated', array['sso_domain.updated']::text[]),
  ('organization.domain_verified', array['sso_domain.verified']::text[]),
  ('party.*', array['company.enriched', 'person.enriched']::text[]),
  ('party.enriched', array['company.enriched', 'person.enriched']::text[]),
  ('pipeline_stage.saved', array['pipeline_stage.created', 'pipeline_stage.updated']::text[]),
  ('policy.*', array['compliance_policy.*']::text[]),
  ('policy.acknowledged', array['acknowledgement.created']::text[]),
  ('policy.published', array['compliance_policy.published']::text[]),
  ('post_board.saved', array['post_board.created', 'post_board.updated']::text[]),
  ('postmortem.*', array['incident_postmortem.*']::text[]),
  ('postmortem.published', array['incident_postmortem.published']::text[]),
  ('rule.*', array['automation.*']::text[]),
  ('rule.disabled', array['automation.disabled']::text[]),
  ('rule.enabled', array['automation.enabled']::text[]),
  ('rule.matched', array['automation.matched']::text[]),
  ('rule.removed', array['automation.deleted']::text[]),
  ('rule.saved', array['automation.created', 'automation.updated']::text[]),
  ('saved_view.saved', array['saved_view.created', 'saved_view.updated']::text[]),
  ('scim_group.saved', array['scim_group.created', 'scim_group.updated']::text[]),
  ('scim_user.saved', array['scim_user.created', 'scim_user.updated']::text[]),
  ('score_model.saved', array['score_model.created', 'score_model.updated']::text[]),
  ('segment.removed', array['segment.deleted']::text[]),
  ('segment.saved', array['segment.created', 'segment.updated']::text[]),
  ('sequence.saved', array['sequence.created', 'sequence.updated']::text[]),
  ('sequence_enrollment.*', array['enrollment.*']::text[]),
  ('sequence_enrollment.completed', array['enrollment.completed']::text[]),
  ('sequence_enrollment.created', array['enrollment.created']::text[]),
  ('sequence_enrollment.exited', array['enrollment.cancelled']::text[]),
  ('sequence_enrollment.paused', array['enrollment.paused']::text[]),
  ('sequence_enrollment.resumed', array['enrollment.resumed']::text[]),
  ('sequence_enrollment.step_completed', array['enrollment.step_completed']::text[]),
  ('signature.*', array['signature_request.*']::text[]),
  ('signature.cancelled', array['signature_request.cancelled']::text[]),
  ('signature.completed', array['signature_request.completed']::text[]),
  ('signature.declined', array['signature_request.declined']::text[]),
  ('signature.requested', array['signature_request.requested']::text[]),
  ('signature.signed', array['signature_request.signed']::text[]),
  ('support.*', array['support_session.*']::text[]),
  ('support.denied', array['support_session.denied']::text[]),
  ('support.ended', array['support_session.ended']::text[]),
  ('support.started', array['support_session.started']::text[]),
  ('time.*', array['time_entry.*']::text[]),
  ('time.invoiced', array['time_entry.invoiced']::text[]),
  ('variant.*', array['product_variant.*']::text[]),
  ('variant.created', array['product_variant.created']::text[]),
  ('variant.deleted', array['product_variant.deleted']::text[]),
  ('variant.updated', array['product_variant.updated']::text[]),
  ('waitlist.*', array['waitlist_entry.*']::text[]),
  ('waitlist.approved', array['waitlist_entry.approved']::text[]),
  ('waitlist.rejected', array['waitlist_entry.rejected']::text[]),
  ('webhook.*', array['webhook_endpoint.*']::text[]),
  ('webhook.delivered', array['webhook_endpoint.delivered']::text[]),
  ('webhook.disabled', array['webhook_endpoint.disabled']::text[]),
  ('webhook.failed', array['webhook_endpoint.failed']::text[]),
  ('webhook.secret_rotated', array['webhook_endpoint.secret_rotated']::text[]),
  ('work_item.*', array['task.*']::text[]),
  ('work_item.archived', array['task.archived']::text[]),
  ('work_item.assigned', array['task.assigned']::text[]),
  ('work_item.closed', array['task.closed']::text[]),
  ('work_item.created', array['task.created']::text[]),
  ('work_item.deleted', array['task.deleted']::text[]),
  ('work_item.reopened', array['task.reopened']::text[]),
  ('work_item.updated', array['task.updated']::text[]),
  ('workflow.*', array['workflow_definition.*']::text[]),
  ('workflow.published', array['workflow_definition.published']::text[])
)
update "better_supabase"."outbox_consumers" t set "types" = array(
  select distinct x from unnest(t."types" || array(
    select n from unnest(t."types") o join m on m.old_type = o
    cross join unnest(m.next_types) n
  )) x order by x
)
where t."types" && array(select old_type from m);

insert into better_supabase.blocks (name, version, mode)
values ('outbox', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
