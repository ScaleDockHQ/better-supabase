import type { AiKeysEvents } from "../../blocks/ai-keys/events.ts";
import type {
  BlockSqlContext,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";
import type { Columns } from "./module-columns.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  raise,
  schemaPreamble,
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
  revokeTable,
} from "../shared.ts";
import { tenantRefGuard } from "./credentials.ts";
import { asText } from "./over-app.ts";
import { moduleOperations } from "./permissions-model.ts";

const KEYS = {
  id: "id",
  tenant: "organization_id",
  provider: "provider",
  name: "name",
  credentialRef: "credential_ref",
  settings: "settings",
  enabled: "enabled",
  createdBy: "created_by",
  createdAt: "created_at",
  updatedAt: "updated_at",
} as const;

const BATCHES = {
  id: "id",
  tenant: "organization_id",
  user: "user_id",
  provider: "provider",
  reference: "reference",
  status: "status",
  rawStatus: "raw_status",
  itemCount: "item_count",
  counts: "counts",
  error: "error",
  metadata: "metadata",
  resultsSaved: "results_saved",
  polls: "polls",
  nextPollAt: "next_poll_at",
  expiresAt: "expires_at",
  completedAt: "completed_at",
  createdAt: "created_at",
  updatedAt: "updated_at",
} as const;

const ITEMS = {
  batch: "batch_id",
  request: "request_id",
  tenant: "organization_id",
  status: "status",
  output: "output",
  usage: "usage",
  error: "error",
  createdAt: "created_at",
} as const;

const EVENTS: BlockSqlEvents<AiKeysEvents> = {
  "ai_provider_key.saved": {
    subject: "organizations",
    payload: ["organizationId", "keyId", "provider", "name"],
  },
  "ai_provider_key.deleted": {
    subject: "organizations",
    payload: ["organizationId", "keyId", "provider", "name"],
  },
};

const NAMES: BlockSqlNames = {
  events: EVENTS,
  options: ["pollEvery"],
  tables: {
    keys: {
      name: "ai_provider_keys",
      columns: KEYS,
      lifecycle: { tenant: "tenant", credentials: ["credentialRef"] },
      app: {},
      optional: ["settings", "enabled", "createdBy", "createdAt", "updatedAt"],
    },
    batches: {
      name: "ai_batches",
      columns: BATCHES,
      lifecycle: { user: "user", tenant: "tenant" },
      app: {},
      optional: [
        "rawStatus",
        "itemCount",
        "counts",
        "error",
        "metadata",
        "polls",
        "expiresAt",
        "completedAt",
        "updatedAt",
      ],
      typed: ["status"],
    },
    items: {
      name: "ai_batch_items",
      columns: ITEMS,
      lifecycle: { tenant: "tenant" },
      app: {},
      optional: ["usage", "error", "createdAt"],
      typed: ["status"],
    },
  },
};

const SLUG = "^[a-z0-9][a-z0-9._-]{0,63}$";

/**
 * The quoted columns of `table`. A column the app's table lacks is empty, so
 * every use of an optional column checks `ctx.has` first.
 */
function presentColumns<T extends Readonly<Record<string, string>>>(
  ctx: BlockSqlContext,
  table: string,
  spec: T,
): Columns<T> {
  // SAFETY: the keys are spec's own keys, each mapped to its quoted name.
  return Object.fromEntries(
    Object.keys(spec).map((key) => [
      key,
      ctx.has(table, key) ? ctx.col(table, key) : "",
    ]),
  ) as Columns<T>;
}

/** `jsonb_build_object` over a spec's columns, `missing` for the ones absent. */
function presentJson(
  ctx: BlockSqlContext,
  table: string,
  spec: Readonly<Record<string, string>>,
  row: string,
  missing?: Readonly<Record<string, string>>,
): string {
  const pairs = Object.entries(spec).map(
    ([key, name]) =>
      `'${name}', ${ctx.has(table, key) ? `${row}.${ctx.col(table, key)}` : (missing?.[key] ?? "null")}`,
  );

  return `jsonb_build_object(${pairs.join(", ")})`;
}

