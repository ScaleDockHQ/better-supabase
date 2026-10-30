import type { BlockSqlContext } from "../context.ts";
import type { QuoteNames } from "./quotes-functions.ts";
import type { QuoteKit } from "./quotes-kit.ts";

import { sqlString } from "../../core/template.ts";
import {
  fail,
  sha256Hex,
  transitionActorSql,
  transitionReasonSql,
  userGrant,
} from "../shared.ts";
import { quoteGuest } from "./quotes-kit.ts";

/** The quote columns a customer sees of a published version. */
const PUBLISHED = [
  "revision",
  "title",
  "currency",
  "validUntil",
  "terms",
  "pricesIncludeTax",
  "discountBps",
  "discountAmount",
  "depositBps",
  "depositAmount",
  "depositRequired",
  "depositDue",
  "listTotal",
  "subtotal",
  "discountTotal",
  "taxTotal",
  "total",
];

/** How one decision function takes the customer's answer. */
interface Answer {
  /** The function's name, which qualifies its arguments. */
  readonly name: string;
  /** SQL for who answered, by name. */
  readonly by: string;
  /** Whether the caller is the customer, whose address and browser count. */
  readonly customer: boolean;
  /** SQL that is true when an answer after the valid-until date expires it. */
  readonly expires: string;
  /**
   * The answering actor as a jsonb SQL expression (`id`, `name`, `email`, `ip`,
   * `userAgent`), passed by the app; `undefined` for the customer's own call,
   * whose request headers count.
   */
  readonly actor?: string;
  /** Whether a required deposit stops the answer (`QUOTE_DEPOSIT_REQUIRED`). */
  readonly deposit: boolean;
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

  // A version line id of the quote's latest version, as its position.
  const vl = (column: string): string => n.c("versionLines", column);

  const position = (element: string): string =>
    k.versionLines
      ? `case when jsonb_typeof(${element}) = 'number' then (${element} #>> '{}')::numeric else (
          select vx.${vl("position")}::numeric from ${t("versionLines")} vx
          where vx.${vl("version")} = ${k.latestVersion("v_row")} and vx.${vl("id")}::text = ${element} #>> '{}'
        ) end`
      : `(${element} #>> '{}')::numeric`;

  // Takes or leaves the optional lines on acceptance: `selected` lists the
  // positions taken${k.versionLines ? ", or the ids of the latest version's lines" : ""}, and an optional line not in it is left out
  // of the totals.
  const selection = (name: string): string =>
    selects
      ? `
    if ${name}.selected is not null then
      if jsonb_typeof(${name}.selected) <> 'array' or exists (
        select 1 from jsonb_array_elements(${name}.selected) e
        where jsonb_typeof(e.value) not in ('number'${k.versionLines ? ", 'string'" : ""}) or not exists (
          select 1 from ${t("lines")} ql
          where ql.${l("parent")} = v_row.${q("id")} and ql.${l("optional")} and ql.${l("position")} = ${position("e.value")}
        )
      ) then
        ${fail("QUOTE_SELECTION_INVALID", `pick optional lines of this quote by position${k.versionLines ? " or version line id" : ""}`, "22023")}
      end if;
      update ${t("lines")} ql set ${l("selected")} = ql.${l("position")} in (select (${position("e.value")})::integer from jsonb_array_elements(${name}.selected) e)
      where ql.${l("parent")} = v_row.${q("id")} and ql.${l("optional")};
    end if;`
      : `
    if ${name}.selected is not null and ${name}.selected <> '[]'::jsonb then
      ${fail("QUOTE_SELECTION_INVALID", "this quote has no optional lines", "22023")}
    end if;`;

  // v_row with the given columns (logical names, or extra column names) taken
  // from snapshot v_snap; only those, as the snapshot holds status labels.
  const snapshotRecord = (columns: readonly string[]): string =>
    `jsonb_populate_record(v_row, coalesce((select jsonb_object_agg(e.key, e.value) from jsonb_each(v_snap) e where e.key in (${columns
      .map((column) =>
        sqlString(
          Object.hasOwn(ctx.names.tables["quotes"]?.columns ?? {}, column)
            ? ctx.colName("quotes", column)
            : column,
        ),
      )
      .join(", ")})), '{}'::jsonb))`;

