import type { ModuleContext } from "../context.ts";
import type { AiChatNames } from "./ai-chat.ts";

import { sqlString } from "../../core/template.ts";
import { raise, serviceGrant, tenantIn, userGrant } from "../shared.ts";

const SLUG = "^[a-z0-9][a-z0-9._-]{0,63}$";

/** The provider a harness session's sandbox gets when the save names none. */
const HARNESS_SANDBOX_PROVIDER = "harness";

function sandboxJson(names: AiChatNames, row: string): string {
  const s = names.c.sandboxes;
  const keys = [
    ["id", s.id],
    ["organization_id", s.tenant],
    ["user_id", s.user],
    ["chat_id", s.chat],
    ["harness_id", s.harness],
    ["provider", s.provider],
    ["sandbox_id", s.sandbox],
    ["container_id", s.container],
    ["status", s.status],
    ["metadata", s.metadata],
    ["idle_seconds", s.idleSeconds],
    ["error", s.error],
    ["last_used_at", s.lastUsedAt],
    ["expires_at", s.expiresAt],
    ["stopped_at", s.stoppedAt],
    ["created_at", s.createdAt],
    ["updated_at", s.updatedAt],
  ] as const;
  return `jsonb_build_object(${keys.map(([key, column]) => `'${key}', ${row}.${column}`).join(", ")})`;
}

/**
 * The sandboxes table: every sandbox or provider container a chat started,
 * a harness session's included (`harness_id`), so one idle-stop claim
 * covers them all. `create table if not exists`, so the upgrade step can run
 * it on a database where ai-providers 1 created the table; `adapt`
 * runs between the table and its indexes.
 */
export function sandboxTable(
  ctx: ModuleContext,
  names: AiChatNames,
  adapt = "",
): string {
  const { t, perm } = names;
  const s = names.c.sandboxes;
  const sandboxes = t.sandboxes;
  return `-- Sandboxes and provider containers a chat started, harness sessions'
-- included, so one idle-stop claim stops the ones nobody used for
-- idle_seconds or past expires_at.
create table if not exists ${sandboxes} (
  ${s.id} uuid primary key default gen_random_uuid(),
  ${s.tenant} ${ctx.idType} not null,
  ${s.user} uuid references auth.users (id) on delete cascade,
  ${s.chat} uuid,
  ${s.harness} text check (length(${s.harness}) between 1 and 200),
  ${s.provider} text not null check (${s.provider} ~ '${SLUG}'),
  ${s.sandbox} text not null check (length(${s.sandbox}) between 1 and 200),
  ${s.container} text check (length(${s.container}) <= 200),
  ${s.status} text not null default 'running' check (${s.status} in ('running', 'stopping', 'stopped')),
  ${s.metadata} jsonb not null default '{}' check (jsonb_typeof(${s.metadata}) = 'object'),
  ${s.idleSeconds} integer not null default ${String(names.sandboxIdleAfter)} check (${s.idleSeconds} > 0),
  ${s.error} text check (length(${s.error}) <= 4000),
  ${s.lastUsedAt} timestamptz not null default now(),
  ${s.expiresAt} timestamptz,
  ${s.stoppedAt} timestamptz,
  ${s.createdAt} timestamptz not null default now(),
  ${s.updatedAt} timestamptz not null default now(),
  unique (${s.provider}, ${s.sandbox})
);${adapt}
create index if not exists ai_sandboxes_open_idx on ${sandboxes} (${s.lastUsedAt}) where ${s.status} <> 'stopped';
create index if not exists ai_sandboxes_chat_idx on ${sandboxes} (${s.chat});
create index if not exists ai_sandboxes_harness_idx on ${sandboxes} (${s.chat}, ${s.harness}) where ${s.harness} is not null;
create index if not exists ai_sandboxes_tenant_idx on ${sandboxes} (${s.tenant});
create index if not exists ai_sandboxes_user_idx on ${sandboxes} (${s.user});
alter table ${sandboxes} enable row level security;
revoke all on ${sandboxes} from anon, authenticated;
grant select on ${sandboxes} to authenticated;
grant all on ${sandboxes} to service_role;
drop policy if exists ai_sandboxes_read on ${sandboxes};
create policy ai_sandboxes_read on ${sandboxes} for select to authenticated
  using (${s.user} = (select auth.uid()) or ${tenantIn(s.tenant, perm.admin)});`;
}

/** The running sandbox id of a harness session, as a SQL expression. */
export function harnessSandbox(names: AiChatNames, row: string): string {
  const s = names.c.sandboxes;
  const h = names.c.harness;
  return `(select y.${s.sandbox} from ${names.t.sandboxes} y where y.${s.chat} = ${row}.${h.chat} and y.${s.harness} = ${row}.${h.harness} and y.${s.status} <> 'stopped' order by y.${s.lastUsedAt} desc limit 1)`;
}

