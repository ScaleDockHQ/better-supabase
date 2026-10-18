-- better-supabase module: webhook-inbox (0.8.0)
-- @bs-module webhook-inbox@8 adopt
-- Stores verified webhooks once per message id, per tenant when given, then processes them with leases, retries and checkpoints; adopt mode runs over an app's table.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- The webhook inbox over an app's table (adopt mode): "centrakit"."inbound_webhook_events".
-- The app owns its columns, a unique key per source, tenant and message id,
-- and its indexes.

-- The signatures before messages had a tenant, before a source set its
-- attempts, and before the attempt was the lease token.
drop function if exists better_supabase.receive_webhook(text, text, text, jsonb, jsonb);
drop function if exists better_supabase.purge_webhooks(interval, boolean, integer);
drop function if exists better_supabase.receive_webhook(text, text, text, jsonb, jsonb, text);
drop function if exists better_supabase.complete_webhook(bigint, text);
drop function if exists better_supabase.fail_webhook(bigint, text, text, interval);
drop function if exists better_supabase.checkpoint_webhook(bigint, text, jsonb);
drop function if exists better_supabase.receive_webhook(text, text, text, jsonb, jsonb, text, integer);
drop function if exists better_supabase.receive_webhook(text, text, text, jsonb, jsonb, text, integer, jsonb);
drop function if exists better_supabase.claim_webhooks(text, text, integer, interval);
drop function if exists better_supabase.list_webhooks(text, text, text, integer);

-- { id, duplicate }: duplicate = true when the source and tenant saw the
-- message id before (the sender retried). max_attempts is the source's
-- limit, 8 when null. fields: the extra columns of a new message.
create or replace function better_supabase.receive_webhook(
  source text,
  message_id text,
  event_type text,
  payload jsonb,
  headers jsonb default '{}',
  tenant text default null,
  max_attempts integer default null
)
returns jsonb
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  inbox_id bigint;
begin
  -- The adopted table's unique constraint is unknown, so a lock per
  -- message serializes the lookup and the insert.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('webhook-inbox'), pg_catalog.hashtext(concat_ws(':', source, receive_webhook.tenant, message_id)));
  select w."id" into inbox_id from "centrakit"."inbound_webhook_events" w
  where w."source" = receive_webhook.source
    and w."organization_id"::text is not distinct from receive_webhook.tenant
    and w."external_id" = receive_webhook.message_id
  limit 1;
  if inbox_id is not null then
    return jsonb_build_object('id', inbox_id, 'duplicate', true);
  end if;
  insert into "centrakit"."inbound_webhook_events" ("source", "external_id", "event_kind", "payload", "organization_id")
  values (source, message_id, event_type, payload, (jsonb_populate_record(null::"centrakit"."inbound_webhook_events", jsonb_build_object('organization_id', receive_webhook.tenant)))."organization_id")
  returning "id" into inbox_id;
  return jsonb_build_object('id', inbox_id, 'duplicate', false);
end;
$$;

-- The claimed messages, a jsonb array. A message whose lease ran out on its
-- last attempt lost its worker (fail_webhook marks it dead otherwise), so the
-- claim marks it dead.
create or replace function better_supabase.claim_webhooks(
  source text,
  worker text,
  batch integer default 10,
  lease interval default '5 minutes'
)
returns jsonb
language sql
set search_path = ''
as $$
  update "centrakit"."inbound_webhook_events" d
  set "status" = 'dead', "last_error" = 'The lease ran out on the last attempt', "locked_by" = null, "locked_until" = null
  where d."source" = claim_webhooks.source and d."status" = 'processing'
    and d."locked_until" < now() and d."attempts" >= 8;
  with next as materialized (
    select c."id" from "centrakit"."inbound_webhook_events" c
    where c."source" = claim_webhooks.source
      and (
        (c."status" = 'pending' and c."available_at" <= now())
        or (c."status" = 'processing' and c."locked_until" < now())
      )
    order by c."available_at", c."id"
    for update skip locked
    limit batch
  ),
  claimed as (
    update "centrakit"."inbound_webhook_events" w
    set "status" = 'processing', "attempts" = w."attempts" + 1, "locked_by" = worker, "locked_until" = now() + lease
    from next
    where w."id" = next."id"
    returning w."id" as id, jsonb_build_object('id', w."id", 'source', w."source", 'message_id', w."external_id", 'event_type', w."event_kind", 'payload', w."payload", 'headers', '{}'::jsonb, 'status', w."status", 'attempts', w."attempts", 'max_attempts', 8, 'available_at', w."available_at", 'locked_by', w."locked_by", 'locked_until', w."locked_until", 'last_error', w."last_error", 'received_at', w."received_at", 'processed_at', w."processed_at", 'tenant', w."organization_id"::text, 'checkpoint', '{}'::jsonb) as message
  )
  select coalesce(jsonb_agg(claimed.message order by claimed.id), '[]'::jsonb) from claimed