  // With a working copy, an acceptance restores the version the customer saw.
  const restored = [
    "title",
    "currency",
    "validUntil",
    "terms",
    "pricesIncludeTax",
    "discountBps",
    "discountAmount",
    "depositBps",
    "depositAmount",
    "depositRequired",
  ].filter(has);

  const restore = k.workingCopy
    ? `
    if v_row.${q("unpublishedChanges")} then
      select v.${n.c("versions", "snapshot")} into v_snap from ${t("versions")} v where v.${n.c("versions", "id")} = ${k.latestVersion("v_row")};
      if v_snap is not null then
        v_pub := ${snapshotRecord([...restored, ...n.extras.map((extra) => extra.name)])};
        update ${t("quotes")} x set ${[...restored.map(q), ...n.extras.map((extra) => extra.ident)].map((column) => `${column} = v_pub.${column}`).join(", ")}
        where x.${q("id")} = v_row.${q("id")};
        perform ${fn("quote_lines_restore")}(v_row.${q("id")}, coalesce(v_snap -> 'lines', '[]'::jsonb));
        select * into v_row from ${t("quotes")} x where x.${q("id")} = v_row.${q("id")};
      end if;
    end if;`
    : "";

  const client = (column: string, value: string): string =>
    has(column) ? `${q(column)} = ${value}, ` : "";

  const headers = `
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;`;

  const restoreVars = k.workingCopy
    ? `
  v_snap jsonb;
  v_pub ${t("quotes")};`
    : "";

  const ip =
    "left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)";

  // The actor the state machine's history keeps for the customer's own call.
  const customerActor = (a: Answer): string =>
    `jsonb_strip_nulls(jsonb_build_object('name', nullif(trim(${a.by}), ''), 'email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))`;

  const actorIp = (a: Answer): string =>
    a.actor === undefined ? ip : `left(${a.actor} ->> 'ip', 64)`;

  const actorAgent = (a: Answer): string =>
    a.actor === undefined
      ? "left(v_headers ->> 'user-agent', 512)"
      : `left(${a.actor} ->> 'userAgent', 512)`;

