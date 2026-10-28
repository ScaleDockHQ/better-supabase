import type { BlockSqlContext } from "../context.ts";
import type { QuoteNames } from "./quotes-functions.ts";
import type { QuoteKit } from "./quotes-kit.ts";

import { fail, sha256Hex, userGrant } from "../shared.ts";
import { quoteGuest } from "./quotes-kit.ts";

/** How one decision function takes the customer's answer. */
interface Answer {
  /** The function's name, which qualifies its arguments. */
  readonly name: string;
  /** SQL for who answered, by name. */
  readonly by: string;
  /** Whether the caller is the customer, whose address and browser count. */
  readonly customer: boolean;
  /** Whether an answer after the valid-until date expires the quote. */
  readonly expires: boolean;
}

/**
 * The functions that take a customer's answer: recorded by staff, through the
 * link, or by a signed-in guest the quote is shared with (ADR 0070), and the
 * reads of a quote's published versions.
 */
export function quoteDecisions(
  ctx: BlockSqlContext,
  n: QuoteNames,
  k: QuoteKit,
): string {
  const { fn, t } = n;
  const { q, l, has, lineHas, st, sv, row, record, editable } = k;
  const v = (column: string): string => n.c("versions", column);
  const guest = quoteGuest(ctx, n, "x.");

  // Without a note column the note still reaches the event.
  const noted = (note: string): string =>
    has("decisionNote")
      ? `v_row.${q("decisionNote")}`
      : `nullif(trim(${note}), '')`;

  const selects = lineHas("optional") && lineHas("selected");

  // Takes or leaves the optional lines on acceptance: `selected` lists the
  // positions taken, and an optional line not in it is left out of the totals.
  const selection = (name: string): string =>
    selects
      ? `
    if ${name}.selected is not null then
      if jsonb_typeof(${name}.selected) <> 'array' or exists (
        select 1 from jsonb_array_elements(${name}.selected) e
        where jsonb_typeof(e.value) <> 'number' or not exists (
          select 1 from ${t("lines")} ql
          where ql.${l("parent")} = v_row.${q("id")} and ql.${l("optional")} and ql.${l("position")} = (e.value #>> '{}')::numeric
        )
      ) then
        ${fail("QUOTE_SELECTION_INVALID", "pick optional lines of this quote by position", "22023")}
      end if;
      update ${t("lines")} ql set ${l("selected")} = ql.${l("position")} in (select (e.value #>> '{}')::integer from jsonb_array_elements(${name}.selected) e)
      where ql.${l("parent")} = v_row.${q("id")} and ql.${l("optional")};
    end if;`
      : `
    if ${name}.selected is not null and ${name}.selected <> '[]'::jsonb then
      ${fail("QUOTE_SELECTION_INVALID", "this quote has no optional lines", "22023")}
    end if;`;

  const client = (column: string, value: string): string =>
    has(column) ? `${q(column)} = ${value}, ` : "";

  const headers = `
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;`;

  const ip =
    "left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)";

  const answer = (a: Answer): string => `
  if ${a.name}.decision not in ('accepted', 'rejected', 'changes_requested') then
    ${fail("QUOTE_DECISION_INVALID", "answer accepted, rejected or changes_requested", "22023")}
  end if;
  if ${st(`v_row.${q("status")}`, ["sent", "viewed"], true)} then
    ${fail("QUOTE_NOT_OPEN", "this quote no longer takes an answer", "55000")}
  end if;${
    a.expires
      ? `
  if v_row.${q("validUntil")} < current_date then
    update ${t("quotes")} x set ${q("status")} = ${sv("expired")}, ${q("updatedAt")} = now() where x.${q("id")} = v_row.${q("id")}
    returning * into v_row;
    ${record("quote.expired", "v_row")}
    return jsonb_build_object('status', 'expired');
  end if;`
      : ""
  }${
    a.customer
      ? `
  if nullif(trim(${a.by}), '') is null then
    ${fail("QUOTE_NAME_REQUIRED", "say who answers", "23502")}
  end if;`
      : ""
  }
  if ${a.name}.decision = 'accepted' then${selection(a.name)}
    ${ctx.hook("before_quote_accept", [["uuid", `v_row.${q("id")}`]])}
  end if;
  update ${t("quotes")} x set ${q("status")} = ${ctx.cast("quotes", "status", `${a.name}.decision`)}, ${q("decidedAt")} = now(), ${q("decidedBy")} = nullif(trim(${a.by}), ''),
    ${has("decisionNote") ? `${q("decisionNote")} = nullif(trim(${a.name}.note), ''), ` : ""}${client("decidedUser", "auth.uid()")}${client("decidedIp", a.customer ? ip : "null")}${client("decidedUserAgent", a.customer ? "left(v_headers ->> 'user-agent', 512)" : "null")}${q("updatedAt")} = now()
  where x.${q("id")} = v_row.${q("id")}
  returning * into v_row;
  case ${a.name}.decision
    when 'accepted' then
      ${record("quote.accepted", "v_row", `, 'total', v_row.${q("total")}::text, 'currency', v_row.${q("currency")}, 'byName', v_row.${q("decidedBy")}, 'revision', v_row.${q("revision")}, 'depositDue', ${has("depositDue") ? `v_row.${q("depositDue")}::text` : "'0'"}`)}
    when 'rejected' then
      ${record("quote.rejected", "v_row", `, 'note', ${noted(`${a.name}.note`)}`)}
    else
      ${record("quote.changes_requested", "v_row", `, 'note', ${noted(`${a.name}.note`)}`)}
  end case;${k.notifyOwner("quote.decided")}
  if ${a.name}.decision = 'accepted' then
    ${ctx.hook("after_quote_accept", [["uuid", `v_row.${q("id")}`]])}
  end if;`;

  const answered = `jsonb_build_object('status', ${ctx.label("quotes", "status", `v_row.${q("status")}`)}, 'identifier', v_row.${q("identifier")}, 'revision', v_row.${q("revision")})`;

  const readable = (alias: string): string =>
    `(${n.service} or ${ctx.scope.can(`${alias}.${q("tenant")}`, n.read)})`;

  return `
-- Records the customer's answer taken another way (by phone, by email):
-- decision is accepted, rejected or changes_requested; by is their name.
-- selected lists the positions of the optional lines they took.
drop function if exists ${fn("decide_quote")}(uuid, text, text, text);
create or replace function ${fn("decide_quote")}(quote uuid, decision text, note text, by text, selected jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("quotes")};
begin
  select * into v_row from ${t("quotes")} x where x.${q("id")} = decide_quote.quote and ${editable("x")} for update;
  if v_row.${q("id")} is null then
    ${fail("QUOTE_NOT_FOUND", "no such quote you can edit", "P0002")}
  end if;${answer({ name: "decide_quote", by: "coalesce(nullif(trim(decide_quote.by), ''), auth.uid()::text)", customer: false, expires: false })}
  return ${row("v_row")};
end;
$$;
${userGrant(`${fn("decide_quote")}(uuid, text, text, text, jsonb)`)}

-- What the customer sees through the link: the quote without internal
-- notes. Opening a sent quote marks it viewed. Callable without signing in.
create or replace function ${fn("public_quote")}(token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("quotes")};
begin
  select * into v_row from ${t("quotes")} x where x.${q("tokenHash")} = ${sha256Hex("public_quote.token")};
  if v_row.${q("id")} is null then
    ${fail("QUOTE_LINK_INVALID", "this link is not valid", "P0002")}
  end if;
${k.markViewed()}
  return ${k.publicJson("v_row")};
end;
$$;
revoke all on function ${fn("public_quote")}(text) from public, anon, authenticated;
grant execute on function ${fn("public_quote")}(text) to anon, authenticated, service_role;

-- The customer's answer through the link: accepted, rejected or
-- changes_requested, with their name, a note and the optional lines they
-- took. Their address and browser are kept with the answer. A quote past its
-- valid date expires instead.
drop function if exists ${fn("respond_to_quote")}(text, text, text, text);
create or replace function ${fn("respond_to_quote")}(token text, decision text, name text, note text, selected jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("quotes")};${headers}
begin
  select * into v_row from ${t("quotes")} x where x.${q("tokenHash")} = ${sha256Hex("respond_to_quote.token")} for update;
  if v_row.${q("id")} is null then
    ${fail("QUOTE_LINK_INVALID", "this link is not valid", "P0002")}
  end if;${answer({ name: "respond_to_quote", by: "respond_to_quote.name", customer: true, expires: true })}
  return ${answered};
end;
$$;
revoke all on function ${fn("respond_to_quote")}(text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function ${fn("respond_to_quote")}(text, text, text, text, jsonb) to anon, authenticated, service_role;

-- A quote shared with the signed-in guest, as the customer sees it: through
-- a grant on the quote or as a guest of its company or contact. Opening a
-- sent quote marks it viewed. No link token is needed.
create or replace function ${fn("portal_quote")}(quote uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("quotes")};
begin
  select * into v_row from ${t("quotes")} x where x.${q("id")} = portal_quote.quote and ${guest};
  if v_row.${q("id")} is null then
    ${fail("QUOTE_NOT_FOUND", "no such quote shared with you", "P0002")}
  end if;
${k.markViewed()}
  return ${k.publicJson("v_row")};
end;
$$;
${userGrant(`${fn("portal_quote")}(uuid)`)}

-- The signed-in guest's answer to a quote shared with them, like
-- respond_to_quote without a token. name defaults to their email; the
-- answer keeps who they are, their address and their browser.
create or replace function ${fn("respond_to_portal_quote")}(quote uuid, decision text, name text, note text, selected jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("quotes")};${headers}
begin
  select * into v_row from ${t("quotes")} x where x.${q("id")} = respond_to_portal_quote.quote and ${guest} for update;
  if v_row.${q("id")} is null then
    ${fail("QUOTE_NOT_FOUND", "no such quote shared with you", "P0002")}
  end if;${answer({ name: "respond_to_portal_quote", by: "coalesce(nullif(trim(respond_to_portal_quote.name), ''), auth.jwt() ->> 'email')", customer: true, expires: true })}
  return ${answered};
end;
$$;
${userGrant(`${fn("respond_to_portal_quote")}(uuid, text, text, text, jsonb)`)}

-- The versions of a quote that were sent, oldest first, without their
-- snapshots.
create or replace function ${fn("quote_versions")}(quote uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("quotes")};
begin
  select * into v_row from ${t("quotes")} x where x.${q("id")} = quote_versions.quote and ${readable("x")};
  if v_row.${q("id")} is null then
    ${fail("QUOTE_NOT_FOUND", "no such quote you can read", "P0002")}
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('revision', x.${v("revision")}, 'total', x.${v("total")}::text, 'currency', x.${v("currency")},
      'publishedAt', x.${v("publishedAt")}, 'publishedBy', ${ctx.has("versions", "publishedBy") ? `x.${v("publishedBy")}` : "null"}) order by x.${v("revision")})
    from ${t("versions")} x where x.${v("quote")} = v_row.${q("id")}), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("quote_versions")}(uuid)`)}

-- The quote as it was sent at revision: the snapshot published then.
create or replace function ${fn("quote_version")}(quote uuid, revision integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("quotes")};
  v_version ${t("versions")};
begin
  select * into v_row from ${t("quotes")} x where x.${q("id")} = quote_version.quote and ${readable("x")};
  if v_row.${q("id")} is null then
    ${fail("QUOTE_NOT_FOUND", "no such quote you can read", "P0002")}
  end if;
  select * into v_version from ${t("versions")} x where x.${v("quote")} = v_row.${q("id")} and x.${v("revision")} = quote_version.revision;
  if v_version.${v("id")} is null then
    ${fail("QUOTE_VERSION_NOT_FOUND", "this quote has no such version", "P0002")}
  end if;
  return v_version.${v("snapshot")} || jsonb_build_object('revision', v_version.${v("revision")}, 'publishedAt', v_version.${v("publishedAt")});
end;
$$;
${userGrant(`${fn("quote_version")}(uuid, integer)`)}
`;
}
