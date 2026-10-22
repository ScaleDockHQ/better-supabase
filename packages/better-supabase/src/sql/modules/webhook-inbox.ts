import type { BlockSqlContext } from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlString } from "../../core/template.ts";
import {
  addExtraColumns,
  extraFieldsArg,
  lockTable,
  SCHEMA,
  serviceOnly,
  withExtraFields,
  writeExtraColumns,
} from "../shared.ts";

const MESSAGE_COLUMNS = {
  id: "id",
  source: "source",
  messageId: "message_id",
  eventType: "event_type",
  payload: "payload",
  headers: "headers",
  status: "status",
  attempts: "attempts",
  maxAttempts: "max_attempts",
  availableAt: "available_at",
  lockedBy: "locked_by",
  lockedUntil: "locked_until",
  lastError: "last_error",
  receivedAt: "received_at",
  processedAt: "processed_at",
  tenant: "tenant",
  checkpoint: "checkpoint",
} as const;

type MessageColumn = keyof typeof MESSAGE_COLUMNS;

/**
 * The keys of a row `claim_webhooks` and `list_webhooks` return, in the managed
 * table's order.
 */
const ROW: readonly (readonly [MessageColumn, string, string])[] = [
  ["id", "id", "bigint"],
  ["source", "source", "text"],
  ["messageId", "message_id", "text"],
  ["eventType", "event_type", "text"],
  ["payload", "payload", "jsonb"],
  ["headers", "headers", "jsonb"],
  ["status", "status", "text"],
  ["attempts", "attempts", "integer"],
  ["maxAttempts", "max_attempts", "integer"],
  ["availableAt", "available_at", "timestamptz"],
  ["lockedBy", "locked_by", "text"],
  ["lockedUntil", "locked_until", "timestamptz"],
  ["lastError", "last_error", "text"],
  ["receivedAt", "received_at", "timestamptz"],
  ["processedAt", "processed_at", "timestamptz"],
  ["tenant", "tenant", "text"],
  ["checkpoint", "checkpoint", "jsonb"],
];

const TABLE = `
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
`;

