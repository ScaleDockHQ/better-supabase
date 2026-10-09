import type { ModuleContext, ModuleNames } from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import {
  canIn,
  raise,
  schemaPreamble,
  SERVICE_CALLER,
  serviceGrant,
  tenantIn,
  userGrant,
} from "../shared.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";
import { tenantRefGuard } from "./credentials.ts";
import { columnsOf, rowJson } from "./module-columns.ts";

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

const SANDBOXES = {
  id: "id",
  tenant: "organization_id",
  user: "user_id",
  chat: "chat_id",
  provider: "provider",
  sandbox: "sandbox_id",
  container: "container_id",
  status: "status",
  metadata: "metadata",
  idleSeconds: "idle_seconds",
  error: "error",
  lastUsedAt: "last_used_at",
  expiresAt: "expires_at",
  stoppedAt: "stopped_at",
  createdAt: "created_at",
  updatedAt: "updated_at",
} as const;

const NAMES: ModuleNames = {
  options: ["pollEvery", "idleAfter"],
  tables: {
    keys: {
      name: "ai_provider_keys",
      columns: KEYS,
      lifecycle: { tenant: "tenant" },
    },
    batches: {
      name: "ai_batches",
      columns: BATCHES,
      lifecycle: { user: "user", tenant: "tenant" },
    },
    items: {
      name: "ai_batch_items",
      columns: ITEMS,
      lifecycle: { tenant: "tenant" },
    },
    sandboxes: {
      name: "ai_sandboxes",
      columns: SANDBOXES,
      lifecycle: { user: "user", tenant: "tenant" },
    },
  },
};

const SLUG = "^[a-z0-9][a-z0-9._-]{0,63}$";

function build(ctx: ModuleContext): string {
  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const k = columnsOf(ctx, "keys", KEYS);
  const b = columnsOf(ctx, "batches", BATCHES);
  const i = columnsOf(ctx, "items", ITEMS);
  const s = columnsOf(ctx, "sandboxes", SANDBOXES);
  const keys = ctx.table("keys");
  const batches = ctx.table("batches");
  const items = ctx.table("items");
  const sandboxes = ctx.table("sandboxes");
  const permissions = MODULE_PERMISSIONS["ai-providers"];
  const use = ctx.permission("use", permissions.use);
  const manage = ctx.permission("manage", permissions.manage);
  const pollEvery = ctx.number("pollEvery", 60);
  const idleAfter = ctx.number("idleAfter", 600);
  for (const [option, value] of [
    ["pollEvery", pollEvery],
    ["idleAfter", idleAfter],
  ] as const) {
    if (!Number.isInteger(value) || value < 1) {
      throw new TypeError(
        `sql.modules.ai-providers.options.${option} must be a whole number of seconds`,
      );
    }
  }
  const keyJson = (row: string): string => rowJson(KEYS, k, row);
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
  const batchJson = (row: string): string => rowJson(BATCHES, b, row);
  const itemJson = (row: string): string => rowJson(ITEMS, i, row);
  const sandboxJson = (row: string): string => rowJson(SANDBOXES, s, row);
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
  ${k.credentialRef} jsonb not null ${refCheck(k.credentialRef)},
  ${k.settings} jsonb not null default '{}' check (jsonb_typeof(${k.settings}) = 'object'),
  ${k.enabled} boolean not null default true,
  ${k.createdBy} uuid references auth.users (id) on delete set null,
  ${k.createdAt} timestamptz not null default now(),
  ${k.updatedAt} timestamptz not null default now(),
  unique (${k.tenant}, ${k.provider}, ${k.name})
);
create index if not exists ai_provider_keys_created_by_idx on ${keys} (${k.createdBy});
alter table ${keys} enable row level security;
revoke all on ${keys} from anon, authenticated;
grant select on ${keys} to authenticated;
grant all on ${keys} to service_role;
drop policy if exists ai_provider_keys_read on ${keys};
create policy ai_provider_keys_read on ${keys} for select to authenticated
  using (${tenantIn(k.tenant, manage)});

