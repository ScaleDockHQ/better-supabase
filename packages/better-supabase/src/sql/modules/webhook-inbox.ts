import type { SqlModule } from "../module-types.ts";

import { SCHEMA, serviceOnly, lockTable } from "../shared.ts";

export const WEBHOOK_INBOX: SqlModule = {
  name: "webhook-inbox",
  title: "Webhook inbox",
  description:
    "Stores verified webhooks once per message id, per tenant when given, then processes them with leases, retries and checkpoints.",
  requires: [],
  target: "schema",
  version: 5,
  upgrades: [
    {
      from: 1,
      description:
        "Messages record a tenant and a checkpoint; receive_webhook and purge_webhooks take a tenant, and checkpoint_webhook and list_webhooks are new.",
      sql: () =>
        "drop function if exists better_supabase.receive_webhook(text, text, text, jsonb, jsonb);\ndrop function if exists better_supabase.purge_webhooks(interval, boolean, integer);",
    },
    {
      from: 2,
      description:
        "receive_webhook takes the source's max_attempts; claims mark a message whose last attempt lost its worker as dead.",
      sql: () =>
        "drop function if exists better_supabase.receive_webhook(text, text, text, jsonb, jsonb, text);",
    },
    {
      from: 3,
      description:
        "Message ids are unique per source and tenant, so two tenants of one provider can send the same id.",
      sql: () => "",
    },
    {
      from: 4,
      description:
        "complete_webhook, fail_webhook and checkpoint_webhook take the claimed attempt as the lease token, extend_webhook renews a lease, and purge_webhooks has indexes.",
      sql: () =>
        [
          "drop function if exists better_supabase.complete_webhook(bigint, text);",
          "drop function if exists better_supabase.fail_webhook(bigint, text, text, interval);",
          "drop function if exists better_supabase.checkpoint_webhook(bigint, text, jsonb);",
        ].join("\n"),
    },
  ],
  sql: `${SCHEMA}

create table if not exists better_supabase.webhook_inbox (
  id bigint generated always as identity primary key,
  source text not null,
  message_id text not null,
  event_type text,
  payload jsonb not null,
  headers jsonb not null default '{}',
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'processed', 'dead')),
  attempts integer not null default 0,
  max_attempts integer not null default 8,
  available_at timestamptz not null default now(),
  locked_by text,
  locked_until timestamptz,
  last_error text,
  received_at timestamptz not null default now(),
  processed_at timestamptz
);
-- The tenant a message belongs to (a per-tenant integration), and progress a
-- handler saved mid-processing (checkpoint_webhook), such as a provider cursor.
alter table better_supabase.webhook_inbox add column if not exists tenant text;
alter table better_supabase.webhook_inbox add column if not exists checkpoint jsonb not null default '{}';
-- Message ids are unique per source and tenant: two tenants of one provider
-- can send the same id. A null tenant counts as one tenant.
do $$
begin
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'better_supabase.webhook_inbox'::regclass
      and conname = 'webhook_inbox_source_tenant_message_id_key'
  ) then
    alter table better_supabase.webhook_inbox
      add constraint webhook_inbox_source_tenant_message_id_key
      unique nulls not distinct (source, tenant, message_id);
  end if;
end;
$$;
alter table better_supabase.webhook_inbox drop constraint if exists webhook_inbox_source_message_id_key;
create index if not exists webhook_inbox_ready_idx
  on better_supabase.webhook_inbox (source, available_at, id) where status in ('pending', 'processing');
create index if not exists webhook_inbox_tenant_idx
  on better_supabase.webhook_inbox (tenant, received_at) where tenant is not null;
-- purge_webhooks: processed messages by processed_at, dead ones by received_at.
create index if not exists webhook_inbox_processed_idx
  on better_supabase.webhook_inbox (processed_at) where status = 'processed';
create index if not exists webhook_inbox_dead_idx
  on better_supabase.webhook_inbox (received_at) where status = 'dead';

${lockTable("better_supabase.webhook_inbox")}

-- The signatures before messages had a tenant, before a source set its
-- attempts, and before the attempt was the lease token.
drop function if exists better_supabase.receive_webhook(text, text, text, jsonb, jsonb);
drop function if exists better_supabase.purge_webhooks(interval, boolean, integer);
drop function if exists better_supabase.receive_webhook(text, text, text, jsonb, jsonb, text);
drop function if exists better_supabase.complete_webhook(bigint, text);
drop function if exists better_supabase.fail_webhook(bigint, text, text, interval);
drop function if exists better_supabase.checkpoint_webhook(bigint, text, jsonb);

-- duplicate = true when the source and tenant saw the message id before (the sender retried).
-- max_attempts is the source's limit, 8 when null.
create or replace function better_supabase.receive_webhook(
  source text,
  message_id text,
  event_type text,
  payload jsonb,
  headers jsonb default '{}',
  tenant text default null,
  max_attempts integer default null
)
returns table (id bigint, duplicate boolean)
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  inbox_id bigint;
begin
  insert into better_supabase.webhook_inbox (source, message_id, event_type, payload, headers, tenant, max_attempts)
  values (source, message_id, event_type, payload, headers, receive_webhook.tenant, greatest(coalesce(receive_webhook.max_attempts, 8), 1))
  on conflict on constraint webhook_inbox_source_tenant_message_id_key do nothing
  returning webhook_inbox.id into inbox_id;
  if inbox_id is not null then
    return query select inbox_id, false;
    return;
  end if;
  return query
    select w.id, true from better_supabase.webhook_inbox w
    where w.source = receive_webhook.source
      and w.tenant is not distinct from receive_webhook.tenant
      and w.message_id = receive_webhook.message_id;
end;
$$;

-- A message whose lease ran out on its last attempt lost its worker
-- (fail_webhook marks it dead otherwise), so the claim marks it dead.
create or replace function better_supabase.claim_webhooks(
  source text,
  worker text,
  batch integer default 10,
  lease interval default '5 minutes'
)
returns setof better_supabase.webhook_inbox
language sql
set search_path = ''
as $$
  update better_supabase.webhook_inbox d
  set status = 'dead', last_error = 'The lease ran out on the last attempt', locked_by = null, locked_until = null
  where d.source = claim_webhooks.source and d.status = 'processing'
    and d.locked_until < now() and d.attempts >= d.max_attempts;
  with next as materialized (
    select c.id from better_supabase.webhook_inbox c
    where c.source = claim_webhooks.source
      and (
        (c.status = 'pending' and c.available_at <= now())
        or (c.status = 'processing' and c.locked_until < now())
      )
    order by c.available_at, c.id
    for update skip locked
    limit batch
  )
  update better_supabase.webhook_inbox w
  set status = 'processing', attempts = w.attempts + 1, locked_by = worker, locked_until = now() + lease
  from next
  where w.id = next.id
  returning w.*
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
    update better_supabase.webhook_inbox
    set status = 'processed', processed_at = now(), locked_by = null, locked_until = null, last_error = null
    where id = inbox_id and locked_by = worker and status = 'processing'
      and (attempt is null or attempts = attempt)
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
  update better_supabase.webhook_inbox
  set status = case when attempts >= max_attempts then 'dead' else 'pending' end,
      available_at = now() + coalesce(retry_in, least(interval '1 hour', interval '1 second' * power(2, attempts))),
      last_error = left(error, 4000),
      locked_by = null,
      locked_until = null
  where id = inbox_id and locked_by = worker and status = 'processing'
    and (attempt is null or attempts = attempt)
  returning status
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
  update better_supabase.webhook_inbox
  set locked_until = now() + lease
  where id = inbox_id and locked_by = worker and status = 'processing'
    and attempts = attempt
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
    update better_supabase.webhook_inbox
    set checkpoint = checkpoint || coalesce(fields, '{}')
    where id = inbox_id and locked_by = worker and status = 'processing'
      and (attempt is null or attempts = attempt)
    returning 1
  )
  select exists (select 1 from saved)
$$;

-- A tenant's messages, newest first, optionally of one source or status.
create or replace function better_supabase.list_webhooks(
  for_tenant text,
  for_source text default null,
  for_status text default null,
  max_rows integer default 100
)
returns setof better_supabase.webhook_inbox
language sql
stable
set search_path = ''
as $$
  select w.* from better_supabase.webhook_inbox w
  where w.tenant = for_tenant
    and (for_source is null or w.source = for_source)
    and (for_status is null or w.status = for_status)
  order by w.received_at desc, w.id desc
  limit least(greatest(max_rows, 1), 1000)
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
language sql
set search_path = ''
as $$
  with purged as (
    delete from better_supabase.webhook_inbox
    where id in (
      select w.id from better_supabase.webhook_inbox w
      where ((w.status = 'processed' and w.processed_at < now() - older_than)
        or (include_dead and w.status = 'dead' and w.received_at < now() - older_than))
        and (for_tenant is null or w.tenant = for_tenant)
      order by w.id
      limit batch
    )
    returning 1
  )
  select count(*)::integer from purged
$$;

${serviceOnly([
  "receive_webhook(text, text, text, jsonb, jsonb, text, integer)",
  "claim_webhooks(text, text, integer, interval)",
  "complete_webhook(bigint, text, integer)",
  "fail_webhook(bigint, text, text, interval, integer)",
  "extend_webhook(bigint, text, integer, interval)",
  "checkpoint_webhook(bigint, text, jsonb, integer)",
  "list_webhooks(text, text, text, integer)",
  "purge_webhooks(interval, boolean, integer, text)",
])}`,
};