$$;

-- attempt is the attempts value the claim returned: it is the lease token,
-- so a call that lost its lease (and the claim that took the message over,
-- even under the same worker name) can't complete, fail or extend it.
-- Without attempt, the worker name alone decides.
create or replace function better_supabase.complete_webhook(inbox_id bigint, worker text, attempt integer default null)
returns boolean
language sql
set search_path = ''
as $$
  with done as (
    update "centrakit"."inbound_webhook_events"
    set "status" = 'processed', "processed_at" = now(), "locked_by" = null, "locked_until" = null, "last_error" = null
    where "id" = inbox_id and "locked_by" = worker and "status" = 'processing'
      and (attempt is null or "attempts" = attempt)
    returning 1
  )
  select exists (select 1 from done)
$$;

create or replace function better_supabase.fail_webhook(
  inbox_id bigint,
  worker text,
  error text,
  retry_in interval default null,
  attempt integer default null
)
returns text
language sql
set search_path = ''
as $$
  update "centrakit"."inbound_webhook_events"
  set "status" = case when "attempts" >= 8 then 'dead' else 'pending' end,
      "available_at" = now() + coalesce(retry_in, least(interval '1 hour', interval '1 second' * power(2, "attempts"))),
      "last_error" = left(error, 4000),
      "locked_by" = null,
      "locked_until" = null
  where "id" = inbox_id and "locked_by" = worker and "status" = 'processing'
    and (attempt is null or "attempts" = attempt)
  returning "status"
$$;

-- Renews the lease of a message the worker still holds for lease more, and
-- returns the lease in seconds; no row when the lease was lost.
create or replace function better_supabase.extend_webhook(
  inbox_id bigint,
  worker text,
  attempt integer,
  lease interval default '5 minutes'
)
returns double precision
language sql
set search_path = ''
as $$
  update "centrakit"."inbound_webhook_events"
  set "locked_until" = now() + lease
  where "id" = inbox_id and "locked_by" = worker and "status" = 'processing'
    and "attempts" = attempt
  returning extract(epoch from lease)::double precision
$$;

-- Saves progress for a message the worker still holds, merged into its
-- checkpoint, so a retry resumes there. False when the lease was lost.
create or replace function better_supabase.checkpoint_webhook(inbox_id bigint, worker text, fields jsonb, attempt integer default null)
returns boolean
language sql
set search_path = ''
as $$
  with saved as (
    update "centrakit"."inbound_webhook_events"
    set "locked_by" = "locked_by"
    where "id" = inbox_id and "locked_by" = worker and "status" = 'processing'
      and (attempt is null or "attempts" = attempt)
    returning 1
  )
  select exists (select 1 from saved)
$$;

