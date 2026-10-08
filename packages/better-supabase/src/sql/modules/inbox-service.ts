import type { InboxSql } from "./inbox-names.ts";

import { forbidden, missing } from "./inbox-functions.ts";
import { topics } from "./inbox-names.ts";

/** The service calls: deliveries, stored webhook events, sweeps, templates and typing. */
export function inboxServiceFunctions(q: InboxSql): string {
  const { id, fn } = q;
  const cv = q.cols("conversations");
  const ms = q.cols("messages");
  const dl = q.cols("deliveries");
  const ie = q.cols("inbound");
  const tp = q.cols("templates");
  const T = (name: string): string => q.t(name);
  const service = q.service;
  const authed = (signature: string): string =>
    `revoke execute on function ${signature} from public, anon;
grant execute on function ${signature} to authenticated, service_role;`;
  const serviceOnly = (signature: string): string =>
    `revoke execute on function ${signature} from public, anon, authenticated;
grant execute on function ${signature} to service_role;`;

  return `-- One message with its first delivery, under the caller's RLS.
create or replace function ${fn("get_message")}(message uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select to_jsonb(m) || jsonb_build_object('delivery', (
    select jsonb_build_object('status', d.${dl("status")}, 'channel', d.${dl("channel")}, 'error', d.${dl("error")}, 'updated_at', d.${dl("updatedAt")})
    from ${T("deliveries")} d where d.${dl("message")} = m.${ms("id")}
    order by d.${dl("createdAt")} limit 1
  ))
  from ${T("messages")} m where m.${ms("id")} = get_message.message;
$$;
${authed(`${fn("get_message")}(uuid)`)}

-- A typing ping on the conversation's topic, from staff, the contact or
-- the service (actor names the bot).
create or replace function ${fn("set_typing")}(conversation uuid, typing boolean default true, actor text default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_who text;
begin
  if ${service} then
    v_who := coalesce(actor, 'bot');
  elsif ${fn("inbox_conversation_allowed")}(conversation::text, true) then
    v_who := (select auth.uid())::text;
  else
    ${forbidden("not allowed to write in this conversation")}
  end if;
  perform realtime.send(
    jsonb_build_object('user_id', v_who, 'typing', coalesce(typing, true)),
    'typing',
    ${topics(q).conversation("conversation")},
    true
  );
  return true;
end;
$$;
${authed(`${fn("set_typing")}(uuid, boolean, text)`)}

-- After posting an outbound message on its channel: records the platform's
-- id and the status.
create or replace function ${fn("record_delivery")}(message uuid, channel text, external_id text default null, status text default 'sent', error text default null)
returns jsonb
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${T("deliveries")}%rowtype;
begin
  insert into ${T("deliveries")} as d (${dl("tenant")}, ${dl("message")}, ${dl("channel")}, ${dl("externalId")}, ${dl("status")}, ${dl("error")}, ${dl("attempts")})
  select m.${ms("tenant")}, m.${ms("id")}, record_delivery.channel, record_delivery.external_id, coalesce(record_delivery.status, 'sent'), record_delivery.error, 1
  from ${T("messages")} m where m.${ms("id")} = record_delivery.message
  on conflict (${dl("message")}, ${dl("channel")}) do update set
    ${dl("externalId")} = coalesce(excluded.${dl("externalId")}, d.${dl("externalId")}),
    ${dl("status")} = excluded.${dl("status")},
    ${dl("error")} = excluded.${dl("error")},
    ${dl("attempts")} = d.${dl("attempts")} + 1
  returning * into v_row;
  if v_row.${dl("id")} is null then
    ${missing("message", "MESSAGE_NOT_FOUND")}
  end if;
  return to_jsonb(v_row);
end;
$$;
${serviceOnly(`${fn("record_delivery")}(uuid, text, text, text, text)`)}

-- A status callback from the channel. Status only moves forward (queued,
-- sent, delivered, read); failed counts only before delivery. Returns the
-- number of deliveries changed.
create or replace function ${fn("set_delivery_status")}(channel text, external_id text, status text, error text default null)
returns integer
language plpgsql
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_count integer;
begin
  update ${T("deliveries")} d set ${dl("status")} = status, ${dl("error")} = coalesce(error, d.${dl("error")})
  where d.${dl("channel")} = channel and d.${dl("externalId")} = external_id
    and (case status when 'failed' then d.${dl("status")} in ('queued', 'sent')
      else array_position(array['queued', 'sent', 'delivered', 'read'], status)
        > coalesce(array_position(array['queued', 'sent', 'delivered', 'read'], d.${dl("status")}), 0) end);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${serviceOnly(`${fn("set_delivery_status")}(text, text, text, text)`)}

-- Stores a webhook body before the ack. { id, duplicate }: a duplicate is a
-- retry of an event already stored under the same external_id.
create or replace function ${fn("store_inbound_event")}(adapter text, body text, external_id text default null, headers jsonb default '{}'::jsonb, inbox uuid default null, tenant ${id} default null)
returns jsonb
language plpgsql
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
begin
  insert into ${T("inbound")} (${ie("adapter")}, ${ie("body")}, ${ie("externalId")}, ${ie("headers")}, ${ie("inbox")}, ${ie("tenant")})
  values (adapter, body, external_id, coalesce(headers, '{}'::jsonb), inbox, tenant)
  on conflict do nothing
  returning ${ie("id")} into v_id;
  if v_id is not null then
    return jsonb_build_object('id', v_id, 'duplicate', false);
  end if;
  select e.${ie("id")} into v_id from ${T("inbound")} e where e.${ie("adapter")} = adapter and e.${ie("externalId")} = external_id;
  return jsonb_build_object('id', v_id, 'duplicate', true);
end;
$$;
${serviceOnly(`${fn("store_inbound_event")}(text, text, text, jsonb, uuid, ${id})`)}

create or replace function ${fn("set_inbound_event_status")}(event uuid, status text, error text default null)
returns boolean
language plpgsql
set search_path = ''
as $$
#variable_conflict use_variable
begin
  update ${T("inbound")} e set
    ${ie("status")} = status,
    ${ie("error")} = error,
    ${ie("attempts")} = e.${ie("attempts")} + 1,
    ${ie("processedAt")} = case when status in ('processed', 'ignored') then now() else e.${ie("processedAt")} end
  where e.${ie("id")} = event;
  return found;
end;
$$;
${serviceOnly(`${fn("set_inbound_event_status")}(uuid, text, text)`)}

-- Inbound events still waiting, oldest first, for a retry sweep.
create or replace function ${fn("pending_inbound_events")}(max integer default 100, max_attempts integer default 5)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(e) order by e.${ie("receivedAt")}), '[]'::jsonb)
  from (
    select * from ${T("inbound")} x
    where x.${ie("status")} in ('received', 'failed') and x.${ie("attempts")} < coalesce(max_attempts, 5)
    order by x.${ie("receivedAt")}
    limit least(greatest(coalesce(max, 100), 1), 1000)
  ) e;
$$;
${serviceOnly(`${fn("pending_inbound_events")}(integer, integer)`)}

-- Deletes handled inbound events older than older_than, at most batch.
create or replace function ${fn("purge_inbound_events")}(older_than interval default '30 days', batch integer default 1000)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from ${T("inbound")} e where e.${ie("id")} in (
    select x.${ie("id")} from ${T("inbound")} x
    where x.${ie("receivedAt")} < now() - coalesce(older_than, interval '30 days')
      and x.${ie("status")} in ('processed', 'ignored')
    limit greatest(coalesce(batch, 1000), 1)
  );
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${serviceOnly(`${fn("purge_inbound_events")}(interval, integer)`)}

-- Reopens snoozed conversations whose time came, for a periodic job.
create or replace function ${fn("wake_snoozed_conversations")}()
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_count integer;
begin
  update ${T("conversations")} set ${cv("status")} = 'open', ${cv("snoozedUntil")} = null
  where ${cv("status")} = 'snoozed' and ${cv("snoozedUntil")} <= now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${serviceOnly(`${fn("wake_snoozed_conversations")}()`)}

create or replace function ${fn("upsert_message_template")}(tenant ${id}, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${T("templates")}%rowtype;
begin
  if not (${service} or ${q.can("tenant", "manage")}) then
    ${forbidden("not allowed to manage templates")}
  end if;
  insert into ${T("templates")} as t (${tp("tenant")}, ${tp("inbox")}, ${tp("name")}, ${tp("channel")}, ${tp("language")}, ${tp("body")}, ${tp("variables")}, ${tp("externalId")})
  values (tenant, (input ->> 'inbox_id')::uuid, input ->> 'name', input ->> 'channel', coalesce(input ->> 'language', 'en'), input ->> 'body', coalesce(input -> 'variables', '[]'::jsonb), input ->> 'external_id')
  on conflict (${tp("tenant")}, ${tp("channel")}, ${tp("name")}, ${tp("language")}) do update set
    ${tp("inbox")} = excluded.${tp("inbox")},
    ${tp("body")} = excluded.${tp("body")},
    ${tp("variables")} = excluded.${tp("variables")},
    ${tp("externalId")} = excluded.${tp("externalId")}
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;
${authed(`${fn("upsert_message_template")}(${id}, jsonb)`)}

create or replace function ${fn("delete_message_template")}(template uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${id};
begin
  select ${tp("tenant")} into v_tenant from ${T("templates")} where ${tp("id")} = delete_message_template.template;
  if not found then
    return false;
  end if;
  if not (${service} or ${q.can("v_tenant", "manage")}) then
    ${forbidden("not allowed to manage templates")}
  end if;
  delete from ${T("templates")} t where t.${tp("id")} = delete_message_template.template;
  return true;
end;
$$;
${authed(`${fn("delete_message_template")}(uuid)`)}`;
}
