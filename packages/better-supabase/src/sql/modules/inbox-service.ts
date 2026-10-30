import type { InboxSql } from "./inbox-names.ts";

import { serviceGrant, pageSize } from "../shared.ts";
import { forbidden, missing } from "./inbox-names.ts";

/**
 * The service calls: deliveries, stored webhook events, file imports, sweeps
 * and templates.
 */
export function inboxServiceFunctions(q: InboxSql): string {
  const { id, fn } = q;
  const cv = q.cols("conversations");
  const dt = q.cols("details");
  const cm = q.core.cols("messages");
  const at = q.ctx.of("attachments");
  const a = (column: string): string => at.col("attachments", column);
  const dl = q.cols("deliveries");
  const ie = q.cols("inbound");
  const tp = q.cols("templates");
  const { people } = q;
  const contacts = people.ctx;
  const T = (name: string): string => q.t(name);
  const service = q.service;
  const { has } = q;

  const delivery = (
    [
      ["tenant", `m.${dt("tenant")}`],
      ["message", `m.${dt("message")}`],
      ["channel", "record_delivery.channel"],
      ["externalId", "record_delivery.external_id"],
      [
        "status",
        q.cast(
          "deliveries",
          "status",
          "coalesce(record_delivery.status, 'sent')",
        ),
      ],
      ["error", "record_delivery.error"],
      ["attempts", "1"],
    ] as const
  ).filter(([column]) => has("deliveries", column));

  const template = (
    [
      ["tenant", "tenant"],
      ["inbox", "(input ->> 'inbox_id')::uuid"],
      ["name", "input ->> 'name'"],
      ["channel", "input ->> 'channel'"],
      ["language", "coalesce(input ->> 'language', 'en')"],
      ["body", "input ->> 'body'"],
      ["variables", "coalesce(input -> 'variables', '[]'::jsonb)"],
      ["externalId", "input ->> 'external_id'"],
    ] as const
  ).filter(([column]) => has("templates", column));

  const authed = (signature: string): string =>
    `revoke execute on function ${signature} from public, anon;
grant execute on function ${signature} to authenticated, service_role;`;

  // The app's tables keep their own foreign keys, so the module's cascades
  // from the core conversation may not reach them.
  const unlinked = (
    [
      [
        "deliveries",
        `${dl("message")} in (select d.${dt("message")} from ${T("details")} d where d.${dt("conversation")} = any (v_ids))`,
      ],
      ["events", `${q.cols("events")("conversation")} = any (v_ids)`],
      ["scheduled", `${q.cols("scheduled")("conversation")} = any (v_ids)`],
      ["details", `${dt("conversation")} = any (v_ids)`],
      ["conversations", `${cv("id")} = any (v_ids)`],
    ] as const
  )
    .filter(([table]) => !q.ctx.owns(table))
    .map(([table, where]) => `\n  delete from ${T(table)} where ${where};`)
    .join("");

  return `-- After posting an outbound message on its channel: records the platform's
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
  insert into ${T("deliveries")} as d (${delivery.map(([column]) => dl(column)).join(", ")})
  select ${delivery.map(([, value]) => value).join(", ")}
  from ${T("details")} m where m.${dt("message")} = record_delivery.message
  on conflict (${dl("message")}, ${dl("channel")}) do update set
    ${dl("externalId")} = coalesce(excluded.${dl("externalId")}, d.${dl("externalId")}),
    ${dl("status")} = excluded.${dl("status")}${
      has("deliveries", "error")
        ? `,
    ${dl("error")} = excluded.${dl("error")}`
        : ""
    }${
      has("deliveries", "attempts")
        ? `,
    ${dl("attempts")} = d.${dl("attempts")} + 1`
        : ""
    }
  returning * into v_row;
  if v_row.${dl("id")} is null then
    ${missing("message", "MESSAGE_NOT_FOUND")}
  end if;
  return ${q.json("deliveries", "v_row")};
end;
$$;
${serviceGrant(`${fn("record_delivery")}(uuid, text, text, text, text)`)}

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
  update ${T("deliveries")} d set ${dl("status")} = ${q.cast("deliveries", "status", "status")}${has("deliveries", "error") ? `, ${dl("error")} = coalesce(error, d.${dl("error")})` : ""}
  where d.${dl("channel")} = channel and d.${dl("externalId")} = external_id
    and (case status when 'failed' then d.${dl("status")} in ('queued', 'sent')
      else array_position(array['queued', 'sent', 'delivered', 'read'], status)
        > coalesce(array_position(array['queued', 'sent', 'delivered', 'read'], ${q.text("deliveries", `d.${dl("status")}`)}), 0) end);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${serviceGrant(`${fn("set_delivery_status")}(text, text, text, text)`)}

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
${serviceGrant(`${fn("store_inbound_event")}(text, text, text, jsonb, uuid, ${id})`)}

create or replace function ${fn("set_inbound_event_status")}(event uuid, status text, error text default null)
returns boolean
language plpgsql
set search_path = ''
as $$
#variable_conflict use_variable
begin
  update ${T("inbound")} e set
    ${ie("status")} = ${q.cast("inbound", "status", "status")},${
      has("inbound", "error")
        ? `
    ${ie("error")} = error,`
        : ""
    }
    ${ie("attempts")} = e.${ie("attempts")} + 1${
      has("inbound", "processedAt")
        ? `,
    ${ie("processedAt")} = case when status in ('processed', 'ignored') then now() else e.${ie("processedAt")} end`
        : ""
    }
  where e.${ie("id")} = event;
  return found;
end;
$$;
${serviceGrant(`${fn("set_inbound_event_status")}(uuid, text, text)`)}

-- Inbound events still waiting, oldest first, for a retry sweep.
create or replace function ${fn("pending_inbound_events")}(max integer default 100, max_attempts integer default 5)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(${q.json("inbound", "e")} order by e.${ie("receivedAt")}), '[]'::jsonb)
  from (
    select * from ${T("inbound")} x
    where x.${ie("status")} in ('received', 'failed') and x.${ie("attempts")} < coalesce(max_attempts, 5)
    order by x.${ie("receivedAt")}
    limit ${pageSize("max", 100, 1000)}
  ) e;
$$;
${serviceGrant(`${fn("pending_inbound_events")}(integer, integer)`)}

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
    where ${q.ctx.expired("inbound_events", { at: `x.${ie("receivedAt")}`, tenant: `x.${ie("tenant")}`, fallback: "coalesce(older_than, interval '30 days')" })}
      and x.${ie("status")} in ('processed', 'ignored')
    limit greatest(coalesce(batch, 1000), 1)
  );
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${serviceGrant(`${fn("purge_inbound_events")}(interval, integer)`)}

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
  insert into ${T("templates")} as t (${template.map(([column]) => tp(column)).join(", ")})
  values (${template.map(([, value]) => value).join(", ")})
  on conflict (${tp("tenant")}, ${tp("channel")}, ${tp("name")}, ${tp("language")}) do update set
    ${["inbox", "body", "variables", "externalId"]
      .filter((column) => has("templates", column))
      .map((column) => `${tp(column)} = excluded.${tp(column)}`)
      .join(",\n    ")}
  returning * into v_row;
  return ${q.json("templates", "v_row")};
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
${authed(`${fn("delete_message_template")}(uuid)`)}

-- Erases a contact for a data subject request: the person, their identities
-- and their conversations with their messages, files, deliveries and events.
-- Returns { conversations, messages, attachments }; attachments are the
-- { bucket, path } of the stored files the caller still has to remove.
create or replace function ${fn("purge_contact")}(contact uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${id};
  v_ids uuid[];
  v_messages integer;
  v_paths jsonb;
begin
  select p.${people.c("tenant")} into v_tenant from ${people.t} p where p.${people.c("id")} = purge_contact.contact;
  if not found then
    ${missing("contact", "CONTACT_NOT_FOUND")}
  end if;
  if not (${service} or ${q.can("v_tenant", "manage")}) then
    ${forbidden("not allowed to erase contacts")}
  end if;
  v_ids := array(select v.${cv("id")} from ${T("conversations")} v where v.${cv("contact")} = purge_contact.contact);
  select count(*)::integer into v_messages from ${q.core.t("messages")} m where m.${cm("conversation")} = any (v_ids);
  with gone as (
    delete from ${at.table("attachments")} x
    where (x.${a("subjectType")} = ${q.core.conversation} and x.${a("subjectId")} = any (array(select i::text from unnest(v_ids) i)))
      or (x.${a("subjectType")} = ${q.core.message} and x.${a("subjectId")} in (
        select m.${cm("id")}::text from ${q.core.t("messages")} m where m.${cm("conversation")} = any (v_ids)))
    returning x.${a("bucket")} as bucket, x.${a("path")} as path, x.${a("uploadedAt")} as uploaded_at
  )
  select coalesce(jsonb_agg(jsonb_build_object('bucket', g.bucket, 'path', g.path)) filter (where g.uploaded_at is not null), '[]'::jsonb)
  into v_paths from gone g;${unlinked}
  delete from ${q.core.t("conversations")} k where k.${q.core.cols("conversations")("id")} = any (v_ids);
  delete from ${contacts.table("identities")} i where i.${contacts.col("identities", "person")} = purge_contact.contact;
  update ${people.t} p set ${people.c("mergedInto")} = null where p.${people.c("mergedInto")} = purge_contact.contact;
  delete from ${people.t} p where p.${people.c("id")} = purge_contact.contact;
  return jsonb_build_object('conversations', cardinality(v_ids), 'messages', v_messages, 'attachments', v_paths);
end;
$$;
${authed(`${fn("purge_contact")}(uuid)`)}

-- Files a channel sent that still wait for their import, oldest first:
-- { id, conversation_id, message_id, tenant_id, bucket, object_path, name,
-- mime_type, source }. source is the channel's file ({ url, name,
-- content_type, size }) or, for files copied from an older inbox,
-- { bucket, path }. Upload the bytes to bucket and object_path, then call
-- confirm_attachment as the service, or inbox_file_failed.
create or replace function ${fn("pending_inbox_files")}(max integer default 50)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x.${a("id")},
    'conversation_id', d.${dt("conversation")},
    'message_id', d.${dt("message")},
    'tenant_id', x.${a("tenant")},
    'bucket', x.${a("bucket")},
    'object_path', x.${a("path")},
    'name', x.${a("name")},
    'mime_type', x.${a("mimeType")},
    'source', x.${a("detail")}::jsonb -> 'source'
  ) order by x.${a("createdAt")}, x.${a("id")}), '[]'::jsonb)
  from (
    select * from ${at.table("attachments")} y
    where y.${a("status")} = 'pending' and y.${a("uploadedAt")} is null
      and y.${a("subjectType")} = ${q.core.message}
      and y.${a("detail")} is not null and y.${a("detail")} like '{"source"%'
    order by y.${a("createdAt")}, y.${a("id")}
    limit ${pageSize("max", 50, 500)}
  ) x
  join ${T("details")} d on d.${dt("message")}::text = x.${a("subjectId")};
$$;
${serviceGrant(`${fn("pending_inbox_files")}(integer)`)}

-- Marks a channel file that could not be imported, with the reason.
create or replace function ${fn("inbox_file_failed")}(attachment uuid, detail text default null)
returns boolean
language plpgsql
set search_path = ''
as $$
begin
  update ${at.table("attachments")} x set
    ${a("status")} = 'failed',
    ${a("detail")} = coalesce(inbox_file_failed.detail, 'import failed'),
    ${a("scannedAt")} = now()
  where x.${a("id")} = inbox_file_failed.attachment and x.${a("status")} = 'pending' and x.${a("uploadedAt")} is null;
  return found;
end;
$$;
${serviceGrant(`${fn("inbox_file_failed")}(uuid, text)`)}`;
}
