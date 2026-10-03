import type { KitContext, KitNames } from "../context.ts";
import type { KitModuleDefinition } from "../kit.ts";

import { sqlString } from "../../core/template.ts";
import { schemaPreamble } from "../shared.ts";

const NAMES: KitNames = {
  tables: {
    events: {
      name: "outbox_events",
      columns: {
        id: "id",
        position: "id",
        type: "type",
        source: "source",
        subject: "subject",
        tenant: "tenant",
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
        cursor: "cursor",
        types: "types",
        leaseOwner: "lease_owner",
        leaseUntil: "lease_until",
        updatedAt: "updated_at",
      },
    },
  },
  hooks: [],
};

const TYPE = /^[a-z][a-z0-9_ ]*(\[\])?$/;

interface Names {
  readonly t: string;
  readonly c: string;
  readonly e: (logical: string) => string;
  readonly k: (logical: string) => string;
  readonly has: (logical: string) => boolean;
}

function names(ctx: KitContext): Names {
  return {
    t: ctx.table("events"),
    c: ctx.table("consumers"),
    e: (logical) => ctx.col("events", logical),
    k: (logical) => ctx.col("consumers", logical),
    has: (logical) => ctx.has("events", logical),
  };
}

function tenantType(ctx: KitContext): string {
  const type = ctx.text("tenantType", "text");
  if (!TYPE.test(type)) {
    throw new TypeError(
      `kits.outbox.options.tenantType must be a type name such as "uuid", not "${type}"`,
    );
  }
  return type;
}

