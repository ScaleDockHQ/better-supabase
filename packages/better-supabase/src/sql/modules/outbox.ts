import type { ModuleContext, ModuleNames } from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import { sqlString } from "../../core/template.ts";
import { schemaPreamble } from "../shared.ts";

const NAMES: ModuleNames = {
  options: ["defaultSource", "emitRoles", "blockSource", "retention", "settle"],
  tables: {
    events: {
      name: "outbox_events",
      columns: {
        id: "id",
        position: "position",
        type: "type",
        source: "source",
        subject: "subject",
        tenant: "organization_id",
        key: "key",
        payload: "payload",
        actor: "actor_id",
        createdAt: "created_at",
        xid: "xid",
      },
      optional: ["source", "subject", "tenant", "key", "actor", "xid"],
    },
    consumers: {
      name: "outbox_consumers",
      columns: {
        name: "name",
        cursorXid: "cursor_xid",
        cursor: "cursor_position",
        types: "types",
        leaseOwner: "lease_owner",
        leaseUntil: "lease_until",
        updatedAt: "updated_at",
      },
    },
  },
  hooks: [],
};

interface Names {
  readonly t: string;
  readonly c: string;
  readonly e: (logical: string) => string;
  readonly k: (logical: string) => string;
  readonly has: (logical: string) => boolean;
}

function names(ctx: ModuleContext): Names {
  return {
    t: ctx.table("events"),
    c: ctx.table("consumers"),
    e: (logical) => ctx.col("events", logical),
    k: (logical) => ctx.col("consumers", logical),
    has: (logical) => ctx.has("events", logical),
  };
}

// Cursors are module state no app has yet, so adopt mode still creates them.
function consumersTable(n: Names): string {
  return `
create table if not exists ${n.c} (
  ${n.k("name")} text primary key,
  -- The last event passed, ordered by (transaction id, position). Without
  -- the xid column, cursor_xid stays 0 and the position alone orders.
  ${n.k("cursorXid")} xid8 not null default '0',
  ${n.k("cursor")} bigint not null default 0,
  -- Type patterns ('organization.*', 'invoice.paid'); null takes every event.
  ${n.k("types")} text[],
  ${n.k("leaseOwner")} text,
  ${n.k("leaseUntil")} timestamptz,
  ${n.k("updatedAt")} timestamptz not null default now()
);
alter table ${n.c} enable row level security;
revoke all on ${n.c} from anon, authenticated;
grant all on ${n.c} to service_role;
`;
}

/** Adopt mode adds the xid column; existing rows get the migration's transaction id. */
function adoptXid(n: Names): string {
  if (!n.has("xid")) return "";
  return `
alter table ${n.t} add column if not exists ${n.e("xid")} xid8 not null default pg_current_xact_id();
create index if not exists outbox_events_xid_idx on ${n.t} (${n.e("xid")}, ${n.e("position")});`;
}

