import type { InvoicesEvents } from "../../blocks/invoices/events.ts";
import type { AccountingSource } from "../accounting-sources-sql.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlTableSpec,
} from "../context.ts";
import type { InvoiceLedger } from "./invoices-ledger.ts";
import type { InvoiceNames } from "./invoices-names.ts";
import type { BlockSqlOperations } from "./permissions-model.ts";

import { bookSource } from "../accounting-sources-sql.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  fail,
  serviceGrant,
  transitionActorSql,
  userGrant,
} from "../shared.ts";
import {
  dunningRunFunctions,
  dunningRunSql,
  hasHandOver,
  hasRuns,
} from "./invoices-dunning-runs.ts";
import { cashCode, paymentKey } from "./invoices-ledger.ts";
import { lockModuleTable } from "./over-app.ts";

/** The invoice columns dunning keeps: the level reached, when, and a pause. */
export const COLLECTION_COLUMNS: readonly string[] = [
  "dunningLevel",
  "dunningAt",
  "dunningPausedUntil",
];

const INVOICE = [
  "organizationId",
  "invoiceId",
  "subjectType",
  "subjectId",
  "identifier",
] as const;

/** The events collections records on an invoice. */
export const COLLECTION_EVENTS: BlockSqlEvents<InvoicesEvents> = {
  "invoice.credit_applied": {
    subject: "invoices",
    payload: [...INVOICE, "paymentId", "partyId", "amount", "balance"],
  },
  "invoice.dunning_escalated": {
    subject: "invoices",
    payload: [
      ...INVOICE,
      "level",
      "templateKey",
      "textKey",
      "fee",
      "final",
      "balance",
      "dueOn",
    ],
  },
  "invoice.dunning_paused": {
    subject: "invoices",
    payload: [...INVOICE, "until", "reason"],
  },
  "invoice.collection_started": {
    subject: "invoices",
    payload: [...INVOICE, "agencyPartyId", "balance", "level"],
  },
};

/** The `invoice_dunning_levels` table: an organization's reminder steps. */
export const DUNNING_LEVELS_TABLE: BlockSqlTableSpec = {
  name: "invoice_dunning_levels",
  app: {},
  optionalTable: true,
  lifecycle: { tenant: "tenant", export: true },
  columns: {
    id: "id",
    tenant: "tenant_id",
    level: "level",
    daysAfterDue: "days_after_due",
    templateKey: "template_key",
    textKey: "text_key",
    fee: "fee",
    final: "final",
    createdAt: "created_at",
    updatedAt: "updated_at",
  },
  optional: ["textKey"],
};

/** What collections adds to the invoice names. */
export interface CollectionNames {
  /** `invoices.collect`: pauses and resumes an invoice's dunning. */
  readonly collect: string;
}

export function collectionNames(
  ctx: BlockSqlContext,
  keys: BlockSqlOperations<"invoices">,
): CollectionNames {
  return { collect: ctx.permission("collect", keys.collect) };
}

/** Whether the invoices table and the levels table can run dunning. */
function hasDunning(ctx: BlockSqlContext): boolean {
  return (
    ctx.hasTable("dunningLevels") &&
    COLLECTION_COLUMNS.every((column) => ctx.has("invoices", column))
  );
}

/** The party columns an invoice names its customer by. */
const partyColumns = (ctx: BlockSqlContext): readonly string[] =>
  ["companyId", "contactId"].filter((column) => ctx.has("invoices", column));

/** Whether payments can be recorded for a party: the table names one. */
function hasPartyCredit(ctx: BlockSqlContext): boolean {
  return partyColumns(ctx).length > 0;
}

/** The code of a party's credit account in one currency. */
const creditCode = (party: string, currency: string): string =>
  `'invoices:credit:' || ${party} || ':' || ${currency}`;

/**
 * The invoice columns collections adds, as `create table` column lines.
 * `column` leaves out the ones the app's table maps to null.
 */
export function collectionColumnsSql(
  column: (logical: string, definition: string) => string,
): string {
  return `${column("dunningLevel", "integer not null default 0")}${column("dunningAt", "timestamptz")}${column("dunningPausedUntil", "date")}`;
}