const KEY_DEFAULTS = { settings: "'{}'::jsonb", enabled: "true" };

const BATCH_DEFAULTS = {
  itemCount: "0",
  counts: "'{}'::jsonb",
  metadata: "'{}'::jsonb",
  polls: "0",
};

function build(ctx: BlockSqlContext): string {
  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const k = presentColumns(ctx, "keys", KEYS);
  const b = presentColumns(ctx, "batches", BATCHES);
  const i = presentColumns(ctx, "items", ITEMS);
  const key = (column: keyof typeof KEYS): boolean => ctx.has("keys", column);

  const batch = (column: keyof typeof BATCHES): boolean =>
    ctx.has("batches", column);

  const item = (column: keyof typeof ITEMS): boolean =>
    ctx.has("items", column);

  const line = (present: boolean, definition: string): string =>
    present ? `\n  ${definition},` : "";

  const unique = (table: string, what: string, columns: string): string =>
    ctx.owns(table)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(table).name}_${what}_key`)} on ${ctx.table(table)} (${columns});`;

  const keys = ctx.table("keys");
  const batches = ctx.table("batches");
  const items = ctx.table("items");
  const permissions = moduleOperations("ai-keys");
  const use = ctx.permission("use", permissions.use);
  const manage = ctx.permission("manage", permissions.manage);
  const pollEvery = ctx.number("pollEvery", 60);

  if (!Number.isInteger(pollEvery) || pollEvery < 1) {
    throw new TypeError(
      "blocks.ai-keys.options.pollEvery must be a whole number of seconds",
    );
  }

  const keyJson = (row: string): string =>
    presentJson(ctx, "keys", KEYS, row, KEY_DEFAULTS);

  const keyEvent = (type: string, row: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${k.tenant}::text, 'keyId', ${row}.${k.id}, 'provider', ${row}.${k.provider}, 'name', ${row}.${k.name})`,
      subject: `'organizations/' || ${row}.${k.tenant}::text || '/ai-provider-keys/' || ${row}.${k.id}::text`,
      tenant: `${row}.${k.tenant}`,
      audit: {
        category: "security",
        targetType: "ai_provider_key",
        recordId: `${row}.${k.id}::text`,
        targetLabel: `${row}.${k.provider} || '/' || ${row}.${k.name}`,
      },
    });

  const batchJson = (row: string): string =>
    presentJson(ctx, "batches", BATCHES, row, BATCH_DEFAULTS);

  const itemJson = (row: string): string =>
    presentJson(ctx, "items", ITEMS, row);

  const batchStatus = (row: string): string =>
    asText(ctx, "batches", `${row}.${b.status}`);

  const keyInsert: readonly (readonly [string, string])[] = [
    [k.tenant, "save_ai_provider_key.tenant"],
    [k.provider, "save_ai_provider_key.provider"],
    [k.name, "coalesce(save_ai_provider_key.name, 'default')"],
    [k.credentialRef, "save_ai_provider_key.credential_ref"],
    ...(key("settings")
      ? ([
          [k.settings, "coalesce(save_ai_provider_key.settings, '{}')"],
        ] as const)
      : []),
    ...(key("enabled")
      ? ([[k.enabled, "coalesce(save_ai_provider_key.enabled, true)"]] as const)
      : []),
    ...(key("createdBy") ? ([[k.createdBy, "auth.uid()"]] as const) : []),
  ];

  const keyUpdate = [
    `${k.credentialRef} = excluded.${k.credentialRef}`,
    ...(key("settings") ? [`${k.settings} = excluded.${k.settings}`] : []),
    ...(key("enabled") ? [`${k.enabled} = excluded.${k.enabled}`] : []),
    ...(key("updatedAt") ? [`${k.updatedAt} = now()`] : []),
  ];

  const batchInsert: readonly (readonly [string, string])[] = [
    [b.tenant, "record_ai_batch.tenant"],
    [
      b.user,
      `case when ${SERVICE_CALLER} then (v_fields ->> 'user_id')::uuid else auth.uid() end`,
    ],
    [b.provider, "record_ai_batch.provider"],
    [b.reference, "record_ai_batch.reference"],
    [
      b.status,
      ctx.cast(
        "batches",
        "status",
        "coalesce(v_fields ->> 'status', 'pending')",
      ),
    ],
    ...(batch("rawStatus")
      ? ([[b.rawStatus, "v_fields ->> 'raw_status'"]] as const)
      : []),
    ...(batch("itemCount")
      ? ([
          [b.itemCount, "coalesce((v_fields ->> 'item_count')::integer, 0)"],
        ] as const)
      : []),
    ...(batch("counts")
      ? ([[b.counts, "coalesce(v_fields -> 'counts', '{}')"]] as const)
      : []),
    ...(batch("metadata")
      ? ([[b.metadata, "coalesce(v_fields -> 'metadata', '{}')"]] as const)
      : []),
    ...(batch("expiresAt")
      ? ([[b.expiresAt, "(v_fields ->> 'expires_at')::timestamptz"]] as const)
      : []),
    [b.nextPollAt, `now() + interval '${pollEvery} seconds'`],
  ];

  const batchUpdate = [
    `${b.status} = ${ctx.cast("batches", "status", `coalesce(v_fields ->> 'status', ${batchStatus("x")})`)}`,
    ...(batch("rawStatus")
      ? [
          `${b.rawStatus} = coalesce(v_fields ->> 'raw_status', x.${b.rawStatus})`,
        ]
      : []),
    ...(batch("counts")
      ? [`${b.counts} = coalesce(v_fields -> 'counts', x.${b.counts})`]
      : []),
    ...(batch("error")
      ? [
          `${b.error} = case when v_fields ? 'error' then left(v_fields ->> 'error', 4000) else x.${b.error} end`,
        ]
      : []),
    ...(batch("expiresAt")
      ? [
          `${b.expiresAt} = coalesce((v_fields ->> 'expires_at')::timestamptz, x.${b.expiresAt})`,
        ]
      : []),
    `${b.resultsSaved} = coalesce((v_fields ->> 'results_saved')::boolean, x.${b.resultsSaved})`,
    `${b.nextPollAt} = case when v_fields ? 'next_poll_at' then (v_fields ->> 'next_poll_at')::timestamptz else x.${b.nextPollAt} end`,
    ...(batch("completedAt")
      ? [
          `${b.completedAt} = case when coalesce(v_fields ->> 'status', ${batchStatus("x")}) <> 'pending' then coalesce(x.${b.completedAt}, now()) else null end`,
        ]
      : []),
    ...(batch("updatedAt") ? [`${b.updatedAt} = now()`] : []),
  ];

  const itemInsert: readonly (readonly [string, string])[] = [
    [i.batch, "save_ai_batch_items.id"],
    [i.request, "item ->> 'request_id'"],
    [i.tenant, "v_tenant"],
    [i.status, ctx.cast("items", "status", "item ->> 'status'")],
    [i.output, "item -> 'output'"],
    ...(item("usage") ? ([[i.usage, "item -> 'usage'"]] as const) : []),
    ...(item("error")
      ? ([[i.error, "left(item ->> 'error', 4000)"]] as const)
      : []),
  ];

  const enabledKey = (row: string): string =>
    key("enabled") ? ` and ${row}.${k.enabled}` : "";

  const refCheck = (column: string): string =>
    `check (jsonb_typeof(${column}) = 'object' and ${column} ? 'provider')`;

  return `${schemaPreamble(ctx)}