function tables(ctx: ModuleContext, n: Names): string {
  if (!ctx.manages) return `${adoptXid(n)}${consumersTable(n)}`;
  const samePosition = n.e("position") === n.e("id");
  const columns = [
    samePosition
      ? `${n.e("id")} bigint generated always as identity primary key`
      : `${n.e("id")} uuid primary key default gen_random_uuid()`,
    ...(samePosition
      ? []
      : [`${n.e("position")} bigint generated always as identity unique`]),
    `${n.e("type")} text not null`,
    n.has("source") ? `${n.e("source")} text` : undefined,
    n.has("subject") ? `${n.e("subject")} text` : undefined,
    n.has("tenant") ? `${n.e("tenant")} ${ctx.idType}` : undefined,
    n.has("key") ? `${n.e("key")} text` : undefined,
    `${n.e("payload")} jsonb not null default '{}'`,
    n.has("actor") ? `${n.e("actor")} uuid` : undefined,
    `${n.e("createdAt")} timestamptz not null default now()`,
    n.has("xid")
      ? `${n.e("xid")} xid8 not null default pg_current_xact_id()`
      : undefined,
  ].filter((line) => line !== undefined);
  const keyIndex = n.has("key")
    ? n.has("tenant")
      ? `\ncreate unique index if not exists outbox_events_key_idx on ${n.t} (${n.e("key")}, ${n.e("tenant")}) nulls not distinct where ${n.e("key")} is not null;`
      : `\ncreate unique index if not exists outbox_events_key_idx on ${n.t} (${n.e("key")}) where ${n.e("key")} is not null;`
    : "";
  const subjectIndex = n.has("subject")
    ? `\ncreate index if not exists outbox_events_subject_idx on ${n.t} (${n.e("subject")}, ${n.e("position")});`
    : "";
  return `
create table if not exists ${n.t} (
  ${columns.join(",\n  ")}
);${keyIndex}${subjectIndex}
create index if not exists outbox_events_type_idx on ${n.t} (${n.e("type")}, ${n.e("position")});
create index if not exists outbox_events_created_idx on ${n.t} (${n.e("createdAt")});${
    n.has("xid")
      ? `\ncreate index if not exists outbox_events_xid_idx on ${n.t} (${n.e("xid")}, ${n.e("position")});`
      : ""
  }
alter table ${n.t} enable row level security;
revoke all on ${n.t} from anon, authenticated;
grant all on ${n.t} to service_role;
${consumersTable(n)}`;
}

function eventJson(n: Names, row: string): string {
  const optional = (logical: string, key: string) =>
    n.has(logical) ? `,\n    '${key}', ${row}.${n.e(logical)}` : "";
  return `jsonb_build_object(
    'position', ${row}.${n.e("position")},
    'id', ${row}.${n.e("id")},
    'type', ${row}.${n.e("type")},
    'payload', ${row}.${n.e("payload")},
    'created_at', ${row}.${n.e("createdAt")}${optional("source", "source")}${optional("subject", "subject")}${optional("tenant", "tenant")}${optional("key", "key")}${optional("actor", "actor_id")}
  )`;
}

function emit(ctx: ModuleContext, n: Names): string {
  const insert: [string, string][] = [
    [n.e("type"), "event_type"],
    [n.e("payload"), "coalesce(payload, '{}')"],
  ];
  if (n.has("source")) {
    const fallback = ctx.text("defaultSource", "");
    insert.push([
      n.e("source"),
      fallback ? `coalesce(source, ${sqlString(fallback)})` : "source",
    ]);
  }
  if (n.has("subject"))
    insert.push([n.e("subject"), "coalesce(subject, payload ->> 'subject')"]);
  if (n.has("tenant")) insert.push([n.e("tenant"), `tenant::${ctx.idType}`]);
  if (n.has("key")) insert.push([n.e("key"), "key"]);
  if (n.has("actor")) insert.push([n.e("actor"), "auth.uid()"]);
  const sameTenant = n.has("tenant")
    ? ` and e.${n.e("tenant")} is not distinct from tenant::${ctx.idType}`
    : "";
  const existing = n.has("key")
    ? `
  if key is not null then
    select e.${n.e("id")}::text into found_id from ${n.t} e
    where e.${n.e("key")} = key${sameTenant};
    if found_id is not null then
      return found_id;
    end if;
  end if;`
    : "";
  const retry = n.has("key")
    ? `
  if found_id is null then
    -- Another transaction emitted the same key first.
    select e.${n.e("id")}::text into found_id from ${n.t} e
    where e.${n.e("key")} = key${sameTenant};
  end if;`
    : "";
  const roles = ctx.list("emitRoles", ["service_role"]);
  for (const role of roles) {
    if (!/^[a-z_][a-z0-9_]*$/.test(role)) {
      throw new TypeError(
        `sql.modules.outbox.options.emitRoles: "${role}" is not a role name`,
      );
    }
  }
  const signature = `${ctx.fn("emit_event")}(text, jsonb, text, text, text, text)`;
  return `
-- create or replace can't change the return type of an earlier install.
drop function if exists ${signature};
-- Appends an event in the caller's transaction, so it exists only if the
-- transaction commits, and returns its id. A repeated key (per tenant)
-- returns the first event's id.
create or replace function ${ctx.fn("emit_event")}(
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
  end if;${existing}
  insert into ${n.t} (${insert.map(([column]) => column).join(", ")})
  values (${insert.map(([, value]) => value).join(", ")})
  on conflict do nothing
  returning ${n.e("id")}::text into found_id;${retry}
  return found_id;
end;
$$;
revoke execute on function ${signature} from public, anon, authenticated;
grant execute on function ${signature} to ${[...new Set(["service_role", ...roles])].join(", ")};`;
}