function webhookInboxSql(ctx: BlockSqlContext): string {
  const managed = ctx.manages;
  const renamed = Object.keys(ctx.config.columns["messages"] ?? {});

  if (managed && renamed.length > 0) {
    throw new TypeError(
      `blocks.webhook-inbox.columns.messages: the module owns its table, so ${renamed.join(", ")} can't be renamed; adopt your own table with ownership "adopt"`,
    );
  }

  const t = managed ? "better_supabase.webhook_inbox" : ctx.table("messages");

  // The managed table keeps its bare column names, so its SQL stays as before.
  const c = (logical: MessageColumn): string =>
    managed ? MESSAGE_COLUMNS[logical] : ctx.col("messages", logical);

  const has = (logical: MessageColumn): boolean =>
    managed || ctx.has("messages", logical);

  const set = (
    pairs: readonly (readonly [MessageColumn, string])[],
    separator = ", ",
  ): string =>
    pairs
      .filter(([logical]) => has(logical))
      .map(([logical, value]) => `${c(logical)} = ${value}`)
      .join(separator);

  const expired = (at: string): string =>
    ctx.expired("webhooks", {
      at,
      tenant: has("tenant") ? `w.${c("tenant")}` : "null",
      fallback: "older_than",
    });

  // An adopted tenant column can be uuid or bigint; the functions take text.
  const tenantText = (alias: string) =>
    managed ? `${alias}.${c("tenant")}` : `${alias}.${c("tenant")}::text`;

  const tenantIs = (alias: string, value: string) =>
    has("tenant")
      ? `${tenantText(alias)} is not distinct from ${value}`
      : `${value} is null`;

  // The extra columns (options.extraColumns): receive_webhook writes them
  // from fields on a new message, the reads return them under fields.
  const extras = ctx.extraColumns("messages", ["fields"]);
  const extra = extraFieldsArg(extras);

  // A column the adopted table lacks reads as the managed table's default.
  const missing: Partial<Record<MessageColumn, string>> = {
    headers: "'{}'::jsonb",
    maxAttempts: "8",
    checkpoint: "'{}'::jsonb",
  };

  // A message as jsonb, keyed by the managed table's column names.
  const rowOf = (alias: string) =>
    withExtraFields(
      `jsonb_build_object(${ROW.map(
        ([logical, name, type]) =>
          `'${name}', ${
            has(logical)
              ? logical === "tenant"
                ? tenantText(alias)
                : `${alias}.${c(logical)}`
              : (missing[logical] ?? `null::${type}`)
          }`,
      ).join(", ")})`,
      alias,
      extras,
    );

  const maxAttempts = (alias: string) =>
    has("maxAttempts") ? `${alias}${c("maxAttempts")}` : "8";

  const inserted = (
    [
      ["source", "source"],
      ["messageId", "message_id"],
      ["eventType", "event_type"],
      ["payload", "payload"],
      ["headers", "headers"],
      [
        "tenant",
        managed
          ? "receive_webhook.tenant"
          : `(jsonb_populate_record(null::${t}, jsonb_build_object(${sqlString(c("tenant").replaceAll('"', ""))}, receive_webhook.tenant))).${c("tenant")}`,
      ],
      ["maxAttempts", "greatest(coalesce(receive_webhook.max_attempts, 8), 1)"],
    ] as const satisfies readonly (readonly [MessageColumn, string])[]
  ).filter(([logical]) => has(logical));

  const insert = `insert into ${t} (${inserted.map(([logical]) => c(logical)).join(", ")})
  values (${inserted.map(([, value]) => value).join(", ")})`;

  const stored = `${writeExtraColumns(t, extras, "receive_webhook.fields", `x.${c("id")} = inbox_id`)}
  return jsonb_build_object('id', inbox_id, 'duplicate', false);`;

  const receive = managed
    ? `  ${insert}
  on conflict on constraint webhook_inbox_source_tenant_message_id_key do nothing
  returning webhook_inbox.id into inbox_id;
  if inbox_id is not null then${stored.replaceAll("\n", "\n  ")}
  end if;
  select w.id into inbox_id from better_supabase.webhook_inbox w
  where w.source = receive_webhook.source
    and w.tenant is not distinct from receive_webhook.tenant
    and w.message_id = receive_webhook.message_id;
  return jsonb_build_object('id', inbox_id, 'duplicate', true);`
    : `  -- The adopted table's unique constraint is unknown, so a lock per
  -- message serializes the lookup and the insert.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('webhook-inbox'), pg_catalog.hashtext(concat_ws(':', source, receive_webhook.tenant, message_id)));
  select w.${c("id")} into inbox_id from ${t} w
  where w.${c("source")} = receive_webhook.source
    and ${tenantIs("w", "receive_webhook.tenant")}
    and w.${c("messageId")} = receive_webhook.message_id
  limit 1;
  if inbox_id is not null then
    return jsonb_build_object('id', inbox_id, 'duplicate', true);
  end if;
  ${insert}
  returning ${c("id")} into inbox_id;${stored}`;

  const leased = `${c("id")} = inbox_id and ${c("lockedBy")} = worker and ${c("status")} = 'processing'`;
  const attemptIs = `${c("attempts")} = attempt`;

  const checkpoint = has("checkpoint")
    ? `set ${c("checkpoint")} = ${c("checkpoint")} || coalesce(fields, '{}')`
    : `set ${c("lockedBy")} = ${c("lockedBy")}`;

  const tenantFilter = (alias: string, value: string) =>
    has("tenant") ? `${tenantText(alias)} = ${value}` : "false";

  // Every function a transport calls returns jsonb, so the earlier ones
  // that returned rows go first; receive_webhook with and without fields.
  const jsonbDrops = `
drop function if exists better_supabase.receive_webhook(text, text, text, jsonb, jsonb, text, integer);
${extra.drop("better_supabase.receive_webhook", "text, text, text, jsonb, jsonb, text, integer")}
drop function if exists better_supabase.claim_webhooks(text, text, integer, interval);
drop function if exists better_supabase.list_webhooks(text, text, text, integer);`;

  return `${SCHEMA}
${managed ? `${TABLE}${addExtraColumns(t, extras)}` : `\n-- The webhook inbox over an app's table (adopt mode): ${t}.\n-- The app owns its columns, a unique key per source, tenant and message id,\n-- and its indexes.\n`}
-- The signatures before messages had a tenant, before a source set its
-- attempts, and before the attempt was the lease token.
drop function if exists better_supabase.receive_webhook(text, text, text, jsonb, jsonb);
drop function if exists better_supabase.purge_webhooks(interval, boolean, integer);
drop function if exists better_supabase.receive_webhook(text, text, text, jsonb, jsonb, text);
drop function if exists better_supabase.complete_webhook(bigint, text);
drop function if exists better_supabase.fail_webhook(bigint, text, text, interval);
drop function if exists better_supabase.checkpoint_webhook(bigint, text, jsonb);${jsonbDrops}

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
  max_attempts integer default null${extra.param}
)
returns jsonb
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  inbox_id bigint;
begin
${receive}
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
  update ${t} d
  set ${set([
    ["status", "'dead'"],
    ["lastError", "'The lease ran out on the last attempt'"],
    ["lockedBy", "null"],
    ["lockedUntil", "null"],
  ])}
  where d.${c("source")} = claim_webhooks.source and d.${c("status")} = 'processing'
    and d.${c("lockedUntil")} < now() and d.${c("attempts")} >= ${maxAttempts("d.")};
  with next as materialized (
    select c.${c("id")} from ${t} c
    where c.${c("source")} = claim_webhooks.source
      and (
        (c.${c("status")} = 'pending' and c.${c("availableAt")} <= now())
        or (c.${c("status")} = 'processing' and c.${c("lockedUntil")} < now())
      )
    order by c.${c("availableAt")}, c.${c("id")}
    for update skip locked
    limit batch
  ),
  claimed as (
    update ${t} w
    set ${c("status")} = 'processing', ${c("attempts")} = w.${c("attempts")} + 1, ${c("lockedBy")} = worker, ${c("lockedUntil")} = now() + lease
    from next
    where w.${c("id")} = next.${c("id")}
    returning w.${c("id")} as id, ${rowOf("w")} as message
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
    update ${t}
    set ${set([
      ["status", "'processed'"],
      ["processedAt", "now()"],
      ["lockedBy", "null"],
      ["lockedUntil", "null"],
      ["lastError", "null"],
    ])}
    where ${leased}
      and (attempt is null or ${attemptIs})
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
  update ${t}
  set ${c("status")} = case when ${c("attempts")} >= ${maxAttempts("")} then 'dead' else 'pending' end,
      ${set(
        [
          [
            "availableAt",
            `now() + coalesce(retry_in, least(interval '1 hour', interval '1 second' * power(2, ${c("attempts")})))`,
          ],
          ["lastError", "left(error, 4000)"],
        ],
        ",\n      ",
      )},
      ${c("lockedBy")} = null,
      ${c("lockedUntil")} = null
  where ${leased}
    and (attempt is null or ${attemptIs})
  returning ${c("status")}
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
  update ${t}
  set ${c("lockedUntil")} = now() + lease
  where ${leased}
    and ${attemptIs}
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
    update ${t}
    ${checkpoint}
    where ${leased}
      and (attempt is null or ${attemptIs})
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
    select ${rowOf("w")} as message, row_number() over (order by w.${c("receivedAt")} desc, w.${c("id")} desc) as n
    from ${t} w
    where ${tenantFilter("w", "for_tenant")}
      and (for_source is null or w.${c("source")} = for_source)
      and (for_status is null or w.${c("status")} = for_status)
    order by w.${c("receivedAt")} desc, w.${c("id")} desc
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
    delete from ${t}
    where ${c("id")} in (
      select w.${c("id")} from ${t} w
      where ((w.${c("status")} = 'processed' and ${expired(has("processedAt") ? `w.${c("processedAt")}` : `w.${c("receivedAt")}`)})
        or (include_dead and w.${c("status")} = 'dead' and ${expired(`w.${c("receivedAt")}`)}))
        and (for_tenant is null or ${tenantFilter("w", "for_tenant")})
      order by w.${c("id")}
      limit batch
    )
    returning 1
  )
  select count(*)::integer into v_purged from purged;
  return v_purged;
