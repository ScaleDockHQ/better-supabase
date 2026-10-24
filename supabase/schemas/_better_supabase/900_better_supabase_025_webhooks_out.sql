-- better-supabase module: webhooks-out
-- @bsb-block webhooks-out@5 managed
-- @bsb-hash sha256:8406659f39c44692145a929e135366a092434be0510bb3d68cadc555a3f1068f
-- Outgoing webhooks: endpoints subscribed to event types, a delivery log unique per endpoint and event with leases and retries, direct dispatch, secrets in Vault with overlap while rotating, auto-disable after an endpoint keeps failing and redelivery.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
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
create table if not exists "better_supabase"."webhook_endpoints" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "name" text not null check (length(trim("name")) > 0),
  "url" text not null check ("url" ~* '^https://'),
  "enabled" boolean not null default true,
  "event_types" text[] not null default '{}',
  "permissions" text[],
  "batch" boolean not null default false,
  "signing" text not null default 'v1' check ("signing" in ('v1', 'v1a')),
  "format" text not null default 'cloudevents' check ("format" ~ '^[a-z][a-z0-9-]{0,39}$'),
  "credential_ref" jsonb check ("credential_ref" is null or (jsonb_typeof("credential_ref") = 'object' and "credential_ref" ? 'provider')),
  "failing_since" timestamptz,
  "disabled_at" timestamptz,
  "disabled_reason" text,
  "created_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