function consumers(ctx: ModuleContext, n: Names): string {
  const byXid = n.has("xid");
  const settle = ctx.text("settle", "5 seconds");
  if (!byXid && /^\s*0+(\.0+)?\s*[a-z]*\s*$/i.test(settle)) {
    throw new TypeError(
      "sql.modules.outbox.options.settle must be longer than zero: without the xid column it is how long a slow commit has to show up",
    );
  }
  const pos = (row: string) => `${row}.${n.e("position")}`;
  // (xid, position) when the xid column exists, else the position alone.
  const key = (row: string) =>
    byXid ? `(${row}.${n.e("xid")}, ${pos(row)})` : pos(row);
  const cursor = (row: string) =>
    byXid
      ? `(${row}.${n.k("cursorXid")}, ${row}.${n.k("cursor")})`
      : `${row}.${n.k("cursor")}`;
  const order = (row: string, direction = "") =>
    byXid
      ? `${row}.${n.e("xid")}${direction}, ${pos(row)}${direction}`
      : `${pos(row)}${direction}`;
  const settled = byXid
    ? `e.${n.e("xid")} < pg_snapshot_xmin(pg_current_snapshot())`
    : `e.${n.e("createdAt")} < now() - ${sqlString(settle)}::interval`;
  const xidOf = (row: string) => (byXid ? `${row}.${n.e("xid")}` : `'0'::xid8`);
  const matches = `(c.${n.k("types")} is null or exists (
        select 1 from unnest(c.${n.k("types")}) p
        where p = '*' or p = e.${n.e("type")}
          or (right(p, 2) = '.*' and starts_with(e.${n.e("type")}, left(p, -1)))
      ))`;
  const history = ctx.fn("outbox_history").split(".").at(-1);
  const subjectFilter = n.has("subject")
    ? `(${history}.subject is null or e.${n.e("subject")} = ${history}.subject)`
    : `${history}.subject is null`;
  const service = (fn: string, args: string) =>
    `revoke execute on function ${ctx.fn(fn)}(${args}) from public, anon, authenticated;
grant execute on function ${ctx.fn(fn)}(${args}) to service_role;`;
  const retention = sqlString(ctx.text("retention", "30 days"));
  return `
drop function if exists ${ctx.fn("purge_outbox")}(interval);

-- Registers a consumer. A new one starts after the latest event, or at the
-- first with from_start. Registering again changes only its types.
create or replace function ${ctx.fn("outbox_register")}(consumer text, types text[] default null, from_start boolean default false)
returns bigint
language sql
security definer
set search_path = ''
as $$
  insert into ${n.c} (${n.k("name")}, ${n.k("cursorXid")}, ${n.k("cursor")}, ${n.k("types")})
  select consumer, coalesce(latest.xid, '0'), coalesce(latest.position, 0), types
  from (select 1) one
  left join lateral (
    select ${xidOf("e")} as xid, ${pos("e")} as position from ${n.t} e
    where not from_start
    order by ${order("e", " desc")}
    limit 1
  ) latest on true
  on conflict (${n.k("name")}) do update set ${n.k("types")} = excluded.${n.k("types")}, ${n.k("updatedAt")} = now()
  returning ${n.k("cursor")}
$$;

-- Deletes a consumer and its cursor, so purge_outbox no longer waits for it.
create or replace function ${ctx.fn("outbox_unregister")}(consumer text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  delete from ${n.c} k where k.${n.k("name")} = consumer;
  return found;
end;
$$;

-- Leases the consumer to owner and returns its next events after the
-- cursor. ${
    byXid
      ? `Events of transactions still running are held back, and
-- events sort by (xid, position), so a transaction that commits late sorts
-- after the cursor and is never skipped.`
      : `Events newer than the settle interval are held back for
-- slow commits.`
  } When no event matches the consumer's types,
-- the cursor moves past the settled events it scanned.
create or replace function ${ctx.fn("outbox_claim")}(consumer text, owner text, max_events integer default 100, lease interval default '1 minute')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  c ${n.c};
  events jsonb;
begin
  update ${n.c} k
  set ${n.k("leaseOwner")} = owner, ${n.k("leaseUntil")} = now() + lease, ${n.k("updatedAt")} = now()
  where k.${n.k("name")} = consumer
    and (k.${n.k("leaseUntil")} is null or k.${n.k("leaseUntil")} < now() or k.${n.k("leaseOwner")} = owner)
  returning k.* into c;
  if not found then
    if not exists (select 1 from ${n.c} k where k.${n.k("name")} = consumer) then
      raise exception 'Unknown outbox consumer %', consumer using errcode = 'P0002', hint = 'OUTBOX_UNKNOWN_CONSUMER';
    end if;
    return '[]';
  end if;
  select jsonb_agg(x.event order by x.n) into events
  from (
    select ${eventJson(n, "e")} as event, row_number() over (order by ${order("e")}) as n
    from ${n.t} e
    where ${key("e")} > ${cursor("c")}
      and ${settled}
      and ${matches}
    order by ${order("e")}
    limit max_events
  ) x;
  if events is null then
    update ${n.c} k
    set (${n.k("cursorXid")}, ${n.k("cursor")}) = (
      select ${xidOf("e")}, ${pos("e")} from ${n.t} e
      where ${key("e")} > ${cursor("c")} and ${settled}
      order by ${order("e", " desc")}
      limit 1
    )
    where k.${n.k("name")} = consumer
      and exists (select 1 from ${n.t} e where ${key("e")} > ${cursor("c")} and ${settled});
  end if;
  return coalesce(events, '[]');
end;
$$;

-- Moves the cursor to the event at position upto (when given) and releases
-- the lease. False when owner no longer holds it.
create or replace function ${ctx.fn("outbox_ack")}(consumer text, owner text, upto bigint default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  update ${n.c} k
  set (${n.k("cursorXid")}, ${n.k("cursor")}) = (
      select ${xidOf("e")}, ${pos("e")} from ${n.t} e where ${pos("e")} = upto
    ),
    ${n.k("leaseOwner")} = null, ${n.k("leaseUntil")} = null, ${n.k("updatedAt")} = now()
  where k.${n.k("name")} = consumer and k.${n.k("leaseOwner")} = owner
    and upto is not null
    and exists (select 1 from ${n.t} e where ${pos("e")} = upto and ${key("e")} > ${cursor("k")});
  if found then
    return true;
  end if;
  update ${n.c} k
  set ${n.k("leaseOwner")} = null, ${n.k("leaseUntil")} = null, ${n.k("updatedAt")} = now()
  where k.${n.k("name")} = consumer and k.${n.k("leaseOwner")} = owner;
  return found;
end;
$$;

-- Kept events, by subject and type, oldest first.
create or replace function ${ctx.fn("outbox_history")}(subject text default null, event_type text default null, after bigint default 0, max_events integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.event order by x.position), '[]')
  from (
    select ${eventJson(n, "e")} as event, e.${n.e("position")} as position
    from ${n.t} e
    where e.${n.e("position")} > ${history}.after
      and ${subjectFilter}
      and (${history}.event_type is null or e.${n.e("type")} = ${history}.event_type)
    order by e.${n.e("position")}
    limit ${history}.max_events
  ) x
$$;

-- Deletes up to batch events older than older_than that every consumer has
-- passed, and returns how many. Run it until it returns less than batch.
-- A null argument takes its default.
create or replace function ${ctx.fn("purge_outbox")}(older_than interval default ${retention}, batch integer default 10000)
returns integer
language sql
security definer
set search_path = ''
as $$
  with gone as (
    delete from ${n.t} e
    where e.${n.e("id")} in (
      select d.${n.e("id")} from ${n.t} d
      where d.${n.e("createdAt")} < now() - coalesce(older_than, ${retention}::interval)
        and (
          not exists (select 1 from ${n.c})
          or ${key("d")} <= (
            select ${byXid ? `k.${n.k("cursorXid")}, ` : ""}k.${n.k("cursor")} from ${n.c} k
            order by ${byXid ? `k.${n.k("cursorXid")}, ` : ""}k.${n.k("cursor")}
            limit 1
          )
        )
      order by d.${n.e("createdAt")}
      limit coalesce(batch, 10000)
    )
    returning 1
  )
  select count(*)::integer from gone
$$;
${service("outbox_register", "text, text[], boolean")}
${service("outbox_unregister", "text")}
${service("outbox_claim", "text, text, integer, interval")}
${service("outbox_ack", "text, text, bigint")}
${service("outbox_history", "text, text, bigint, integer")}
${service("purge_outbox", "interval, integer")}`;
}