/**
 * What `save_ai_harness_session` runs for a `sandbox_id` field: a sandbox id
 * registers (or reuses) the session's sandbox, `null` marks its sandboxes
 * stopped. Runs with `v_chat` and `v_row` (the locked session) set.
 */
export function harnessSandboxSave(names: AiChatNames, fields: string): string {
  const s = names.c.sandboxes;
  const h = names.c.harness;
  const ch = names.c.chats;
  const sandboxes = names.t.sandboxes;
  return `
  if ${fields} ? 'sandbox_id' then
    if nullif(${fields} ->> 'sandbox_id', '') is null then
      update ${sandboxes} y set ${s.status} = 'stopped', ${s.stoppedAt} = now(), ${s.updatedAt} = now()
      where y.${s.chat} = v_row.${h.chat} and y.${s.harness} = v_row.${h.harness} and y.${s.status} <> 'stopped';
    else
      insert into ${sandboxes} as cur (${s.tenant}, ${s.user}, ${s.chat}, ${s.harness}, ${s.provider}, ${s.sandbox})
      values (v_chat.${ch.tenant}, v_chat.${ch.owner}, v_chat.${ch.id}, v_row.${h.harness}, coalesce(nullif(${fields} ->> 'sandbox_provider', ''), '${HARNESS_SANDBOX_PROVIDER}'), ${fields} ->> 'sandbox_id')
      on conflict (${s.provider}, ${s.sandbox}) do update set
        ${s.chat} = excluded.${s.chat},
        ${s.harness} = excluded.${s.harness},
        ${s.status} = 'running',
        ${s.error} = null,
        ${s.stoppedAt} = null,
        ${s.lastUsedAt} = now(),
        ${s.updatedAt} = now()
      where cur.${s.tenant} = excluded.${s.tenant};
      if not found then
        ${raise("sandbox % belongs to another tenant", "42501", "AI_SANDBOX_FORBIDDEN", `${fields} ->> 'sandbox_id'`)}
      end if;
    end if;
  elsif ${fields} ->> 'status' is null then
    update ${sandboxes} y set ${s.lastUsedAt} = now(), ${s.updatedAt} = now()
    where y.${s.chat} = v_row.${h.chat} and y.${s.harness} = v_row.${h.harness} and y.${s.status} = 'running';
  end if;`;
}