alter table "better_supabase"."webhook_endpoints" add column if not exists "permissions" text[];
alter table "better_supabase"."webhook_endpoints" add column if not exists "batch" boolean not null default false;
alter table "better_supabase"."webhook_endpoints" add column if not exists "signing" text not null default 'v1' check ("signing" in ('v1', 'v1a'));
alter table "better_supabase"."webhook_endpoints" add column if not exists "format" text not null default 'cloudevents' check ("format" ~ '^[a-z][a-z0-9-]{0,39}$');
alter table "better_supabase"."webhook_endpoints" add column if not exists "credential_ref" jsonb check ("credential_ref" is null or (jsonb_typeof("credential_ref") = 'object' and "credential_ref" ? 'provider'));
alter table "better_supabase"."webhook_endpoints" alter column "format" set default 'cloudevents';
create index if not exists webhook_endpoints_types_idx on "better_supabase"."webhook_endpoints" using gin ("event_types");
create index if not exists webhook_endpoints_tenant_idx on "better_supabase"."webhook_endpoints" ("organization_id");
create index if not exists webhook_endpoints_created_by_idx on "better_supabase"."webhook_endpoints" ("created_by");
alter table "better_supabase"."webhook_endpoints" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."webhook_endpoints";
create trigger bsb_updated_at before update on "better_supabase"."webhook_endpoints"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."webhook_endpoints" enable row level security;
revoke all on "better_supabase"."webhook_endpoints" from anon, authenticated;
grant all on "better_supabase"."webhook_endpoints" to service_role;
grant select, insert, update, delete on "better_supabase"."webhook_endpoints" to authenticated;
drop policy if exists "bsb_webhook_endpoints_read" on "better_supabase"."webhook_endpoints";
create policy "bsb_webhook_endpoints_read" on "better_supabase"."webhook_endpoints" for select to authenticated using ("organization_id" in (select better_supabase.tenant_ids_with('webhooks.read')));
drop policy if exists bsb_webhook_endpoints_write on "better_supabase"."webhook_endpoints";
drop policy if exists "bsb_webhook_endpoints_insert" on "better_supabase"."webhook_endpoints";
create policy "bsb_webhook_endpoints_insert" on "better_supabase"."webhook_endpoints" for insert to authenticated with check (("organization_id" in (select better_supabase.tenant_ids_with('webhooks.manage'))) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_webhook_endpoints_update" on "better_supabase"."webhook_endpoints";
create policy "bsb_webhook_endpoints_update" on "better_supabase"."webhook_endpoints" for update to authenticated using (("organization_id" in (select better_supabase.tenant_ids_with('webhooks.manage'))) and (select better_supabase.actor_may_write())) with check (("organization_id" in (select better_supabase.tenant_ids_with('webhooks.manage'))) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_webhook_endpoints_delete" on "better_supabase"."webhook_endpoints";
create policy "bsb_webhook_endpoints_delete" on "better_supabase"."webhook_endpoints" for delete to authenticated using (("organization_id" in (select better_supabase.tenant_ids_with('webhooks.manage'))) and (select better_supabase.actor_may_write()));

create table if not exists "better_supabase"."webhook_endpoint_secrets" (
  "id" uuid primary key default gen_random_uuid(),
  "endpoint_id" uuid not null references "better_supabase"."webhook_endpoints" ("id") on delete cascade,
  "organization_id" uuid,
  "vault_secret_id" uuid not null,
  "expires_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create index if not exists webhook_endpoint_secrets_endpoint_idx on "better_supabase"."webhook_endpoint_secrets" ("endpoint_id");
alter table "better_supabase"."webhook_endpoint_secrets" enable row level security;
revoke all on "better_supabase"."webhook_endpoint_secrets" from anon, authenticated;
grant all on "better_supabase"."webhook_endpoint_secrets" to service_role;

create table if not exists "better_supabase"."webhook_deliveries" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid,
  "endpoint_id" uuid not null references "better_supabase"."webhook_endpoints" ("id") on delete cascade,
  "event_id" text,
  "run_id" text,
  "event_type" text not null,
  "subject" text,
  "payload" jsonb not null default '{}',
  "status" text not null default 'pending' check ("status" in ('pending', 'delivering', 'succeeded', 'retrying', 'dead', 'canceled')),
  "attempt" integer not null default 0 check ("attempt" >= 0),
  "available_at" timestamptz not null default now(),
  "leased_until" timestamptz,
  "response_status" integer,
  "response_body" text,
  "duration_ms" integer,
  "last_error" text,
  "processed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
alter table "better_supabase"."webhook_deliveries" add column if not exists "subject" text;
create index if not exists webhook_deliveries_due_idx on "better_supabase"."webhook_deliveries" ("available_at", "leased_until") where "status" in ('pending', 'retrying', 'delivering');
create index if not exists webhook_deliveries_endpoint_idx on "better_supabase"."webhook_deliveries" ("endpoint_id", "created_at" desc);
create index if not exists webhook_deliveries_open_idx on "better_supabase"."webhook_deliveries" ("endpoint_id") where "status" in ('pending', 'retrying');
create index if not exists webhook_deliveries_finished_idx on "better_supabase"."webhook_deliveries" ("created_at") where "status" in ('succeeded', 'canceled', 'dead');
create index if not exists webhook_deliveries_tenant_created_idx on "better_supabase"."webhook_deliveries" ("organization_id", "created_at" desc);
create unique index if not exists webhook_deliveries_endpoint_event_idx on "better_supabase"."webhook_deliveries" ("endpoint_id", "event_id") where "event_id" is not null;
alter table "better_supabase"."webhook_deliveries" enable row level security;
revoke all on "better_supabase"."webhook_deliveries" from anon, authenticated;
grant all on "better_supabase"."webhook_deliveries" to service_role;
grant select on "better_supabase"."webhook_deliveries" to authenticated;
drop policy if exists "bsb_webhook_deliveries_read" on "better_supabase"."webhook_deliveries";
create policy "bsb_webhook_deliveries_read" on "better_supabase"."webhook_deliveries" for select to authenticated using ("organization_id" in (select better_supabase.tenant_ids_with('webhooks.read')));

create or replace function "better_supabase"."reset_webhook_endpoint"()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new."enabled" and not old."enabled" then
    new."failing_since" := null;
    new."disabled_at" := null;
    new."disabled_reason" := null;
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."reset_webhook_endpoint"() from public, anon, authenticated;
drop trigger if exists "bsb_webhook_endpoint_reenable" on "better_supabase"."webhook_endpoints";
create trigger "bsb_webhook_endpoint_reenable" before update of "enabled" on "better_supabase"."webhook_endpoints"
  for each row execute function "better_supabase"."reset_webhook_endpoint"();

create or replace function "better_supabase"."drop_webhook_vault_secret"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from vault.secrets vs where vs.id = old."vault_secret_id";
  return null;
end;
$$;
revoke execute on function "better_supabase"."drop_webhook_vault_secret"() from public, anon, authenticated;
drop trigger if exists "bsb_webhook_secret_vault" on "better_supabase"."webhook_endpoint_secrets";
create trigger "bsb_webhook_secret_vault" after delete on "better_supabase"."webhook_endpoint_secrets"
  for each row execute function "better_supabase"."drop_webhook_vault_secret"();

drop function if exists "better_supabase"."publish_webhook_event"(text, jsonb, uuid, text);
-- Queues the event for every enabled endpoint subscribed to its type:
-- the exact type, '*', or a prefix pattern such as 'invoice.*'. The
-- patterns that can match are built from the type, so && uses the GIN
-- index on the subscriptions. The same event id never queues twice for one
-- endpoint. An endpoint only gets events its owner may read: a user's
-- endpoint needs read_permission (the module's view permission when unset)
-- in the tenant; one without a user owner is a service principal's: the
-- tenant's default principal needs read_permission through its role when
-- the service-accounts module is installed and the tenant has one, else
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
  v_permission text := coalesce(nullif(publish_webhook_event.read_permission, ''), 'webhooks.read');
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
  insert into "better_supabase"."webhook_deliveries" ("endpoint_id", "event_type", "payload", "organization_id", "event_id", "subject")
  select d."id", publish_webhook_event.event_type, coalesce(publish_webhook_event.payload, '{}'), d."organization_id", publish_webhook_event.event_id::text, publish_webhook_event.subject
  from "better_supabase"."webhook_endpoints" d
  where d."enabled"
    and d."organization_id" is not distinct from publish_webhook_event.tenant
    and d."event_types" && patterns
    and (case when d."created_by" is not null then coalesce(better_supabase.can_user(d."created_by", 'tenant', d."organization_id", v_permission), false) else (case when "better_supabase"."default_service_principal"(d."organization_id") is not null then coalesce(better_supabase.can_user("better_supabase"."default_service_principal"(d."organization_id"), 'tenant', d."organization_id", v_permission), false) else (publish_webhook_event.read_permission is null or coalesce(d."permissions" && v_held, false)) end) end)
  on conflict ("endpoint_id", "event_id") where "event_id" is not null do nothing;
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if coalesce(dispatch_webhook.event_type, '') = '' then
    raise exception 'An event type is required' using errcode = '22023', hint = 'WEBHOOK_TYPE_REQUIRED';
  end if;
  select d."organization_id", d."enabled" into v_tenant, v_enabled
  from "better_supabase"."webhook_endpoints" d where d."id" = dispatch_webhook.endpoint;
  if not found then
    raise exception 'Webhook endpoint not found' using errcode = 'P0002', hint = 'WEBHOOK_ENDPOINT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.can('tenant', v_tenant, 'webhooks.manage'), false) then
    raise exception 'Not allowed to manage this webhook endpoint' using errcode = '42501', hint = 'WEBHOOK_FORBIDDEN';
  end if;
  if not v_enabled then
    raise exception 'Webhook endpoint is disabled' using errcode = '55000', hint = 'WEBHOOK_ENDPOINT_DISABLED';
  end if;
  if dispatch_webhook.event_id is not null then
    select v."id" into v_id from "better_supabase"."webhook_deliveries" v
    where v."endpoint_id" = dispatch_webhook.endpoint and v."event_id" = dispatch_webhook.event_id::text;
    if v_id is not null then
      return v_id;
    end if;
  end if;
  insert into "better_supabase"."webhook_deliveries" ("endpoint_id", "event_type", "payload", "organization_id", "run_id", "event_id")
  values (dispatch_webhook.endpoint, dispatch_webhook.event_type, coalesce(dispatch_webhook.payload, '{}'), v_tenant, dispatch_webhook.run_id::text, dispatch_webhook.event_id::text)
  on conflict ("endpoint_id", "event_id") where "event_id" is not null do nothing
  returning "id" into v_id;
  if v_id is null then
    -- Another transaction dispatched the same event first.
    select v."id" into v_id from "better_supabase"."webhook_deliveries" v
    where v."endpoint_id" = dispatch_webhook.endpoint and v."event_id" = dispatch_webhook.event_id::text;
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
  update "better_supabase"."webhook_deliveries" v
  set "status" = 'canceled', "leased_until" = null, "last_error" = 'Endpoint is disabled', "processed_at" = now(), "updated_at" = now()
  from "better_supabase"."webhook_endpoints" d
  where d."id" = v."endpoint_id"
    and not d."enabled"
    and v."status" in ('pending', 'retrying');

  update "better_supabase"."webhook_deliveries" v
  set "status" = 'dead', "leased_until" = null, "last_error" = 'The lease ran out on the last attempt', "processed_at" = now(), "updated_at" = now()
  where v."status" = 'delivering'
    and v."leased_until" <= now()
    and v."attempt" >= greatest(1, coalesce(claim_webhook_deliveries.max_attempts, 8));

  with due as (
    select v."id" as id
    from "better_supabase"."webhook_deliveries" v
    where v."status" in ('pending', 'retrying', 'delivering')
      and v."available_at" <= now()
      and (v."leased_until" is null or v."leased_until" <= now())
    order by v."available_at", v."created_at"
    for update skip locked
    limit greatest(1, least(coalesce(claim_webhook_deliveries.max_items, 25), 100))
  ),
  claimed as (
    update "better_supabase"."webhook_deliveries" v
    set "status" = 'delivering',
      "attempt" = v."attempt" + 1,
      "leased_until" = now() + coalesce(claim_webhook_deliveries.lease, '2 minutes'), "updated_at" = now()
    from due
    where v."id" = due.id
    returning v.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', c."id",
    'endpoint_id', c."endpoint_id",
    'type', c."event_type",
    'payload', c."payload",
    'attempt', c."attempt",
    'url', d."url",
    'created_at', c."created_at", 'tenant', c."organization_id", 'event_id', c."event_id", 'run_id', c."run_id", 'subject', c."subject", 'owner', d."created_by", 'principal', case when d."created_by" is null then "better_supabase"."default_service_principal"(d."organization_id") end, 'permissions', d."permissions", 'batch', d."batch", 'signing', d."signing", 'format', d."format", 'credential_ref', d."credential_ref"
  ) order by c."available_at"), '[]')
  into result
  from claimed c
  join "better_supabase"."webhook_endpoints" d on d."id" = c."endpoint_id";
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
  update "better_supabase"."webhook_deliveries" v
  set "status" = v_status,
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
    and v."status" = 'delivering'
  returning v."endpoint_id" into v_endpoint;
  if not found then
    if exists (select 1 from "better_supabase"."webhook_deliveries" v where v."id" = complete_webhook_delivery.delivery) then
      return 'stale';
    end if;
    raise exception 'Webhook delivery not found' using errcode = 'P0002', hint = 'WEBHOOK_DELIVERY_NOT_FOUND';
  end if;
  if v_status = 'succeeded' then
    update "better_supabase"."webhook_endpoints" d set "failing_since" = null
    where d."id" = v_endpoint and d."failing_since" is not null;
  elsif v_status in ('retrying', 'dead') then
    update "better_supabase"."webhook_endpoints" d set "failing_since" = coalesce(d."failing_since", now())
    where d."id" = v_endpoint
    returning d."failing_since", d."organization_id" into v_since, v_tenant;
    if v_since <= now() - '5 days'::interval then
      update "better_supabase"."webhook_endpoints" d set "enabled" = false, "disabled_at" = now(), "disabled_reason" = format('Deliveries failed since %s', v_since), "updated_at" = now()
      where d."id" = v_endpoint and d."enabled";
      if found then
        v_result := 'disabled';
        perform "better_supabase".emit_event('webhook.disabled', jsonb_build_object('endpointId', v_endpoint, 'organizationId', v_tenant::text, 'failingSince', v_since), 'webhooks/' || v_endpoint::text, (v_tenant::text)::text, 'webhook.disabled:' || v_endpoint::text || ':' || v_since::text, 'better-supabase/webhooks-out');
  perform better_supabase.audit_event(
    event_type => 'webhook.disabled',
    category => 'integration',
    target_type => 'webhook_endpoint',
    record_id => v_endpoint::text,
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('endpointId', v_endpoint, 'organizationId', v_tenant::text, 'failingSince', v_since),
    idempotency_key => 'webhook.disabled:' || v_endpoint::text || ':' || v_since::text
  );
      end if;
    end if;
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select v."endpoint_id", v."status" into v_endpoint, v_status
  from "better_supabase"."webhook_deliveries" v where v."id" = redeliver_webhook.delivery;
  if not found then
    raise exception 'Webhook delivery not found' using errcode = 'P0002', hint = 'WEBHOOK_DELIVERY_NOT_FOUND';
  end if;
  select d."organization_id", d."enabled" into v_tenant, v_enabled
  from "better_supabase"."webhook_endpoints" d where d."id" = v_endpoint;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.can('tenant', v_tenant, 'webhooks.manage'), false) then
    raise exception 'Not allowed to manage this webhook endpoint' using errcode = '42501', hint = 'WEBHOOK_FORBIDDEN';
  end if;
  if v_status in ('pending', 'delivering') then
    raise exception 'The delivery is still in progress' using errcode = '55000', hint = 'WEBHOOK_DELIVERY_IN_PROGRESS';
  end if;
  if not v_enabled then
    raise exception 'Webhook endpoint is disabled' using errcode = '55000', hint = 'WEBHOOK_ENDPOINT_DISABLED';
  end if;
  update "better_supabase"."webhook_deliveries" v
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
    delete from "better_supabase"."webhook_deliveries"
    where "id" in (
      select v."id" from "better_supabase"."webhook_deliveries" v
      where (v."created_at" < now() - least(purge_webhook_deliveries.older_than, "better_supabase"."retention_floor"('webhook_deliveries'))
      and v."created_at" < now() - coalesce("better_supabase"."retention_for"('webhook_deliveries', (v."organization_id")::text), purge_webhook_deliveries.older_than)
      and not "better_supabase"."is_held"('webhook_deliveries', (v."organization_id")::text))
        and (
          v."status" in ('succeeded', 'canceled')
          or (purge_webhook_deliveries.include_dead and v."status" = 'dead')
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
  v_vault uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select d."organization_id", d."enabled" into v_tenant, v_enabled
  from "better_supabase"."webhook_endpoints" d where d."id" = rotate_webhook_secret.endpoint;
  if not found then
    raise exception 'Webhook endpoint not found' using errcode = 'P0002', hint = 'WEBHOOK_ENDPOINT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.can('tenant', v_tenant, 'webhooks.manage'), false) then
    raise exception 'Not allowed to manage this webhook endpoint' using errcode = '42501', hint = 'WEBHOOK_FORBIDDEN';
  end if;
  if length(v_secret) < 16 then
    raise exception 'A webhook secret needs at least 16 characters' using errcode = '22023', hint = 'WEBHOOK_SECRET_TOO_SHORT';
  end if;
  delete from vault.secrets vs using "better_supabase"."webhook_endpoint_secrets" s where vs.id = s."vault_secret_id" and s."endpoint_id" = rotate_webhook_secret.endpoint and s."expires_at" <= now();
  delete from "better_supabase"."webhook_endpoint_secrets" s where s."endpoint_id" = rotate_webhook_secret.endpoint and s."expires_at" <= now();
  update "better_supabase"."webhook_endpoint_secrets" s set "expires_at" = now() + coalesce(rotate_webhook_secret.overlap, '24 hours')
  where s."endpoint_id" = rotate_webhook_secret.endpoint and s."expires_at" is null;
  v_vault := vault.create_secret(
    v_secret,
    'webhook:' || rotate_webhook_secret.endpoint::text || ':' || gen_random_uuid()::text,
    'better-supabase outgoing webhook signing secret'
  );
  insert into "better_supabase"."webhook_endpoint_secrets" ("endpoint_id", "vault_secret_id", "organization_id")
  values (rotate_webhook_secret.endpoint, v_vault, v_tenant);
  perform "better_supabase".emit_event('webhook.secret_rotated', jsonb_build_object('endpointId', rotate_webhook_secret.endpoint, 'organizationId', v_tenant::text), 'webhooks/' || rotate_webhook_secret.endpoint::text, (v_tenant)::text, null, 'better-supabase/webhooks-out');
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
    select ds.decrypted_secret as secret, s."expires_at" as expires, s."created_at" as created
    from "better_supabase"."webhook_endpoint_secrets" s
    join vault.decrypted_secrets ds on ds.id = s."vault_secret_id"
    where s."endpoint_id" = webhook_secrets.endpoint
      and (s."expires_at" is null or s."expires_at" > now())
  ) x
$$;
revoke execute on function "better_supabase"."webhook_secrets"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."webhook_secrets"(uuid) to service_role;

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
drop policy if exists bsb_tenant_scope on "better_supabase"."webhook_endpoints";
create policy bsb_tenant_scope on "better_supabase"."webhook_endpoints" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("organization_id" in (select better_supabase.tenant_ids_with('webhooks.read')))
    or ("organization_id" in (select better_supabase.tenant_ids_with('webhooks.manage')))
  )
  with check (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("organization_id" in (select better_supabase.tenant_ids_with('webhooks.manage')))
  );
drop policy if exists bsb_tenant_scope on "better_supabase"."webhook_deliveries";
create policy bsb_tenant_scope on "better_supabase"."webhook_deliveries" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("organization_id" in (select better_supabase.tenant_ids_with('webhooks.read')))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));