-- A tenant's own provider keys (BYOK). credential_ref names the key in a
-- CredentialProvider, such as Vault; the key itself is never stored here.
-- settings holds the provider's other options (a region, a project id) and
-- must not hold secrets.
create table if not exists ${keys} (
  ${k.id} uuid primary key default gen_random_uuid(),
  ${k.tenant} ${id} not null,
  ${k.provider} text not null check (${k.provider} ~ '${SLUG}'),
  ${k.name} text not null default 'default' check (length(${k.name}) between 1 and 100),
  ${k.credentialRef} jsonb not null ${refCheck(k.credentialRef)},${line(key("settings"), `${k.settings} jsonb not null default '{}' check (jsonb_typeof(${k.settings}) = 'object')`)}${line(key("enabled"), `${k.enabled} boolean not null default true`)}${line(key("createdBy"), `${k.createdBy} uuid references auth.users (id) on delete set null`)}${line(key("createdAt"), `${k.createdAt} timestamptz not null default now()`)}${line(key("updatedAt"), `${k.updatedAt} timestamptz not null default now()`)}
  unique (${k.tenant}, ${k.provider}, ${k.name})
);${unique("keys", "name", `${k.tenant}, ${k.provider}, ${k.name}`)}${key("createdBy") ? `\ncreate index if not exists ai_provider_keys_created_by_idx on ${keys} (${k.createdBy});` : ""}
alter table ${keys} enable row level security;
${revokeTable(keys)}
grant select on ${keys} to authenticated;
grant all on ${keys} to service_role;
drop policy if exists ai_provider_keys_read on ${keys};
create policy ai_provider_keys_read on ${keys} for select to authenticated
  using (${ctx.scope.check(k.tenant, manage)});

