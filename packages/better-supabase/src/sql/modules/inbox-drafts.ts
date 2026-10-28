import type { InboxSql } from "./inbox-names.ts";

import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { fail, lockTable, serviceGrant, updatedAt } from "../shared.ts";
import { forbidden, missing } from "./inbox-names.ts";

const STRIPPED =
  "- 'files' - 'external_id' - 'author_type' - 'delivered_by_caller'";

/**
 * Reply drafts: a staff member's own draft per conversation, and suggestions an
 * AI writes through the service role, which any staff member who can reply
 * sees, edits into a send or discards.
 */
export function inboxDraftsDdl(q: InboxSql): string {
  const dr = q.cols("drafts");
  const cv = q.cols("conversations");
  const table = q.t("drafts");

  const metadata = q.has("drafts", "metadata")
    ? `\n  ${dr("metadata")} jsonb not null default '{}'::jsonb,`
    : "";

  const createdAt = q.has("drafts", "createdAt")
    ? `,\n  ${dr("createdAt")} timestamptz not null default now()`
    : "";

  return `-- Reply drafts. A user draft belongs to its author, one open draft per
-- conversation; an ai draft has no author and every staff member who can
-- reply in the tenant sees it. status moves from draft to sent or discarded.
create table if not exists ${table} (
  ${dr("id")} uuid primary key default gen_random_uuid(),
  ${dr("tenant")} ${q.id} not null,
  ${dr("conversation")} uuid not null references ${q.t("conversations")} (${cv("id")}) on delete cascade,
  ${dr("author")} uuid references auth.users (id) on delete cascade,
  ${dr("source")} text not null default 'user' check (${dr("source")} in ('user', 'ai')),
  ${dr("input")} jsonb not null check (jsonb_typeof(${dr("input")}) = 'object'),
  ${dr("status")} text not null default 'draft' check (${dr("status")} in ('draft', 'sent', 'discarded')),${metadata}
  ${dr("updatedAt")} timestamptz not null default now()${createdAt},
  constraint ${q.ctx.naming.rename("inbox_drafts_author_check")} check (${dr("source")} = 'ai' or ${dr("author")} is not null)
);
create unique index if not exists ${q.ctx.naming.rename("inbox_drafts_open_key")} on ${table} (${dr("conversation")}, ${dr("author")}) where ${dr("source")} = 'user' and ${dr("status")} = 'draft';
create index if not exists ${q.ctx.naming.rename("inbox_drafts_conversation_idx")} on ${table} (${dr("conversation")}) where ${dr("status")} = 'draft';
create index if not exists ${q.ctx.naming.rename("inbox_drafts_author_idx")} on ${table} (${dr("author")});
${updatedAt(table, dr("updatedAt"))}
${lockTable(table, { read: true })}
${renderPolicy(
  makePolicy({
    table,
    name: q.ctx.naming.rename("inbox_drafts_read"),
    command: "select",
    roles: ["authenticated"],
    using: `(${dr("author")} = (select auth.uid()) or ${dr("source")} = 'ai') and ${q.staff(dr("tenant"), "reply")}`,
  }),
  { drop: true, target: table },
)}`;
}

