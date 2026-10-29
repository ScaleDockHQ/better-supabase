import type { ExtraColumn, BlockSqlContext } from "../context.ts";
import type { QuoteKit } from "./quotes-kit.ts";

import { sqlString } from "../../core/template.ts";
import {
  catalogLineFallback,
  declared,
  lineColumn,
  lineItemsSql,
  TOTAL_COLUMNS,
} from "../line-items-sql.ts";
import { assignNumberSql } from "../numbering-sql.ts";
import {
  fail,
  insertExtraColumns,
  serviceGrant,
  sha256Hex,
  transitionActorSql,
  transitionReasonSql,
  triggerGrant,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import { quoteDecisions } from "./quotes-decisions.ts";
import { quoteKit, quoteOrigin, quoteParty } from "./quotes-kit.ts";

export { quoteGuest, quoteOrigin, quoteParty } from "./quotes-kit.ts";

export interface QuoteNames {
  readonly fn: (name: string) => string;
  readonly t: (table: string) => string;
  readonly c: (table: string, column: string) => string;
  readonly read: string;
  readonly write: string;
  readonly manage: string;
  /** `permissions.send`, else `write`: send and publish. */
  readonly send: string;
  /** `permissions.decide`, else `write`: record the customer's answer. */
  readonly decide: string;
  /** `permissions.withdraw`, else `write`. */
  readonly withdraw: string;
  readonly company: string;
  readonly contact: string;
  readonly prefix: string;
  /** Days a new quote stays valid. */
  readonly validDays: number;
  readonly service: string;
  /** `options.extraColumns` of the quotes table, written from `attrs.fields`. */
  readonly extras: readonly ExtraColumn[];
  readonly lineExtras: readonly ExtraColumn[];
  /** `options.versionLineExtraColumns`, copied from the line of the same name. */
  readonly versionLineExtras: readonly ExtraColumn[];
  /** `options.totals: "app"`: the app keeps the totals, the block reads them. */
  readonly appTotals: boolean;
  /** `options.resend`: send takes a rejected, withdrawn or expired quote. */
  readonly resend: boolean;
}

/**
 * SQL that links `source` to `origin` with a `created_from` relation when the
 * relations module is installed, so lineage reads find the chain.
 */
export function createdFromLink(
  ctx: BlockSqlContext,
  link: {
    readonly tenant: string;
    readonly sourceType: string;
    readonly sourceId: string;
    readonly originType: string;
    readonly originId: string;
  },
): string {
  if (!ctx.installed("relations")) {
    return "";
  }

  const r = ctx.of("relations");
  const col = (name: string): string => r.col("relations", name);

  return `insert into ${r.table("relations")} (${col("tenant")}, ${col("kind")}, ${col("sourceType")}, ${col("sourceId")}, ${col("targetType")}, ${col("targetId")}, ${col("createdBy")})
    select ${link.tenant}, 'created_from', ${link.sourceType}, ${link.sourceId}, ${link.originType}, ${link.originId}, auth.uid()
    where not exists (
      select 1 from ${r.table("relations")} x
      where x.${col("kind")} = 'created_from' and x.${col("sourceType")} = ${link.sourceType} and x.${col("sourceId")} = ${link.sourceId}
    );`;
}

export function quoteFunctions(ctx: BlockSqlContext, n: QuoteNames): string {
  const catalogPrice = ctx.installed("catalog")
    ? catalogLineFallback(ctx)
    : undefined;

  const { fn, t } = n;
  const k = quoteKit(ctx, n);
  const { q, l, has, also, present, assign, valueLines, refuse } = k;
  const { editable, st, sv, open, row, record, checkParty } = k;
  const company = quoteParty(ctx, "company");
  const contact = quoteParty(ctx, "contact");
  const origin = quoteOrigin(ctx);
  const v = (column: string): string => n.c("versions", column);

  // Clears the answer of an earlier revision, as the start of a set list.
  const decisionReset = [
    "decidedAt",
    "decidedBy",
    "decisionNote",
    "decidedUser",
    "decidedIp",
    "decidedUserAgent",
  ]
    .filter(has)
    .map((column) => `${q(column)} = null, `)
    .join("");

  // Refuses pricing the app's quotes table has no column for.
  const pricing = (attrs: string): string =>
    [
      refuse(
        has("pricesIncludeTax"),
        `nullif(${attrs} ->> 'pricesIncludeTax', 'false')`,
        "PRICING",
        "prices_include_tax column",
      ),
      refuse(
        has("discountBps"),
        `nullif(${attrs} ->> 'discountBps', '0')`,
        "DISCOUNT",
        "discount column",
      ),
      refuse(
        has("discountAmount"),
        `nullif(${attrs} ->> 'discountAmount', '0')`,
        "DISCOUNT",
        "discount amount column",
      ),
      refuse(
        has("depositBps"),
        `${attrs} ->> 'depositBps'`,
        "DEPOSIT",
        "deposit column",
      ),
      refuse(
        has("depositAmount"),
        `${attrs} ->> 'depositAmount'`,
        "DEPOSIT",
        "deposit amount column",
      ),
      refuse(
        has("depositRequired"),
        `nullif(${attrs} ->> 'depositRequired', 'false')`,
        "DEPOSIT",
        "deposit required column",
      ),
    ].join("");

  // A deposit is a share of the total or a fixed amount, never both.
  const oneDeposit =
    has("depositBps") && has("depositAmount")
      ? `
  if v_row.${q("depositBps")} is not null and v_row.${q("depositAmount")} is not null then
    ${fail("QUOTE_ATTRS_INVALID", "a deposit is a share (depositBps) or an amount (depositAmount), not both", "22023")}
  end if;`
      : "";

  // The set list entries of update_quote for a company or contact it is given.
  const partyAssign = (party: "company" | "contact"): string => {
    const given = `update_quote.attrs ? ${sqlString(party)}`;
    const id = `update_quote.attrs -> ${sqlString(party)} ->> 'id'`;
    const type = `coalesce(update_quote.attrs -> ${sqlString(party)} ->> 'type', ${sqlString(party === "company" ? n.company : n.contact)})`;
    const values = k.partyValues(party, type, id);

    return k
      .partyFields(party)
      .map((field, index) =>
        assign(
          field,
          (col) =>
            `case when ${given} then ${values[index] ?? "null"} else x.${col} end`,
        ),
      )
      .join("");
  };

  // Hands the actor of a staff call to the state machine's history.
  const actor = (name: string): string =>
    `\n  ${transitionActorSql(`${name}.actor`, "QUOTE_ACTOR_INVALID")}`;

  // A declined quote sent again (options.resend) is revised in the same call:
  // a fresh valid-until date and, without a working copy, no view yet.
  const resent =
    k.declined.length === 0
      ? ""
      : `${q("validUntil")} = case when ${st(`x.${q("status")}`, k.declined)} then greatest(x.${q("validUntil")}, current_date + ${String(n.validDays)}) else x.${q("validUntil")} end, ${
          has("viewedAt") && !k.workingCopy
            ? `${q("viewedAt")} = case when ${st(`x.${q("status")}`, k.declined)} then null else x.${q("viewedAt")} end, `
            : ""
        }`;

  const publishedBy = `coalesce(auth.uid(), nullif(send_quote.actor ->> 'id', '')::uuid)`;

  // The published lines as rows with their own ids, when versionLines is on.
  const versionLinesCopy = (() => {
    if (!k.versionLines) {
      return "";
    }

    const vl = (column: string): string => n.c("versionLines", column);

    const copied = [
      "position",
      "description",
      "quantity",
      "unitAmount",
      "periods",
      "discountBps",
      "taxRateBps",
      "taxCode",
      "section",
      "optional",
      "selected",
      "productType",
      "productId",
    ].filter(
      (column) =>
        declared(ctx, "versionLines", column) && declared(ctx, "lines", column),
    );

    const value = (column: string): string =>
      column === "productType"
        ? ctx.cast("versionLines", column, `ql.${l(column)}::text`)
        : `ql.${l(column)}`;

    const lineExtraNames = new Set(n.lineExtras.map((extra) => extra.name));

    const extras = n.versionLineExtras
      .filter((extra) => lineExtraNames.has(extra.name))
      .map((extra) => extra.ident);

    return `
  insert into ${t("versionLines")} (${vl("tenant")}, ${vl("version")}, ${[...copied.map(vl), ...extras].join(", ")})
  select v_row.${q("tenant")}, v_version, ${[...copied.map(value), ...extras.map((ident) => `ql.${ident}`)].join(", ")}
  from ${t("lines")} ql where ql.${l("parent")} = v_row.${q("id")};`;
  })();

  const deals = ctx.installed("deals") ? ctx.of("deals") : undefined;

  const fromDeal =
    deals === undefined
      ? ""
      : (() => {
          const d = (column: string): string => deals.col("deals", column);
          const dk = (column: string): string => deals.col("contacts", column);
          const dl = (column: string): string => deals.col("lines", column);

          const fromDealBody = `select x.${dk("contactType")} as type, x.${dk("contactId")} as id into v_contact
  from ${deals.table("contacts")} x where x.${dk("deal")} = v_deal.${d("id")} order by x.${dk("isPrimary")} desc limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('description', x.${dl("description")}, 'quantity', x.${dl("quantity")}, 'unitAmount', x.${dl("unitAmount")}::text,
      'discountBps', ${lineColumn(deals, "lines", "x", "discountBps")}, 'taxRateBps', ${lineColumn(deals, "lines", "x", "taxRateBps")}, 'taxCode', ${lineColumn(deals, "lines", "x", "taxCode")},
      'product', case when ${lineColumn(deals, "lines", "x", "productType")} is null then null else jsonb_build_object('type', ${lineColumn(deals, "lines", "x", "productType")}, 'id', ${lineColumn(deals, "lines", "x", "productId")}) end
    ) order by x.${dl("position")}), '[]'::jsonb) into v_lines
  from ${deals.table("lines")} x where x.${dl("parent")} = v_deal.${d("id")};
  if jsonb_array_length(v_lines) = 0 and v_deal.${d("amount")} > 0 then
    v_lines := jsonb_build_array(jsonb_build_object('description', v_deal.${d("name")}, 'quantity', 1, 'unitAmount', v_deal.${d("amount")}::text));
  end if;
  return ${fn("create_quote")}(v_deal.${d("tenant")}, jsonb_build_object(
    'title', v_deal.${d("name")}, 'currency', v_deal.${d("currency")}, 'ownerId', v_deal.${d("owner")},
    'company', ${company ? `case when v_deal.${d("companyId")} is null then null else jsonb_build_object('type', v_deal.${d("companyType")}, 'id', v_deal.${d("companyId")}) end` : "null"},
    'contact', ${contact ? "case when v_contact.id is null then null else jsonb_build_object('type', v_contact.type, 'id', v_contact.id) end" : "null"},
    'origin', jsonb_build_object('type', 'deal', 'id', v_deal.${d("id")}::text)), v_lines);`;

          return `
-- A draft quote from a deal: its name, company, primary contact, currency,
-- owner and lines (or one line for its amount). Converting a deal again
-- returns the quote it already made.
create or replace function ${fn("quote_from_deal")}(deal uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deal ${deals.table("deals")};
  v_row ${t("quotes")};
  v_contact record;
  v_lines jsonb;
begin
  select * into v_deal from ${deals.table("deals")} x where x.${d("id")} = quote_from_deal.deal;
  if v_deal.${d("id")} is null or not (${n.service} or ${ctx.scope.can(`v_deal.${d("tenant")}`, n.write)}) then
    ${fail("QUOTE_ORIGIN_NOT_FOUND", "no such deal you can quote", "P0002")}
  end if;${
    origin
      ? `
  select * into v_row from ${t("quotes")} x
  where x.${q("originType")} = 'deal' and x.${q("originId")} = v_deal.${d("id")}::text
  order by x.${q("createdAt")} limit 1;
  if v_row.${q("id")} is not null then
    return ${row("v_row")};
  end if;
  ${fromDealBody}`
      : `
  ${fail("QUOTE_ORIGIN_UNSUPPORTED", "this quotes table has no origin columns, so a deal can't be converted once", "22023")}`
  }
end;
$$;
${userGrant(`${fn("quote_from_deal")}(uuid)`)}
`;
        })();

  return `
-- Creates a draft quote. attrs: title (required), currency, company and
-- contact ({ type, id }), ownerId, validUntil, terms, note, origin ({ type,
-- id }, the record it was made from), pricesIncludeTax, discountBps,
-- discountAmount (minor units as text), depositBps, or depositAmount (minor
-- units as text) for a fixed deposit, and depositRequired, which makes the
-- customer pay it before they accept. lines: see set_quote_lines.
create or replace function ${fn("create_quote")}(tenant ${ctx.idType}, attrs jsonb, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_seq bigint;
  v_identifier text;
  v_row ${t("quotes")};
  v_company_type text := coalesce(create_quote.attrs -> 'company' ->> 'type', ${sqlString(n.company)});
  v_company_id text := create_quote.attrs -> 'company' ->> 'id';
  v_contact_type text := coalesce(create_quote.attrs -> 'contact' ->> 'type', ${sqlString(n.contact)});
  v_contact_id text := create_quote.attrs -> 'contact' ->> 'id';
begin
  if not (${n.service} or ${ctx.scope.can("create_quote.tenant", n.write)}) then
    ${fail("QUOTE_FORBIDDEN", "not allowed to change quotes")}
  end if;
  if nullif(trim(create_quote.attrs ->> 'title'), '') is null then
    ${fail("QUOTE_ATTRS_INVALID", "a quote needs a title", "23502")}
  end if;${checkParty("COMPANY", "v_company_type", "v_company_id", "create_quote.tenant")}${checkParty("CONTACT", "v_contact_type", "v_contact_id", "create_quote.tenant")}${refuse(has("terms"), "create_quote.attrs ->> 'terms'", "TERMS", "terms column")}${refuse(has("note"), "create_quote.attrs ->> 'note'", "NOTE", "note column")}${refuse(origin, "(create_quote.attrs -> 'origin' ->> 'id')", "ORIGIN", "origin columns")}${pricing("create_quote.attrs")}
  ${assignNumberSql(
    ctx,
    "quote",
    "create_quote.tenant",
    { seq: "v_seq", identifier: "v_identifier" },
    {
      table: t("quotes"),
      seq: q("number"),
      tenant: q("tenant"),
      prefix: n.prefix,
    },
  )}
  begin
    insert into ${t("quotes")} (${q("tenant")}, ${q("number")}, ${q("identifier")}, ${q("title")}${[...k.partyFields("company"), ...k.partyFields("contact")].map((field) => `, ${q(field)}`).join("")},
      ${q("owner")}, ${q("currency")}, ${q("validUntil")}${also("terms")}${also("note")}${also("originType")}${also("originId")}${also("pricesIncludeTax")}${also("discountBps")}${also("discountAmount")}${also("depositBps")}${also("depositAmount")}${also("depositRequired")}${also("createdBy")}${insertExtraColumns(t("quotes"), n.extras, "coalesce(create_quote.attrs -> 'fields', '{}'::jsonb)").columns})
    values (${valueLines(
      "      ",
      [
        "create_quote.tenant",
        "v_seq",
        "v_identifier",
        "trim(create_quote.attrs ->> 'title')",
      ],
      k.partyValues("company", "v_company_type", "v_company_id"),
      k.partyValues("contact", "v_contact_type", "v_contact_id"),
      [
        "coalesce((create_quote.attrs ->> 'ownerId')::uuid, auth.uid())",
        "upper(coalesce(create_quote.attrs ->> 'currency', 'EUR'))",
      ],
      [
        `coalesce((create_quote.attrs ->> 'validUntil')::date, current_date + ${String(n.validDays)})`,
      ],
      [
        present("terms", "create_quote.attrs ->> 'terms'"),
        present("note", "create_quote.attrs ->> 'note'"),
      ],
      [
        present("originType", "create_quote.attrs -> 'origin' ->> 'type'"),
        present("originId", "create_quote.attrs -> 'origin' ->> 'id'"),
      ],
      [
        present(
          "pricesIncludeTax",
          "coalesce((create_quote.attrs ->> 'pricesIncludeTax')::boolean, false)",
        ),
        present(
          "discountBps",
          "coalesce((create_quote.attrs ->> 'discountBps')::integer, 0)",
        ),
        present(
          "discountAmount",
          "coalesce((create_quote.attrs ->> 'discountAmount')::bigint, 0)",
        ),
        present("depositBps", "(create_quote.attrs ->> 'depositBps')::integer"),
        present(
          "depositAmount",
          "(create_quote.attrs ->> 'depositAmount')::bigint",
        ),
        present(
          "depositRequired",
          "coalesce((create_quote.attrs ->> 'depositRequired')::boolean, false)",
        ),
        present("createdBy", "auth.uid()"),
      ],
    )}${insertExtraColumns(t("quotes"), n.extras, "coalesce(create_quote.attrs -> 'fields', '{}'::jsonb)").values})
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    ${fail("QUOTE_ATTRS_INVALID", "a quote field has an invalid value", "22023")}
  end;${oneDeposit}
  if create_quote.lines is not null then
    perform ${fn("set_quote_lines")}(v_row.${q("id")}, create_quote.lines);
  end if;${
    origin
      ? `
  if v_row.${q("originId")} is not null then
    ${createdFromLink(ctx, { tenant: `v_row.${q("tenant")}`, sourceType: "'quote'", sourceId: `v_row.${q("id")}::text`, originType: `v_row.${q("originType")}`, originId: `v_row.${q("originId")}` })}
  end if;`
      : ""
  }
  ${record("quote.created", "v_row")}
  return (select ${row("x")} from ${t("quotes")} x where x.${q("id")} = v_row.${q("id")});
end;
$$;
${userGrant(`${fn("create_quote")}(${ctx.idType}, jsonb, jsonb)`)}

-- Changes a draft quote, or one the customer asked changes on: title,
-- company, contact, currency, ownerId, validUntil, terms, note,
-- pricesIncludeTax, discountBps, discountAmount, depositBps, depositAmount
-- and depositRequired. The totals follow the new pricing.${k.workingCopy ? "\n-- A sent quote changes too; the customer sees it once it is sent again." : ""}
create or replace function ${fn("update_quote")}(quote uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("quotes")};
begin
  select * into v_row from ${t("quotes")} x where x.${q("id")} = update_quote.quote and ${editable("x")};
  if v_row.${q("id")} is null then
    ${fail("QUOTE_NOT_FOUND", "no such quote you can edit", "P0002")}
  end if;
  if not (${open("v_row")}) then
    ${fail("QUOTE_NOT_EDITABLE", "only a draft quote, or one with changes requested, can change", "55000")}
  end if;${checkParty("COMPANY", `coalesce(update_quote.attrs -> 'company' ->> 'type', ${sqlString(n.company)})`, "(update_quote.attrs -> 'company' ->> 'id')", `v_row.${q("tenant")}`)}${checkParty("CONTACT", `coalesce(update_quote.attrs -> 'contact' ->> 'type', ${sqlString(n.contact)})`, "(update_quote.attrs -> 'contact' ->> 'id')", `v_row.${q("tenant")}`)}${refuse(has("terms"), "update_quote.attrs ->> 'terms'", "TERMS", "terms column")}${refuse(has("note"), "update_quote.attrs ->> 'note'", "NOTE", "note column")}${pricing("update_quote.attrs")}
  begin
    update ${t("quotes")} x set
      ${q("title")} = coalesce(nullif(trim(update_quote.attrs ->> 'title'), ''), x.${q("title")}),
      ${q("currency")} = coalesce(upper(update_quote.attrs ->> 'currency'), x.${q("currency")}),
      ${q("owner")} = case when update_quote.attrs ? 'ownerId' then (update_quote.attrs ->> 'ownerId')::uuid else x.${q("owner")} end,
      ${q("validUntil")} = case when update_quote.attrs ? 'validUntil' then (update_quote.attrs ->> 'validUntil')::date else x.${q("validUntil")} end,${assign("terms", (col) => `case when update_quote.attrs ? 'terms' then update_quote.attrs ->> 'terms' else x.${col} end`)}${assign("note", (col) => `case when update_quote.attrs ? 'note' then update_quote.attrs ->> 'note' else x.${col} end`)}${assign("pricesIncludeTax", (col) => `case when update_quote.attrs ? 'pricesIncludeTax' then coalesce((update_quote.attrs ->> 'pricesIncludeTax')::boolean, false) else x.${col} end`)}${assign("discountBps", (col) => `case when update_quote.attrs ? 'discountBps' then coalesce((update_quote.attrs ->> 'discountBps')::integer, 0) else x.${col} end`)}${assign("discountAmount", (col) => `case when update_quote.attrs ? 'discountAmount' then coalesce((update_quote.attrs ->> 'discountAmount')::bigint, 0) else x.${col} end`)}${assign("depositBps", (col) => `case when update_quote.attrs ? 'depositBps' then (update_quote.attrs ->> 'depositBps')::integer else x.${col} end`)}${assign("depositAmount", (col) => `case when update_quote.attrs ? 'depositAmount' then (update_quote.attrs ->> 'depositAmount')::bigint else x.${col} end`)}${assign("depositRequired", (col) => `case when update_quote.attrs ? 'depositRequired' then coalesce((update_quote.attrs ->> 'depositRequired')::boolean, false) else x.${col} end`)}${k.workingCopy ? assign("unpublishedChanges", () => "true") : ""}${partyAssign("company")}${partyAssign("contact")}
      ${q("updatedAt")} = now()
    where x.${q("id")} = v_row.${q("id")}
    returning * into v_row;${
      n.extras.length === 0
        ? ""
        : `${writeExtraColumns(t("quotes"), n.extras, "(update_quote.attrs -> 'fields')", `x.${q("id")} = v_row.${q("id")}`)}
    select * into v_row from ${t("quotes")} x where x.${q("id")} = v_row.${q("id")};`
    }
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    ${fail("QUOTE_ATTRS_INVALID", "a quote field has an invalid value", "22023")}
  end;${oneDeposit}${
    n.appTotals
      ? ""
      : `
  perform ${fn("set_quote_lines_recount")}(v_row.${q("id")});`
  }
  select * into v_row from ${t("quotes")} x where x.${q("id")} = v_row.${q("id")};
  ${record("quote.updated", "v_row")}
  return ${row("v_row")};
end;
$$;
${userGrant(`${fn("update_quote")}(uuid, jsonb)`)}
${lineItemsSql(
  ctx,
  {
    lines: "lines",
    parent: "quotes",
    frozen: `not (${open("p")})`,
    extras: n.lineExtras,
    taxLines: "taxLines",
    totals: !n.appTotals,
    ...(k.depositDue === undefined ? {} : { afterTotals: k.depositDue }),
  },
  {
    setter: "set_quote_lines",
    guard: `if not exists (select 1 from ${t("quotes")} x where x.${q("id")} = v_parent and ${editable("x")}) then
    ${fail("QUOTE_NOT_FOUND", "no such quote you can edit", "P0002")}
  end if;${
    k.workingCopy
      ? `
  update ${t("quotes")} x set ${q("unpublishedChanges")} = true where x.${q("id")} = v_parent;`
      : ""
  }`,
    ...(catalogPrice ? { fallback: catalogPrice } : {}),
    ...(k.workingCopy ? { restorer: "quote_lines_restore" } : {}),
  },
)}
-- Sends a quote: it gets a public link the customer opens and a published
-- version, a snapshot that never changes. The quote can't change until it is
-- revised or the customer asks for changes; sending it again then publishes
-- the next revision. Returns the quote with the link's token, which is stored
-- only as a hash and returned this once.${k.workingCopy ? "\n-- A sent quote keeps its link: sending it again publishes the working copy\n-- as the next revision on the same link, without a new token." : ""}
-- actor: who sent it, for the state machine's history.
drop function if exists ${fn("send_quote")}(uuid);
create or replace function ${fn("send_quote")}(quote uuid, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("quotes")};
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_version uuid;${k.workingCopy ? "\n  v_linked boolean;" : ""}
begin
  select * into v_row from ${t("quotes")} x where x.${q("id")} = send_quote.quote and ${editable("x", n.send)} for update;
  if v_row.${q("id")} is null then
    ${fail("QUOTE_NOT_FOUND", "no such quote you can edit", "P0002")}
  end if;
  if not (${open("v_row")}${k.declined.length > 0 && !k.workingCopy ? ` or ${st(`v_row.${q("status")}`, k.declined)}` : ""}) then
    ${fail("QUOTE_NOT_EDITABLE", "the quote was already sent; revise it to send a new version", "55000")}
  end if;
  if not exists (select 1 from ${t("lines")} x where x.${l("parent")} = v_row.${q("id")}) then
    ${fail("QUOTE_EMPTY", "a quote needs a line before it is sent", "23514")}
  end if;${actor("send_quote")}
  ${ctx.hook("before_quote_send", [["uuid", `v_row.${q("id")}`]])}${k.workingCopy ? `\n  v_linked := v_row.${q("tokenHash")} is not null;` : ""}
  update ${t("quotes")} x set ${q("status")} = ${sv("sent")}, ${q("sentAt")} = now(), ${q("tokenHash")} = ${k.workingCopy ? `coalesce(x.${q("tokenHash")}, ${sha256Hex("v_token")})` : sha256Hex("v_token")},
    ${q("revision")} = case when exists (select 1 from ${t("versions")} v where v.${v("quote")} = x.${q("id")} and v.${v("revision")} = x.${q("revision")}) then x.${q("revision")} + 1 else x.${q("revision")} end,
    ${decisionReset}${resent}${k.workingCopy ? `${q("unpublishedChanges")} = false, ` : ""}${q("updatedAt")} = now()
  where x.${q("id")} = v_row.${q("id")}
  returning * into v_row;
  insert into ${t("versions")} (${v("tenant")}, ${v("quote")}, ${v("revision")}, ${v("snapshot")}, ${v("total")}, ${v("currency")}${ctx.has("versions", "publishedBy") ? `, ${v("publishedBy")}` : ""})
  values (v_row.${q("tenant")}, v_row.${q("id")}, v_row.${q("revision")}, ${row("v_row")}, v_row.${q("total")}, v_row.${q("currency")}${ctx.has("versions", "publishedBy") ? `, ${publishedBy}` : ""})
  returning ${v("id")} into v_version;${versionLinesCopy}
  ${record("quote.sent", "v_row", `, 'revision', v_row.${q("revision")}`)}
  ${ctx.hook("after_quote_send", [["uuid", `v_row.${q("id")}`]])}
  return ${row("v_row")} || jsonb_build_object('token', ${k.workingCopy ? "case when v_linked then null else v_token end" : "v_token"});
end;
$$;
${userGrant(`${fn("send_quote")}(uuid, jsonb)`)}

-- Opens a sent or declined quote again as a draft of its next revision: the
-- same quote, number and lines, a fresh valid-until date, and its link ends.
-- The versions already published stay as they were. An accepted quote is
-- kept as the customer accepted it; start a new quote instead.${k.workingCopy ? "\n-- With a working copy the link stays and so does a sent quote's status; a\n-- declined quote goes back to draft until it is sent again." : ""}
drop function if exists ${fn("revise_quote")}(uuid);
create or replace function ${fn("revise_quote")}(quote uuid, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("quotes")};
begin
  select * into v_row from ${t("quotes")} x where x.${q("id")} = revise_quote.quote and ${editable("x")} for update;
  if v_row.${q("id")} is null then
    ${fail("QUOTE_NOT_FOUND", "no such quote you can edit", "P0002")}
  end if;
  if ${st(`v_row.${q("status")}`, ["draft"])} then
    ${fail("QUOTE_NOT_SENT", "a draft is edited, not revised", "55000")}
  end if;
  if ${st(`v_row.${q("status")}`, ["accepted"])} then
    ${fail("QUOTE_ACCEPTED", "an accepted quote stays as accepted; start a new quote", "55000")}
  end if;${actor("revise_quote")}
  ${
    k.workingCopy
      ? `update ${t("quotes")} x set ${q("status")} = case when ${st(`x.${q("status")}`, ["sent", "viewed"])} then x.${q("status")} else ${sv("draft")} end,
    ${q("validUntil")} = greatest(x.${q("validUntil")}, current_date + ${String(n.validDays)}),
    ${decisionReset}${q("updatedAt")} = now()`
      : `update ${t("quotes")} x set ${q("status")} = ${sv("draft")}, ${q("revision")} = x.${q("revision")} + 1, ${q("tokenHash")} = null, ${q("sentAt")} = null,${has("viewedAt") ? ` ${q("viewedAt")} = null,` : ""}
    ${q("validUntil")} = greatest(x.${q("validUntil")}, current_date + ${String(n.validDays)}),
    ${decisionReset}${q("updatedAt")} = now()`
  }
  where x.${q("id")} = v_row.${q("id")}
  returning * into v_row;
  ${record("quote.revised", "v_row", `, 'revision', v_row.${q("revision")}`)}
  return ${row("v_row")};
end;
$$;
${userGrant(`${fn("revise_quote")}(uuid, jsonb)`)}

-- Takes back a sent or expired quote the customer hasn't accepted: it can't
-- be answered any more until it is revised and sent again. The actor and
-- reason go to the state machine's history.
drop function if exists ${fn("withdraw_quote")}(uuid, jsonb);
create or replace function ${fn("withdraw_quote")}(quote uuid, actor jsonb default null, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("quotes")};
begin
  select * into v_row from ${t("quotes")} x where x.${q("id")} = withdraw_quote.quote and ${editable("x", n.withdraw)} for update;
  if v_row.${q("id")} is null then
    ${fail("QUOTE_NOT_FOUND", "no such quote you can edit", "P0002")}
  end if;
  if ${st(`v_row.${q("status")}`, ["sent", "viewed", "changes_requested", "expired"], true)} then
    ${fail("QUOTE_NOT_OPEN", "only a sent quote that wasn't answered is withdrawn", "55000")}
  end if;${actor("withdraw_quote")}
  ${transitionReasonSql("withdraw_quote.reason")}
  update ${t("quotes")} x set ${q("status")} = ${sv("withdrawn")}, ${q("updatedAt")} = now()
  where x.${q("id")} = v_row.${q("id")}
  returning * into v_row;
  ${transitionReasonSql()}
  ${record("quote.withdrawn", "v_row", `, 'revision', v_row.${q("revision")}`)}
  return ${row("v_row")};
end;
$$;
${userGrant(`${fn("withdraw_quote")}(uuid, jsonb, text)`)}
${quoteDecisions(ctx, n, k)}
-- Expires sent quotes past their valid date. Run it daily from a job.
create or replace function ${fn("expire_quotes")}()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("quotes")};
  v_count integer := 0;
begin
  perform set_config('better_supabase.transition_actor', '', true);
  for v_row in
    update ${t("quotes")} x set ${q("status")} = ${sv("expired")}, ${q("updatedAt")} = now()
    where ${st(`x.${q("status")}`, ["sent", "viewed"])} and x.${q("validUntil")} < current_date
    returning *
  loop
    ${record("quote.expired", "v_row")}
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("expire_quotes")}()`)}
${appTotalsGuard(ctx, n, k)}${fromDeal}`;
}

/**
 * With `options.totals: "app"`, a trigger on the quotes table that refuses a
 * change to the totals once a quote is answered, expired or withdrawn, and
 * keeps the deposit due on the app's total.
 */
function appTotalsGuard(
  ctx: BlockSqlContext,
  n: QuoteNames,
  k: QuoteKit,
): string {
  if (!n.appTotals) {
    return "";
  }

  const { q, has, st } = k;
  const trigger = ctx.trigger("quotes_app_totals");
  const fn = `better_supabase.${trigger.replaceAll('"', "")}()`;

  const totals = Object.keys(TOTAL_COLUMNS).filter(has).map(q);

  const changeable = [...new Set([...k.openStatuses, "sent", "viewed"])];

  const depositDue = has("depositDue")
    ? `
  new.${q("depositDue")} := case${has("depositAmount") ? ` when new.${q("depositAmount")} is not null then least(greatest(new.${q("total")}, 0), new.${q("depositAmount")})` : ""}${has("depositBps") ? ` when new.${q("depositBps")} is not null then round(new.${q("total")} * new.${q("depositBps")} / 10000.0)::bigint` : ""} else 0 end;`
    : "";

  return `
-- The app keeps the quote's totals: once a quote is answered, expired or
-- withdrawn they no longer change, and the deposit due follows the total.
create or replace function ${fn}
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and ${st(`old.${q("status")}`, changeable, true)}
    and (${totals.map((column) => `new.${column}`).join(", ")}) is distinct from (${totals.map((column) => `old.${column}`).join(", ")}) then
    ${fail("QUOTE_TOTALS_FROZEN", "the totals of an answered, expired or withdrawn quote don't change", "55000")}
  end if;${depositDue}
  return new;
end;
$$;
${triggerGrant(fn)}
drop trigger if exists ${trigger} on ${n.t("quotes")};
create trigger ${trigger} before insert or update on ${n.t("quotes")}
for each row execute function ${fn};
`;
}