-- Batch jobs started with a provider's batch API, polled until they finish.
-- reference is the SDK's batch reference ({ version, id, provider }).
create table if not exists ${batches} (
  ${b.id} uuid primary key default gen_random_uuid(),
  ${b.tenant} ${id} not null,
  ${b.user} uuid references auth.users (id) on delete cascade,
  ${b.provider} text not null check (length(${b.provider}) between 1 and 100),
  ${b.reference} jsonb not null check (jsonb_typeof(${b.reference}) = 'object'),
  ${b.status} text not null default 'pending' check (${b.status} in ('pending', 'completed', 'failed', 'cancelled')),${line(batch("rawStatus"), `${b.rawStatus} text check (length(${b.rawStatus}) <= 100)`)}${line(batch("itemCount"), `${b.itemCount} integer not null default 0 check (${b.itemCount} >= 0)`)}${line(batch("counts"), `${b.counts} jsonb not null default '{}' check (jsonb_typeof(${b.counts}) = 'object')`)}${line(batch("error"), `${b.error} text check (length(${b.error}) <= 4000)`)}${line(batch("metadata"), `${b.metadata} jsonb not null default '{}' check (jsonb_typeof(${b.metadata}) = 'object')`)}
  ${b.resultsSaved} boolean not null default false,${line(batch("polls"), `${b.polls} integer not null default 0`)}
  ${b.nextPollAt} timestamptz default now(),${line(batch("expiresAt"), `${b.expiresAt} timestamptz`)}${line(batch("completedAt"), `${b.completedAt} timestamptz`)}
  ${b.createdAt} timestamptz not null default now()${batch("updatedAt") ? `,\n  ${b.updatedAt} timestamptz not null default now()` : ""}
);
create index if not exists ai_batches_due_idx on ${batches} (${b.nextPollAt}) where ${b.status} = 'pending' or not ${b.resultsSaved};
create index if not exists ai_batches_tenant_idx on ${batches} (${b.tenant}, ${b.createdAt} desc);
create index if not exists ai_batches_user_idx on ${batches} (${b.user});
alter table ${batches} enable row level security;
${revokeTable(batches)}
grant select on ${batches} to authenticated;
grant all on ${batches} to service_role;
drop policy if exists ai_batches_read on ${batches};
create policy ai_batches_read on ${batches} for select to authenticated
  using (${b.user} = (select auth.uid()) or ${ctx.scope.check(b.tenant, manage)});