function tables(ctx: KitContext, n: Names): string {
  if (!ctx.manages) return "";
  const samePosition = n.e("position") === n.e("id");
  const columns = [
    `${n.e("id")} bigint generated always as identity primary key`,
    ...(samePosition
      ? []
      : [`${n.e("position")} bigint generated always as identity unique`]),
    `${n.e("type")} text not null`,
    n.has("source") ? `${n.e("source")} text` : undefined,
    n.has("subject") ? `${n.e("subject")} text` : undefined,
    n.has("tenant") ? `${n.e("tenant")} ${tenantType(ctx)}` : undefined,
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
      ? `\ncreate unique index if not exists outbox_events_key_idx on ${n.t} (${n.e("tenant")}, ${n.e("key")}) nulls not distinct where ${n.e("key")} is not null;`
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
create index if not exists outbox_events_created_idx on ${n.t} (${n.e("createdAt")});
alter table ${n.t} enable row level security;
revoke all on ${n.t} from anon, authenticated;
grant all on ${n.t} to service_role;

create table if not exists ${n.c} (
  ${n.k("name")} text primary key,
  ${n.k("cursor")} bigint not null default 0,
  -- Type patterns ('org.*', 'invoice.paid'); null takes every event.
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

function emit(ctx: KitContext, n: Names): string {
  const insert: [string, string][] = [
    [n.e("type"), "event_type"],
    [n.e("payload"), "coalesce(payload, '{}')"],
  ];
  if (n.has("source")) insert.push([n.e("source"), "source"]);
  if (n.has("subject"))
    insert.push([n.e("subject"), "coalesce(subject, payload ->> 'subject')"]);
  if (n.has("tenant"))
    insert.push([n.e("tenant"), `tenant::${tenantType(ctx)}`]);
  if (n.has("key")) insert.push([n.e("key"), "key"]);
  if (n.has("actor")) insert.push([n.e("actor"), "auth.uid()"]);
  const sameTenant = n.has("tenant")
    ? ` and e.${n.e("tenant")} is not distinct from tenant::${tenantType(ctx)}`
    : "";
  const existing = n.has("key")
    ? `
  if key is not null then
    select e.${n.e("position")} into found_position from ${n.t} e
    where e.${n.e("key")} = key${sameTenant};
    if found_position is not null then
      return found_position;
    end if;
  end if;`
    : "";
  const retry = n.has("key")
    ? `
  if found_position is null then
    -- Another transaction emitted the same key first.
    select e.${n.e("position")} into found_position from ${n.t} e
    where e.${n.e("key")} = key${sameTenant};
  end if;`
    : "";
  const roles = ctx.list("emitRoles", ["service_role"]);
  for (const role of roles) {
    if (!/^[a-z_][a-z0-9_]*$/.test(role)) {
      throw new TypeError(
        `kits.outbox.options.emitRoles: "${role}" is not a role name`,
      );
    }
  }
  const signature = `${ctx.fn("emit_event")}(text, jsonb, text, text, text, text)`;
  return `
-- Appends an event in the caller's transaction, so it exists only if the
-- transaction commits. A repeated key (per tenant) returns the first event.
create or replace function ${ctx.fn("emit_event")}(
  event_type text,
  payload jsonb default '{}',
  subject text default null,
  tenant text default null,
  key text default null,
  source text default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  found_position bigint;
begin
  if event_type is null or btrim(event_type) = '' then
    raise exception 'An event needs a type' using errcode = '22023', hint = 'OUTBOX_TYPE_REQUIRED';
  end if;${existing}
  insert into ${n.t} (${insert.map(([column]) => column).join(", ")})
  values (${insert.map(([, value]) => value).join(", ")})
  on conflict do nothing
  returning ${n.e("position")} into found_position;${retry}
  return found_position;
end;
$$;
revoke execute on function ${signature} from public, anon, authenticated;
grant execute on function ${signature} to ${[...new Set(["service_role", ...roles])].join(", ")};`;
}

function consumers(ctx: KitContext, n: Names): string {
  const settled = n.has("xid")
    ? `e.${n.e("xid")} < pg_snapshot_xmin(pg_current_snapshot())`
    : `e.${n.e("createdAt")} < now() - ${sqlString(ctx.text("settle", "5 seconds"))}::interval`;
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
-- Registers a consumer. A new one starts after the latest event, or at the
-- first with from_start. Registering again changes only its types.
create or replace function ${ctx.fn("outbox_register")}(consumer text, types text[] default null, from_start boolean default false)
returns bigint
language sql
security definer
set search_path = ''
as $$
  insert into ${n.c} (${n.k("name")}, ${n.k("cursor")}, ${n.k("types")})
  values (
    consumer,
    case when from_start then 0 else coalesce((select max(e.${n.e("position")}) from ${n.t} e), 0) end,
    types
  )
  on conflict (${n.k("name")}) do update set ${n.k("types")} = excluded.${n.k("types")}, ${n.k("updatedAt")} = now()
  returning ${n.k("cursor")}
$$;

-- Leases the consumer to owner and returns its next events after the
-- cursor, oldest first. Events of transactions still running are held back,
-- so a slow commit is never skipped. Empty while another owner holds it.
create or replace function ${ctx.fn("outbox_claim")}(consumer text, owner text, max_events integer default 100, lease interval default '1 minute')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  c ${n.c};
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
  return coalesce((
    select jsonb_agg(x.event order by x.position)
    from (
      select ${eventJson(n, "e")} as event, e.${n.e("position")} as position
      from ${n.t} e
      where e.${n.e("position")} > c.${n.k("cursor")}
        and ${settled}
        and ${matches}
      order by e.${n.e("position")}
      limit max_events
    ) x
  ), '[]');
end;
$$;

-- Moves the cursor to upto (when given) and releases the lease. False when
-- owner no longer holds it.
create or replace function ${ctx.fn("outbox_ack")}(consumer text, owner text, upto bigint default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  update ${n.c} k
  set ${n.k("cursor")} = greatest(k.${n.k("cursor")}, coalesce(upto, k.${n.k("cursor")})),
    ${n.k("leaseOwner")} = null, ${n.k("leaseUntil")} = null, ${n.k("updatedAt")} = now()
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

-- Deletes events older than older_than that every consumer has passed.
create or replace function ${ctx.fn("purge_outbox")}(older_than interval default ${retention})
returns integer
language sql
security definer
set search_path = ''
as $$
  with gone as (
    delete from ${n.t} e
    where e.${n.e("createdAt")} < now() - older_than
      and e.${n.e("position")} <= coalesce((select min(k.${n.k("cursor")}) from ${n.c} k), e.${n.e("position")})
    returning 1
  )
  select count(*)::integer from gone
$$;
${service("outbox_register", "text, text[], boolean")}
${service("outbox_claim", "text, text, integer, interval")}
${service("outbox_ack", "text, text, bigint")}
${service("outbox_history", "text, text, bigint, integer")}
${service("purge_outbox", "interval")}`;
}

function tracking(ctx: KitContext): string {
  const trigger = ctx.trigger("outbox_events");
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
  execute format(
    'create trigger ${trigger.replaceAll("%", "%%")} after insert or update or delete on %s for each row execute function ${ctx.fn("outbox_row_event").replaceAll("%", "%%")}(%L, %L)',
    target, coalesce(type_prefix, ''), coalesce(tenant_column, '')
  );
end;
$$;
revoke execute on function ${ctx.fn("track_events")}(regclass, text, text) from public, anon, authenticated;`;
}

function build(ctx: KitContext): string {
  if (ctx.mode === "custom") return "";
  const n = names(ctx);
  return [
    `${schemaPreamble(ctx)}${tables(ctx, n)}`,
    emit(ctx, n),
    consumers(ctx, n),
    tracking(ctx),
  ].join("\n");
}

export const OUTBOX: KitModuleDefinition = {
  name: "outbox",
  title: "Outbox",
  description:
    "Events written in the same transaction as the change, read by named consumers with their own cursor and lease, kept for history and relayed as CloudEvents.",
  requires: [],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 1,
  names: NAMES,
  contract: () => [
    {
      name: "emit_event",
      args: ["text", "jsonb", "text", "text", "text", "text"],
      returns: "bigint",
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
    { name: "purge_outbox", args: ["interval"], returns: "integer" },
  ],
  build,
};
