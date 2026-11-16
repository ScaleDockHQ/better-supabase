import type { InboxSql } from "./inbox-names.ts";

import { archivedListFilter } from "../archive-sql.ts";
import {
  filterAny,
  filterHasInvalid,
  listBody,
  listDeclare,
  searchPattern,
} from "../list-template.ts";
import { fail } from "../shared.ts";
import { missing } from "./inbox-names.ts";

const CHANNELS = ["in_app", "email", "whatsapp", "slack", "sms"] as const;
const BOT_MODES = ["bot", "human", "paused"] as const;

/**
 * The inboxes and the message templates of a tenant as keyset pages (ADR 1077),
 * each with a `get` that returns the row or a not-found error. They run as the
 * caller, so the staff read policy of each table decides what comes back.
 */
export function inboxCatalogPages(q: InboxSql): string {
  const { id, fn } = q;
  const ib = q.cols("inboxes");
  const tp = q.cols("templates");

  const authed = (signature: string): string =>
    `revoke execute on function ${signature} from public, anon;
grant execute on function ${signature} to authenticated, service_role;`;

  const inboxKey = { expr: `x.${ib("id")}`, dir: "asc", type: "uuid" } as const;

  const templateKey = {
    expr: `x.${tp("id")}`,
    dir: "asc",
    type: "uuid",
  } as const;

  const created = (table: "inboxes" | "templates", alias: string): string =>
    q.has(table, "createdAt")
      ? `${alias}.${q.cols(table)("createdAt")}`
      : "'-infinity'::timestamptz";

  const inboxName = {
    expr: `x.${ib("name")}`,
    dir: "asc",
    type: "text",
  } as const;

  const inboxCreated = {
    expr: created("inboxes", "x"),
    dir: "desc",
    type: "timestamptz",
  } as const;

  const hasArchived = q.has("inboxes", "archivedAt");

  const inboxSearch = [
    `x.${ib("name")} ilike v_search`,
    ...(q.has("inboxes", "address")
      ? [`x.${ib("address")} ilike v_search`]
      : []),
  ];

  const channel = q.text("inboxes", `x.${ib("channel")}`);
  const botMode = q.text("inboxes", `x.${ib("botMode")}`);

  const inboxPage = {
    name: "page_inboxes",
    from: q.t("inboxes"),
    alias: "x",
    where: [
      `x.${ib("tenant")} = page_inboxes.tenant`,
      filterAny("channel", channel),
      filterAny("botMode", botMode),
      hasArchived ? archivedListFilter("x", ib("archivedAt")) : "true",
      `(v_search is null or ${inboxSearch.join(" or ")})`,
    ],
    keys: [inboxName, inboxKey],
    sorts: { name: [inboxName, inboxKey], createdAt: [inboxCreated, inboxKey] },
    facets: { channel, botMode },
    rowJson: q.json("inboxes", "x"),
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) => fail("INBOX_INVALID", message, "22023"),
  } as const;

  const templateName = {
    expr: `x.${tp("name")}`,
    dir: "asc",
    type: "text",
  } as const;

  const templateCreated = {
    expr: created("templates", "x"),
    dir: "desc",
    type: "timestamptz",
  } as const;

  const templateChannel = q.text("templates", `x.${tp("channel")}`);

  const templatePage = {
    name: "page_message_templates",
    from: q.t("templates"),
    alias: "x",
    where: [
      `x.${tp("tenant")} = page_message_templates.tenant`,
      filterAny("channel", templateChannel),
      filterAny("language", `x.${tp("language")}`),
      filterAny("inboxId", `x.${tp("inbox")}`, "uuid"),
      `(v_search is null or x.${tp("name")} ilike v_search or x.${tp("body")} ilike v_search)`,
    ],
    keys: [templateName, templateKey],
    sorts: {
      name: [templateName, templateKey],
      createdAt: [templateCreated, templateKey],
    },
    facets: { channel: templateChannel, language: `x.${tp("language")}` },
    rowJson: q.json("templates", "x"),
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) => fail("INBOX_INVALID", message, "22023"),
  } as const;

  return `-- The inboxes of a tenant as a keyset page (ADR 1077), by name. filters is
-- { channel (${CHANNELS.join(", ")}), botMode (${BOT_MODES.join(", ")}), archived
-- (true lists only the archived ones; archived inboxes are hidden by default),
-- search (name and address), sort (name, createdAt), direction, facet (channel,
-- botMode), count, limit, after, offset, paged, total, totalCap }.
create or replace function ${fn("page_inboxes")}(tenant ${id}, filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_inboxes.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  ${listDeclare(inboxPage)}
begin
  if ${filterHasInvalid("channel", CHANNELS)} or ${filterHasInvalid("botMode", BOT_MODES)} then
    ${fail("INBOX_INVALID", "channel and botMode name a channel and a bot mode", "22023")}
  end if;
  ${listBody(inboxPage)}
end;
$$;
${authed(`${fn("page_inboxes")}(${id}, jsonb)`)}

-- One inbox, or a not-found error.
create or replace function ${fn("get_inbox")}(inbox uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_row jsonb;
begin
  select ${q.json("inboxes", "x")} into v_row from ${q.t("inboxes")} x where x.${ib("id")} = get_inbox.inbox;
  if v_row is null then
    ${missing("inbox", "INBOX_NOT_FOUND")}
  end if;
  return v_row;
end;
$$;
${authed(`${fn("get_inbox")}(uuid)`)}

-- The message templates of a tenant as a keyset page (ADR 1077), by name.
-- filters is { channel, language, inboxId (each a value or a list), search
-- (name and body), sort (name, createdAt), direction, facet (channel,
-- language), count, limit, after, offset, paged, total, totalCap }.
create or replace function ${fn("page_message_templates")}(tenant ${id}, filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_message_templates.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  ${listDeclare(templatePage)}
begin
  if ${filterHasInvalid("inboxId")} then
    ${fail("INBOX_INVALID", "inboxId is a uuid", "22023")}
  end if;
  ${listBody(templatePage)}
end;
$$;
${authed(`${fn("page_message_templates")}(${id}, jsonb)`)}

-- One message template, or a not-found error.
create or replace function ${fn("get_message_template")}(template uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_row jsonb;
begin
  select ${q.json("templates", "x")} into v_row from ${q.t("templates")} x where x.${tp("id")} = get_message_template.template;
  if v_row is null then
    ${missing("message template", "INBOX_TEMPLATE_NOT_FOUND")}
  end if;
  return v_row;
end;
$$;
${authed(`${fn("get_message_template")}(uuid)`)}`;
}