function tracking(ctx: ModuleContext): string {
  const trigger = ctx.trigger("outbox_events");
  const updateTrigger = ctx.trigger("outbox_events_update");
  const run = ctx.fn("outbox_row_event").replaceAll("%", "%%");
  return `
-- A row trigger that emits <prefix>.created, .updated and .deleted with the
-- row as payload. prefix defaults to the table name.
create or replace function ${ctx.fn("outbox_row_event")}()
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
  perform ${ctx.fn("emit_event")}(
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

create or replace function ${ctx.fn("track_events")}(target regclass, type_prefix text default null, tenant_column text default null)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists ${trigger.replaceAll("%", "%%")} on %s', target);
  execute format('drop trigger if exists ${updateTrigger.replaceAll("%", "%%")} on %s', target);
  execute format(
    'create trigger ${trigger.replaceAll("%", "%%")} after insert or delete on %s for each row execute function ${run}(%L, %L)',
    target, coalesce(type_prefix, ''), coalesce(tenant_column, '')
  );
  -- jsonb, not the row: a row comparison fails on columns without equality (json).
  execute format(
    'create trigger ${updateTrigger.replaceAll("%", "%%")} after update on %s for each row when (to_jsonb(old) is distinct from to_jsonb(new)) execute function ${run}(%L, %L)',
    target, coalesce(type_prefix, ''), coalesce(tenant_column, '')
  );
end;
$$;
revoke execute on function ${ctx.fn("track_events")}(regclass, text, text) from public, anon, authenticated;`;
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const n = names(ctx);
  return [
    `${schemaPreamble(ctx)}${tables(ctx, n)}`,
    emit(ctx, n),
    consumers(ctx, n),
    tracking(ctx),
  ].join("\n");
}

