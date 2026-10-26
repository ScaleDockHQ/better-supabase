import type { ExtraColumn, BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import {
  catalogLineFallback,
  lineColumn,
  lineCopyColumns,
  lineFieldsJson,
  lineItemsSql,
  TOTAL_COLUMNS,
} from "../line-items-sql.ts";
import { int8Text } from "../money-sql.ts";
import { assignNumberSql } from "../numbering-sql.ts";
import {
  columnsObject,
  fail,
  serviceGrant,
  sha256Hex,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import { subjectInTenant } from "../subject-check-sql.ts";

export interface QuoteNames {
  readonly fn: (name: string) => string;
  readonly t: (table: string) => string;
  readonly c: (table: string, column: string) => string;
  readonly read: string;
  readonly write: string;
  readonly manage: string;
  readonly company: string;
  readonly contact: string;
  readonly prefix: string;
  /** Days a new quote stays valid. */
  readonly validDays: number;
  readonly service: string;
  /** `options.extraColumns` of the quotes table, written from `attrs.fields`. */
  readonly extras: readonly ExtraColumn[];
  readonly lineExtras: readonly ExtraColumn[];
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

/** Whether the quotes table has both columns of a company or contact link. */
export function quoteParty(
  ctx: BlockSqlContext,
  party: "company" | "contact",
): boolean {
  return ctx.has("quotes", `${party}Type`) && ctx.has("quotes", `${party}Id`);
}

/** Whether the quotes table has both columns of the record it was made from. */
export function quoteOrigin(ctx: BlockSqlContext): boolean {
  return ctx.has("quotes", "originType") && ctx.has("quotes", "originId");
}

export function quoteFunctions(ctx: BlockSqlContext, n: QuoteNames): string {
  const catalogPrice = ctx.installed("catalog")
    ? catalogLineFallback(ctx)
    : undefined;

  const { fn, t, c } = n;
  const q = (column: string): string => c("quotes", column);
  const l = (column: string): string => c("lines", column);
  const company = quoteParty(ctx, "company");
  const contact = quoteParty(ctx, "contact");
  const origin = quoteOrigin(ctx);
  const has = (logical: string): boolean => ctx.has("quotes", logical);

  // A column of row, or null when the app maps it to null.
  const or = (row: string, logical: string): string =>
    has(logical) ? `${row}.${q(logical)}` : "null";

  // ", <column>" for an insert's column list, when the column exists.
  const also = (logical: string): string =>
    has(logical) ? `, ${q(logical)}` : "";

  // The column's name, or "" when the app maps it to null, so present() can
  // take it without throwing.
  const copy = (logical: string): string => (has(logical) ? q(logical) : "");

  // value when the column exists, for valueLines().
  const present = (logical: string, value: string): string | undefined =>
    has(logical) ? value : undefined;

  // `<column> = value(<column>),` on its own line of an update's set list.
  const assign = (
    logical: string,
    value: (column: string) => string,
  ): string =>
    has(logical) ? `\n      ${q(logical)} = ${value(q(logical))},` : "";

  // The values of an insert, the present ones of each group on a line.
  const valueLines = (
    indent: string,
    ...groups: readonly (string | undefined)[][]
  ): string =>
    groups
      .map((group) => group.filter((value) => value !== undefined).join(", "))
      .filter((line) => line !== "")
      .join(`,\n${indent}`);

  // Refuses a value the app's quotes table has no column for.
  const refuse = (
    supported: boolean,
    given: string,
    thing: string,
    what: string,
  ): string =>
    supported
      ? ""
      : `
  if ${given} is not null then
    ${fail(`QUOTE_${thing}_UNSUPPORTED`, `this quotes table has no ${what}`, "22023")}
  end if;`;

  const editable = (alias: string): string =>
    `(${n.service} or ${ctx.scope.can(`${alias}.${q("tenant")}`, n.write)})`;

  const st = (value: string, labels: readonly string[], negate = false) =>
    ctx.is("quotes", "status", value, labels, negate);

  const sv = (label: string): string => ctx.value("quotes", "status", label);

  const viewed = ctx.appValues("quotes", "status", "viewed").length > 0;

  const markViewed = (): string =>
    viewed || has("viewedAt")
      ? `  if ${st(`v_row.${q("status")}`, ["sent"])}${viewed ? "" : ` and v_row.${q("viewedAt")} is null`} then
    update ${t("quotes")} x set ${viewed ? `${q("status")} = ${sv("viewed")}${has("viewedAt") ? ", " : ""}` : ""}${has("viewedAt") ? `${q("viewedAt")} = now()` : ""} where x.${q("id")} = v_row.${q("id")}
    returning * into v_row;
    ${record("quote.viewed", "v_row")}
  end if;`
      : "  null;";

  const open = (alias: string): string =>
    st(`${alias}.${q("status")}`, ["draft", "changes_requested"]);

  const lines = (alias: string): string =>
    `coalesce((select jsonb_agg(jsonb_build_object('description', ql.${l("description")}, 'quantity', ql.${l("quantity")}, 'unitAmount', ql.${l("unitAmount")}::text, 'discountBps', ${lineColumn(ctx, "lines", "ql", "discountBps")}, 'taxRateBps', ${lineColumn(ctx, "lines", "ql", "taxRateBps")}, 'taxCode', ${lineColumn(ctx, "lines", "ql", "taxCode")}, 'product', case when ${lineColumn(ctx, "lines", "ql", "productType")} is null then null else jsonb_build_object('type', ${lineColumn(ctx, "lines", "ql", "productType")}, 'id', ${lineColumn(ctx, "lines", "ql", "productId")}) end${lineFieldsJson("ql", n.lineExtras)}) order by ql.${l("position")}) from ${t("lines")} ql where ql.${l("parent")} = ${alias}.${q("id")}), '[]'::jsonb)`;

  const int8 = ["number", ...Object.keys(TOTAL_COLUMNS)].map(q);

  const int8As = Object.fromEntries(
    ["number", ...Object.keys(TOTAL_COLUMNS)].map((logical) => [
      logical,
      (value: string) => `${value}::text`,
    ]),
  );

  const row = (alias: string): string =>
    `(${ctx.rowJson("quotes", alias, { as: int8As })} - ${sqlString(q("tokenHash").replaceAll('"', ""))}${q("tokenHash") === '"token_hash"' ? "" : " - 'token_hash'"}) || ${int8Text(alias, int8)} || jsonb_build_object('lines', ${lines(alias)}${
      n.extras.length === 0
        ? ""
        : `, 'fields', ${columnsObject(
            alias,
            n.extras.map((extra) => extra.name),
          )}`
    })`;

  const record = (type: string, alias: string, extra = ""): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${alias}.${q("tenant")}, 'quoteId', ${alias}.${q("id")}, 'subjectType', 'quote', 'subjectId', ${alias}.${q("id")}::text, 'identifier', ${alias}.${q("identifier")}${extra})`,
      subject: `'quotes/' || ${alias}.${q("id")}::text`,
      tenant: `${alias}.${q("tenant")}::text`,
      audit: false,
    });

  const checkParty = (
    kind: "COMPANY" | "CONTACT",
    type: string,
    id: string,
    tenant: string,
  ): string =>
    (kind === "COMPANY" ? company : contact)
      ? `
  if ${id} is not null and not ${subjectInTenant(ctx, type, id, tenant)} then
    ${fail(`QUOTE_${kind}_FORBIDDEN`, `the ${kind.toLowerCase()} is unknown or not readable in this organization`, "42501")}
  end if;`
      : refuse(false, id, kind, `${kind.toLowerCase()} columns`);

  const notifyOwner = (event: string): string =>
    ctx.installed("notifications")
      ? `
  if v_row.${q("owner")} is not null then
    ${ctx.notify(
      `jsonb_build_object(
      'type', ${sqlString(event)},
      'tenant', v_row.${q("tenant")},
      'subject_type', 'quote',
      'subject_id', v_row.${q("id")}::text,
      'summary', v_row.${q("identifier")} || ' ' || v_row.${q("title")},
      'recipients', jsonb_build_array(v_row.${q("owner")}),
      'key', ${sqlString(`${event}:`)} || v_row.${q("id")}::text,
      'data', jsonb_build_object('quoteId', v_row.${q("id")}, 'status', v_row.${q("status")})
    )`,
      { indent: "    " },
    )}
  end if;`
      : "";

  // Without a note column the note still reaches the event.
  const decide = (decision: string, note: string, by: string): string => {
    const noted = has("decisionNote")
      ? `v_row.${q("decisionNote")}`
      : `nullif(trim(${note}), '')`;

    return `
  update ${t("quotes")} x set ${q("status")} = ${ctx.cast("quotes", "status", decision)}, ${q("decidedAt")} = now(), ${q("decidedBy")} = ${by},
    ${has("decisionNote") ? `${q("decisionNote")} = nullif(trim(${note}), ''), ` : ""}${q("updatedAt")} = now()
  where x.${q("id")} = v_row.${q("id")}
  returning * into v_row;
  case ${decision}
    when 'accepted' then
      ${record("quote.accepted", "v_row", `, 'total', v_row.${q("total")}::text, 'currency', v_row.${q("currency")}, 'byName', v_row.${q("decidedBy")}`)}
    when 'rejected' then
      ${record("quote.rejected", "v_row", `, 'note', ${noted}`)}
    else
      ${record("quote.changes_requested", "v_row", `, 'note', ${noted}`)}
  end case;${notifyOwner("quote.decided")}`;
  };

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
  where x.${q("originType")} = 'deal' and x.${q("originId")} = v_deal.${d("id")}::text and x.${q("supersedes")} is null
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
-- id }, the record it was made from). lines: see set_quote_lines.
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
  end if;${checkParty("COMPANY", "v_company_type", "v_company_id", "create_quote.tenant")}${checkParty("CONTACT", "v_contact_type", "v_contact_id", "create_quote.tenant")}${refuse(has("terms"), "create_quote.attrs ->> 'terms'", "TERMS", "terms column")}${refuse(has("note"), "create_quote.attrs ->> 'note'", "NOTE", "note column")}${refuse(origin, "(create_quote.attrs -> 'origin' ->> 'id')", "ORIGIN", "origin columns")}
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
    insert into ${t("quotes")} (${q("tenant")}, ${q("number")}, ${q("identifier")}, ${q("title")}${also("companyType")}${also("companyId")}${also("contactType")}${also("contactId")},
      ${q("owner")}, ${q("currency")}, ${q("validUntil")}${also("terms")}${also("note")}${also("originType")}${also("originId")}${also("createdBy")})
    values (${valueLines(
      "      ",
      [
        "create_quote.tenant",
        "v_seq",
        "v_identifier",
        "trim(create_quote.attrs ->> 'title')",
      ],
      company
        ? [
            "case when v_company_id is null then null else v_company_type end",
            "v_company_id",
          ]
        : [],
      contact
        ? [
            "case when v_contact_id is null then null else v_contact_type end",
            "v_contact_id",
          ]
        : [],
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
        present("createdBy", "auth.uid()"),
      ],
    )})
    returning * into v_row;${writeExtraColumns(t("quotes"), n.extras, "(create_quote.attrs -> 'fields')", `x.${q("id")} = v_row.${q("id")}`)}
  exception when check_violation or invalid_text_representation or datetime_field_overflow then
    ${fail("QUOTE_ATTRS_INVALID", "a quote field has an invalid value", "22023")}
  end;
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
-- company, contact, currency, ownerId, validUntil, terms, note.
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
  end if;${checkParty("COMPANY", `coalesce(update_quote.attrs -> 'company' ->> 'type', ${sqlString(n.company)})`, "(update_quote.attrs -> 'company' ->> 'id')", `v_row.${q("tenant")}`)}${checkParty("CONTACT", `coalesce(update_quote.attrs -> 'contact' ->> 'type', ${sqlString(n.contact)})`, "(update_quote.attrs -> 'contact' ->> 'id')", `v_row.${q("tenant")}`)}${refuse(has("terms"), "update_quote.attrs ->> 'terms'", "TERMS", "terms column")}${refuse(has("note"), "update_quote.attrs ->> 'note'", "NOTE", "note column")}
  begin
    update ${t("quotes")} x set
      ${q("title")} = coalesce(nullif(trim(update_quote.attrs ->> 'title'), ''), x.${q("title")}),
      ${q("currency")} = coalesce(upper(update_quote.attrs ->> 'currency'), x.${q("currency")}),
      ${q("owner")} = case when update_quote.attrs ? 'ownerId' then (update_quote.attrs ->> 'ownerId')::uuid else x.${q("owner")} end,
      ${q("validUntil")} = case when update_quote.attrs ? 'validUntil' then (update_quote.attrs ->> 'validUntil')::date else x.${q("validUntil")} end,${assign("terms", (col) => `case when update_quote.attrs ? 'terms' then update_quote.attrs ->> 'terms' else x.${col} end`)}${assign("note", (col) => `case when update_quote.attrs ? 'note' then update_quote.attrs ->> 'note' else x.${col} end`)}${company ? assign("companyType", (col) => `case when update_quote.attrs ? 'company' then case when update_quote.attrs -> 'company' ->> 'id' is null then null else coalesce(update_quote.attrs -> 'company' ->> 'type', ${sqlString(n.company)}) end else x.${col} end`) + assign("companyId", (col) => `case when update_quote.attrs ? 'company' then update_quote.attrs -> 'company' ->> 'id' else x.${col} end`) : ""}${contact ? assign("contactType", (col) => `case when update_quote.attrs ? 'contact' then case when update_quote.attrs -> 'contact' ->> 'id' is null then null else coalesce(update_quote.attrs -> 'contact' ->> 'type', ${sqlString(n.contact)}) end else x.${col} end`) + assign("contactId", (col) => `case when update_quote.attrs ? 'contact' then update_quote.attrs -> 'contact' ->> 'id' else x.${col} end`) : ""}
      ${q("updatedAt")} = now()
    where x.${q("id")} = v_row.${q("id")}
    returning * into v_row;${
      n.extras.length === 0
        ? ""
        : `${writeExtraColumns(t("quotes"), n.extras, "(update_quote.attrs -> 'fields')", `x.${q("id")} = v_row.${q("id")}`)}
    select * into v_row from ${t("quotes")} x where x.${q("id")} = v_row.${q("id")};`
    }
  exception when check_violation or invalid_text_representation or datetime_field_overflow then
    ${fail("QUOTE_ATTRS_INVALID", "a quote field has an invalid value", "22023")}
  end;
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
  },
  {
    setter: "set_quote_lines",
    guard: `if not exists (select 1 from ${t("quotes")} x where x.${q("id")} = v_parent and ${editable("x")}) then
    ${fail("QUOTE_NOT_FOUND", "no such quote you can edit", "P0002")}
  end if;`,
    ...(catalogPrice ? { fallback: catalogPrice } : {}),
  },
)}
-- Sends a quote: it gets a public link the customer opens, and can't
-- change until it is revised. Returns the quote with the link's token,
-- which is stored only as a hash and returned this once.
create or replace function ${fn("send_quote")}(quote uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("quotes")};
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
begin
  select * into v_row from ${t("quotes")} x where x.${q("id")} = send_quote.quote and ${editable("x")} for update;
  if v_row.${q("id")} is null then
    ${fail("QUOTE_NOT_FOUND", "no such quote you can edit", "P0002")}
  end if;
  if not (${open("v_row")}) then
    ${fail("QUOTE_NOT_EDITABLE", "the quote was already sent; revise it to send a new version", "55000")}
  end if;
  if not exists (select 1 from ${t("lines")} x where x.${l("parent")} = v_row.${q("id")}) then
    ${fail("QUOTE_EMPTY", "a quote needs a line before it is sent", "23514")}
  end if;
  ${ctx.hook("before_quote_send", [["uuid", `v_row.${q("id")}`]])}
  update ${t("quotes")} x set ${q("status")} = ${sv("sent")}, ${q("sentAt")} = now(), ${q("tokenHash")} = ${sha256Hex("v_token")},
    ${q("decidedAt")} = null, ${q("decidedBy")} = null, ${has("decisionNote") ? `${q("decisionNote")} = null, ` : ""}${q("updatedAt")} = now()
  where x.${q("id")} = v_row.${q("id")}
  returning * into v_row;
  ${record("quote.sent", "v_row")}
  ${ctx.hook("after_quote_send", [["uuid", `v_row.${q("id")}`]])}
  return ${row("v_row")} || jsonb_build_object('token', v_token);
end;
$$;
${userGrant(`${fn("send_quote")}(uuid)`)}

-- Records the customer's answer taken another way (by phone, by email):
-- decision is accepted, rejected or changes_requested; by is their name.
create or replace function ${fn("decide_quote")}(quote uuid, decision text, note text, by text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("quotes")};
  v_claims text;
begin
  select * into v_row from ${t("quotes")} x where x.${q("id")} = decide_quote.quote and ${editable("x")} for update;
  if v_row.${q("id")} is null then
    ${fail("QUOTE_NOT_FOUND", "no such quote you can edit", "P0002")}
  end if;
  if decide_quote.decision not in ('accepted', 'rejected', 'changes_requested') then
    ${fail("QUOTE_DECISION_INVALID", "decide accepted, rejected or changes_requested", "22023")}
  end if;
  if ${st(`v_row.${q("status")}`, ["sent", "viewed"], true)} then
    ${fail("QUOTE_NOT_OPEN", "only a sent quote takes a decision", "55000")}
  end if;
  if decide_quote.decision = 'accepted' then
    ${ctx.hook("before_quote_accept", [["uuid", `v_row.${q("id")}`]])}
  end if;${decide("decide_quote.decision", "decide_quote.note", "coalesce(nullif(trim(decide_quote.by), ''), auth.uid()::text)")}
  if decide_quote.decision = 'accepted' then
    ${ctx.hook("after_quote_accept", [["uuid", `v_row.${q("id")}`]])}
  end if;
  return ${row("v_row")};
end;
$$;
${userGrant(`${fn("decide_quote")}(uuid, text, text, text)`)}

-- A new draft of a sent or decided quote with the same number, the next
-- revision and the same lines. The old one is withdrawn unless accepted.
create or replace function ${fn("revise_quote")}(quote uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old ${t("quotes")};
  v_row ${t("quotes")};
begin
  select * into v_old from ${t("quotes")} x where x.${q("id")} = revise_quote.quote and ${editable("x")} for update;
  if v_old.${q("id")} is null then
    ${fail("QUOTE_NOT_FOUND", "no such quote you can edit", "P0002")}
  end if;
  if ${st(`v_old.${q("status")}`, ["draft"])} then
    ${fail("QUOTE_NOT_SENT", "a draft is edited, not revised", "55000")}
  end if;
  if exists (select 1 from ${t("quotes")} x where x.${q("supersedes")} = v_old.${q("id")}) then
    ${fail("QUOTE_ALREADY_REVISED", "this quote already has a newer revision", "55000")}
  end if;
  insert into ${t("quotes")} (${valueLines(
    "    ",
    [
      q("tenant"),
      q("number"),
      q("identifier"),
      q("revision"),
      q("supersedes"),
      q("title"),
      present("companyType", copy("companyType")),
      present("companyId", copy("companyId")),
    ],
    [
      present("contactType", copy("contactType")),
      present("contactId", copy("contactId")),
      q("owner"),
      q("currency"),
      q("validUntil"),
      present("terms", copy("terms")),
      present("note", copy("note")),
      present("originType", copy("originType")),
      present("originId", copy("originId")),
      present("createdBy", copy("createdBy")),
    ],
  )})
  select ${valueLines(
    "    ",
    [
      `x.${q("tenant")}`,
      `x.${q("number")}`,
      `x.${q("identifier")}`,
      `x.${q("revision")} + 1`,
      `x.${q("id")}`,
      `x.${q("title")}`,
      present("companyType", `x.${copy("companyType")}`),
      present("companyId", `x.${copy("companyId")}`),
    ],
    [
      present("contactType", `x.${copy("contactType")}`),
      present("contactId", `x.${copy("contactId")}`),
      `x.${q("owner")}`,
      `x.${q("currency")}`,
      `greatest(x.${q("validUntil")}, current_date + ${String(n.validDays)})`,
      present("terms", `x.${copy("terms")}`),
      present("note", `x.${copy("note")}`),
    ],
    [
      present("originType", `x.${copy("originType")}`),
      present("originId", `x.${copy("originId")}`),
      present("createdBy", "auth.uid()"),
    ],
  )}
  from ${t("quotes")} x where x.${q("id")} = v_old.${q("id")}
  returning * into v_row;${
    n.extras.length === 0
      ? ""
      : `
  update ${t("quotes")} x set ${n.extras.map((extra) => `${extra.ident} = o.${extra.ident}`).join(", ")}
  from ${t("quotes")} o where o.${q("id")} = v_old.${q("id")} and x.${q("id")} = v_row.${q("id")};`
  }
  insert into ${t("lines")} (${lineCopyColumns(ctx, "lines").map(l).join(", ")})
  select ${lineCopyColumns(ctx, "lines")
    .map((column) =>
      column === "parent" ? `v_row.${q("id")}` : `x.${l(column)}`,
    )
    .join(", ")}
  from ${t("lines")} x where x.${l("parent")} = v_old.${q("id")};
  if ${st(`v_old.${q("status")}`, ["accepted"], true)} then
    update ${t("quotes")} x set ${q("status")} = ${sv("withdrawn")}, ${q("tokenHash")} = null, ${q("updatedAt")} = now() where x.${q("id")} = v_old.${q("id")};
  end if;
  ${record("quote.revised", "v_old", `, 'revisionId', v_row.${q("id")}`)}
  return (select ${row("x")} from ${t("quotes")} x where x.${q("id")} = v_row.${q("id")});
end;
$$;
${userGrant(`${fn("revise_quote")}(uuid)`)}

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
${markViewed()}
  return jsonb_build_object(
    'identifier', v_row.${q("identifier")}, 'revision', v_row.${q("revision")}, 'title', v_row.${q("title")},
    'status', ${ctx.label("quotes", "status", `v_row.${q("status")}`)}, 'currency', v_row.${q("currency")}, 'validUntil', v_row.${q("validUntil")},
    'terms', ${or("v_row", "terms")}, 'subtotal', v_row.${q("subtotal")}::text, 'discountTotal', v_row.${q("discountTotal")}::text,
    'taxTotal', v_row.${q("taxTotal")}::text, 'total', v_row.${q("total")}::text, 'lines', ${lines("v_row")});
end;
$$;
revoke all on function ${fn("public_quote")}(text) from public, anon, authenticated;
grant execute on function ${fn("public_quote")}(text) to anon, authenticated, service_role;

-- The customer's answer through the link: accepted, rejected or
-- changes_requested, with their name and a note. A quote past its valid
-- date expires instead.
create or replace function ${fn("respond_to_quote")}(token text, decision text, name text, note text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("quotes")};
  v_claims text;
begin
  select * into v_row from ${t("quotes")} x where x.${q("tokenHash")} = ${sha256Hex("respond_to_quote.token")} for update;
  if v_row.${q("id")} is null then
    ${fail("QUOTE_LINK_INVALID", "this link is not valid", "P0002")}
  end if;
  if respond_to_quote.decision not in ('accepted', 'rejected', 'changes_requested') then
    ${fail("QUOTE_DECISION_INVALID", "answer accepted, rejected or changes_requested", "22023")}
  end if;
  if ${st(`v_row.${q("status")}`, ["sent", "viewed"], true)} then
    ${fail("QUOTE_NOT_OPEN", "this quote no longer takes an answer", "55000")}
  end if;
  if v_row.${q("validUntil")} < current_date then
    update ${t("quotes")} x set ${q("status")} = ${sv("expired")}, ${q("updatedAt")} = now() where x.${q("id")} = v_row.${q("id")}
    returning * into v_row;
    ${record("quote.expired", "v_row")}
    return jsonb_build_object('status', 'expired');
  end if;
  if nullif(trim(respond_to_quote.name), '') is null then
    ${fail("QUOTE_NAME_REQUIRED", "say who answers", "23502")}
  end if;
  if respond_to_quote.decision = 'accepted' then
    ${ctx.hook("before_quote_accept", [["uuid", `v_row.${q("id")}`]])}
  end if;${decide("respond_to_quote.decision", "respond_to_quote.note", "trim(respond_to_quote.name)")}
  if respond_to_quote.decision = 'accepted' then
    ${ctx.hook("after_quote_accept", [["uuid", `v_row.${q("id")}`]])}
  end if;
  return jsonb_build_object('status', ${ctx.label("quotes", "status", `v_row.${q("status")}`)}, 'identifier', v_row.${q("identifier")});
end;
$$;
revoke all on function ${fn("respond_to_quote")}(text, text, text, text) from public, anon, authenticated;
grant execute on function ${fn("respond_to_quote")}(text, text, text, text) to anon, authenticated, service_role;

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
${fromDeal}`;
}