/** The levels table, its index and its read policy. */
export function dunningTableSql(ctx: BlockSqlContext, read: string): string {
  if (!ctx.hasTable("dunningLevels")) {
    return "";
  }

  const t = ctx.table("dunningLevels");
  const d = (column: string): string => ctx.col("dunningLevels", column);

  return `
create table if not exists ${t} (
  ${d("id")} uuid primary key default gen_random_uuid(),
  ${d("tenant")} ${ctx.idType} not null,
  ${d("level")} integer not null check (${d("level")} between 1 and 20),
  ${d("daysAfterDue")} integer not null check (${d("daysAfterDue")} >= 0),
  ${d("templateKey")} text not null check (length(${d("templateKey")}) between 1 and 200),${ctx.has("dunningLevels", "textKey") ? `\n  ${d("textKey")} text check (length(${d("textKey")}) between 1 and 200),` : ""}
  ${d("fee")} bigint not null default 0 check (${d("fee")} >= 0),
  ${d("final")} boolean not null default false,
  ${d("createdAt")} timestamptz not null default now(),
  ${d("updatedAt")} timestamptz not null default now(),
  unique (${d("tenant")}, ${d("level")})
);
${lockModuleTable(ctx, "dunningLevels", { read: true })}
${renderPolicy(
  makePolicy({
    table: t,
    name: ctx.naming.rename("invoice_dunning_levels_read"),
    command: "select",
    roles: ["authenticated"],
    using: ctx.scope.check(d("tenant"), read),
  }),
  { drop: true, target: t },
)}
`;
}

/** The helpers of `invoiceFunctions` collections builds on. */
export interface CollectionHelpers {
  readonly i: (column: string) => string;
  readonly can: (alias: string, permission: string) => string;
  readonly st: (
    value: string,
    labels: readonly string[],
    negate?: boolean,
  ) => string;
  readonly kd: (
    value: string,
    labels: readonly string[],
    negate?: boolean,
  ) => string;
  readonly balance: (alias: string) => string;
  readonly row: (alias: string) => string;
  readonly record: (
    type: string,
    alias: string,
    extra?: string,
    audit?: boolean,
  ) => string;
  readonly settle: (alias: string) => string;
  readonly ledger: InvoiceLedger;
  /** Whether the invoices block has its charges table, for dunning fees. */
  readonly charges: boolean;
}

/**
 * Collections on invoices: a payment from a party split over its invoices, the
 * rest kept as credit on a ledger account (`invoices:credit:<party>:<CUR>`)
 * that later invoices draw on, and dunning: reminder levels per organization
 * that `run_invoice_dunning` raises an overdue invoice through.
 */
export function invoiceCollections(
  ctx: BlockSqlContext,
  n: InvoiceNames,
  h: CollectionHelpers,
): string {
  return `${partyCreditSql(ctx, n, h)}${dunningSql(ctx, n, h)}`;
}

function partyCreditSql(
  ctx: BlockSqlContext,
  n: InvoiceNames,
  h: CollectionHelpers,
): string {
  if (!hasPartyCredit(ctx)) {
    return "";
  }

  const { fn, t } = n;
  const { i } = h;
  const ledger = ctx.of("ledger");
  const la = (column: string): string => ledger.col("accounts", column);
  const le = (column: string): string => ledger.col("entries", column);
  const tx = (column: string): string => ledger.col("transactions", column);
  const accounts = ledger.table("accounts");
  const entries = ledger.table("entries");
  const sales = ctx.has("invoices", "direction");

  const allowed = (tenant: string, permission: string): string =>
    `(${n.service} or ${ctx.scope.can(tenant, permission)})`;

  // Whether the invoice row `alias` is the party's.
  const ofParty = (alias: string, party: string): string =>
    `(${partyColumns(ctx)
      .map((column) => `${alias}.${i(column)}::text = ${party}`)
      .join(" or ")})`;

  const isSales = (alias: string): string =>
    sales ? ` and ${alias}.${i("direction")} = 'sales'` : "";

  // What a credit account holds: the negated balance of its entries.
  const available = (account: string): string =>
    `coalesce(-(select sum(e.${le("amount")}) from ${entries} e where e.${le("account")} = ${account}), 0)`;

  const creditAccount = (
    tenant: string,
    party: string,
    currency: string,
  ): string =>
    `${ledger.fn("ledger_account_for")}(${tenant}, 'credit', ${creditCode(party, currency)},
      'Credit ' || ${party} || ' ' || ${currency}, ${currency}, 0::smallint, 'invoice_party', ${party},
      null, true, ${n.read}, 'invoices', null)`;

  const cashAccount = (tenant: string, currency: string): string =>
    `${ledger.fn("ledger_account_for")}(${tenant}, 'cash', ${cashCode(currency)},
      'Invoice payments ' || ${currency}, ${currency}, 0::smallint, null, null,
      null, true, ${n.read}, 'invoices', null)`;

  const partyInvalid = (party: string): string => `
  if nullif(trim(${party}), '') is null or length(${party}) > 150 then
    ${fail("INVOICE_PARTY_INVALID", "a party id is a non-empty text of at most 150 characters", "22023")}
  end if;`;

  return `
-- A party's unallocated payments, per currency: what record_party_payment
-- kept as credit, less what apply_party_credit drew on.
create or replace function ${fn("list_party_credits")}(tenant ${ctx.idType}, party_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${allowed("list_party_credits.tenant", n.read)} then
    ${fail("INVOICE_FORBIDDEN", "not allowed to read this organization's invoices", "42501")}
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('currency', a.${la("unit")}, 'amount', ${available(`a.${la("id")}`)}::text) order by a.${la("unit")})
    from ${accounts} a
    where a.${la("tenant")} = list_party_credits.tenant and a.${la("managedBy")} = 'invoices'
      and a.${la("holderType")} = 'invoice_party' and a.${la("holderId")} = list_party_credits.party_id
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_party_credits")}(${ctx.idType}, text)`)}