create table if not exists ${items} (
  ${i.batch} uuid not null references ${batches} (${b.id}) on delete cascade,
  ${i.request} text not null check (length(${i.request}) between 1 and 200),
  ${i.tenant} ${id} not null,
  ${i.status} text not null check (${i.status} in ('succeeded', 'failed', 'cancelled', 'expired')),
  ${i.output} jsonb,${line(item("usage"), `${i.usage} jsonb`)}${line(item("error"), `${i.error} text check (length(${i.error}) <= 4000)`)}${line(item("createdAt"), `${i.createdAt} timestamptz not null default now()`)}
  primary key (${i.batch}, ${i.request})
);${unique("items", "request", `${i.batch}, ${i.request}`)}
create index if not exists ai_batch_items_tenant_idx on ${items} (${i.tenant});
alter table ${items} enable row level security;
${revokeTable(items)}
grant select on ${items} to authenticated;
grant all on ${items} to service_role;
drop policy if exists ai_batch_items_read on ${items};
create policy ai_batch_items_read on ${items} for select to authenticated
  using (exists (select 1 from ${batches} y where y.${b.id} = ${i.batch}));

create or replace function ${fn("list_ai_provider_keys")}(tenant ${id})
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${keyJson("x")} order by x.${k.provider}, x.${k.name}), '[]')
  from ${keys} x where x.${k.tenant} = list_ai_provider_keys.tenant
$$;
${userGrant(`${fn("list_ai_provider_keys")}(${id})`)}