end;
$$;

${serviceOnly([
  `receive_webhook(text, text, text, jsonb, jsonb, text, integer${extra.type})`,
  "claim_webhooks(text, text, integer, interval)",
  "complete_webhook(bigint, text, integer)",
  "fail_webhook(bigint, text, text, interval, integer)",
  "extend_webhook(bigint, text, integer, interval)",
  "checkpoint_webhook(bigint, text, jsonb, integer)",
  "list_webhooks(text, text, text, integer)",
  "purge_webhooks(interval, boolean, integer, text)",
])}`;
}

export const WEBHOOK_INBOX: BlockSqlDefinition = {
  name: "webhook-inbox",
  title: "Webhook inbox",
  description:
    "Stores verified webhooks once per message id, per tenant when given, then processes them with leases, retries and checkpoints; adopt mode runs over an app's table.",
  requires: [],
  integrates: ["data-lifecycle"],
  target: "schema",
  modes: ["managed", "adopt"],
  names: {
    options: ["extraColumns"],
    tables: {
      messages: {
        name: "webhook_inbox",
        columns: MESSAGE_COLUMNS,
        optional: [
          "eventType",
          "headers",
          "maxAttempts",
          "lastError",
          "processedAt",
          "tenant",
          "checkpoint",
        ],
      },
    },
  },
  version: 8,
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
    {
      from: 5,
      description:
        "Adopt mode stores messages in an app's table; the functions stay in better_supabase.",
      sql: () => "",
    },
    {
      from: 6,
      description:
        "receive_webhook, claim_webhooks and list_webhooks return jsonb, so the block calls them over any transport; options.extraColumns adds columns to the messages.",
      sql: () => "",
    },
    {
      from: 7,
      description:
        "purge_webhooks keeps messages for the data-lifecycle retention policy and skips those under a legal hold.",
      sql: () => "",
    },
  ],
  build: webhookInboxSql,
};