-- Records one payment from a party over several of its invoices.
-- allocations: [{ invoiceId, amount }], each recorded as a payment of that
-- invoice with the reference "<reference>/<invoiceId>". What the allocations
-- leave over becomes the party's credit in the payment's currency. The
-- reference is required and unique per organization, so recording the same
-- payment twice adds it once.
create or replace function ${fn("record_party_payment")}(tenant ${ctx.idType}, party_id text, amount bigint, currency text, allocations jsonb, received_on date, reference text, method text default null, note text default null, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_currency text := upper(record_party_payment.currency);
  v_reference text := nullif(trim(record_party_payment.reference), '');
  v_allocations jsonb := coalesce(record_party_payment.allocations, '[]'::jsonb);
  v_paid_at timestamptz := coalesce(record_party_payment.received_on::timestamptz, now());
  v_allocated bigint := 0;
  v_remainder bigint;
  v_alloc record;
  v_row ${t("invoices")};
  v_credit uuid;
  v_key text;
begin
  if not ${allowed("record_party_payment.tenant", n.payment)} then
    ${fail("INVOICE_FORBIDDEN", "not allowed to record payments in this organization", "42501")}
  end if;${partyInvalid("record_party_payment.party_id")}
  if coalesce(record_party_payment.amount, 0) <= 0 then
    ${fail("INVOICE_PAYMENT_INVALID", "a party payment has a positive amount", "22023")}
  end if;
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    ${fail("INVOICE_CURRENCY_INVALID", "currency is a three-letter ISO 4217 code", "22023")}
  end if;
  if v_reference is null then
    ${fail("INVOICE_PAYMENT_REFERENCE_REQUIRED", "a party payment needs a reference, such as the bank transaction id", "22023")}
  end if;
  if jsonb_typeof(v_allocations) <> 'array' or exists (
    select 1 from jsonb_array_elements(v_allocations) x
    where jsonb_typeof(x.value) <> 'object'
      or coalesce(x.value ->> 'invoiceId', '') !~ '^[0-9a-fA-F-]{36}$'
      or coalesce(x.value ->> 'amount', '') !~ '^[0-9]{1,18}$'
      or (x.value ->> 'amount')::bigint = 0
  ) or (
    select count(*) <> count(distinct x.value ->> 'invoiceId') from jsonb_array_elements(v_allocations) x
  ) then
    ${fail("INVOICE_ALLOCATIONS_INVALID", "allocations is an array of { invoiceId, amount } with a positive amount, one per invoice", "22023")}
  end if;
  select coalesce(sum((x.value ->> 'amount')::bigint), 0) into v_allocated from jsonb_array_elements(v_allocations) x;
  if v_allocated > record_party_payment.amount then
    ${fail("INVOICE_ALLOCATIONS_TOO_LARGE", "the allocations add up to more than the payment", "23514")}
  end if;
  ${transitionActorSql("record_party_payment.actor", "INVOICE_ACTOR_INVALID")}
  for v_alloc in
    select (x.value ->> 'invoiceId')::uuid as invoice, (x.value ->> 'amount')::bigint as amount
    from jsonb_array_elements(v_allocations) with ordinality x
    order by x.ordinality
  loop
    select * into v_row from ${t("invoices")} x
    where x.${i("id")} = v_alloc.invoice and x.${i("tenant")} = record_party_payment.tenant
      and ${ofParty("x", "record_party_payment.party_id")}${isSales("x")};
    if v_row.${i("id")} is null then
      ${fail("INVOICE_NOT_FOUND", "an allocation names no invoice of this party", "P0002")}
    end if;
    if v_alloc.amount > ${h.balance("v_row")} and not exists (
      select 1 from ${ledger.table("transactions")} y
      where y.${tx("tenant")} = v_row.${i("tenant")} and y.${tx("key")} = ${paymentKey("(v_reference || '/' || v_alloc.invoice::text)")}
    ) then
      ${fail("INVOICE_ALLOCATION_TOO_LARGE", "an allocation is more than the invoice's balance; keep the rest as credit", "23514")}
    end if;
    perform ${fn("record_invoice_payment")}(v_alloc.invoice, v_alloc.amount, v_currency, v_paid_at,
      record_party_payment.method, v_reference || '/' || v_alloc.invoice::text,
      record_party_payment.note, record_party_payment.actor, null);
  end loop;
  v_remainder := record_party_payment.amount - v_allocated;
  v_key := 'invoice-party-payment:' || v_reference;
  if v_remainder > 0 then
    select y.${tx("id")} into v_credit from ${ledger.table("transactions")} y
    where y.${tx("tenant")} = record_party_payment.tenant and y.${tx("key")} = v_key;
    if v_credit is null then
      v_credit := ${ledger.fn("ledger_post")}(record_party_payment.tenant, 'invoice.party_payment',
        jsonb_build_array(
          jsonb_build_object('account', ${cashAccount("record_party_payment.tenant", "v_currency")}, 'amount', v_remainder),
          jsonb_build_object('account', ${creditAccount("record_party_payment.tenant", "record_party_payment.party_id", "v_currency")}, 'amount', -v_remainder)),
        'invoices', record_party_payment.party_id, null, v_key, v_paid_at,
        jsonb_strip_nulls(jsonb_build_object('partyId', record_party_payment.party_id, 'currency', v_currency,
          'method', record_party_payment.method, 'reference', v_reference, 'note', nullif(trim(record_party_payment.note), ''))));
      ${bookSource(ctx, "invoice_party_payment", "v_credit")}
    end if;
  end if;
  return jsonb_build_object(
    'partyId', record_party_payment.party_id,
    'currency', v_currency,
    'amount', record_party_payment.amount::text,
    'allocated', v_allocated::text,
    'credited', v_remainder::text,
    'creditTransactionId', v_credit,
    'credit', ${available(`(select a.${la("id")} from ${accounts} a where a.${la("tenant")} = record_party_payment.tenant and a.${la("code")} = ${creditCode("record_party_payment.party_id", "v_currency")})`)}::text
  );
end;
$$;
${userGrant(`${fn("record_party_payment")}(${ctx.idType}, text, bigint, text, jsonb, date, text, text, text, jsonb)`)}

-- Pays part or all of an open invoice from its party's credit in the
-- invoice's currency, as a ledger transaction from the receivable to the
-- credit account. It shows among the invoice's payments with method credit.
create or replace function ${fn("apply_party_credit")}(party_id text, invoice uuid, amount bigint, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("invoices")};
  v_account uuid;
  v_payment uuid;
  v_was text;
begin
  select * into v_row from ${t("invoices")} x where x.${i("id")} = apply_party_credit.invoice and ${h.can("x", n.payment)} for update;
  if v_row.${i("id")} is null then
    ${fail("INVOICE_NOT_FOUND", "no such invoice you can edit", "P0002")}
  end if;
  if not ${ofParty("v_row", "apply_party_credit.party_id")} then
    ${fail("INVOICE_PARTY_MISMATCH", "the invoice isn't this party's", "22023")}
  end if;
  if ${h.kd(`v_row.${i("kind")}`, ["invoice"], true)} or ${h.st(`v_row.${i("status")}`, ["issued", "partially_paid"], true)}${sales ? ` or v_row.${i("direction")} <> 'sales'` : ""} then
    ${fail("INVOICE_NOT_PAYABLE", "only an open sales invoice takes credit", "55000")}
  end if;
  if coalesce(apply_party_credit.amount, 0) <= 0 then
    ${fail("INVOICE_PAYMENT_INVALID", "credit is applied in a positive amount", "22023")}
  end if;
  if apply_party_credit.amount > ${h.balance("v_row")} then
    ${fail("INVOICE_CREDIT_TOO_LARGE", "the amount is more than the invoice's balance", "23514")}
  end if;
  select a.${la("id")} into v_account from ${accounts} a
  where a.${la("tenant")} = v_row.${i("tenant")} and a.${la("code")} = ${creditCode("apply_party_credit.party_id", `v_row.${i("currency")}`)}
  for update;
  if v_account is null or apply_party_credit.amount > ${available("v_account")} then
    ${fail("INVOICE_CREDIT_INSUFFICIENT", "the party doesn't have this much credit in the invoice's currency", "23514")}
  end if;
  ${transitionActorSql("apply_party_credit.actor", "INVOICE_ACTOR_INVALID")}
  v_was := v_row.${i("status")};
  v_payment := ${ledger.fn("ledger_post")}(v_row.${i("tenant")}, 'invoice.credit_applied',
    jsonb_build_array(
      jsonb_build_object('account', ${h.ledger.receivable("v_row")}, 'amount', -apply_party_credit.amount),
      jsonb_build_object('account', v_account, 'amount', apply_party_credit.amount)),
    'invoices', v_row.${i("id")}::text, null, null, now(),
    jsonb_build_object('invoiceId', v_row.${i("id")}, 'method', 'credit', 'partyId', apply_party_credit.party_id));${h.settle("v_row")}
  ${h.record("invoice.credit_applied", "v_row", `, 'paymentId', v_payment, 'partyId', apply_party_credit.party_id, 'amount', apply_party_credit.amount::text, 'balance', ${h.balance("v_row")}::text`, true)}
  if ${h.st(`v_row.${i("status")}`, ["paid"])} and ${h.st("v_was", ["paid"], true)} then
    ${h.record("invoice.paid", "v_row", `, 'total', v_row.${i("total")}::text`)}
  end if;
  return ${h.row("v_row")};
end;
$$;
${userGrant(`${fn("apply_party_credit")}(text, uuid, bigint, jsonb)`)}
`;
}

function dunningSql(
  ctx: BlockSqlContext,
  n: InvoiceNames,
  h: CollectionHelpers,
): string {
  if (!hasDunning(ctx)) {
    return "";
  }

  const { fn, t } = n;
  const { i } = h;
  const levels = ctx.table("dunningLevels");
  const d = (column: string): string => ctx.col("dunningLevels", column);
  const sales = ctx.has("invoices", "direction");

  const partyExpression = `coalesce(${
    partyColumns(ctx)
      .map((column) => `v_row.${i(column)}::text`)
      .join(", ") || "null"
  })`;

  const run = dunningRunSql(ctx, h, partyExpression);

  const allowed = (tenant: string, permission: string): string =>
    `(${n.service} or ${ctx.scope.can(tenant, permission)})`;

  const hasText = ctx.has("dunningLevels", "textKey");

  const textKey = (alias: string): string =>
    hasText ? `${alias}.${d("textKey")}` : "null::text";

  const levelJson = (alias: string): string =>
    `jsonb_build_object('level', ${alias}.${d("level")}, 'daysAfterDue', ${alias}.${d("daysAfterDue")}, 'templateKey', ${alias}.${d("templateKey")}, 'textKey', ${textKey(alias)}, 'fee', ${alias}.${d("fee")}::text, 'final', ${alias}.${d("final")})`;

  const listLevels = (tenant: string): string =>
    `coalesce((select jsonb_agg(${levelJson("l")} order by l.${d("level")}) from ${levels} l where l.${d("tenant")} = ${tenant}), '[]'::jsonb)`;

  // The highest level an overdue invoice has reached and not yet been sent.
  const due = (alias: string, today: string): string =>
    `from ${levels} l where l.${d("tenant")} = ${alias}.${i("tenant")} and l.${d("level")} > ${alias}.${i("dunningLevel")} and ${alias}.${i("dueOn")} + l.${d("daysAfterDue")} <= ${today}`;

  const notify =
    ctx.installed("notifications") && ctx.has("invoices", "createdBy")
      ? `
    if v_row.${i("createdBy")} is not null then
      ${ctx.notify(
        `jsonb_build_object(
        'type', 'invoice.dunning_escalated',
        'tenant', v_row.${i("tenant")},
        'actor', null,
        'subject_type', 'invoice',
        'subject_id', v_row.${i("id")}::text,
        'summary', coalesce(v_row.${i("identifier")}, v_row.${i("title")}) || ' reached reminder level ' || v_level.${d("level")},
        'recipients', to_jsonb(array[v_row.${i("createdBy")}]),
        'key', 'invoice.dunning_escalated:' || v_row.${i("id")}::text || ':' || v_level.${d("level")},
        'data', jsonb_build_object('level', v_level.${d("level")}, 'templateKey', v_level.${d("templateKey")}, 'final', v_level.${d("final")})
      )`,
        { indent: "      " },
      )}
    end if;`
      : "";

  const fee = h.charges
    ? `
    if v_level.${d("fee")} > 0 then
      perform ${fn("add_invoice_charge")}(invoice => v_row.${i("id")}, amount => v_level.${d("fee")}, currency => v_row.${i("currency")}::text,
        description => 'Reminder fee, level ' || v_level.${d("level")});
      select * into v_row from ${t("invoices")} x where x.${i("id")} = v_row.${i("id")};
    end if;`
    : "";

  return `
create or replace function ${fn("list_invoice_dunning_levels")}(tenant ${ctx.idType})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${allowed("list_invoice_dunning_levels.tenant", n.read)} then
    ${fail("INVOICE_FORBIDDEN", "not allowed to read this organization's invoices", "42501")}
  end if;
  return ${listLevels("list_invoice_dunning_levels.tenant")};
end;
$$;
${userGrant(`${fn("list_invoice_dunning_levels")}(${ctx.idType})`)}

-- Replaces an organization's reminder levels. levels: [{ daysAfterDue,
-- templateKey, textKey, fee, final }], numbered 1, 2, ... in order, with daysAfterDue
-- rising. fee: minor units of the invoice's currency, added as a charge when
-- the level is reached. Only the last level can be final.
create or replace function ${fn("set_invoice_dunning_levels")}(tenant ${ctx.idType}, levels jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not ${allowed("set_invoice_dunning_levels.tenant", n.manage)} then
    ${fail("INVOICE_FORBIDDEN", "not allowed to manage this organization's invoices", "42501")}
  end if;
  if jsonb_typeof(set_invoice_dunning_levels.levels) is distinct from 'array'
    or jsonb_array_length(set_invoice_dunning_levels.levels) > 20
    or exists (
      select 1 from jsonb_array_elements(set_invoice_dunning_levels.levels) with ordinality x
      where jsonb_typeof(x.value) <> 'object'
        or coalesce(x.value ->> 'daysAfterDue', '') !~ '^[0-9]{1,5}$'
        or length(coalesce(trim(x.value ->> 'templateKey'), '')) not between 1 and 200
        or length(coalesce(nullif(trim(x.value ->> 'textKey'), ''), 'x')) not between 1 and 200
        or coalesce(x.value ->> 'fee', '0') !~ '^[0-9]{1,18}$'
        or jsonb_typeof(coalesce(x.value -> 'final', 'false'::jsonb)) <> 'boolean'
        or ((x.value ->> 'final')::boolean is true and x.ordinality < jsonb_array_length(set_invoice_dunning_levels.levels))
    ) then
    ${fail("INVOICE_DUNNING_LEVELS_INVALID", "levels is an array of at most 20 { daysAfterDue, templateKey, fee, final }, and only the last is final", "22023")}
  end if;
  if exists (
    select 1 from (
      select (x.value ->> 'daysAfterDue')::integer as days,
        lag((x.value ->> 'daysAfterDue')::integer) over (order by x.ordinality) as before
      from jsonb_array_elements(set_invoice_dunning_levels.levels) with ordinality x
    ) s where s.days <= s.before
  ) then
    ${fail("INVOICE_DUNNING_LEVELS_INVALID", "each level comes more days after the due date than the one before", "22023")}
  end if;${
    h.charges
      ? ""
      : `
  if exists (select 1 from jsonb_array_elements(set_invoice_dunning_levels.levels) x where coalesce((x.value ->> 'fee')::bigint, 0) > 0) then
    ${fail("INVOICE_DUNNING_FEE_UNSUPPORTED", "a reminder fee needs the invoice_charges table", "22023")}
  end if;`
  }
  delete from ${levels} l where l.${d("tenant")} = set_invoice_dunning_levels.tenant;
  insert into ${levels} (${d("tenant")}, ${d("level")}, ${d("daysAfterDue")}, ${d("templateKey")}${hasText ? `, ${d("textKey")}` : ""}, ${d("fee")}, ${d("final")})
  select set_invoice_dunning_levels.tenant, x.ordinality, (x.value ->> 'daysAfterDue')::integer, trim(x.value ->> 'templateKey'),${hasText ? "\n    nullif(trim(x.value ->> 'textKey'), '')," : ""}
    coalesce((x.value ->> 'fee')::bigint, 0), coalesce((x.value ->> 'final')::boolean, false)
  from jsonb_array_elements(set_invoice_dunning_levels.levels) with ordinality x;
  return ${listLevels("set_invoice_dunning_levels.tenant")};
end;
$$;
${userGrant(`${fn("set_invoice_dunning_levels")}(${ctx.idType}, jsonb)`)}

-- Raises each overdue invoice with a balance to the highest reminder level it
-- has reached (one organization, or all), adds the level's fee as a charge,
-- notifies who created the invoice and records invoice.dunning_escalated with
-- the level's template key, for a sink that sends the reminder. Each
-- organization's invoices go into one run (invoice_dunning_runs) with the
-- items picked per customer and a history row per invoice. Invoices paused
-- until today or later, and invoices handed over to collection, wait. Returns how many invoices moved up.
create or replace function ${fn("run_invoice_dunning")}(tenant ${ctx.idType} default null, as_of date default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := coalesce(run_invoice_dunning.as_of, current_date);
  v_row ${t("invoices")};
  v_level ${levels};
  v_count integer := 0;${run.declare}${ctx.installed("notifications") ? "\n  v_claims text;" : ""}
begin
  for v_row in
    select x.* from ${t("invoices")} x
    where (run_invoice_dunning.tenant is null or x.${i("tenant")} = run_invoice_dunning.tenant)
      and ${h.kd(`x.${i("kind")}`, ["invoice"])} and ${h.st(`x.${i("status")}`, ["issued", "partially_paid"])}${sales ? ` and x.${i("direction")} = 'sales'` : ""}
      and x.${i("dueOn")} < v_today${hasHandOver(ctx) ? `\n      and x.${i("collectionStatus")} is null` : ""}
      and (x.${i("dunningPausedUntil")} is null or x.${i("dunningPausedUntil")} < v_today)
      and ${h.balance("x")} > 0
      and exists (select 1 ${due("x", "v_today")})
    order by x.${i("tenant")}, x.${i("dueOn")}, x.${i("id")}
    for update of x skip locked
  loop
    select l.* into v_level ${due("v_row", "v_today")} order by l.${d("level")} desc limit 1;
    update ${t("invoices")} x set
      ${i("dunningLevel")} = v_level.${d("level")},
      ${i("dunningAt")} = now(),
      ${i("updatedAt")} = now()
    where x.${i("id")} = v_row.${i("id")}
    returning * into v_row;${fee}${notify}
    ${h.record("invoice.dunning_escalated", "v_row", `, 'level', v_level.${d("level")}, 'templateKey', v_level.${d("templateKey")}, 'textKey', ${hasText ? `v_level.${d("textKey")}` : "null::text"}, 'fee', v_level.${d("fee")}::text, 'final', v_level.${d("final")}, 'balance', ${h.balance("v_row")}::text, 'dueOn', v_row.${i("dueOn")}`, true)}
${run.record}
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("run_invoice_dunning")}(${ctx.idType}, date)`)}

-- Holds an invoice's reminders until a date, such as while the customer
-- disputes it; until null resumes them. reason: why, for the audit log.
create or replace function ${fn("pause_invoice_dunning")}(invoice uuid, until date, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("invoices")};
begin
  select * into v_row from ${t("invoices")} x where x.${i("id")} = pause_invoice_dunning.invoice and ${h.can("x", n.collect)} for update;
  if v_row.${i("id")} is null then
    ${fail("INVOICE_NOT_FOUND", "no such invoice you can edit", "P0002")}
  end if;
  if pause_invoice_dunning.until < current_date then
    ${fail("INVOICE_DUNNING_PAUSE_INVALID", "a pause lasts until today or later", "22023")}
  end if;
  if length(pause_invoice_dunning.reason) > 2000 then
    ${fail("INVOICE_DUNNING_PAUSE_INVALID", "a reason is at most 2000 characters", "22023")}
  end if;
  update ${t("invoices")} x set
    ${i("dunningPausedUntil")} = pause_invoice_dunning.until,
    ${i("updatedAt")} = now()
  where x.${i("id")} = v_row.${i("id")}
  returning * into v_row;
  ${h.record("invoice.dunning_paused", "v_row", ", 'until', pause_invoice_dunning.until, 'reason', nullif(trim(pause_invoice_dunning.reason), '')", true)}
  return ${h.row("v_row")};
end;
$$;
${userGrant(`${fn("pause_invoice_dunning")}(uuid, date, text)`)}
${dunningRunFunctions(ctx, n, h)}`;
}