-- Batch jobs started with a provider's batch API, polled until they finish.
-- reference is the SDK's batch reference ({ version, id, provider }).
create table if not exists ${batches} (
  ${b.id} uuid primary key default gen_random_uuid(),
  ${b.tenant} ${id} not null,
  ${b.user} uuid references auth.users (id) on delete cascade,
  ${b.provider} text not null check (length(${b.provider}) between 1 and 100),
  ${b.reference} jsonb not null check (jsonb_typeof(${b.reference}) = 'object'),
  ${b.status} text not null default 'pending' check (${b.status} in ('pending', 'completed', 'failed', 'cancelled')),
  ${b.rawStatus} text check (length(${b.rawStatus}) <= 100),
  ${b.itemCount} integer not null default 0 check (${b.itemCount} >= 0),
  ${b.counts} jsonb not null default '{}' check (jsonb_typeof(${b.counts}) = 'object'),
  ${b.error} text check (length(${b.error}) <= 4000),
  ${b.metadata} jsonb not null default '{}' check (jsonb_typeof(${b.metadata}) = 'object'),
  ${b.resultsSaved} boolean not null default false,
  ${b.polls} integer not null default 0,
  ${b.nextPollAt} timestamptz default now(),
  ${b.expiresAt} timestamptz,
  ${b.completedAt} timestamptz,
  ${b.createdAt} timestamptz not null default now(),
  ${b.updatedAt} timestamptz not null default now()
);
create index if not exists ai_batches_due_idx on ${batches} (${b.nextPollAt}) where ${b.status} = 'pending' or not ${b.resultsSaved};
create index if not exists ai_batches_tenant_idx on ${batches} (${b.tenant}, ${b.createdAt} desc);
create index if not exists ai_batches_user_idx on ${batches} (${b.user});
alter table ${batches} enable row level security;
revoke all on ${batches} from anon, authenticated;
grant select on ${batches} to authenticated;
grant all on ${batches} to service_role;
drop policy if exists ai_batches_read on ${batches};
create policy ai_batches_read on ${batches} for select to authenticated
  using (${b.user} = (select auth.uid()) or ${tenantIn(b.tenant, manage)});

create table if not exists ${items} (
  ${i.batch} uuid not null references ${batches} (${b.id}) on delete cascade,
  ${i.request} text not null check (length(${i.request}) between 1 and 200),
  ${i.tenant} ${id} not null,
  ${i.status} text not null check (${i.status} in ('succeeded', 'failed', 'cancelled', 'expired')),
  ${i.output} jsonb,
  ${i.usage} jsonb,
  ${i.error} text check (length(${i.error}) <= 4000),
  ${i.createdAt} timestamptz not null default now(),
  primary key (${i.batch}, ${i.request})
);
create index if not exists ai_batch_items_tenant_idx on ${items} (${i.tenant});
alter table ${items} enable row level security;
revoke all on ${items} from anon, authenticated;
grant select on ${items} to authenticated;
grant all on ${items} to service_role;
drop policy if exists ai_batch_items_read on ${items};
create policy ai_batch_items_read on ${items} for select to authenticated
  using (exists (select 1 from ${batches} y where y.${b.id} = ${i.batch}));