-- A tenant's messages, newest first, optionally of one source or status, as
-- a jsonb array.
create or replace function better_supabase.list_webhooks(
  for_tenant text,
  for_source text default null,
  for_status text default null,
  max_rows integer default 100
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.message order by x.n), '[]'::jsonb)
  from (
    select jsonb_build_object('id', w."id", 'source', w."source", 'message_id', w."external_id", 'event_type', w."event_kind", 'payload', w."payload", 'headers', '{}'::jsonb, 'status', w."status", 'attempts', w."attempts", 'max_attempts', 8, 'available_at', w."available_at", 'locked_by', w."locked_by", 'locked_until', w."locked_until", 'last_error', w."last_error", 'received_at', w."received_at", 'processed_at', w."processed_at", 'tenant', w."organization_id"::text, 'checkpoint', '{}'::jsonb) as message, row_number() over (order by w."received_at" desc, w."id" desc) as n
    from "centrakit"."inbound_webhook_events" w
    where w."organization_id"::text = for_tenant
      and (for_source is null or w."source" = for_source)
      and (for_status is null or w."status" = for_status)
    order by w."received_at" desc, w."id" desc
    limit least(greatest(max_rows, 1), 1000)
  ) x
$$;

-- Deletes up to batch processed messages (and dead ones with include_dead)
-- older than older_than, of one tenant when for_tenant is set (all of that
-- tenant's messages, whatever their status, with older_than '0'). A sender
-- that retries a purged message id gets it stored again, so keep older_than
-- above the sender's retry window.
-- Nightly with pg_cron: select cron.schedule('purge-webhooks', '30 3 * * *', 'select better_supabase.purge_webhooks()');
create or replace function better_supabase.purge_webhooks(
  older_than interval default '30 days',
  include_dead boolean default false,
  batch integer default 10000,
  for_tenant text default null
)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_purged integer;
begin
  with purged as (
    delete from "centrakit"."inbound_webhook_events"
    where "id" in (
      select w."id" from "centrakit"."inbound_webhook_events" w
      where ((w."status" = 'processed' and (w."processed_at" < now() - least(older_than, "better_supabase"."retention_floor"('webhooks'))
      and w."processed_at" < now() - coalesce("better_supabase"."retention_for"('webhooks', (w."organization_id")::text), older_than)
      and not "better_supabase"."is_held"('webhooks', (w."organization_id")::text)))
        or (include_dead and w."status" = 'dead' and (w."received_at" < now() - least(older_than, "better_supabase"."retention_floor"('webhooks'))
      and w."received_at" < now() - coalesce("better_supabase"."retention_for"('webhooks', (w."organization_id")::text), older_than)
      and not "better_supabase"."is_held"('webhooks', (w."organization_id")::text))))
        and (for_tenant is null or w."organization_id"::text = for_tenant)
      order by w."id"
      limit batch
    )
    returning 1
  )
  select count(*)::integer into v_purged from purged;
  return v_purged;
end;
$$;

revoke execute on function better_supabase.receive_webhook(text, text, text, jsonb, jsonb, text, integer) from public, anon, authenticated;
grant execute on function better_supabase.receive_webhook(text, text, text, jsonb, jsonb, text, integer) to service_role;
revoke execute on function better_supabase.claim_webhooks(text, text, integer, interval) from public, anon, authenticated;
grant execute on function better_supabase.claim_webhooks(text, text, integer, interval) to service_role;
revoke execute on function better_supabase.complete_webhook(bigint, text, integer) from public, anon, authenticated;
grant execute on function better_supabase.complete_webhook(bigint, text, integer) to service_role;
revoke execute on function better_supabase.fail_webhook(bigint, text, text, interval, integer) from public, anon, authenticated;
grant execute on function better_supabase.fail_webhook(bigint, text, text, interval, integer) to service_role;
revoke execute on function better_supabase.extend_webhook(bigint, text, integer, interval) from public, anon, authenticated;
grant execute on function better_supabase.extend_webhook(bigint, text, integer, interval) to service_role;
revoke execute on function better_supabase.checkpoint_webhook(bigint, text, jsonb, integer) from public, anon, authenticated;
grant execute on function better_supabase.checkpoint_webhook(bigint, text, jsonb, integer) to service_role;
revoke execute on function better_supabase.list_webhooks(text, text, text, integer) from public, anon, authenticated;
grant execute on function better_supabase.list_webhooks(text, text, text, integer) to service_role;
revoke execute on function better_supabase.purge_webhooks(interval, boolean, integer, text) from public, anon, authenticated;
grant execute on function better_supabase.purge_webhooks(interval, boolean, integer, text) to service_role;

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