/** The functions collections adds to the invoices contract. */
export function collectionContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  return [
    ...(hasPartyCredit(ctx)
      ? [
          {
            name: "list_party_credits",
            args: ["{id}", "text"],
            returns: "jsonb",
          },
          {
            name: "record_party_payment",
            args: [
              "{id}",
              "text",
              "bigint",
              "text",
              "jsonb",
              "date",
              "text",
              "text",
              "text",
              "jsonb",
            ],
            returns: "jsonb",
          },
          {
            name: "apply_party_credit",
            args: ["text", "uuid", "bigint", "jsonb"],
            returns: "jsonb",
          },
        ]
      : []),
    ...(hasDunning(ctx)
      ? [
          {
            name: "list_invoice_dunning_levels",
            args: ["{id}"],
            returns: "jsonb",
          },
          {
            name: "set_invoice_dunning_levels",
            args: ["{id}", "jsonb"],
            returns: "jsonb",
          },
          {
            name: "run_invoice_dunning",
            args: ["{id}", "date"],
            returns: "integer",
          },
          {
            name: "pause_invoice_dunning",
            args: ["uuid", "date", "text"],
            returns: "jsonb",
          },
        ]
      : []),
    ...(hasRuns(ctx)
      ? [
          {
            name: "list_invoice_dunning_runs",
            args: ["{id}", "integer"],
            returns: "jsonb",
          },
          {
            name: "list_invoice_dunning_run_items",
            args: ["uuid"],
            returns: "jsonb",
          },
          {
            name: "list_invoice_dunning_history",
            args: ["uuid"],
            returns: "jsonb",
          },
        ]
      : []),
    ...(hasHandOver(ctx)
      ? [
          {
            name: "hand_over_to_collection",
            args: ["uuid[]", "text", "text"],
            returns: "jsonb",
          },
        ]
      : []),
  ];
}