-- Sandboxes and provider containers a chat started, so an idle-stop job can
-- stop the ones nobody used for idle_seconds or past expires_at.
create table if not exists ${sandboxes} (
  ${s.id} uuid primary key default gen_random_uuid(),
  ${s.tenant} ${id} not null,
  ${s.user} uuid references auth.users (id) on delete cascade,
  ${s.chat} uuid,
  ${s.provider} text not null check (${s.provider} ~ '${SLUG}'),
  ${s.sandbox} text not null check (length(${s.sandbox}) between 1 and 200),
  ${s.container} text check (length(${s.container}) <= 200),
  ${s.status} text not null default 'running' check (${s.status} in ('running', 'stopping', 'stopped')),
  ${s.metadata} jsonb not null default '{}' check (jsonb_typeof(${s.metadata}) = 'object'),
  ${s.idleSeconds} integer not null default ${idleAfter} check (${s.idleSeconds} > 0),
  ${s.error} text check (length(${s.error}) <= 4000),
  ${s.lastUsedAt} timestamptz not null default now(),
  ${s.expiresAt} timestamptz,
  ${s.stoppedAt} timestamptz,
  ${s.createdAt} timestamptz not null default now(),
  ${s.updatedAt} timestamptz not null default now(),
  unique (${s.provider}, ${s.sandbox})
);
create index if not exists ai_sandboxes_open_idx on ${sandboxes} (${s.lastUsedAt}) where ${s.status} <> 'stopped';
create index if not exists ai_sandboxes_chat_idx on ${sandboxes} (${s.chat});
create index if not exists ai_sandboxes_tenant_idx on ${sandboxes} (${s.tenant});
create index if not exists ai_sandboxes_user_idx on ${sandboxes} (${s.user});
alter table ${sandboxes} enable row level security;
revoke all on ${sandboxes} from anon, authenticated;
grant select on ${sandboxes} to authenticated;
grant all on ${sandboxes} to service_role;
drop policy if exists ai_sandboxes_read on ${sandboxes};
create policy ai_sandboxes_read on ${sandboxes} for select to authenticated
  using (${s.user} = (select auth.uid()) or ${tenantIn(s.tenant, manage)});

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
  if not (${SERVICE_CALLER} or ${canIn("save_ai_provider_key.tenant", manage)}) then
    ${raise("you may not manage provider keys here", "42501", "AI_PROVIDER_KEY_FORBIDDEN")}
  end if;
  ${tenantRefGuard("save_ai_provider_key.credential_ref", "save_ai_provider_key.tenant")}
  select x.${k.credentialRef} into v_old from ${keys} x
  where x.${k.tenant} = save_ai_provider_key.tenant and x.${k.provider} = save_ai_provider_key.provider and x.${k.name} = coalesce(save_ai_provider_key.name, 'default')
  for update;
  insert into ${keys} (${k.tenant}, ${k.provider}, ${k.name}, ${k.credentialRef}, ${k.settings}, ${k.enabled}, ${k.createdBy})
  values (save_ai_provider_key.tenant, save_ai_provider_key.provider, coalesce(save_ai_provider_key.name, 'default'), save_ai_provider_key.credential_ref, coalesce(save_ai_provider_key.settings, '{}'), coalesce(save_ai_provider_key.enabled, true), auth.uid())
  on conflict (${k.tenant}, ${k.provider}, ${k.name}) do update set
    ${k.credentialRef} = excluded.${k.credentialRef},
    ${k.settings} = excluded.${k.settings},
    ${k.enabled} = excluded.${k.enabled},
    ${k.updatedAt} = now()
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
  if not found or not (${SERVICE_CALLER} or ${canIn(`v_row.${k.tenant}`, manage)}) then
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
  where x.${k.tenant} = ai_provider_keys_for.tenant and x.${k.enabled}
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
  if not (${SERVICE_CALLER} or (auth.uid() is not null and ${canIn("record_ai_batch.tenant", use)})) then
    ${raise("you may not start batches here", "42501", "AI_BATCH_FORBIDDEN")}
  end if;
  insert into ${batches} (${b.tenant}, ${b.user}, ${b.provider}, ${b.reference}, ${b.status}, ${b.rawStatus}, ${b.itemCount}, ${b.counts}, ${b.metadata}, ${b.expiresAt}, ${b.nextPollAt})
  values (
    record_ai_batch.tenant,
    case when ${SERVICE_CALLER} then (v_fields ->> 'user_id')::uuid else auth.uid() end,
    record_ai_batch.provider,
    record_ai_batch.reference,
    coalesce(v_fields ->> 'status', 'pending'),
    v_fields ->> 'raw_status',
    coalesce((v_fields ->> 'item_count')::integer, 0),
    coalesce(v_fields -> 'counts', '{}'),
    coalesce(v_fields -> 'metadata', '{}'),
    (v_fields ->> 'expires_at')::timestamptz,
    now() + interval '${pollEvery} seconds'
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
    ${b.status} = coalesce(v_fields ->> 'status', x.${b.status}),
    ${b.rawStatus} = coalesce(v_fields ->> 'raw_status', x.${b.rawStatus}),
    ${b.counts} = coalesce(v_fields -> 'counts', x.${b.counts}),
    ${b.error} = case when v_fields ? 'error' then left(v_fields ->> 'error', 4000) else x.${b.error} end,
    ${b.expiresAt} = coalesce((v_fields ->> 'expires_at')::timestamptz, x.${b.expiresAt}),
    ${b.resultsSaved} = coalesce((v_fields ->> 'results_saved')::boolean, x.${b.resultsSaved}),
    ${b.nextPollAt} = case when v_fields ? 'next_poll_at' then (v_fields ->> 'next_poll_at')::timestamptz else x.${b.nextPollAt} end,
    ${b.completedAt} = case when coalesce(v_fields ->> 'status', x.${b.status}) <> 'pending' then coalesce(x.${b.completedAt}, now()) else null end,
    ${b.updatedAt} = now()
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
      ${b.polls} = x.${b.polls} + 1,
      ${b.nextPollAt} = now() + make_interval(secs => greatest(due_ai_batches.lease_seconds, 1)),
      ${b.updatedAt} = now()
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
  insert into ${items} (${i.batch}, ${i.request}, ${i.tenant}, ${i.status}, ${i.output}, ${i.usage}, ${i.error})
  select save_ai_batch_items.id, item ->> 'request_id', v_tenant, item ->> 'status', item -> 'output', item -> 'usage', left(item ->> 'error', 4000)
  from jsonb_array_elements(case when jsonb_typeof(v_items) = 'array' then v_items else '[]' end) item
  on conflict (${i.batch}, ${i.request}) do update set
    ${i.status} = excluded.${i.status},
    ${i.output} = excluded.${i.output},
    ${i.usage} = excluded.${i.usage},
    ${i.error} = excluded.${i.error};
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
    where y.${b.tenant} = list_ai_batches.tenant and (list_ai_batches.status is null or y.${b.status} = list_ai_batches.status)
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
${userGrant(`${fn("list_ai_batch_items")}(uuid, text, integer)`)}

-- Records a sandbox or container the app started, or marks a known one used
-- (service role). fields: user_id, chat_id, container_id, metadata,
-- idle_seconds, expires_at.
create or replace function ${fn("register_ai_sandbox")}(tenant ${id}, provider text, sandbox_id text, fields jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${sandboxes}%rowtype;
  v_fields jsonb := coalesce(register_ai_sandbox.fields, '{}');
begin
  insert into ${sandboxes} as cur (${s.tenant}, ${s.user}, ${s.chat}, ${s.provider}, ${s.sandbox}, ${s.container}, ${s.metadata}, ${s.idleSeconds}, ${s.expiresAt})
  values (
    register_ai_sandbox.tenant,
    (v_fields ->> 'user_id')::uuid,
    (v_fields ->> 'chat_id')::uuid,
    register_ai_sandbox.provider,
    register_ai_sandbox.sandbox_id,
    v_fields ->> 'container_id',
    coalesce(v_fields -> 'metadata', '{}'),
    coalesce((v_fields ->> 'idle_seconds')::integer, ${idleAfter}),
    (v_fields ->> 'expires_at')::timestamptz
  )
  on conflict (${s.provider}, ${s.sandbox}) do update set
    ${s.container} = coalesce(excluded.${s.container}, cur.${s.container}),
    ${s.chat} = coalesce(excluded.${s.chat}, cur.${s.chat}),
    ${s.metadata} = cur.${s.metadata} || excluded.${s.metadata},
    ${s.idleSeconds} = excluded.${s.idleSeconds},
    ${s.expiresAt} = coalesce(excluded.${s.expiresAt}, cur.${s.expiresAt}),
    ${s.status} = 'running',
    ${s.error} = null,
    ${s.stoppedAt} = null,
    ${s.lastUsedAt} = now(),
    ${s.updatedAt} = now()
  where cur.${s.tenant} = excluded.${s.tenant}
  returning * into v_row;
  if not found then
    ${raise("sandbox % belongs to another tenant", "42501", "AI_SANDBOX_FORBIDDEN", "register_ai_sandbox.sandbox_id")}
  end if;
  return ${sandboxJson("v_row")};
end;
$$;
${serviceGrant(`${fn("register_ai_sandbox")}(${id}, text, text, jsonb)`)}

-- Marks a sandbox used now (service role); false when it is not running.
create or replace function ${fn("touch_ai_sandbox")}(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update ${sandboxes} x set ${s.lastUsedAt} = now(), ${s.updatedAt} = now()
  where x.${s.id} = touch_ai_sandbox.id and x.${s.status} = 'running';
  return found;
end;
$$;
${serviceGrant(`${fn("touch_ai_sandbox")}(uuid)`)}

-- The running sandbox of a chat for a provider, to reuse it (service role).
create or replace function ${fn("ai_sandbox_for")}(chat_id uuid, provider text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select ${sandboxJson("x")} from ${sandboxes} x
  where x.${s.chat} = ai_sandbox_for.chat_id and x.${s.provider} = ai_sandbox_for.provider and x.${s.status} = 'running'
    and (x.${s.expiresAt} is null or x.${s.expiresAt} > now())
  order by x.${s.lastUsedAt} desc
  limit 1
$$;
${serviceGrant(`${fn("ai_sandbox_for")}(uuid, text)`)}

-- Claims sandboxes to stop (service role): running ones idle for
-- idle_seconds or past expires_at, and ones a stopper claimed more than
-- lease_seconds ago without finishing.
create or replace function ${fn("idle_ai_sandboxes")}(batch integer default 50, lease_seconds integer default 300)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  with due as (
    select y.${s.id} from ${sandboxes} y
    where (y.${s.status} = 'running' and (y.${s.lastUsedAt} + make_interval(secs => y.${s.idleSeconds}) <= now() or y.${s.expiresAt} <= now()))
       or (y.${s.status} = 'stopping' and y.${s.updatedAt} <= now() - make_interval(secs => greatest(idle_ai_sandboxes.lease_seconds, 1)))
    order by y.${s.lastUsedAt}
    limit least(greatest(idle_ai_sandboxes.batch, 1), 500)
    for update skip locked
  ), claimed as (
    update ${sandboxes} x set ${s.status} = 'stopping', ${s.updatedAt} = now()
    from due where x.${s.id} = due.${s.id}
    returning x.*
  )
  select coalesce(jsonb_agg(${sandboxJson("claimed")}), '[]') into v_rows from claimed;
  return v_rows;
end;
$$;
${serviceGrant(`${fn("idle_ai_sandboxes")}(integer, integer)`)}

-- Finishes a stop (service role): stopped, or back to running with the
-- error so the next run tries again.
create or replace function ${fn("finish_ai_sandbox_stop")}(id uuid, stopped boolean, error text default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update ${sandboxes} x set
    ${s.status} = case when finish_ai_sandbox_stop.stopped then 'stopped' else 'running' end,
    ${s.stoppedAt} = case when finish_ai_sandbox_stop.stopped then now() else null end,
    ${s.error} = left(finish_ai_sandbox_stop.error, 4000),
    ${s.updatedAt} = now()
  where x.${s.id} = finish_ai_sandbox_stop.id and x.${s.status} <> 'stopped';
  return found;
end;
$$;
${serviceGrant(`${fn("finish_ai_sandbox_stop")}(uuid, boolean, text)`)}

create or replace function ${fn("list_ai_sandboxes")}(tenant ${id}, chat_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${sandboxJson("x")} order by x.${s.createdAt} desc), '[]')
  from ${sandboxes} x
  where x.${s.tenant} = list_ai_sandboxes.tenant and (list_ai_sandboxes.chat_id is null or x.${s.chat} = list_ai_sandboxes.chat_id)
$$;
${userGrant(`${fn("list_ai_sandboxes")}(${id}, uuid)`)}`;
}

export const AI_PROVIDERS: ModuleDefinition = {
  name: "ai-providers",
  title: "AI providers",
  description:
    "A tenant's own provider keys as credential_ref rows, a registry of provider batch jobs with their results and a poll claim, and a registry of sandboxes and containers with an idle-stop claim.",
  requires: ["tenant", "access"],
  target: "schema",
  version: 1,
  names: NAMES,
  build,
};