export function inboxDraftFunctions(q: InboxSql): string {
  const { fn } = q;
  const cv = q.cols("conversations");
  const dr = q.cols("drafts");
  const T = (name: string): string => q.t(name);
  const metadata = q.has("drafts", "metadata");

  const authed = (signature: string): string =>
    `revoke execute on function ${signature} from public, anon;
grant execute on function ${signature} to authenticated, service_role;`;

  const loadConversation = (
    param: string,
  ): string => `select * into v_conv from ${T("conversations")} where ${cv("id")} = ${param};
  if not found then
    ${missing("conversation", "CONVERSATION_NOT_FOUND")}
  end if;`;

  const checkBody = `if length(coalesce(v_input ->> 'body', '')) > ${String(q.maxBody)} then
    ${fail("INBOX_MESSAGE_TOO_LONG", `a message is at most ${String(q.maxBody)} characters`, "22023")}
  end if;`;

  // An open draft the caller may act on: their own, or an ai draft in a
  // tenant where they can reply; the service role acts on every draft.
  const loadDraft = (
    param: string,
  ): string => `select * into v_row from ${T("drafts")} where ${dr("id")} = ${param} for update;
  if not found or v_row.${dr("status")} <> 'draft' or not (${q.service} or ((v_row.${dr("author")} = (select auth.uid()) or v_row.${dr("source")} = 'ai') and ${q.can(`v_row.${dr("tenant")}`, "reply")})) then
    ${missing("draft", "INBOX_DRAFT_NOT_FOUND")}
  end if;`;

  const insertColumns = (source: string, author: string): string => {
    const entries = [
      [dr("tenant"), `v_conv.${cv("tenant")}`],
      [dr("conversation"), `v_conv.${cv("id")}`],
      [dr("author"), author],
      [dr("source"), source],
      [dr("input"), "v_input"],
      ...(metadata
        ? [[dr("metadata"), "coalesce(v_metadata, '{}'::jsonb)"]]
        : []),
    ];

    return `insert into ${T("drafts")} (${entries.map(([column]) => column).join(", ")})
  values (${entries.map(([, value]) => value).join(", ")})
  returning * into v_row;`;
  };

  const metadataDeclare = (param: string): string =>
    metadata ? `\n  v_metadata jsonb := ${param};` : "";

  const metadataCheck = metadata
    ? `
  if v_metadata is not null and jsonb_typeof(v_metadata) <> 'object' then
    ${fail("INBOX_DRAFT_METADATA", "metadata must be an object", "22023")}
  end if;`
    : "";

  const metadataSet = metadata
    ? `, ${dr("metadata")} = coalesce(v_metadata, x.${dr("metadata")})`
    : "";

  return `-- Saves the caller's draft reply on a conversation: the one open draft is
-- replaced, else a new one starts. The input is the one send_inbox_message
-- takes, without the service's fields; an empty body is fine until it sends.
create or replace function ${fn("save_inbox_draft")}(conversation uuid, input jsonb, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conv ${T("conversations")}%rowtype;
  v_row ${T("drafts")}%rowtype;
  v_input jsonb := coalesce(input, '{}'::jsonb) ${STRIPPED};${metadataDeclare("save_inbox_draft.metadata")}
begin
  ${loadConversation("save_inbox_draft.conversation")}
  if (select auth.uid()) is null or not ${q.command(`v_conv.${cv("tenant")}`, "reply", "reply")} then
    ${forbidden("not allowed to reply in this conversation")}
  end if;
  ${checkBody}${metadataCheck}
  update ${T("drafts")} x set ${dr("input")} = v_input${metadataSet}
  where x.${dr("conversation")} = v_conv.${cv("id")} and x.${dr("author")} = (select auth.uid())
    and x.${dr("source")} = 'user' and x.${dr("status")} = 'draft'
  returning * into v_row;
  if not found then
    ${insertColumns("'user'", "(select auth.uid())")}
  end if;
  return ${q.json("drafts", "v_row")};
end;
$$;
${authed(`${fn("save_inbox_draft")}(uuid, jsonb, jsonb)`)}

-- Adds an ai draft to a conversation for its staff to review. The service
-- role only: the model runs on the server.
create or replace function ${fn("suggest_inbox_draft")}(conversation uuid, input jsonb, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conv ${T("conversations")}%rowtype;
  v_row ${T("drafts")}%rowtype;
  v_input jsonb := coalesce(input, '{}'::jsonb) ${STRIPPED};${metadataDeclare("suggest_inbox_draft.metadata")}
begin
  ${loadConversation("suggest_inbox_draft.conversation")}
  ${checkBody}${metadataCheck}
  ${insertColumns("'ai'", "null")}
  return ${q.json("drafts", "v_row")};
end;
$$;
${serviceGrant(`${fn("suggest_inbox_draft")}(uuid, jsonb, jsonb)`)}

-- The open drafts the caller sees, newest first: their own and the ai
-- drafts of their tenants, on one conversation when conversation is set.
create or replace function ${fn("list_inbox_drafts")}(conversation uuid default null)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(${q.json("drafts", "d")} order by d.${dr("updatedAt")} desc, d.${dr("id")}), '[]'::jsonb)
  from ${T("drafts")} d
  where d.${dr("status")} = 'draft'
    and (list_inbox_drafts.conversation is null or d.${dr("conversation")} = list_inbox_drafts.conversation);
$$;
${authed(`${fn("list_inbox_drafts")}(uuid)`)}

-- Sends a draft as the caller through send_inbox_message, with input's
-- fields over the draft's, and marks it sent. Returns the message.
create or replace function ${fn("send_inbox_draft")}(draft uuid, input jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${T("drafts")}%rowtype;
  v_message jsonb;
begin
  ${loadDraft("send_inbox_draft.draft")}
  v_message := ${fn("send_inbox_message")}(v_row.${dr("conversation")}, v_row.${dr("input")} || (coalesce(send_inbox_draft.input, '{}'::jsonb) ${STRIPPED}));
  update ${T("drafts")} set ${dr("status")} = 'sent' where ${dr("id")} = v_row.${dr("id")};
  return v_message;
end;
$$;
${authed(`${fn("send_inbox_draft")}(uuid, jsonb)`)}

-- Discards a draft the caller can act on.
create or replace function ${fn("discard_inbox_draft")}(draft uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${T("drafts")}%rowtype;
begin
  ${loadDraft("discard_inbox_draft.draft")}
  update ${T("drafts")} set ${dr("status")} = 'discarded' where ${dr("id")} = v_row.${dr("id")};
  return true;
end;
$$;
${authed(`${fn("discard_inbox_draft")}(uuid)`)}`;
}