/**
 * The accounting source of a party payment's unallocated rest: bank against the
 * party's receivable, so the customer's balance in the books drops when the
 * money arrives, not when its credit is applied to an invoice.
 */
export function partyPaymentSource(
  ctx: BlockSqlContext,
): readonly AccountingSource[] {
  if (!hasPartyCredit(ctx)) {
    return [];
  }

  const ledger = ctx.of("ledger");
  const tx = (column: string): string => ledger.col("transactions", column);
  const le = (column: string): string => ledger.col("entries", column);
  const la = (column: string): string => ledger.col("accounts", column);

  return [
    {
      source: "invoice_party_payment",
      journal: "bank",
      fn: "accounting_invoice_party_payment_lines",
      comment:
        "The entry of a party payment's unallocated rest for accounting: bank against\nthe party's receivable.",
      body: `  select jsonb_build_object(
    'organizationId', y.${tx("tenant")},
    'entryDate', (y.${tx("effectiveAt")} at time zone 'UTC')::date,
    'currency', y.${tx("metadata")} ->> 'currency',
    'reference', y.${tx("metadata")} ->> 'reference',
    'memo', 'Payment on account',
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'bank', 'debit', p.amount::text),
      jsonb_build_object('role', 'receivable', 'credit', p.amount::text, 'partyId', y.${tx("metadata")} ->> 'partyId'))
  )
  from ${ledger.table("transactions")} y
  cross join lateral (
    select sum(e.${le("amount")}) as amount from ${ledger.table("entries")} e
    join ${ledger.table("accounts")} a on a.${la("id")} = e.${le("account")}
    where e.${le("transaction")} = y.${tx("id")} and a.${la("code")} = ${cashCode(`(y.${tx("metadata")} ->> 'currency')`)}
  ) p
  where y.${tx("id")}::text = source_id and y.${tx("referenceType")} = 'invoices'
    and y.${tx("metadata")} ? 'partyId' and not y.${tx("metadata")} ? 'invoiceId' and p.amount <> 0`,
    },
  ];
}
