-- better-supabase module: webhooks-out (0.8.0)
-- @bs-module webhooks-out@5 adopt
-- Outgoing webhooks: endpoints subscribed to event types, a delivery log unique per endpoint and event with leases and retries, direct dispatch, secrets in Vault with overlap while rotating, auto-disable after an endpoint keeps failing and redelivery.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
drop trigger if exists "bs_webhook_endpoint_reenable" on "centrakit"."webhook_destinations";
drop trigger if exists "bs_webhook_secret_vault" on "centrakit"."webhook_destination_secrets";

drop function if exists "better_supabase"."publish_webhook_event"(text, jsonb, uuid, text);
-- Queues the event for every enabled endpoint subscribed to its type:
-- the exact type, '*', or a prefix pattern such as 'invoice.*'. The
-- patterns that can match are built from the type, so && uses the GIN
-- index on the subscriptions. The same event id never queues twice for one
-- endpoint. An endpoint only gets events its owner may read: a user's
-- endpoint needs read_permission (the module's view permission when unset)
-- in the tenant; one without a user owner is a service principal's: the
-- tenant's default principal needs read_permission through its role when
-- the service-principals module is installed and the tenant has one, else
-- the endpoint needs read_permission among its declared permissions.
create or replace function "better_supabase"."publish_webhook_event"(event_type text, payload jsonb, tenant uuid default null, event_id text default null, subject text default null, read_permission text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  inserted integer;
  segments text[] := string_to_array(publish_webhook_event.event_type, '.');
  patterns text[];
  v_permission text := coalesce(nullif(publish_webhook_event.read_permission, ''), 'webhook.view');
  v_held text[];
begin
  if coalesce(publish_webhook_event.event_type, '') = '' then
    raise exception 'An event type is required' using errcode = '22023', hint = 'WEBHOOK_TYPE_REQUIRED';
  end if;
  patterns := array[publish_webhook_event.event_type, '*'] || array(
    select array_to_string(segments[1:i], '.') || '.*'
    from generate_series(1, cardinality(segments) - 1) i
  );
  v_held := array[v_permission, '*'] || array(
    select array_to_string(p[1:i], '.') || '.*'
    from (select string_to_array(v_permission, '.') as p) parts,
      generate_series(1, cardinality(parts.p) - 1) i
  );
  insert into "centrakit"."webhook_deliveries" ("destination_id", "event_kind", "payload", "organization_id", "event_id")
  select d."id", publish_webhook_event.event_type, coalesce(publish_webhook_event.payload, '{}'), d."organization_id", publish_webhook_event.event_id::uuid
  from "centrakit"."webhook_destinations" d
  where d."enabled"
    and d."organization_id" is not distinct from publish_webhook_event.tenant
    and d."event_kinds" && patterns
    and (case when d."created_by" is not null then d."organization_id"::text in (select t.id::text from centrakit.authz_organization_ids_with_for(d."created_by", v_permission) as t(id)) else publish_webhook_event.read_permission is null end)
  on conflict ("destination_id", "event_id") where "event_id" is not null do nothing;
  get diagnostics inserted = row_count;
  return inserted;
end;
$$;
revoke execute on function "better_supabase"."publish_webhook_event"(text, jsonb, uuid, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."publish_webhook_event"(text, jsonb, uuid, text, text, text) to service_role;

-- publish_webhook_event for a batch of events in one call (the outbox
-- sink): each element takes its argument names as keys, keeps its checks
-- and returns {"count"} or {"error"} in order.
create or replace function "better_supabase"."publish_webhook_events"(events jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  batch_event jsonb;
  results jsonb := '[]';
  batch_result integer;
  failed_state text;
  failed_message text;
  failed_hint text;
begin
  if pg_catalog.jsonb_typeof(events) is distinct from 'array' then
    raise exception '"publish_webhook_events" takes a jsonb array of events'
      using errcode = '22023', hint = 'WEBHOOK_BATCH_NOT_ARRAY';
  end if;
  if pg_catalog.jsonb_array_length(events) > 1000 then
    raise exception '"publish_webhook_events" got % events, more than 1000', pg_catalog.jsonb_array_length(events)
      using errcode = '22023', hint = 'WEBHOOK_BATCH_TOO_LARGE';
  end if;
  for batch_event in select e from pg_catalog.jsonb_array_elements(events) e loop
    begin
      batch_result := "better_supabase"."publish_webhook_event"(
        event_type => batch_event ->> 'event_type',
        payload => coalesce(nullif(batch_event -> 'payload', 'null'::jsonb), '{}'),
        tenant => (batch_event ->> 'tenant')::uuid,
        event_id => batch_event ->> 'event_id',
        subject => batch_event ->> 'subject',
        read_permission => batch_event ->> 'read_permission'
      );
      results := results || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('count', batch_result));
    exception when others then
      get stacked diagnostics
        failed_state = returned_sqlstate,
        failed_message = message_text,
        failed_hint = pg_exception_hint;
      results := results || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object('code', failed_state, 'message', failed_message, 'hint', nullif(failed_hint, ''))
      ));
    end;
  end loop;
  return results;
end;
$$;
revoke execute on function "better_supabase"."publish_webhook_events"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."publish_webhook_events"(jsonb) to service_role;

-- Sends one event to one endpoint, outside its subscriptions, e.g. from a
-- workflow step. With an event id, dispatching it again returns the first delivery.
create or replace function "better_supabase"."dispatch_webhook"(endpoint uuid, event_type text, payload jsonb, run_id text default null, event_id text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_enabled boolean;
  v_id uuid;
begin
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if coalesce(dispatch_webhook.event_type, '') = '' then
    raise exception 'An event type is required' using errcode = '22023', hint = 'WEBHOOK_TYPE_REQUIRED';
  end if;
  select d."organization_id", d."enabled" into v_tenant, v_enabled
  from "centrakit"."webhook_destinations" d where d."id" = dispatch_webhook.endpoint;
  if not found then
    raise exception 'Webhook endpoint not found' using errcode = 'P0002', hint = 'WEBHOOK_ENDPOINT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.can('tenant', v_tenant, 'webhook.manage'), false) then
    raise exception 'Not allowed to manage this webhook endpoint' using errcode = '42501', hint = 'WEBHOOK_FORBIDDEN';
  end if;
  if not v_enabled then
    raise exception 'Webhook endpoint is disabled' using errcode = '55000', hint = 'WEBHOOK_ENDPOINT_DISABLED';
  end if;
  if dispatch_webhook.event_id is not null then
    select v."id" into v_id from "centrakit"."webhook_deliveries" v
    where v."destination_id" = dispatch_webhook.endpoint and v."event_id" = dispatch_webhook.event_id::uuid;
    if v_id is not null then
      return v_id;
    end if;
  end if;
  insert into "centrakit"."webhook_deliveries" ("destination_id", "event_kind", "payload", "organization_id", "workflow_run_id", "event_id")
  values (dispatch_webhook.endpoint, dispatch_webhook.event_type, coalesce(dispatch_webhook.payload, '{}'), v_tenant, dispatch_webhook.run_id::uuid, dispatch_webhook.event_id::uuid)
  on conflict ("destination_id", "event_id") where "event_id" is not null do nothing
  returning "id" into v_id;
  if v_id is null then
    -- Another transaction dispatched the same event first.
    select v."id" into v_id from "centrakit"."webhook_deliveries" v
    where v."destination_id" = dispatch_webhook.endpoint and v."event_id" = dispatch_webhook.event_id::uuid;
  end if;
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."dispatch_webhook"(uuid, text, jsonb, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."dispatch_webhook"(uuid, text, jsonb, text, text) to authenticated, service_role;

drop function if exists "better_supabase"."claim_webhook_deliveries"(integer, interval);
-- Leases due deliveries to one worker and counts the attempt, so a worker
-- that dies mid-send still uses one up. The attempt is the lease token that
-- complete_webhook_delivery checks. Deliveries of disabled endpoints are
-- canceled instead, a lease that ran out is claimed again, and one that ran
-- out on the last attempt is dead-lettered.
create or replace function "better_supabase"."claim_webhook_deliveries"(max_items integer default 25, lease interval default '2 minutes', max_attempts integer default 8)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  result jsonb;
begin
  update "centrakit"."webhook_deliveries" v
  set "status" = 'canceled', "leased_until" = null, "last_error" = 'Endpoint is disabled', "processed_at" = now(), "updated_at" = now()
  from "centrakit"."webhook_destinations" d
  where d."id" = v."destination_id"
    and not d."enabled"
    and v."status" in ('pending', 'failed');

  update "centrakit"."webhook_deliveries" v
  set "status" = 'dead_lettered', "leased_until" = null, "last_error" = 'The lease ran out on the last attempt', "processed_at" = now(), "updated_at" = now()
  where v."status" = 'processing'
    and v."leased_until" <= now()
    and v."attempt" >= greatest(1, coalesce(claim_webhook_deliveries.max_attempts, 8));

  with due as (
    select v."id" as id
    from "centrakit"."webhook_deliveries" v
    where v."status" in ('pending', 'failed', 'processing')
      and v."available_at" <= now()
      and (v."leased_until" is null or v."leased_until" <= now())
    order by v."available_at", v."created_at"
    for update skip locked
    limit greatest(1, least(coalesce(claim_webhook_deliveries.max_items, 25), 100))
  ),
  claimed as (
    update "centrakit"."webhook_deliveries" v
    set "status" = 'processing',
      "attempt" = v."attempt" + 1,
      "leased_until" = now() + coalesce(claim_webhook_deliveries.lease, '2 minutes'), "updated_at" = now()
    from due
    where v."id" = due.id
    returning v.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', c."id",
    'endpoint_id', c."destination_id",
    'type', c."event_kind",
    'payload', c."payload",
    'attempt', c."attempt",
    'url', d."url",
    'created_at', c."created_at", 'tenant', c."organization_id", 'event_id', c."event_id", 'run_id', c."workflow_run_id", 'owner', d."created_by"
  ) order by c."available_at"), '[]')
  into result
  from claimed c
  join "centrakit"."webhook_destinations" d on d."id" = c."destination_id";
  return result;
end;
$$;
revoke execute on function "better_supabase"."claim_webhook_deliveries"(integer, interval, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."claim_webhook_deliveries"(integer, interval, integer) to service_role;

-- Records an attempt for the worker that holds the lease: outcome.attempt
-- must be the attempt the claim returned, and a delivery claimed again in
-- the meantime returns 'stale' unchanged. 'retrying' retries at retry_at, and
-- an endpoint that keeps failing for disableAfter is disabled.
create or replace function "better_supabase"."complete_webhook_delivery"(delivery uuid, outcome jsonb)
returns text
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_status text := complete_webhook_delivery.outcome ->> 'status';
  v_attempt integer := (complete_webhook_delivery.outcome ->> 'attempt')::integer;
  v_endpoint uuid;
  v_tenant uuid;
  v_since timestamptz;
  v_result text := 'ok';
begin
  if v_status is null or v_status not in ('succeeded', 'retrying', 'dead', 'canceled') then
    raise exception 'status must be succeeded, retrying, dead or canceled' using errcode = '22023', hint = 'WEBHOOK_STATUS_UNKNOWN';
  end if;
  if v_attempt is null then
    raise exception 'outcome.attempt must be the attempt the claim returned' using errcode = '22023', hint = 'WEBHOOK_ATTEMPT_REQUIRED';
  end if;
  update "centrakit"."webhook_deliveries" v
  set "status" = case v_status when 'pending' then 'pending' when 'delivering' then 'processing' when 'succeeded' then 'completed' when 'retrying' then 'failed' when 'dead' then 'dead_lettered' when 'canceled' then 'canceled' end,
    "attempt" = case when v_status = 'canceled' then greatest(v."attempt" - 1, 0) else v."attempt" end,
    "available_at" = case when v_status = 'retrying' then coalesce((complete_webhook_delivery.outcome ->> 'retry_at')::timestamptz, now()) else v."available_at" end,
    "leased_until" = null,
    "response_status" = (complete_webhook_delivery.outcome ->> 'response_status')::integer,
    "response_body" = complete_webhook_delivery.outcome ->> 'response_body',
    "duration_ms" = (complete_webhook_delivery.outcome ->> 'duration_ms')::integer,
    "last_error" = complete_webhook_delivery.outcome ->> 'error',
    "processed_at" = case when v_status = 'retrying' then null else now() end,
    "updated_at" = now()
  where v."id" = complete_webhook_delivery.delivery
    and v."attempt" = v_attempt
    and v."status" = 'processing'
  returning v."destination_id" into v_endpoint;
  if not found then
    if exists (select 1 from "centrakit"."webhook_deliveries" v where v."id" = complete_webhook_delivery.delivery) then
      return 'stale';
    end if;
    raise exception 'Webhook delivery not found' using errcode = 'P0002', hint = 'WEBHOOK_DELIVERY_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_webhook_delivery"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using complete_webhook_delivery.delivery, v_status;
    end if;
  end;
  return v_result;
end;
$$;
revoke execute on function "better_supabase"."complete_webhook_delivery"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."complete_webhook_delivery"(uuid, jsonb) to service_role;

-- Queues a finished delivery again, e.g. after the receiver fixed a bug.
create or replace function "better_supabase"."redeliver_webhook"(delivery uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_endpoint uuid;
  v_status text;
  v_tenant uuid;
  v_enabled boolean;
begin
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select v."destination_id", v."status" into v_endpoint, v_status
  from "centrakit"."webhook_deliveries" v where v."id" = redeliver_webhook.delivery;
  if not found then
    raise exception 'Webhook delivery not found' using errcode = 'P0002', hint = 'WEBHOOK_DELIVERY_NOT_FOUND';
  end if;
  select d."organization_id", d."enabled" into v_tenant, v_enabled
  from "centrakit"."webhook_destinations" d where d."id" = v_endpoint;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.can('tenant', v_tenant, 'webhook.manage'), false) then
    raise exception 'Not allowed to manage this webhook endpoint' using errcode = '42501', hint = 'WEBHOOK_FORBIDDEN';
  end if;
  if v_status in ('pending', 'processing') then
    raise exception 'The delivery is still in progress' using errcode = '55000', hint = 'WEBHOOK_DELIVERY_IN_PROGRESS';
  end if;
  if not v_enabled then
    raise exception 'Webhook endpoint is disabled' using errcode = '55000', hint = 'WEBHOOK_ENDPOINT_DISABLED';
  end if;
  update "centrakit"."webhook_deliveries" v
  set "status" = 'pending', "attempt" = 0, "available_at" = now(), "leased_until" = null, "processed_at" = null, "last_error" = null, "updated_at" = now()
  where v."id" = redeliver_webhook.delivery;
  return redeliver_webhook.delivery;
end;
$$;
revoke execute on function "better_supabase"."redeliver_webhook"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."redeliver_webhook"(uuid) to authenticated, service_role;

-- Deletes up to batch finished deliveries (and dead ones with include_dead)
-- created before older_than. A purged event id can be queued again for the
-- same endpoint, so keep older_than above the window you republish in.
-- Nightly with pg_cron: select cron.schedule('purge-webhook-deliveries', '45 3 * * *', 'select "better_supabase"."purge_webhook_deliveries"()');
create or replace function "better_supabase"."purge_webhook_deliveries"(older_than interval default '30 days', include_dead boolean default false, batch integer default 10000)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_purged integer;
begin
  with purged as (
    delete from "centrakit"."webhook_deliveries"
    where "id" in (
      select v."id" from "centrakit"."webhook_deliveries" v
      where (v."created_at" < now() - least(purge_webhook_deliveries.older_than, "better_supabase"."retention_floor"('webhook_deliveries'))
      and v."created_at" < now() - coalesce("better_supabase"."retention_for"('webhook_deliveries', (v."organization_id")::text), purge_webhook_deliveries.older_than)
      and not "better_supabase"."is_held"('webhook_deliveries', (v."organization_id")::text))
        and (
          v."status" in ('completed', 'canceled')
          or (purge_webhook_deliveries.include_dead and v."status" = 'dead_lettered')
        )
      limit purge_webhook_deliveries.batch
    )
    returning 1
  )
  select count(*)::integer into v_purged from purged;
  return v_purged;
end;
$$;
revoke execute on function "better_supabase"."purge_webhook_deliveries"(interval, boolean, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."purge_webhook_deliveries"(interval, boolean, integer) to service_role;

-- A new signing secret, returned once. Older secrets keep signing for
-- overlap, so receivers can switch without dropping deliveries.
create or replace function "better_supabase"."rotate_webhook_secret"(endpoint uuid, overlap interval default '24 hours', secret text default null)
returns text
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_enabled boolean;
  v_secret text := coalesce(
    rotate_webhook_secret.secret,
    'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
  );
begin
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select d."organization_id", d."enabled" into v_tenant, v_enabled
  from "centrakit"."webhook_destinations" d where d."id" = rotate_webhook_secret.endpoint;
  if not found then
    raise exception 'Webhook endpoint not found' using errcode = 'P0002', hint = 'WEBHOOK_ENDPOINT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.can('tenant', v_tenant, 'webhook.manage'), false) then
    raise exception 'Not allowed to manage this webhook endpoint' using errcode = '42501', hint = 'WEBHOOK_FORBIDDEN';
  end if;
  if length(v_secret) < 16 then
    raise exception 'A webhook secret needs at least 16 characters' using errcode = '22023', hint = 'WEBHOOK_SECRET_TOO_SHORT';
  end if;
  delete from "centrakit"."webhook_destination_secrets" s where s."destination_id" = rotate_webhook_secret.endpoint;
  insert into "centrakit"."webhook_destination_secrets" ("destination_id", "secret", "organization_id")
  values (rotate_webhook_secret.endpoint, v_secret, v_tenant);
  perform "better_supabase".emit_event('webhook.secret_rotated', jsonb_build_object('endpointId', rotate_webhook_secret.endpoint, 'organizationId', v_tenant::text), 'webhooks/' || rotate_webhook_secret.endpoint::text, (v_tenant)::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'webhook.secret_rotated',
    category => 'security',
    target_type => 'webhook_endpoint',
    record_id => rotate_webhook_secret.endpoint::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('endpointId', rotate_webhook_secret.endpoint, 'organizationId', v_tenant::text)
  );
  return v_secret;
end;
$$;
revoke execute on function "better_supabase"."rotate_webhook_secret"(uuid, interval, text) from public, anon, authenticated;
grant execute on function "better_supabase"."rotate_webhook_secret"(uuid, interval, text) to authenticated, service_role;

-- The secrets that sign an endpoint's deliveries: the current one first, then by age.
create or replace function "better_supabase"."webhook_secrets"(endpoint uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(x.secret order by x.expires desc nulls first, x.created desc), '{}')
  from (
    select s."secret" as secret, null::timestamptz as expires, s."created_at" as created
    from "centrakit"."webhook_destination_secrets" s
    where s."destination_id" = webhook_secrets.endpoint
  ) x
$$;
revoke execute on function "better_supabase"."webhook_secrets"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."webhook_secrets"(uuid) to service_role;

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