/** The sandbox registry's functions, the one idle-stop claim included. */
export function sandboxFunctions(
  ctx: ModuleContext,
  names: AiChatNames,
): string {
  const fn = (name: string): string => ctx.fn(name);
  const id = ctx.idType;
  const s = names.c.sandboxes;
  const h = names.c.harness;
  const sandboxes = names.t.sandboxes;
  const json = (row: string): string => sandboxJson(names, row);
  return `-- Records a sandbox or container the app started, or marks a known one used
-- (service role). fields: user_id, chat_id, harness_id, container_id,
-- metadata, idle_seconds, expires_at.
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
  insert into ${sandboxes} as cur (${s.tenant}, ${s.user}, ${s.chat}, ${s.harness}, ${s.provider}, ${s.sandbox}, ${s.container}, ${s.metadata}, ${s.idleSeconds}, ${s.expiresAt})
  values (
    register_ai_sandbox.tenant,
    (v_fields ->> 'user_id')::uuid,
    (v_fields ->> 'chat_id')::uuid,
    v_fields ->> 'harness_id',
    register_ai_sandbox.provider,
    register_ai_sandbox.sandbox_id,
    v_fields ->> 'container_id',
    coalesce(v_fields -> 'metadata', '{}'),
    coalesce((v_fields ->> 'idle_seconds')::integer, ${String(names.sandboxIdleAfter)}),
    (v_fields ->> 'expires_at')::timestamptz
  )
  on conflict (${s.provider}, ${s.sandbox}) do update set
    ${s.container} = coalesce(excluded.${s.container}, cur.${s.container}),
    ${s.chat} = coalesce(excluded.${s.chat}, cur.${s.chat}),
    ${s.harness} = coalesce(excluded.${s.harness}, cur.${s.harness}),
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
  return ${json("v_row")};
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
  select ${json("x")} from ${sandboxes} x
  where x.${s.chat} = ai_sandbox_for.chat_id and x.${s.provider} = ai_sandbox_for.provider and x.${s.status} = 'running'
    and (x.${s.expiresAt} is null or x.${s.expiresAt} > now())
  order by x.${s.lastUsedAt} desc
  limit 1
$$;
${serviceGrant(`${fn("ai_sandbox_for")}(uuid, text)`)}

-- Claims sandboxes to stop (service role): running ones idle for
-- idle_seconds or past expires_at, and ones a stopper claimed more than
-- lease_seconds ago without finishing. A sandbox whose harness session a
-- turn holds the lock of is skipped.
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
    where ((y.${s.status} = 'running' and (y.${s.lastUsedAt} + make_interval(secs => y.${s.idleSeconds}) <= now() or y.${s.expiresAt} <= now()))
       or (y.${s.status} = 'stopping' and y.${s.updatedAt} <= now() - make_interval(secs => greatest(idle_ai_sandboxes.lease_seconds, 1))))
      and not exists (
        select 1 from ${names.t.harness} z
        where z.${h.chat} = y.${s.chat} and z.${h.harness} = y.${s.harness} and z.${h.lockedUntil} > now()
      )
    order by y.${s.lastUsedAt}
    limit least(greatest(idle_ai_sandboxes.batch, 1), 500)
    for update skip locked
  ), claimed as (
    update ${sandboxes} x set ${s.status} = 'stopping', ${s.updatedAt} = now()
    from due where x.${s.id} = due.${s.id}
    returning x.*
  )
  select coalesce(jsonb_agg(${json("claimed")}), '[]') into v_rows from claimed;
  return v_rows;
end;
$$;
${serviceGrant(`${fn("idle_ai_sandboxes")}(integer, integer)`)}

-- Finishes a stop the caller claimed (service role): stopped, or back to
-- running with the error so the next run tries again. A stopped harness
-- sandbox also stops its session. False when a turn used the sandbox again
-- since the claim.
create or replace function ${fn("finish_ai_sandbox_stop")}(id uuid, stopped boolean, error text default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${sandboxes}%rowtype;
begin
  update ${sandboxes} x set
    ${s.status} = case when finish_ai_sandbox_stop.stopped then 'stopped' else 'running' end,
    ${s.stoppedAt} = case when finish_ai_sandbox_stop.stopped then now() else null end,
    ${s.error} = left(finish_ai_sandbox_stop.error, 4000),
    ${s.updatedAt} = now()
  where x.${s.id} = finish_ai_sandbox_stop.id and x.${s.status} = 'stopping'
  returning x.* into v_row;
  if not found then
    return false;
  end if;
  if finish_ai_sandbox_stop.stopped and v_row.${s.harness} is not null then
    update ${names.t.harness} z set ${h.status} = 'stopped', ${h.updatedAt} = now()
    where z.${h.chat} = v_row.${s.chat} and z.${h.harness} = v_row.${s.harness}
      and z.${h.status} in ('active', 'idle')
      and not exists (
        select 1 from ${sandboxes} y
        where y.${s.chat} = v_row.${s.chat} and y.${s.harness} = v_row.${s.harness} and y.${s.status} <> 'stopped'
      );
  end if;
  return true;
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
  select coalesce(jsonb_agg(${json("x")} order by x.${s.createdAt} desc), '[]')
  from ${sandboxes} x
  where x.${s.tenant} = list_ai_sandboxes.tenant and (list_ai_sandboxes.chat_id is null or x.${s.chat} = list_ai_sandboxes.chat_id)
$$;
${userGrant(`${fn("list_ai_sandboxes")}(${id}, uuid)`)}`;
}

/**
 * Upgrade step from ai-chat 1: harness sessions keep their sandbox in
 * `ai_sandboxes` (created here when ai-providers had not), so the column on
 * `ai_harness_sessions` goes.
 */
export function upgradeSandboxes(
  ctx: ModuleContext,
  names: AiChatNames,
): string {
  const s = names.c.sandboxes;
  const h = names.c.harness;
  const ch = names.c.chats;
  const harness = names.t.harness;
  // The ai-chat 1 column, which the current layout no longer names.
  const sandbox = "sandbox_id";
  return `${sandboxTable(
    ctx,
    names,
    `
alter table ${names.t.sandboxes} add column if not exists ${s.harness} text check (length(${s.harness}) between 1 and 200);`,
  )}
do $$
begin
  if exists (
    select 1 from pg_catalog.pg_attribute
    where attrelid = ${sqlString(harness)}::regclass and attname = '${sandbox}' and not attisdropped
  ) then
    execute $sql$
      insert into ${names.t.sandboxes} (${s.tenant}, ${s.user}, ${s.chat}, ${s.harness}, ${s.provider}, ${s.sandbox}, ${s.status}, ${s.lastUsedAt}, ${s.stoppedAt}, ${s.createdAt})
      select c.${ch.tenant}, x.${h.owner}, x.${h.chat}, x.${h.harness}, '${HARNESS_SANDBOX_PROVIDER}', x.${sandbox},
        case when x.${h.status} = 'stopped' then 'stopped' else 'running' end,
        x.${h.lastActiveAt},
        case when x.${h.status} = 'stopped' then x.${h.updatedAt} end,
        x.${h.createdAt}
      from ${harness} x
      join ${names.t.chats} c on c.${ch.id} = x.${h.chat}
      where x.${sandbox} is not null and length(x.${sandbox}) between 1 and 200
      on conflict (${s.provider}, ${s.sandbox}) do nothing
    $sql$;
    alter table ${harness} drop column ${sandbox};
  end if;
end;
$$;`;
}