  const answer = (a: Answer): string => `
  if ${a.name}.decision not in ('accepted', 'rejected', 'changes_requested') then
    ${fail("QUOTE_DECISION_INVALID", "answer accepted, rejected or changes_requested", "22023")}
  end if;
  if ${st(`v_row.${q("status")}`, ["sent", "viewed"], true)} then
    ${fail("QUOTE_NOT_OPEN", "this quote no longer takes an answer", "55000")}
  end if;${
    a.actor === undefined
      ? a.customer
        ? `
  begin
    v_ip := ${ip}::inet;
  exception when invalid_text_representation then
    v_ip := null;
  end;
  perform set_config('better_supabase.transition_actor', ${customerActor(a)}::text, true);`
        : ""
      : `
  ${transitionActorSql(a.actor, "QUOTE_ACTOR_INVALID")}`
  }${
    a.expires === "false"
      ? ""
      : `
  if (${a.expires}) and v_row.${q("validUntil")} < current_date then
    update ${t("quotes")} x set ${q("status")} = ${sv("expired")}, ${q("updatedAt")} = now() where x.${q("id")} = v_row.${q("id")}
    returning * into v_row;
    ${record("quote.expired", "v_row")}
    return ${a.customer ? "jsonb_build_object('status', 'expired')" : row("v_row")};
  end if;`
  }${
    a.customer
      ? `
  if nullif(trim(${a.by}), '') is null then
    ${fail("QUOTE_NAME_REQUIRED", "say who answers", "23502")}
  end if;`
      : ""
  }
  if ${a.name}.decision = 'accepted' then${restore}${
    a.deposit && has("depositRequired") && has("depositDue")
      ? `
    if v_row.${q("depositRequired")} and v_row.${q("depositDue")} > 0 then
      ${fail("QUOTE_DEPOSIT_REQUIRED", "pay the deposit before accepting; the app records the acceptance once it is paid", "55000")}
    end if;`
      : ""
  }${selection(a.name)}
    ${ctx.hook("before_quote_accept", [["uuid", `v_row.${q("id")}`]])}
  end if;
  ${a.customer ? "" : `${transitionReasonSql(`${a.name}.note`)}\n  `}update ${t("quotes")} x set ${q("status")} = ${ctx.cast("quotes", "status", `${a.name}.decision`)}, ${q("decidedAt")} = now(), ${q("decidedBy")} = nullif(trim(${a.by}), ''),
    ${has("decisionNote") ? `${q("decisionNote")} = nullif(trim(${a.name}.note), ''), ` : ""}${client("decidedUser", a.actor === undefined ? "auth.uid()" : `coalesce(nullif(${a.actor} ->> 'id', '')::uuid, auth.uid())`)}${client("decidedIp", a.customer || a.actor !== undefined ? actorIp(a) : "null")}${client("decidedUserAgent", a.customer || a.actor !== undefined ? actorAgent(a) : "null")}${k.workingCopy ? `${q("unpublishedChanges")} = case when ${a.name}.decision = 'accepted' then false else x.${q("unpublishedChanges")} end, ` : ""}${q("updatedAt")} = now()
  where x.${q("id")} = v_row.${q("id")}
  returning * into v_row;${a.customer ? "" : `\n  ${transitionReasonSql()}`}
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

  // The viewer the state machine's history keeps when opening marks a quote
  // viewed: the app's actor, or the caller's email, address and browser.
  const viewer = (actor?: string): string => {
    const own = `begin
    v_ip := ${ip}::inet;
  exception when invalid_text_representation then
    v_ip := null;
  end;
  perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);`;

    return actor === undefined
      ? `
  ${own}`
      : `
  if ${actor} is not null and not ${n.service} then
    ${fail("QUOTE_ACTOR_FORBIDDEN", "only the service role names who opened a quote", "42501")}
  end if;
  ${transitionActorSql(actor, "QUOTE_ACTOR_INVALID")}
  if ${actor} is null then
    ${own.replaceAll("\n", "\n  ")}
  end if;`;
  };

  const answered = `jsonb_build_object('status', ${ctx.label("quotes", "status", `v_row.${q("status")}`)}, 'identifier', v_row.${q("identifier")}, 'revision', v_row.${q("revision")})`;

  // What the customer sees: with a working copy, the last published version
  // with the quote's current status.
  const customerView = k.workingCopy
    ? `select v.${n.c("versions", "snapshot")} into v_snap from ${t("versions")} v where v.${n.c("versions", "id")} = ${k.latestVersion("v_row")};
  if v_snap is null then
    return ${k.publicJson("v_row")};
  end if;
  v_pub := ${snapshotRecord(PUBLISHED.filter(has))};
  return ${k.publicJson("v_pub", "v_snap")} || jsonb_build_object('status', ${ctx.label("quotes", "status", `v_row.${q("status")}`)});`
    : `return ${k.publicJson("v_row")};`;

  const keys = Object.values(n.answers);

  const decideKey = keys.every((key) => key === n.decide)
    ? editable("x", n.decide)
    : `(case decide_quote.decision when 'accepted' then ${editable("x", n.answers.accepted)} when 'rejected' then ${editable("x", n.answers.rejected)} else ${editable("x", n.answers.changes_requested)} end)`;

  const readable = (alias: string): string =>
    `(${n.service} or ${ctx.scope.can(`${alias}.${q("tenant")}`, n.read)})`;

  return `
-- Records the customer's answer taken another way (by phone, by email):
-- decision is accepted, rejected or changes_requested; by is their name,
-- and without it or an actor the answer names no one. The note is also the
-- reason in the state machine's history.
-- selected lists the positions of the optional lines they took. actor is
-- the customer when the app takes the answer in its own portal: id, name,
-- email, ip and userAgent, kept with the answer and in the state machine's
-- history; a quote past its valid date then expires instead, and the expired
-- quote is returned.
drop function if exists ${fn("decide_quote")}(uuid, text, text, text);
drop function if exists ${fn("decide_quote")}(uuid, text, text, text, jsonb);
create or replace function ${fn("decide_quote")}(quote uuid, decision text, note text, by text, selected jsonb default null, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("quotes")};
  v_claims text;${restoreVars}