-- blocks.webhooks-out.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."publish_webhook_event"(text, jsonb, uuid, text);
drop function if exists "api"."claim_webhook_deliveries"(integer, interval);

create or replace function "api"."actor_may_write"()
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."actor_may_write"() $$;
revoke execute on function "api"."actor_may_write"() from public;
grant execute on function "api"."actor_may_write"() to anon, authenticated, service_role;

create or replace function "api"."raise_actor_readonly"()
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."raise_actor_readonly"() $$;
revoke execute on function "api"."raise_actor_readonly"() from public;
grant execute on function "api"."raise_actor_readonly"() to anon, authenticated, service_role;

create or replace function "api"."publish_webhook_event"(event_type text, payload jsonb, tenant uuid default null, event_id text default null, subject text default null, read_permission text default null)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."publish_webhook_event"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."publish_webhook_event"(text, jsonb, uuid, text, text, text) from public, anon, authenticated;
grant execute on function "api"."publish_webhook_event"(text, jsonb, uuid, text, text, text) to service_role;

create or replace function "api"."publish_webhook_events"(events jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."publish_webhook_events"($1) $$;
revoke execute on function "api"."publish_webhook_events"(jsonb) from public, anon, authenticated;
grant execute on function "api"."publish_webhook_events"(jsonb) to service_role;

create or replace function "api"."dispatch_webhook"(endpoint uuid, event_type text, payload jsonb, run_id text default null, event_id text default null)
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."dispatch_webhook"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."dispatch_webhook"(uuid, text, jsonb, text, text) from public, anon;
grant execute on function "api"."dispatch_webhook"(uuid, text, jsonb, text, text) to authenticated, service_role;

create or replace function "api"."claim_webhook_deliveries"(max_items integer default 25, lease interval default '2 minutes', max_attempts integer default 8)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."claim_webhook_deliveries"($1, $2, $3) $$;
revoke execute on function "api"."claim_webhook_deliveries"(integer, interval, integer) from public, anon, authenticated;
grant execute on function "api"."claim_webhook_deliveries"(integer, interval, integer) to service_role;

create or replace function "api"."complete_webhook_delivery"(delivery uuid, outcome jsonb)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."complete_webhook_delivery"($1, $2) $$;
revoke execute on function "api"."complete_webhook_delivery"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "api"."complete_webhook_delivery"(uuid, jsonb) to service_role;

create or replace function "api"."redeliver_webhook"(delivery uuid)
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."redeliver_webhook"($1) $$;
revoke execute on function "api"."redeliver_webhook"(uuid) from public, anon;
grant execute on function "api"."redeliver_webhook"(uuid) to authenticated, service_role;

create or replace function "api"."purge_webhook_deliveries"(older_than interval default '30 days', include_dead boolean default false, batch integer default 10000)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."purge_webhook_deliveries"($1, $2, $3) $$;
revoke execute on function "api"."purge_webhook_deliveries"(interval, boolean, integer) from public, anon, authenticated;
grant execute on function "api"."purge_webhook_deliveries"(interval, boolean, integer) to service_role;

create or replace function "api"."rotate_webhook_secret"(endpoint uuid, overlap interval default '24 hours', secret text default null)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."rotate_webhook_secret"($1, $2, $3) $$;
revoke execute on function "api"."rotate_webhook_secret"(uuid, interval, text) from public, anon;
grant execute on function "api"."rotate_webhook_secret"(uuid, interval, text) to authenticated, service_role;

create or replace function "api"."webhook_secrets"(endpoint uuid)
returns text[]
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."webhook_secrets"($1) $$;
revoke execute on function "api"."webhook_secrets"(uuid) from public, anon, authenticated;
grant execute on function "api"."webhook_secrets"(uuid) to service_role;

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;