export const OUTBOX: ModuleDefinition = {
  name: "outbox",
  title: "Outbox",
  description:
    "Events written in the same transaction as the change, read by named consumers with their own cursor and lease, kept for history and relayed as CloudEvents.",
  requires: [],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 2,
  names: NAMES,
  upgrades: [
    {
      from: 1,
      description:
        "track_events adds an update trigger that skips updates that change nothing; call it again for tables it already tracks.",
      sql: () => "",
    },
  ],
  contract: () => [
    {
      name: "emit_event",
      args: ["text", "jsonb", "text", "text", "text", "text"],
      returns: "text",
    },
    {
      name: "outbox_register",
      args: ["text", "text[]", "boolean"],
      returns: "bigint",
    },
    {
      name: "outbox_claim",
      args: ["text", "text", "integer", "interval"],
      returns: "jsonb",
    },
    {
      name: "outbox_ack",
      args: ["text", "text", "bigint"],
      returns: "boolean",
    },
    {
      name: "outbox_history",
      args: ["text", "text", "bigint", "integer"],
      returns: "jsonb",
    },
    { name: "outbox_unregister", args: ["text"], returns: "boolean" },
    {
      name: "purge_outbox",
      args: ["interval", "integer"],
      returns: "integer",
    },
  ],
  build,
};