begin
  select * into v_row from ${t("quotes")} x where x.${q("id")} = decide_quote.quote and ${decideKey} for update;
  if v_row.${q("id")} is null then
    ${fail("QUOTE_NOT_FOUND", "no such quote you can edit", "P0002")}
  end if;${answer({ name: "decide_quote", by: "coalesce(nullif(trim(decide_quote.by), ''), nullif(trim(decide_quote.actor ->> 'name'), ''), decide_quote.actor ->> 'email')", customer: false, expires: "decide_quote.actor is not null", actor: "decide_quote.actor", deposit: false })}
  return ${row("v_row")};
end;
$$;
${userGrant(`${fn("decide_quote")}(uuid, text, text, text, jsonb, jsonb)`)}

-- What the customer sees through the link: the quote without internal
-- notes. Opening a sent quote marks it viewed. Callable without signing in.
create or replace function ${fn("public_quote")}(token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("quotes")};${headers}${restoreVars}
begin
  select * into v_row from ${t("quotes")} x where x.${q("tokenHash")} = ${sha256Hex("public_quote.token")};
  if v_row.${q("id")} is null then
    ${fail("QUOTE_LINK_INVALID", "this link is not valid", "P0002")}
  end if;${viewer()}
${k.markViewed()}
  ${customerView}
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
  v_claims text;${restoreVars}
begin
  select * into v_row from ${t("quotes")} x where x.${q("tokenHash")} = ${sha256Hex("respond_to_quote.token")} for update;
  if v_row.${q("id")} is null then
    ${fail("QUOTE_LINK_INVALID", "this link is not valid", "P0002")}
  end if;${answer({ name: "respond_to_quote", by: "respond_to_quote.name", customer: true, expires: "true", deposit: true })}
  return ${answered};
end;
$$;
revoke all on function ${fn("respond_to_quote")}(text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function ${fn("respond_to_quote")}(text, text, text, text, jsonb) to anon, authenticated, service_role;

-- A quote shared with the signed-in guest, as the customer sees it: through
-- a grant on the quote or as a guest of its company or contact. Opening a
-- sent quote marks it viewed. No link token is needed. The service role
-- reads it too, for an app's own portal; actor is then the customer who
-- opened it, for the state machine's history.
drop function if exists ${fn("portal_quote")}(uuid);
create or replace function ${fn("portal_quote")}(quote uuid, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("quotes")};${headers}${restoreVars}
begin${viewer("portal_quote.actor")}
  select * into v_row from ${t("quotes")} x where x.${q("id")} = portal_quote.quote and (${guest} or (${n.service} and ${k.st(`x.${q("status")}`, ["draft"], true)}));
  if v_row.${q("id")} is null then
    ${fail("QUOTE_NOT_FOUND", "no such quote shared with you", "P0002")}
  end if;
${k.markViewed()}
  ${customerView}
end;
$$;
${userGrant(`${fn("portal_quote")}(uuid, jsonb)`)}

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
  v_claims text;${restoreVars}
begin
  select * into v_row from ${t("quotes")} x where x.${q("id")} = respond_to_portal_quote.quote and ${guest} for update;
  if v_row.${q("id")} is null then
    ${fail("QUOTE_NOT_FOUND", "no such quote shared with you", "P0002")}
  end if;${answer({ name: "respond_to_portal_quote", by: "coalesce(nullif(trim(respond_to_portal_quote.name), ''), auth.jwt() ->> 'email')", customer: true, expires: "true", deposit: true })}
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
  return v_version.${v("snapshot")} || jsonb_build_object('revision', v_version.${v("revision")}, 'publishedAt', v_version.${v("publishedAt")}${
    k.versionLines
      ? `,
    'lines', ${k.withVersionLineIds(`coalesce(v_version.${v("snapshot")} -> 'lines', '[]'::jsonb)`, `v_version.${v("id")}`)}`
      : ""
  });
end;
$$;
${userGrant(`${fn("quote_version")}(uuid, integer)`)}
`;
}
