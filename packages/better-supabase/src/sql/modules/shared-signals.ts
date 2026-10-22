import type { SharedSignalsEvents } from "../../blocks/shared-signals/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { SSF_POLL, SSF_PUSH } from "../../blocks/shared-signals/methods.ts";
import { sqlString } from "../../core/template.ts";
import {
  fail,
  lockTable,
  schemaPreamble,
  SERVICE_CALLER,
  serviceGrant,
  updatedAt,
} from "../shared.ts";

const EVENTS: BlockSqlEvents<SharedSignalsEvents> = {
  "ssf_stream.created": {
    subject: "shared-signals",
    payload: ["streamId", "receiver", "tenant", "method"],
  },
  "ssf_stream.status_changed": {
    subject: "shared-signals",
    payload: ["streamId", "receiver", "tenant", "status", "reason"],
  },
  "ssf_stream.deleted": {
    subject: "shared-signals",
    payload: ["streamId", "receiver", "tenant"],
  },
};

const NAMES: BlockSqlNames = {
  events: EVENTS,
  options: ["retention"],
  tables: {
    streams: {
      name: "ssf_streams",
      columns: {
        id: "id",
        tenant: "tenant",
        receiver: "receiver",
        audience: "audience",
        description: "description",
        eventsRequested: "events_requested",
        eventsDelivered: "events_delivered",
        method: "delivery_method",
        endpoint: "endpoint_id",
        status: "status",
        reason: "reason",
        verifiedAt: "verified_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    events: {
      name: "ssf_events",
      columns: {
        stream: "stream_id",
        jti: "jti",
        token: "token",
        createdAt: "created_at",
      },
    },
    received: {
      name: "ssf_received",
      columns: { issuer: "issuer", jti: "jti", receivedAt: "received_at" },
    },
  },
};

const guard = `
  if not (${SERVICE_CALLER}) then
    ${fail("SSF_FORBIDDEN", "only the service role manages shared signals streams")}
  end if;`;

type StreamEvent =
  | "ssf_stream.created"
  | "ssf_stream.status_changed"
  | "ssf_stream.deleted";

function streamEvent(
  ctx: BlockSqlContext,
  type: StreamEvent,
  row: string,
): string {
  const s = (logical: string): string =>
    `${row}.${ctx.col("streams", logical)}`;

  const extra =
    type === "ssf_stream.created"
      ? `, 'method', ${s("method")}`
      : type === "ssf_stream.status_changed"
        ? `, 'status', ${s("status")}, 'reason', ${s("reason")}`
        : "";

  return ctx.record({
    type,
    payload: `jsonb_build_object('streamId', ${s("id")}, 'receiver', ${s("receiver")}, 'tenant', ${s("tenant")}${extra})`,
    subject: `'shared-signals/' || ${s("id")}`,
    audit: {
      category: "security",
      targetType: "ssf_stream",
      recordId: `${s("id")}::text`,
    },
  });
}

/** The webhooks-out names a push stream writes, when that module is installed. */
interface PushNames {
  readonly table: string;
  readonly col: (logical: string) => string;
  readonly has: (logical: string) => boolean;
  readonly idType: string;
  readonly dispatch: string;
}

function pushNames(ctx: BlockSqlContext): PushNames | undefined {
  if (!ctx.installed("webhooks-out")) {
    return undefined;
  }

  const w = ctx.of("webhooks-out");

  if (!w.has("endpoints", "format")) {
    throw new TypeError(
      "blocks.shared-signals: push streams need the webhooks-out endpoints format column",
    );
  }

  return {
    table: w.table("endpoints"),
    col: (logical) => w.col("endpoints", logical),
    has: (logical) => w.has("endpoints", logical),
    idType: w.idType,
    dispatch: w.fn("dispatch_webhook"),
  };
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const t = ctx.table("streams");
  const e = ctx.table("events");
  const r = ctx.table("received");
  const c = (logical: string): string => ctx.col("streams", logical);
  const ev = (logical: string): string => ctx.col("events", logical);
  const rc = (logical: string): string => ctx.col("received", logical);
  const fn = (name: string): string => ctx.fn(name);
  const retention = sqlString(ctx.text("retention", "7 days"));
  const push = pushNames(ctx);
  const w = push?.col ?? ((logical: string) => logical);

  const endpointUrl = (alias: string): string =>
    push
      ? `(select we.${w("url")} from ${push.table} we where we.${w("id")} = ${alias}.${c("endpoint")})`
      : "null::text";

  const streamJson = (alias: string): string => `jsonb_build_object(
    'id', ${alias}.${c("id")},
    'tenant', ${alias}.${c("tenant")},
    'receiver', ${alias}.${c("receiver")},
    'audience', to_jsonb(${alias}.${c("audience")}),
    'description', ${alias}.${c("description")},
    'eventsRequested', to_jsonb(${alias}.${c("eventsRequested")}),
    'eventsDelivered', to_jsonb(${alias}.${c("eventsDelivered")}),
    'method', ${alias}.${c("method")},
    'endpointUrl', ${endpointUrl(alias)},
    'status', ${alias}.${c("status")},
    'reason', ${alias}.${c("reason")},
    'createdAt', ${alias}.${c("createdAt")},
    'updatedAt', ${alias}.${c("updatedAt")}
  )`;

  const endpointColumns = push
    ? [
        ...(push.has("tenant")
          ? [[w("tenant"), `v_row.${c("tenant")}::${push.idType}`]]
          : []),
        ...(push.has("name")
          ? [[w("name"), `'Shared Signals stream ' || v_row.${c("id")}`]]
          : []),
        [w("url"), "create_ssf_stream.endpoint_url"],
        [w("format"), "'set'"],
        ...(push.has("credentialRef")
          ? [[w("credentialRef"), "create_ssf_stream.credential_ref"]]
          : []),
      ]
    : [];

  const createPush = push
    ? `
    if coalesce(create_ssf_stream.endpoint_url, '') = '' then
      ${fail("SSF_ENDPOINT_REQUIRED", "a push stream needs an endpoint_url", "22023")}
    end if;${
      push.has("tenant")
        ? `
    if v_row.${c("tenant")} is null then
      ${fail("SSF_TENANT_REQUIRED", "a push stream needs a tenant when webhook endpoints have one", "22023")}
    end if;`
        : ""
    }
    insert into ${push.table} as we (${endpointColumns.map(([column]) => column).join(", ")})
    values (${endpointColumns.map(([, value]) => value).join(", ")})
    returning we.${w("id")} into v_endpoint;
    update ${t} s set ${c("endpoint")} = v_endpoint where s.${c("id")} = v_row.${c("id")}
    returning s.* into v_row;`
    : `
    ${fail("SSF_PUSH_UNAVAILABLE", "push delivery needs the webhooks-out module", "0A000")}`;

  const updatePush = push
    ? `
  if update_ssf_stream.patch ? 'endpointUrl' and v_row.${c("endpoint")} is not null then
    update ${push.table} we set ${w("url")} = update_ssf_stream.patch ->> 'endpointUrl'
    where we.${w("id")} = v_row.${c("endpoint")};
  end if;`
    : "";

  const deleteEndpoint = push
    ? `
  if v_row.${c("endpoint")} is not null then
    delete from ${push.table} we where we.${w("id")} = v_row.${c("endpoint")};
  end if;`
    : "";

  // Dispatching needs an enabled endpoint; anything else holds the SET.
  const dispatchSet = (stream: string, jti: string, token: string): string =>
    push
      ? `perform ${push.dispatch}(${stream}.${c("endpoint")}, 'ssf.set', jsonb_build_object('set', ${token}), null, ${jti});`
      : "null;";

  const pushReady = (stream: string): string =>
    push
      ? `exists (select 1 from ${push.table} we where we.${w("id")} = ${stream}.${c("endpoint")} and we.${w("enabled")})`
      : "false";

  return `${schemaPreamble(ctx)}
-- Shared Signals streams this app transmits on (OpenID SSF 1.0): one row per
-- receiver stream, pushed through a webhooks-out endpoint (RFC 8935) or
-- polled (RFC 8936). ssf_events holds SETs to poll or held while paused;
-- ssf_received is the receiver's replay table of (issuer, jti).
create table if not exists ${t} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} text check (length(${c("tenant")}) between 1 and 200),
  ${c("receiver")} text not null check (length(${c("receiver")}) between 1 and 200),
  ${c("audience")} text[] not null check (cardinality(${c("audience")}) between 1 and 20),
  ${c("description")} text check (length(${c("description")}) <= 1000),
  ${c("eventsRequested")} text[] not null default '{}',
  ${c("eventsDelivered")} text[] not null default '{}',
  ${c("method")} text not null check (${c("method")} in ('${SSF_PUSH}', '${SSF_POLL}')),
  ${c("endpoint")} uuid${push ? ` references ${push.table} (${w("id")}) on delete set null` : ""},
  ${c("status")} text not null default 'enabled' check (${c("status")} in ('enabled', 'paused', 'disabled')),
  ${c("reason")} text check (length(${c("reason")}) <= 1000),
  ${c("verifiedAt")} timestamptz,
  ${c("createdAt")} timestamptz not null default now(),
  ${c("updatedAt")} timestamptz not null default now()
);
create index if not exists ssf_streams_receiver_idx on ${t} (${c("receiver")});
create index if not exists ssf_streams_events_idx on ${t} using gin (${c("eventsDelivered")});
create index if not exists ssf_streams_endpoint_idx on ${t} (${c("endpoint")}) where ${c("endpoint")} is not null;
${updatedAt(t, c("updatedAt"))}
${lockTable(t)}

create table if not exists ${e} (
  ${ev("stream")} uuid not null references ${t} (${c("id")}) on delete cascade,
  ${ev("jti")} text not null check (length(${ev("jti")}) between 1 and 200),
  ${ev("token")} text not null,
  ${ev("createdAt")} timestamptz not null default now(),
  primary key (${ev("stream")}, ${ev("jti")})
);
create index if not exists ssf_events_order_idx on ${e} (${ev("stream")}, ${ev("createdAt")});
create index if not exists ssf_events_created_idx on ${e} (${ev("createdAt")});
${lockTable(e)}

create table if not exists ${r} (
  ${rc("issuer")} text not null,
  ${rc("jti")} text not null check (length(${rc("jti")}) between 1 and 200),
  ${rc("receivedAt")} timestamptz not null default now(),
  primary key (${rc("issuer")}, ${rc("jti")})
);
create index if not exists ssf_received_at_idx on ${r} (${rc("receivedAt")});
${lockTable(r)}

-- Creates a stream; a push stream gets a webhooks-out endpoint with format 'set'.
create or replace function ${fn("create_ssf_stream")}(id uuid, receiver text, tenant text, audience text[], delivery_method text, events_requested text[], events_delivered text[], description text default null, endpoint_url text default null, credential_ref jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t};
  v_endpoint uuid;
begin${guard}
  insert into ${t} (${c("id")}, ${c("tenant")}, ${c("receiver")}, ${c("audience")}, ${c("method")}, ${c("eventsRequested")}, ${c("eventsDelivered")}, ${c("description")})
  values (create_ssf_stream.id, create_ssf_stream.tenant, create_ssf_stream.receiver, create_ssf_stream.audience,
    create_ssf_stream.delivery_method, coalesce(create_ssf_stream.events_requested, '{}'),
    coalesce(create_ssf_stream.events_delivered, '{}'), create_ssf_stream.description)
  returning * into v_row;
  if v_row.${c("method")} = '${SSF_PUSH}' then${createPush}
  end if;
  ${streamEvent(ctx, "ssf_stream.created", "v_row")}
  return ${streamJson("v_row")};
end;
$$;
${serviceGrant(`${fn("create_ssf_stream")}(uuid, text, text, text[], text, text[], text[], text, text, jsonb)`)}

-- One stream, or null.
create or replace function ${fn("ssf_stream")}(id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin${guard}
  return (select ${streamJson("s")} from ${t} s where s.${c("id")} = ssf_stream.id);
end;
$$;
${serviceGrant(`${fn("ssf_stream")}(uuid)`)}

-- The streams of a receiver, oldest first.
create or replace function ${fn("ssf_streams")}(receiver text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin${guard}
  return coalesce((
    select jsonb_agg(${streamJson("s")} order by s.${c("createdAt")})
    from ${t} s where s.${c("receiver")} = ssf_streams.receiver
  ), '[]'::jsonb);
end;
$$;
${serviceGrant(`${fn("ssf_streams")}(text)`)}

-- Updates the receiver-supplied fields present in patch: description,
-- eventsRequested, eventsDelivered and endpointUrl.
create or replace function ${fn("update_ssf_stream")}(id uuid, patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t};
begin${guard}
  update ${t} s set
    ${c("description")} = case when update_ssf_stream.patch ? 'description' then update_ssf_stream.patch ->> 'description' else s.${c("description")} end,
    ${c("eventsRequested")} = case when update_ssf_stream.patch ? 'eventsRequested'
      then array(select jsonb_array_elements_text(update_ssf_stream.patch -> 'eventsRequested')) else s.${c("eventsRequested")} end,
    ${c("eventsDelivered")} = case when update_ssf_stream.patch ? 'eventsDelivered'
      then array(select jsonb_array_elements_text(update_ssf_stream.patch -> 'eventsDelivered')) else s.${c("eventsDelivered")} end
  where s.${c("id")} = update_ssf_stream.id
  returning s.* into v_row;
  if not found then
    return null;
  end if;${updatePush}
  return ${streamJson("v_row")};
end;
$$;
${serviceGrant(`${fn("update_ssf_stream")}(uuid, jsonb)`)}

-- Deletes a stream, its held SETs and its endpoint.
create or replace function ${fn("delete_ssf_stream")}(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t};
begin${guard}
  delete from ${t} s where s.${c("id")} = delete_ssf_stream.id returning s.* into v_row;
  if not found then
    return false;
  end if;${deleteEndpoint}
  ${streamEvent(ctx, "ssf_stream.deleted", "v_row")}
  return true;
end;
$$;
${serviceGrant(`${fn("delete_ssf_stream")}(uuid)`)}

-- Sends a SET to a stream: dispatched to an enabled push endpoint, queued
-- for polling, held while paused (or while the endpoint is disabled), or
-- dropped on a disabled stream. Returns which.
create or replace function ${fn("queue_ssf_set")}(stream_id uuid, jti text, token text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t};
begin${guard}
  select * into v_row from ${t} s where s.${c("id")} = queue_ssf_set.stream_id for update;
  if not found then
    ${fail("SSF_STREAM_NOT_FOUND", "stream not found", "P0002")}
  end if;
  if v_row.${c("status")} = 'disabled' then
    return 'dropped';
  end if;
  if v_row.${c("method")} = '${SSF_PUSH}' and v_row.${c("status")} = 'enabled' and ${pushReady("v_row")} then
    ${dispatchSet("v_row", "queue_ssf_set.jti", "queue_ssf_set.token")}
    return 'dispatched';
  end if;
  insert into ${e} (${ev("stream")}, ${ev("jti")}, ${ev("token")})
  values (v_row.${c("id")}, queue_ssf_set.jti, queue_ssf_set.token)
  on conflict do nothing;
  return case when v_row.${c("method")} = '${SSF_POLL}' and v_row.${c("status")} = 'enabled' then 'queued' else 'held' end;
end;
$$;
${serviceGrant(`${fn("queue_ssf_set")}(uuid, text, text)`)}

-- Sets a stream's status. Enabling a push stream dispatches the SETs held
-- while it was paused; disabling drops them. Returns the previous status.
create or replace function ${fn("set_ssf_stream_status")}(id uuid, status text, reason text default null)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t};
  v_previous text;
  v_held record;
begin${guard}
  if set_ssf_stream_status.status not in ('enabled', 'paused', 'disabled') then
    ${fail("SSF_STATUS_INVALID", "status is enabled, paused or disabled", "22023")}
  end if;
  select s.${c("status")} into v_previous from ${t} s where s.${c("id")} = set_ssf_stream_status.id for update;
  if not found then
    ${fail("SSF_STREAM_NOT_FOUND", "stream not found", "P0002")}
  end if;
  update ${t} s set ${c("status")} = set_ssf_stream_status.status, ${c("reason")} = set_ssf_stream_status.reason
  where s.${c("id")} = set_ssf_stream_status.id
  returning s.* into v_row;
  if v_row.${c("status")} = 'disabled' then
    delete from ${e} q where q.${ev("stream")} = v_row.${c("id")};
  elsif v_row.${c("status")} = 'enabled' and v_row.${c("method")} = '${SSF_PUSH}' and ${pushReady("v_row")} then
    for v_held in
      select q.${ev("jti")} as jti, q.${ev("token")} as token from ${e} q
      where q.${ev("stream")} = v_row.${c("id")} order by q.${ev("createdAt")}
    loop
      ${dispatchSet("v_row", "v_held.jti", "v_held.token")}
    end loop;
    delete from ${e} q where q.${ev("stream")} = v_row.${c("id")};
  end if;
  if v_previous is distinct from v_row.${c("status")} then
    ${streamEvent(ctx, "ssf_stream.status_changed", "v_row")}
  end if;
  return v_previous;
end;
$$;
${serviceGrant(`${fn("set_ssf_stream_status")}(uuid, text, text)`)}

-- The streams an event of event_type goes to: streams of the tenant and
-- app-wide streams (no tenant) that deliver it and aren't disabled.
create or replace function ${fn("ssf_streams_for_event")}(tenant text, event_type text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin${guard}
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', s.${c("id")}, 'audience', to_jsonb(s.${c("audience")})) order by s.${c("createdAt")})
    from ${t} s
    where s.${c("status")} <> 'disabled'
      and ssf_streams_for_event.event_type = any (s.${c("eventsDelivered")})
      and (s.${c("tenant")} is null or s.${c("tenant")} = ssf_streams_for_event.tenant)
  ), '[]'::jsonb);
end;
$$;
${serviceGrant(`${fn("ssf_streams_for_event")}(text, text)`)}

-- RFC 8936: acknowledges ack and the jtis in errors, then returns up to
-- max_events SETs of an enabled poll stream. A SET stays until acknowledged.
create or replace function ${fn("poll_ssf_events")}(stream_id uuid, max_events integer, ack text[] default '{}', errors jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t};
  v_limit integer := least(greatest(coalesce(poll_ssf_events.max_events, 100), 0), 1000);
  v_sets jsonb;
  v_more boolean;
begin${guard}
  select * into v_row from ${t} s where s.${c("id")} = poll_ssf_events.stream_id;
  if not found then
    ${fail("SSF_STREAM_NOT_FOUND", "stream not found", "P0002")}
  end if;
  if v_row.${c("method")} <> '${SSF_POLL}' then
    ${fail("SSF_STREAM_NOT_POLL", "the stream is not delivered by polling", "22023")}
  end if;
  delete from ${e} q
  where q.${ev("stream")} = v_row.${c("id")}
    and (q.${ev("jti")} = any (coalesce(poll_ssf_events.ack, '{}'))
      or coalesce(poll_ssf_events.errors, '{}'::jsonb) ? q.${ev("jti")});
  if v_row.${c("status")} <> 'enabled' or v_limit = 0 then
    return jsonb_build_object('sets', '{}'::jsonb, 'moreAvailable', false);
  end if;
  select count(*) > v_limit into v_more
  from (select 1 from ${e} q where q.${ev("stream")} = v_row.${c("id")} limit v_limit + 1) x;
  select coalesce(jsonb_object_agg(l.jti, l.token), '{}'::jsonb) into v_sets
  from (
    select q.${ev("jti")} as jti, q.${ev("token")} as token from ${e} q
    where q.${ev("stream")} = v_row.${c("id")}
    order by q.${ev("createdAt")}, q.${ev("jti")}
    limit v_limit
  ) l;
  return jsonb_build_object('sets', v_sets, 'moreAvailable', v_more);
end;
$$;
${serviceGrant(`${fn("poll_ssf_events")}(uuid, integer, text[], jsonb)`)}

-- Records a verification request; false when the stream's last one is newer
-- than min_interval, which the endpoint answers with 429.
create or replace function ${fn("note_ssf_verification")}(stream_id uuid, min_interval interval)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_noted boolean;
begin${guard}
  if not exists (select 1 from ${t} s where s.${c("id")} = note_ssf_verification.stream_id) then
    ${fail("SSF_STREAM_NOT_FOUND", "stream not found", "P0002")}
  end if;
  update ${t} s set ${c("verifiedAt")} = now()
  where s.${c("id")} = note_ssf_verification.stream_id
    and (s.${c("verifiedAt")} is null or s.${c("verifiedAt")} + coalesce(note_ssf_verification.min_interval, '0 seconds') <= now())
  returning true into v_noted;
  return coalesce(v_noted, false);
end;
$$;
${serviceGrant(`${fn("note_ssf_verification")}(uuid, interval)`)}

-- The receiver's replay check: true the first time (issuer, jti) is seen.
create or replace function ${fn("record_ssf_received")}(issuer text, jti text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_new boolean;
begin${guard}
  insert into ${r} (${rc("issuer")}, ${rc("jti")})
  values (record_ssf_received.issuer, record_ssf_received.jti)
  on conflict do nothing
  returning true into v_new;
  return coalesce(v_new, false);
end;
$$;
${serviceGrant(`${fn("record_ssf_received")}(text, text)`)}

-- Forgets a received SET whose handler failed, so the transmitter's retry is processed.
create or replace function ${fn("forget_ssf_received")}(issuer text, jti text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin${guard}
  delete from ${r} x where x.${rc("issuer")} = forget_ssf_received.issuer and x.${rc("jti")} = forget_ssf_received.jti;
  return found;
end;
$$;
${serviceGrant(`${fn("forget_ssf_received")}(text, text)`)}

-- Deletes replay entries and held or unpolled SETs older than the retention.
create or replace function ${fn("purge_shared_signals")}(older_than interval default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cutoff timestamptz := now() - coalesce(purge_shared_signals.older_than, ${retention}::interval);
  v_received integer;
  v_events integer;
begin${guard}
  delete from ${r} x where x.${rc("receivedAt")} < v_cutoff;
  get diagnostics v_received = row_count;
  delete from ${e} q where q.${ev("createdAt")} < v_cutoff;
  get diagnostics v_events = row_count;
  return v_received + v_events;
end;
$$;
${serviceGrant(`${fn("purge_shared_signals")}(interval)`)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "create_ssf_stream",
      args: [
        "uuid",
        "text",
        "text",
        "text[]",
        "text",
        "text[]",
        "text[]",
        "text",
        "text",
        "jsonb",
      ],
      returns: "jsonb",
    },
    { name: "ssf_stream", args: ["uuid"], returns: "jsonb" },
    { name: "ssf_streams", args: ["text"], returns: "jsonb" },
    { name: "update_ssf_stream", args: ["uuid", "jsonb"], returns: "jsonb" },
    { name: "delete_ssf_stream", args: ["uuid"], returns: "boolean" },
    { name: "queue_ssf_set", args: ["uuid", "text", "text"], returns: "text" },
    {
      name: "set_ssf_stream_status",
      args: ["uuid", "text", "text"],
      returns: "text",
    },
    { name: "ssf_streams_for_event", args: ["text", "text"], returns: "jsonb" },
    {
      name: "poll_ssf_events",
      args: ["uuid", "integer", "text[]", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "note_ssf_verification",
      args: ["uuid", "interval"],
      returns: "boolean",
    },
    { name: "record_ssf_received", args: ["text", "text"], returns: "boolean" },
    { name: "forget_ssf_received", args: ["text", "text"], returns: "boolean" },
    { name: "purge_shared_signals", args: ["interval"], returns: "integer" },
  ];
}

export const SHARED_SIGNALS: BlockSqlDefinition = {
  name: "shared-signals",
  title: "Shared signals",
  description:
    "OpenID Shared Signals streams: stream configuration and status per receiver, push delivery through a webhooks-out endpoint with format 'set' (RFC 8935), a poll queue (RFC 8936), SETs held while a stream is paused, and a receiver replay table. Only the service role calls it; createSsfTransmitter() and createSsfReceiver() in better-supabase/blocks/shared-signals mint and verify the SETs.",
  requires: [],
  integrates: ["webhooks-out", "outbox", "audit"],
  target: "schema",
  version: 1,
  names: NAMES,
  contract,
  build,
};