-- Adds or replaces a tenant's key for a provider (${manage} or the service
-- role). Returns the key and the credential_ref it replaced, which the caller
-- revokes when it differs.
create or replace function ${fn("save_ai_provider_key")}(tenant ${id}, provider text, credential_ref jsonb, name text default 'default', settings jsonb default '{}', enabled boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_old jsonb;
  v_row ${keys}%rowtype;
begin
  if not (${SERVICE_CALLER} or ${ctx.scope.can("save_ai_provider_key.tenant", manage)}) then
    ${raise("you may not manage provider keys here", "42501", "AI_PROVIDER_KEY_FORBIDDEN")}
  end if;
  ${tenantRefGuard("save_ai_provider_key.credential_ref", "save_ai_provider_key.tenant")}
  select x.${k.credentialRef} into v_old from ${keys} x
  where x.${k.tenant} = save_ai_provider_key.tenant and x.${k.provider} = save_ai_provider_key.provider and x.${k.name} = coalesce(save_ai_provider_key.name, 'default')
  for update;
  insert into ${keys} (${keyInsert.map(([column]) => column).join(", ")})
  values (${keyInsert.map(([, value]) => value).join(", ")})
  on conflict (${k.tenant}, ${k.provider}, ${k.name}) do update set
    ${keyUpdate.join(",\n    ")}
  returning * into v_row;
  ${keyEvent("ai_provider_key.saved", "v_row")}
  return jsonb_build_object('key', ${keyJson("v_row")}, 'replaced', v_old);
end;
$$;
${userGrant(`${fn("save_ai_provider_key")}(${id}, text, jsonb, text, jsonb, boolean)`)}

-- Deletes a key (${manage} or the service role) and returns it, so the caller
-- revokes its credential; null when there is no such key.
create or replace function ${fn("delete_ai_provider_key")}(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${keys}%rowtype;
begin
  select * into v_row from ${keys} x where x.${k.id} = delete_ai_provider_key.id for update;
  if not found or not (${SERVICE_CALLER} or ${ctx.scope.can(`v_row.${k.tenant}`, manage)}) then
    return null;
  end if;
  delete from ${keys} x where x.${k.id} = v_row.${k.id};
  ${keyEvent("ai_provider_key.deleted", "v_row")}
  return ${keyJson("v_row")};
end;
$$;
${userGrant(`${fn("delete_ai_provider_key")}(uuid)`)}

-- Deletes every key of a tenant and returns them (service role), for the
-- step that revokes their credentials when a tenant is deleted.
create or replace function ${fn("delete_ai_provider_keys")}(tenant ${id})
returns jsonb
language sql
security definer
set search_path = ''
as $$
  with gone as (
    delete from ${keys} x where x.${k.tenant} = delete_ai_provider_keys.tenant returning x.*
  )
  select coalesce(jsonb_agg(${keyJson("gone")}), '[]') from gone
$$;
${serviceGrant(`${fn("delete_ai_provider_keys")}(${id})`)}

-- The enabled keys of a tenant, for the request that resolves them (service role).
create or replace function ${fn("ai_provider_keys_for")}(tenant ${id}, providers text[] default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(${keyJson("x")} order by x.${k.provider}, x.${k.name}), '[]')
  from ${keys} x
  where x.${k.tenant} = ai_provider_keys_for.tenant${enabledKey("x")}
    and (ai_provider_keys_for.providers is null or x.${k.provider} = any (ai_provider_keys_for.providers))
$$;
${serviceGrant(`${fn("ai_provider_keys_for")}(${id}, text[])`)}

-- Records a started batch (${use} or the service role). fields: user_id
-- (service role only), item_count, metadata, status, raw_status, counts,
-- expires_at.
create or replace function ${fn("record_ai_batch")}(tenant ${id}, provider text, reference jsonb, fields jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${batches}%rowtype;
  v_fields jsonb := coalesce(record_ai_batch.fields, '{}');
begin
  if not (${SERVICE_CALLER} or (auth.uid() is not null and ${ctx.scope.can("record_ai_batch.tenant", use)})) then
    ${raise("you may not start batches here", "42501", "AI_BATCH_FORBIDDEN")}
  end if;
  insert into ${batches} (${batchInsert.map(([column]) => column).join(", ")})
  values (
    ${batchInsert.map(([, value]) => value).join(",\n    ")}
  )
  returning * into v_row;
  return ${batchJson("v_row")};
end;
$$;
${userGrant(`${fn("record_ai_batch")}(${id}, text, jsonb, jsonb)`)}

-- Writes what a poll learned (service role). fields: status, raw_status,
-- counts, error, expires_at, results_saved, next_poll_at.
create or replace function ${fn("update_ai_batch")}(id uuid, fields jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${batches}%rowtype;
  v_fields jsonb := coalesce(update_ai_batch.fields, '{}');
begin
  update ${batches} x set
    ${batchUpdate.join(",\n    ")}
  where x.${b.id} = update_ai_batch.id
  returning * into v_row;
  if not found then
    ${raise("batch % not found", "P0002", "AI_BATCH_NOT_FOUND", "update_ai_batch.id")}
  end if;
  return ${batchJson("v_row")};
end;
$$;
${serviceGrant(`${fn("update_ai_batch")}(uuid, jsonb)`)}

-- Claims batches to poll (service role): pending ones, and finished ones
-- whose results aren't saved yet. Each claim pushes next_poll_at out by
-- lease_seconds, so two pollers don't take the same batch.
create or replace function ${fn("due_ai_batches")}(batch integer default 20, lease_seconds integer default 300)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  with due as (
    select y.${b.id} from ${batches} y
    where (y.${b.status} = 'pending' or not y.${b.resultsSaved}) and y.${b.nextPollAt} <= now()
    order by y.${b.nextPollAt}
    limit least(greatest(due_ai_batches.batch, 1), 200)
    for update skip locked
  ), claimed as (
    update ${batches} x set
      ${[
        ...(batch("polls") ? [`${b.polls} = x.${b.polls} + 1`] : []),
        `${b.nextPollAt} = now() + make_interval(secs => greatest(due_ai_batches.lease_seconds, 1))`,
        ...(batch("updatedAt") ? [`${b.updatedAt} = now()`] : []),
      ].join(",\n      ")}
    from due where x.${b.id} = due.${b.id}
    returning x.*
  )
  select coalesce(jsonb_agg(${batchJson("claimed")}), '[]') into v_rows from claimed;
  return v_rows;
end;
$$;
${serviceGrant(`${fn("due_ai_batches")}(integer, integer)`)}

-- Saves result items: { "items": [{ "request_id", "status", "output",
-- "usage", "error" }] } (service role). Returns how many were written.
create or replace function ${fn("save_ai_batch_items")}(id uuid, items jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${id};
  v_items jsonb := case when jsonb_typeof(save_ai_batch_items.items) = 'object' then save_ai_batch_items.items -> 'items' else save_ai_batch_items.items end;
  v_count integer;
begin
  select x.${b.tenant} into v_tenant from ${batches} x where x.${b.id} = save_ai_batch_items.id;
  if not found then
    ${raise("batch % not found", "P0002", "AI_BATCH_NOT_FOUND", "save_ai_batch_items.id")}
  end if;
  insert into ${items} (${itemInsert.map(([column]) => column).join(", ")})
  select ${itemInsert.map(([, value]) => value).join(", ")}
  from jsonb_array_elements(case when jsonb_typeof(v_items) = 'array' then v_items else '[]' end) item
  on conflict (${i.batch}, ${i.request}) do update set
    ${itemInsert
      .slice(3)
      .map(([column]) => `${column} = excluded.${column}`)
      .join(",\n    ")};
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${serviceGrant(`${fn("save_ai_batch_items")}(uuid, jsonb)`)}

create or replace function ${fn("get_ai_batch")}(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${batchJson("x")} from ${batches} x where x.${b.id} = get_ai_batch.id
$$;
${userGrant(`${fn("get_ai_batch")}(uuid)`)}

create or replace function ${fn("list_ai_batches")}(tenant ${id}, status text default null, max_rows integer default 50)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${batchJson("x")} order by x.${b.createdAt} desc), '[]')
  from (
    select * from ${batches} y
    where y.${b.tenant} = list_ai_batches.tenant and (list_ai_batches.status is null or ${batchStatus("y")} = list_ai_batches.status)
    order by y.${b.createdAt} desc
    limit least(greatest(list_ai_batches.max_rows, 1), 200)
  ) x
$$;
${userGrant(`${fn("list_ai_batches")}(${id}, text, integer)`)}

-- A page of a batch's results, after request_id after.
create or replace function ${fn("list_ai_batch_items")}(id uuid, after text default null, max_rows integer default 100)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${itemJson("x")} order by x.${i.request}), '[]')
  from (
    select * from ${items} y
    where y.${i.batch} = list_ai_batch_items.id and (list_ai_batch_items.after is null or y.${i.request} > list_ai_batch_items.after)
    order by y.${i.request}
    limit least(greatest(list_ai_batch_items.max_rows, 1), 1000)
  ) x
$$;
${userGrant(`${fn("list_ai_batch_items")}(uuid, text, integer)`)}`;
}

// Version 2 leaves ai_sandboxes to ai-chat. Without ai-chat the table would
// go with this module's old file, so the upgrade stops while it holds rows.
function upgradeSandboxes(ctx: BlockSqlContext): string {
  if (ctx.installed("ai-chat")) {
    return "";
  }

  const table = `${ctx.schema}.ai_sandboxes`;

  return `do $$
begin
  if to_regclass(${sqlString(table)}) is not null and exists (select 1 from ${table}) then
    raise exception 'ai_sandboxes moved to the ai-chat module: add ai-chat to blocks before upgrading, or delete the rows';
  end if;
end;
$$;`;
}

export const AI_PROVIDERS: BlockSqlDefinition = {
  name: "ai-keys",
  scopes: ["tenant"],
  title: "AI providers",
  description:
    "A tenant's own provider keys as credential_ref rows, and a registry of provider batch jobs with their results and a poll claim. Sandboxes live in ai-chat.",
  requires: ["memberships", "permissions"],
  integrates: ["ai-chat"],
  target: "schema",
  version: 2,
  names: NAMES,
  upgrades: [
    {
      from: 1,
      description:
        "Sandboxes move to the ai-chat module, which harness sessions share.",
      sql: upgradeSandboxes,
    },
  ],
  build,
};
