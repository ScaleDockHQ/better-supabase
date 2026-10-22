import type { ModuleContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { assignNumberSql } from "../numbering-sql.ts";
import {
  extraFieldsArg,
  extraFieldsJson,
  fail,
  pageSize,
  SERVICE_CALLER,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import { subjectInTenant } from "../subject-check-sql.ts";
import { moduleOperations } from "./access-model.ts";

const step = (frequency: string): string =>
  `(case ${frequency} when 'weekly' then interval '1 week' when 'monthly' then interval '1 month' when 'quarterly' then interval '3 months' else interval '1 year' end)`;

/** The keys the gift reads return next to the extra columns. */
export const GIFT_RESERVED = ["fields"] as const;

/** The donations module's functions. */
export function donationsFunctions(ctx: ModuleContext): string {
  const ledger = ctx.of("ledger");
  const funds = ctx.table("funds");
  const pledges = ctx.table("pledges");
  const receipts = ctx.table("receipts");
  const donations = ctx.table("donations");
  const f = (column: string): string => ctx.col("funds", column);
  const p = (column: string): string => ctx.col("pledges", column);
  const r = (column: string): string => ctx.col("receipts", column);
  const d = (column: string): string => ctx.col("donations", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const extras = ctx.extraColumns("donations", GIFT_RESERVED);
  const extra = extraFieldsArg(extras);
  const ops = moduleOperations("donations");
  const read = ctx.permission("read", ops.read);
  const manage = ctx.permission("manage", ops.manage);
  const e = (name: string): string => ctx.resolved.entityNaming.rename(name);

  const fundType =
    ctx.resolved.entities["donation_fund"]?.to.singular ?? "donation_fund";

  const giftKey = sqlString(e("donationId"));

  const can = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`;

  const forbidden = (message: string): string =>
    fail("DONATIONS_FORBIDDEN", message);

  const invalid = (code: string, message: string): string =>
    fail(code, message, "22023");

  const giftNotFound = fail(
    "DONATION_NOT_FOUND",
    "no such gift you can read",
    "P0002",
  );

  const donorCheck = (type: string, id: string, tenant: string): string => `
  if ${type} is null or ${id} is null or not ${subjectInTenant(ctx, type, id, tenant)} then
    ${invalid("DONATION_DONOR_INVALID", "the donor is unknown or not in this organization")}
  end if;`;

  const moneyCheck = (amount: string, currency: string): string => `
  if ${amount} is null or ${amount} <= 0 then
    ${invalid("DONATION_AMOUNT_INVALID", "an amount is more than zero minor units")}
  end if;
  if ${currency} is null or ${currency} !~ '^[A-Z]{3}$' then
    ${invalid("DONATION_AMOUNT_INVALID", "currency must be a three-letter currency code")}
  end if;`;

  const fundCheck = (fund: string, tenant: string): string => `
  if ${fund} is not null and not exists (
    select 1 from ${funds} y where y.${f("id")} = ${fund} and y.${f("tenant")} = ${tenant} and y.${f("archivedAt")} is null
  ) then
    ${invalid("DONATION_FUND_INVALID", "the fund is unknown, archived or not in this organization")}
  end if;`;

  const raised = (row: string): string =>
    `case when ${row}.${f("currency")} is null then null else coalesce((select sum(g.${d("amount")}) from ${donations} g where g.${d("fund")} = ${row}.${f("id")} and g.${d("status")} = 'posted' and g.${d("currency")} = ${row}.${f("currency")}), 0)::text end`;

  const fundJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${f("id")}, 'organizationId', ${row}.${f("tenant")}, 'key', ${row}.${f("key")}, 'name', ${row}.${f("name")}, 'kind', ${row}.${f("kind")}, 'goal', ${row}.${f("goal")}::text, 'currency', ${row}.${f("currency")}, 'raised', ${raised(row)}, 'startsOn', ${row}.${f("startsOn")}, 'endsOn', ${row}.${f("endsOn")}, 'archivedAt', ${row}.${f("archivedAt")}, 'createdAt', ${row}.${f("createdAt")}, 'updatedAt', ${row}.${f("updatedAt")})`;

  const pledgeJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${p("id")}, 'organizationId', ${row}.${p("tenant")}, 'donorType', ${row}.${p("donorType")}, 'donorId', ${row}.${p("donorId")}, 'fundId', ${row}.${p("fund")}, 'amount', ${row}.${p("amount")}::text, 'currency', ${row}.${p("currency")}, 'frequency', ${row}.${p("frequency")}, 'startsOn', ${row}.${p("startsOn")}, 'endsOn', ${row}.${p("endsOn")}, 'status', ${row}.${p("status")}, 'provider', ${row}.${p("provider")}, 'providerCustomer', ${row}.${p("providerCustomer")}, 'note', ${row}.${p("note")}, 'createdBy', ${row}.${p("createdBy")}, 'createdAt', ${row}.${p("createdAt")}, 'updatedAt', ${row}.${p("updatedAt")})`;

  const giftJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${d("id")}, 'organizationId', ${row}.${d("tenant")}, 'donorType', ${row}.${d("donorType")}, 'donorId', ${row}.${d("donorId")}, 'fundId', ${row}.${d("fund")}, 'pledgeId', ${row}.${d("pledge")}, 'periodStart', ${row}.${d("periodStart")}, 'amount', ${row}.${d("amount")}::text, 'currency', ${row}.${d("currency")}, 'receivedOn', ${row}.${d("receivedOn")}, 'method', ${row}.${d("method")}, 'status', ${row}.${d("status")}, 'provider', ${row}.${d("provider")}, 'paymentReference', ${row}.${d("paymentReference")}, 'transactionId', ${row}.${d("transaction")}, 'refundTransactionId', ${row}.${d("refundTransaction")}, 'receiptId', ${row}.${d("receipt")}, 'note', ${row}.${d("note")}, 'createdBy', ${row}.${d("createdBy")}, 'createdAt', ${row}.${d("createdAt")}, 'updatedAt', ${row}.${d("updatedAt")}${extraFieldsJson(row, extras)})`;

  const receiptJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${r("id")}, 'organizationId', ${row}.${r("tenant")}, 'donorType', ${row}.${r("donorType")}, 'donorId', ${row}.${r("donorId")}, 'sequence', ${row}.${r("sequence")}::text, 'number', ${row}.${r("number")}, 'kind', ${row}.${r("kind")}, 'year', ${row}.${r("year")}, 'amount', ${row}.${r("amount")}::text, 'currency', ${row}.${r("currency")}, 'issuedAt', ${row}.${r("issuedAt")}, 'voidedAt', ${row}.${r("voidedAt")}, 'voidReason', ${row}.${r("voidReason")})`;

  const giftRecord = (type: string, summary: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', v_row.${d("tenant")}, 'id', v_row.${d("id")}, 'donorType', v_row.${d("donorType")}, 'donorId', v_row.${d("donorId")}, 'fundId', v_row.${d("fund")}, 'pledgeId', v_row.${d("pledge")}, 'amount', v_row.${d("amount")}::text, 'currency', v_row.${d("currency")}, 'status', v_row.${d("status")})`,
      subject: `'donations/' || v_row.${d("id")}::text`,
      tenant: `v_row.${d("tenant")}`,
      audit: {
        category: "billing",
        targetType: "donation",
        recordId: `v_row.${d("id")}::text`,
        summary: `'${summary}'`,
      },
    });

  const pledgeRecord = (type: string, summary: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', v_row.${p("tenant")}, 'id', v_row.${p("id")}, 'donorType', v_row.${p("donorType")}, 'donorId', v_row.${p("donorId")}, 'fundId', v_row.${p("fund")}, 'amount', v_row.${p("amount")}::text, 'currency', v_row.${p("currency")}, 'frequency', v_row.${p("frequency")}, 'status', v_row.${p("status")})`,
      subject: `'pledges/' || v_row.${p("id")}::text`,
      tenant: `v_row.${p("tenant")}`,
      audit: {
        category: "billing",
        targetType: "pledge",
        recordId: `v_row.${p("id")}::text`,
        summary: `'${summary}'`,
      },
    });

  const receiptRecord = (type: string, summary: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', v_receipt.${r("tenant")}, 'id', v_receipt.${r("id")}, 'number', v_receipt.${r("number")}, 'kind', v_receipt.${r("kind")}, 'donorType', v_receipt.${r("donorType")}, 'donorId', v_receipt.${r("donorId")}, 'amount', v_receipt.${r("amount")}::text, 'currency', v_receipt.${r("currency")})`,
      subject: `'donation-receipts/' || v_receipt.${r("id")}::text`,
      tenant: `v_receipt.${r("tenant")}`,
      audit: {
        category: "billing",
        targetType: "donation_receipt",
        recordId: `v_receipt.${r("id")}::text`,
        targetLabel: `v_receipt.${r("number")}`,
        summary: `'${summary}'`,
      },
    });

  const cashAccount = `${ledger.fn("ledger_account_for")}(v_row.${d("tenant")}, 'gift_cash', 'donations.cash:' || v_row.${d("currency")},
      'Donations received ' || v_row.${d("currency")}, v_row.${d("currency")}::text, 0::smallint, null, null, null, true, ${read}, 'donations', null)`;

  const incomeAccount = `${ledger.fn("ledger_account_for")}(v_row.${d("tenant")}, 'gift_income',
      'donations.fund:' || coalesce(v_fund.${f("key")}, 'general') || ':' || v_row.${d("currency")},
      'Donations: ' || coalesce(v_fund.${f("name")}, 'General'), v_row.${d("currency")}::text, 0::smallint,
      case when v_fund.${f("id")} is null then null else ${sqlString(fundType)} end, v_fund.${f("id")}::text, null, true, ${read}, 'donations', null)`;

  const assignReceiptNumber = (tenant: string): string =>
    assignNumberSql(
      ctx,
      e("donation_receipt"),
      tenant,
      { seq: "v_seq", identifier: "v_number" },
      {
        table: receipts,
        seq: r("sequence"),
        tenant: r("tenant"),
        prefix: "R-",
      },
    );

  const yearOf = (date: string): string =>
    `extract(year from ${date})::integer`;

  return `
-- Creates or updates the fund or campaign with this key.
create or replace function ${fn("save_donation_fund")}(tenant ${idType}, key text, name text, kind text default 'fund', goal bigint default null, currency text default null, starts_on date default null, ends_on date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${funds}%rowtype;
begin
  if not ${can("save_donation_fund.tenant", manage)} then
    ${forbidden("not allowed to manage donations")}
  end if;
  if save_donation_fund.key is null or save_donation_fund.key !~ '^[a-z][a-z0-9_]{0,62}$' then
    ${invalid("DONATION_FUND_INVALID", "a key is lowercase letters, digits and underscores")}
  end if;
  if nullif(trim(save_donation_fund.name), '') is null then
    ${invalid("DONATION_FUND_INVALID", "a fund needs a name")}
  end if;
  if coalesce(save_donation_fund.kind, 'fund') not in ('fund', 'campaign') then
    ${invalid("DONATION_FUND_INVALID", "kind is fund or campaign")}
  end if;
  if save_donation_fund.goal is not null and (save_donation_fund.goal <= 0 or save_donation_fund.currency is null or save_donation_fund.currency !~ '^[A-Z]{3}$') then
    ${invalid("DONATION_FUND_INVALID", "a goal is more than zero minor units of a three-letter currency")}
  end if;
  if save_donation_fund.starts_on is not null and save_donation_fund.ends_on is not null and save_donation_fund.ends_on < save_donation_fund.starts_on then
    ${invalid("DONATION_FUND_INVALID", "ends_on is on or after starts_on")}
  end if;
  insert into ${funds} (${f("tenant")}, ${f("key")}, ${f("name")}, ${f("kind")}, ${f("goal")}, ${f("currency")}, ${f("startsOn")}, ${f("endsOn")})
  values (save_donation_fund.tenant, save_donation_fund.key, trim(save_donation_fund.name), coalesce(save_donation_fund.kind, 'fund'),
    save_donation_fund.goal, save_donation_fund.currency, save_donation_fund.starts_on, save_donation_fund.ends_on)
  on conflict (${f("tenant")}, ${f("key")}) do update set
    ${f("name")} = excluded.${f("name")}, ${f("kind")} = excluded.${f("kind")}, ${f("goal")} = excluded.${f("goal")},
    ${f("currency")} = excluded.${f("currency")}, ${f("startsOn")} = excluded.${f("startsOn")}, ${f("endsOn")} = excluded.${f("endsOn")},
    ${f("archivedAt")} = null, ${f("updatedAt")} = now()
  returning * into v_row;
  return ${fundJson("v_row")};
end;
$$;
${userGrant(`${fn("save_donation_fund")}(${idType}, text, text, text, bigint, text, date, date)`)}

create or replace function ${fn("archive_donation_fund")}(fund_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${funds}%rowtype;
begin
  select * into v_row from ${funds} x where x.${f("id")} = archive_donation_fund.fund_id for update;
  if not found or not ${can(`v_row.${f("tenant")}`, manage)} then
    ${fail("DONATION_FUND_NOT_FOUND", "no such fund you can manage", "P0002")}
  end if;
  update ${funds} x set ${f("archivedAt")} = coalesce(x.${f("archivedAt")}, now()), ${f("updatedAt")} = now()
    where x.${f("id")} = v_row.${f("id")}
    returning * into v_row;
  return ${fundJson("v_row")};
end;
$$;
${userGrant(`${fn("archive_donation_fund")}(uuid)`)}

-- Funds and campaigns with what they raised: posted gifts in the goal's
-- currency.
create or replace function ${fn("list_donation_funds")}(tenant ${idType}, include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not ${can("list_donation_funds.tenant", read)} then
    ${forbidden("not allowed to read donations")}
  end if;
  return (
    select coalesce(jsonb_agg(${fundJson("x")} order by x.${f("name")}, x.${f("id")}), '[]'::jsonb)
    from ${funds} x
    where x.${f("tenant")} = list_donation_funds.tenant
      and (coalesce(list_donation_funds.include_archived, false) or x.${f("archivedAt")} is null)
  );
end;
$$;
${userGrant(`${fn("list_donation_funds")}(${idType}, boolean)`)}

-- Moves a gift along: pending stores the payment, succeeded posts it on
-- the ledger (cash in, fund income out), failed marks a pending gift, and
-- refunded reverses a posted one and voids its gift receipt. Each posting
-- carries a key per gift, so a repeat changes nothing. Internal.
create or replace function ${fn("donation_settle")}(gift_id uuid, status text, provider text default null, payment_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${donations}%rowtype;
  v_fund ${funds}%rowtype;
  v_tx uuid;
begin
  select * into v_row from ${donations} x where x.${d("id")} = donation_settle.gift_id for update;
  if not found then
    ${giftNotFound}
  end if;
  if donation_settle.status not in ('pending', 'succeeded', 'failed', 'refunded') then
    ${invalid("DONATION_STATUS_INVALID", "status is pending, succeeded, failed or refunded")}
  end if;
  if donation_settle.payment_id is not null and v_row.${d("paymentReference")} is null then
    update ${donations} x set ${d("provider")} = coalesce(donation_settle.provider, x.${d("provider")}),
        ${d("paymentReference")} = donation_settle.payment_id, ${d("updatedAt")} = now()
      where x.${d("id")} = v_row.${d("id")}
      returning * into v_row;
  end if;
  select * into v_fund from ${funds} y where y.${f("id")} = v_row.${d("fund")};
  if donation_settle.status = 'succeeded' and v_row.${d("status")} in ('pending', 'failed') then
    v_tx := ${ledger.fn("ledger_post")}(v_row.${d("tenant")}, 'donation.gift',
      jsonb_build_array(
        jsonb_build_object('account', ${cashAccount}, 'amount', v_row.${d("amount")}),
        jsonb_build_object('account', ${incomeAccount}, 'amount', -v_row.${d("amount")})),
      'donations', v_row.${d("id")}::text, 'Gift', 'donation:' || v_row.${d("id")}::text || ':posted', v_row.${d("receivedOn")}::timestamptz,
      jsonb_strip_nulls(jsonb_build_object(${giftKey}, v_row.${d("id")}, 'donorType', v_row.${d("donorType")}, 'donorId', v_row.${d("donorId")}, 'fundId', v_row.${d("fund")})));
    update ${donations} x set ${d("status")} = 'posted', ${d("transaction")} = v_tx, ${d("updatedAt")} = now()
      where x.${d("id")} = v_row.${d("id")}
      returning * into v_row;
    ${giftRecord("donation.received", "received a gift")}
  elsif donation_settle.status = 'failed' and v_row.${d("status")} = 'pending' then
    update ${donations} x set ${d("status")} = 'failed', ${d("updatedAt")} = now()
      where x.${d("id")} = v_row.${d("id")}
      returning * into v_row;
    ${giftRecord("donation.failed", "a gift payment failed")}
  elsif donation_settle.status = 'refunded' and v_row.${d("status")} = 'posted' then
    v_tx := ${ledger.fn("ledger_post")}(v_row.${d("tenant")}, 'donation.refund',
      jsonb_build_array(
        jsonb_build_object('account', ${cashAccount}, 'amount', -v_row.${d("amount")}),
        jsonb_build_object('account', ${incomeAccount}, 'amount', v_row.${d("amount")})),
      'donations', v_row.${d("id")}::text, 'Gift refunded', 'donation:' || v_row.${d("id")}::text || ':refunded', null,
      jsonb_build_object(${giftKey}, v_row.${d("id")}));
    update ${receipts} x set ${r("voidedAt")} = now(), ${r("voidReason")} = 'the gift was refunded'
      where x.${r("id")} = v_row.${d("receipt")} and x.${r("kind")} = 'gift' and x.${r("voidedAt")} is null;
    update ${donations} x set ${d("status")} = 'refunded', ${d("refundTransaction")} = v_tx, ${d("receipt")} = null, ${d("updatedAt")} = now()
      where x.${d("id")} = v_row.${d("id")}
      returning * into v_row;
    ${giftRecord("donation.refunded", "refunded a gift")}
  end if;
  return ${giftJson("v_row")};
end;
$$;
revoke execute on function ${fn("donation_settle")}(uuid, text, text, text) from public, anon, authenticated;

-- Records a gift received outside a payments provider (cash, a check, a
-- bank transfer) and posts it at once. With a pledge and period it pays
-- that installment; a second call for the same period returns the gift.
-- fields: the extra columns to set.
${extra.drop(fn("record_gift"), `${idType}, text, text, bigint, text, uuid, date, text, text, uuid, date`)}
create or replace function ${fn("record_gift")}(tenant ${idType}, donor_type text, donor_id text, amount bigint, currency text, fund_id uuid default null, received_on date default null, method text default null, note text default null, pledge_id uuid default null, period_start date default null${extra.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${donations}%rowtype;
  v_pledge ${pledges}%rowtype;
begin
  if not ${can("record_gift.tenant", manage)} then
    ${forbidden("not allowed to manage donations")}
  end if;${donorCheck("record_gift.donor_type", "record_gift.donor_id", "record_gift.tenant")}${moneyCheck("record_gift.amount", "record_gift.currency")}${fundCheck("record_gift.fund_id", "record_gift.tenant")}
  if record_gift.pledge_id is not null then
    select * into v_pledge from ${pledges} y where y.${p("id")} = record_gift.pledge_id and y.${p("tenant")} = record_gift.tenant;
    if not found or v_pledge.${p("donorType")} <> record_gift.donor_type or v_pledge.${p("donorId")} <> record_gift.donor_id
      or v_pledge.${p("currency")} <> record_gift.currency or record_gift.period_start is null then
      ${invalid("DONATION_PLEDGE_INVALID", "the pledge is unknown, another donor's or in another currency, or the period is missing")}
    end if;
  end if;
  insert into ${donations} (${d("tenant")}, ${d("donorType")}, ${d("donorId")}, ${d("fund")}, ${d("pledge")}, ${d("periodStart")}, ${d("amount")},
    ${d("currency")}, ${d("receivedOn")}, ${d("method")}, ${d("note")}, ${d("createdBy")})
  values (record_gift.tenant, record_gift.donor_type, record_gift.donor_id, coalesce(record_gift.fund_id, v_pledge.${p("fund")}), record_gift.pledge_id,
    case when record_gift.pledge_id is null then null else record_gift.period_start end, record_gift.amount, record_gift.currency,
    coalesce(record_gift.received_on, current_date), nullif(trim(record_gift.method), ''), nullif(trim(record_gift.note), ''), auth.uid())
  on conflict (${d("pledge")}, ${d("periodStart")}) do nothing
  returning * into v_row;${writeExtraColumns(donations, extras, "record_gift.fields", `x.${d("id")} = v_row.${d("id")}`, "v_row")}
  if v_row.${d("id")} is null then
    select * into v_row from ${donations} x where x.${d("pledge")} = record_gift.pledge_id and x.${d("periodStart")} = record_gift.period_start;
  end if;
  return ${fn("donation_settle")}(v_row.${d("id")}, 'succeeded');
end;
$$;
${userGrant(`${fn("record_gift")}(${idType}, text, text, bigint, text, uuid, date, text, text, uuid, date${extra.type})`)}

-- Opens a pending gift a payments provider will charge. With a pledge and
-- period a second call returns the same gift, so a retried charge run never
-- charges a period twice. fields: the extra columns to set.
${extra.drop(fn("open_gift"), `${idType}, text, text, bigint, text, uuid, uuid, date, text, text`)}
create or replace function ${fn("open_gift")}(tenant ${idType}, donor_type text, donor_id text, amount bigint, currency text, fund_id uuid default null, pledge_id uuid default null, period_start date default null, provider text default null, note text default null${extra.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${donations}%rowtype;
begin
  if not ${can("open_gift.tenant", manage)} then
    ${forbidden("not allowed to manage donations")}
  end if;${donorCheck("open_gift.donor_type", "open_gift.donor_id", "open_gift.tenant")}${moneyCheck("open_gift.amount", "open_gift.currency")}${fundCheck("open_gift.fund_id", "open_gift.tenant")}
  if open_gift.pledge_id is not null and (open_gift.period_start is null or not exists (
    select 1 from ${pledges} y where y.${p("id")} = open_gift.pledge_id and y.${p("tenant")} = open_gift.tenant
      and y.${p("donorType")} = open_gift.donor_type and y.${p("donorId")} = open_gift.donor_id and y.${p("currency")} = open_gift.currency
  )) then
    ${invalid("DONATION_PLEDGE_INVALID", "the pledge is unknown, another donor's or in another currency, or the period is missing")}
  end if;
  insert into ${donations} (${d("tenant")}, ${d("donorType")}, ${d("donorId")}, ${d("fund")}, ${d("pledge")}, ${d("periodStart")}, ${d("amount")},
    ${d("currency")}, ${d("method")}, ${d("provider")}, ${d("note")}, ${d("createdBy")})
  values (open_gift.tenant, open_gift.donor_type, open_gift.donor_id, open_gift.fund_id, open_gift.pledge_id,
    case when open_gift.pledge_id is null then null else open_gift.period_start end, open_gift.amount, open_gift.currency,
    'card', open_gift.provider, nullif(trim(open_gift.note), ''), auth.uid())
  on conflict (${d("pledge")}, ${d("periodStart")}) do nothing
  returning * into v_row;${writeExtraColumns(donations, extras, "open_gift.fields", `x.${d("id")} = v_row.${d("id")}`, "v_row")}
  if v_row.${d("id")} is null then
    select * into v_row from ${donations} x where x.${d("pledge")} = open_gift.pledge_id and x.${d("periodStart")} = open_gift.period_start;
  end if;
  return ${giftJson("v_row")};
end;
$$;
${userGrant(`${fn("open_gift")}(${idType}, text, text, bigint, text, uuid, uuid, date, text, text${extra.type})`)}

-- Records what the payments provider reported for a gift: by its id, or
-- (gift_id null) by the provider's payment id. succeeded posts it, failed
-- marks it, refunded reverses it. A webhook calls it with the service role.
create or replace function ${fn("record_gift_payment")}(gift_id uuid, provider text, payment_id text, status text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${donations}%rowtype;
begin
  if record_gift_payment.gift_id is not null then
    select * into v_row from ${donations} x where x.${d("id")} = record_gift_payment.gift_id;
  else
    select * into v_row from ${donations} x
      where x.${d("provider")} = record_gift_payment.provider and x.${d("paymentReference")} = record_gift_payment.payment_id;
  end if;
  if not found or not ${can(`v_row.${d("tenant")}`, manage)} then
    ${giftNotFound}
  end if;
  return ${fn("donation_settle")}(v_row.${d("id")}, record_gift_payment.status, record_gift_payment.provider, record_gift_payment.payment_id);
end;
$$;
${userGrant(`${fn("record_gift_payment")}(uuid, text, text, text)`)}

create or replace function ${fn("get_gift")}(gift_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${donations}%rowtype;
begin
  select * into v_row from ${donations} x where x.${d("id")} = get_gift.gift_id;
  if not found or not ${can(`v_row.${d("tenant")}`, read)} then
    ${giftNotFound}
  end if;
  return ${giftJson("v_row")};
end;
$$;
${userGrant(`${fn("get_gift")}(uuid)`)}

create or replace function ${fn("list_gifts")}(tenant ${idType}, donor_type text default null, donor_id text default null, fund_id uuid default null, pledge_id uuid default null, status text default null, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not ${can("list_gifts.tenant", read)} then
    ${forbidden("not allowed to read donations")}
  end if;
  return (
    select coalesce(jsonb_agg(${giftJson("q")} order by q.${d("receivedOn")} desc, q.${d("createdAt")} desc), '[]'::jsonb)
    from (
      select * from ${donations} x
      where x.${d("tenant")} = list_gifts.tenant
        and (list_gifts.donor_type is null or (x.${d("donorType")} = list_gifts.donor_type and x.${d("donorId")} = list_gifts.donor_id))
        and (list_gifts.fund_id is null or x.${d("fund")} = list_gifts.fund_id)
        and (list_gifts.pledge_id is null or x.${d("pledge")} = list_gifts.pledge_id)
        and (list_gifts.status is null or x.${d("status")} = list_gifts.status)
      order by x.${d("receivedOn")} desc, x.${d("createdAt")} desc
      limit ${pageSize("list_gifts.page_size", 100, 1000)}
    ) q
  );
end;
$$;
${userGrant(`${fn("list_gifts")}(${idType}, text, text, uuid, uuid, text, integer)`)}

create or replace function ${fn("create_pledge")}(tenant ${idType}, donor_type text, donor_id text, amount bigint, currency text, frequency text default 'monthly', fund_id uuid default null, starts_on date default null, ends_on date default null, provider text default null, provider_customer text default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${pledges}%rowtype;
begin
  if not ${can("create_pledge.tenant", manage)} then
    ${forbidden("not allowed to manage donations")}
  end if;${donorCheck("create_pledge.donor_type", "create_pledge.donor_id", "create_pledge.tenant")}${moneyCheck("create_pledge.amount", "create_pledge.currency")}${fundCheck("create_pledge.fund_id", "create_pledge.tenant")}
  if coalesce(create_pledge.frequency, 'monthly') not in ('weekly', 'monthly', 'quarterly', 'yearly') then
    ${invalid("DONATION_PLEDGE_INVALID", "frequency is weekly, monthly, quarterly or yearly")}
  end if;
  if create_pledge.ends_on is not null and create_pledge.ends_on <= coalesce(create_pledge.starts_on, current_date) then
    ${invalid("DONATION_PLEDGE_INVALID", "ends_on is after starts_on")}
  end if;
  insert into ${pledges} (${p("tenant")}, ${p("donorType")}, ${p("donorId")}, ${p("fund")}, ${p("amount")}, ${p("currency")}, ${p("frequency")},
    ${p("startsOn")}, ${p("endsOn")}, ${p("provider")}, ${p("providerCustomer")}, ${p("note")}, ${p("createdBy")})
  values (create_pledge.tenant, create_pledge.donor_type, create_pledge.donor_id, create_pledge.fund_id, create_pledge.amount, create_pledge.currency,
    coalesce(create_pledge.frequency, 'monthly'), coalesce(create_pledge.starts_on, current_date), create_pledge.ends_on,
    nullif(trim(create_pledge.provider), ''), nullif(trim(create_pledge.provider_customer), ''), nullif(trim(create_pledge.note), ''), auth.uid())
  returning * into v_row;
  ${pledgeRecord("pledge.created", "created a pledge")}
  return ${pledgeJson("v_row")};
end;
$$;
${userGrant(`${fn("create_pledge")}(${idType}, text, text, bigint, text, text, uuid, date, date, text, text, text)`)}

-- Pauses, resumes or ends a pledge, moves its end or changes its amount for
-- installments from now on. Null keeps a value.
create or replace function ${fn("update_pledge")}(pledge_id uuid, status text default null, ends_on date default null, amount bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${pledges}%rowtype;
begin
  select * into v_row from ${pledges} x where x.${p("id")} = update_pledge.pledge_id for update;
  if not found or not ${can(`v_row.${p("tenant")}`, manage)} then
    ${fail("DONATION_PLEDGE_NOT_FOUND", "no such pledge you can manage", "P0002")}
  end if;
  if update_pledge.status is not null and update_pledge.status not in ('active', 'paused', 'ended') then
    ${invalid("DONATION_PLEDGE_INVALID", "status is active, paused or ended")}
  end if;
  if v_row.${p("status")} = 'ended' and coalesce(update_pledge.status, 'ended') <> 'ended' then
    ${fail("DONATION_PLEDGE_ENDED", "an ended pledge can't restart; create a new one", "55000")}
  end if;
  if update_pledge.ends_on is not null and update_pledge.ends_on <= v_row.${p("startsOn")} then
    ${invalid("DONATION_PLEDGE_INVALID", "ends_on is after starts_on")}
  end if;
  if update_pledge.amount is not null and update_pledge.amount <= 0 then
    ${invalid("DONATION_AMOUNT_INVALID", "an amount is more than zero minor units")}
  end if;
  update ${pledges} x set
      ${p("status")} = coalesce(update_pledge.status, x.${p("status")}),
      ${p("endsOn")} = coalesce(update_pledge.ends_on, x.${p("endsOn")}),
      ${p("amount")} = coalesce(update_pledge.amount, x.${p("amount")}),
      ${p("updatedAt")} = now()
    where x.${p("id")} = v_row.${p("id")}
    returning * into v_row;
  ${pledgeRecord("pledge.updated", "updated a pledge")}
  return ${pledgeJson("v_row")};
end;
$$;
${userGrant(`${fn("update_pledge")}(uuid, text, date, bigint)`)}

create or replace function ${fn("list_pledges")}(tenant ${idType}, donor_type text default null, donor_id text default null, status text default null, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not ${can("list_pledges.tenant", read)} then
    ${forbidden("not allowed to read donations")}
  end if;
  return (
    select coalesce(jsonb_agg(${pledgeJson("q")} order by q.${p("createdAt")} desc, q.${p("id")}), '[]'::jsonb)
    from (
      select * from ${pledges} x
      where x.${p("tenant")} = list_pledges.tenant
        and (list_pledges.donor_type is null or (x.${p("donorType")} = list_pledges.donor_type and x.${p("donorId")} = list_pledges.donor_id))
        and (list_pledges.status is null or x.${p("status")} = list_pledges.status)
      order by x.${p("createdAt")} desc, x.${p("id")}
      limit ${pageSize("list_pledges.page_size", 100, 1000)}
    ) q
  );
end;
$$;
${userGrant(`${fn("list_pledges")}(${idType}, text, text, text, integer)`)}

-- The installments of active pledges that start on or before through
-- (default today) and have no gift yet, oldest first, up to max_rows. A
-- gift opened but never charged (pending without a payment) stays due, so
-- the next run charges it under the same idempotency key; a declined one
-- doesn't.
create or replace function ${fn("due_pledge_installments")}(tenant ${idType}, through date default null, max_rows integer default 500)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_through date := coalesce(due_pledge_installments.through, current_date);
  v_max integer := ${pageSize("due_pledge_installments.max_rows", 500, 5000)};
  v_row ${pledges}%rowtype;
  v_items jsonb := '[]'::jsonb;
  v_n integer;
  v_start date;
begin
  if not ${can("due_pledge_installments.tenant", manage)} then
    ${forbidden("not allowed to manage donations")}
  end if;
  <<installments>>
  for v_row in
    select * from ${pledges} x
    where x.${p("tenant")} = due_pledge_installments.tenant and x.${p("status")} = 'active' and x.${p("startsOn")} <= v_through
    order by x.${p("startsOn")}, x.${p("id")}
  loop
    v_n := 0;
    loop
      v_start := (v_row.${p("startsOn")} + v_n * ${step(`v_row.${p("frequency")}`)})::date;
      exit when v_start > v_through or (v_row.${p("endsOn")} is not null and v_start >= v_row.${p("endsOn")});
      if not exists (select 1 from ${donations} g where g.${d("pledge")} = v_row.${p("id")} and g.${d("periodStart")} = v_start
        and not (g.${d("status")} = 'pending' and g.${d("paymentReference")} is null)) then
        exit installments when jsonb_array_length(v_items) >= v_max;
        v_items := v_items || jsonb_build_array(jsonb_build_object('periodStart', v_start, 'pledgeId', v_row.${p("id")},
          'donorType', v_row.${p("donorType")}, 'donorId', v_row.${p("donorId")}, 'fundId', v_row.${p("fund")},
          'amount', v_row.${p("amount")}::text, 'currency', v_row.${p("currency")},
          'provider', v_row.${p("provider")}, 'providerCustomer', v_row.${p("providerCustomer")}));
      end if;
      v_n := v_n + 1;
    end loop;
  end loop;
  return v_items;
end;
$$;
${userGrant(`${fn("due_pledge_installments")}(${idType}, date, integer)`)}

-- Issues a numbered tax receipt for one posted gift. Numbers come from
-- number-sequences when it configures donation_receipt, else one more than
-- the organization's highest.
create or replace function ${fn("issue_gift_receipt")}(gift_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${donations}%rowtype;
  v_receipt ${receipts}%rowtype;
  v_seq bigint;
  v_number text;
begin
  select * into v_row from ${donations} x where x.${d("id")} = issue_gift_receipt.gift_id for update;
  if not found or not ${can(`v_row.${d("tenant")}`, manage)} then
    ${giftNotFound}
  end if;
  if v_row.${d("status")} <> 'posted' then
    ${fail("DONATION_STATUS_INVALID", "only a posted gift gets a receipt", "55000")}
  end if;
  if v_row.${d("receipt")} is not null then
    select * into v_receipt from ${receipts} x where x.${r("id")} = v_row.${d("receipt")};
    return ${receiptJson("v_receipt")};
  end if;
  ${assignReceiptNumber(`v_row.${d("tenant")}`)}
  insert into ${receipts} (${r("tenant")}, ${r("donorType")}, ${r("donorId")}, ${r("sequence")}, ${r("number")}, ${r("kind")}, ${r("year")}, ${r("amount")}, ${r("currency")})
  values (v_row.${d("tenant")}, v_row.${d("donorType")}, v_row.${d("donorId")}, v_seq, v_number, 'gift', ${yearOf(`v_row.${d("receivedOn")}`)},
    v_row.${d("amount")}, v_row.${d("currency")})
  returning * into v_receipt;
  update ${donations} x set ${d("receipt")} = v_receipt.${r("id")}, ${d("updatedAt")} = now() where x.${d("id")} = v_row.${d("id")};
  ${receiptRecord("donation_receipt.issued", "issued a gift receipt")}
  return ${receiptJson("v_receipt")};
end;
$$;
${userGrant(`${fn("issue_gift_receipt")}(uuid)`)}

-- Issues a donor's yearly tax receipt: their posted gifts received in year
-- in currency. A second call returns the receipt until it is voided.
create or replace function ${fn("issue_yearly_receipt")}(tenant ${idType}, donor_type text, donor_id text, year integer, currency text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_receipt ${receipts}%rowtype;
  v_amount bigint;
  v_seq bigint;
  v_number text;
begin
  if not ${can("issue_yearly_receipt.tenant", manage)} then
    ${forbidden("not allowed to manage donations")}
  end if;
  if issue_yearly_receipt.year is null or issue_yearly_receipt.currency is null then
    ${invalid("DONATION_RECEIPT_INVALID", "a yearly receipt needs a year and a currency")}
  end if;
  perform pg_advisory_xact_lock(hashtextextended('donations.yearly:' || issue_yearly_receipt.tenant::text || ':' || issue_yearly_receipt.donor_type
    || ':' || issue_yearly_receipt.donor_id || ':' || issue_yearly_receipt.year::text || ':' || issue_yearly_receipt.currency, 0));
  select * into v_receipt from ${receipts} x
    where x.${r("tenant")} = issue_yearly_receipt.tenant and x.${r("donorType")} = issue_yearly_receipt.donor_type
      and x.${r("donorId")} = issue_yearly_receipt.donor_id and x.${r("year")} = issue_yearly_receipt.year
      and x.${r("currency")} = issue_yearly_receipt.currency and x.${r("kind")} = 'yearly' and x.${r("voidedAt")} is null;
  if found then
    return ${receiptJson("v_receipt")};
  end if;
  select coalesce(sum(g.${d("amount")}), 0) into v_amount from ${donations} g
    where g.${d("tenant")} = issue_yearly_receipt.tenant and g.${d("donorType")} = issue_yearly_receipt.donor_type
      and g.${d("donorId")} = issue_yearly_receipt.donor_id and g.${d("currency")} = issue_yearly_receipt.currency
      and g.${d("status")} = 'posted' and ${yearOf(`g.${d("receivedOn")}`)} = issue_yearly_receipt.year;
  if v_amount <= 0 then
    ${invalid("DONATION_RECEIPT_EMPTY", "the donor has no posted gifts in this year and currency")}
  end if;
  ${assignReceiptNumber("issue_yearly_receipt.tenant")}
  insert into ${receipts} (${r("tenant")}, ${r("donorType")}, ${r("donorId")}, ${r("sequence")}, ${r("number")}, ${r("kind")}, ${r("year")}, ${r("amount")}, ${r("currency")})
  values (issue_yearly_receipt.tenant, issue_yearly_receipt.donor_type, issue_yearly_receipt.donor_id, v_seq, v_number, 'yearly',
    issue_yearly_receipt.year, v_amount, issue_yearly_receipt.currency)
  returning * into v_receipt;
  ${receiptRecord("donation_receipt.issued", "issued a yearly receipt")}
  return ${receiptJson("v_receipt")};
end;
$$;
${userGrant(`${fn("issue_yearly_receipt")}(${idType}, text, text, integer, text)`)}

-- Voids a receipt; its number stays used. A voided gift receipt frees the
-- gift for a new one.
create or replace function ${fn("void_donation_receipt")}(receipt_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_receipt ${receipts}%rowtype;
begin
  select * into v_receipt from ${receipts} x where x.${r("id")} = void_donation_receipt.receipt_id for update;
  if not found or not ${can(`v_receipt.${r("tenant")}`, manage)} then
    ${fail("DONATION_RECEIPT_NOT_FOUND", "no such receipt you can manage", "P0002")}
  end if;
  if v_receipt.${r("voidedAt")} is not null then
    return ${receiptJson("v_receipt")};
  end if;
  update ${receipts} x set ${r("voidedAt")} = now(), ${r("voidReason")} = nullif(trim(void_donation_receipt.reason), '')
    where x.${r("id")} = v_receipt.${r("id")}
    returning * into v_receipt;
  update ${donations} x set ${d("receipt")} = null, ${d("updatedAt")} = now() where x.${d("receipt")} = v_receipt.${r("id")};
  ${receiptRecord("donation_receipt.voided", "voided a receipt")}
  return ${receiptJson("v_receipt")};
end;
$$;
${userGrant(`${fn("void_donation_receipt")}(uuid, text)`)}

create or replace function ${fn("list_donation_receipts")}(tenant ${idType}, donor_type text default null, donor_id text default null, year integer default null, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not ${can("list_donation_receipts.tenant", read)} then
    ${forbidden("not allowed to read donations")}
  end if;
  return (
    select coalesce(jsonb_agg(${receiptJson("q")} order by q.${r("issuedAt")} desc, q.${r("id")}), '[]'::jsonb)
    from (
      select * from ${receipts} x
      where x.${r("tenant")} = list_donation_receipts.tenant
        and (list_donation_receipts.donor_type is null or (x.${r("donorType")} = list_donation_receipts.donor_type and x.${r("donorId")} = list_donation_receipts.donor_id))
        and (list_donation_receipts.year is null or x.${r("year")} = list_donation_receipts.year)
      order by x.${r("issuedAt")} desc, x.${r("id")}
      limit ${pageSize("list_donation_receipts.page_size", 100, 1000)}
    ) q
  );
end;
$$;
${userGrant(`${fn("list_donation_receipts")}(${idType}, text, text, integer, integer)`)}

-- A donor's giving in a year (default this one): posted totals per
-- currency, per fund, and the receipts issued for the year.
create or replace function ${fn("yearly_giving_summary")}(tenant ${idType}, donor_type text, donor_id text, year integer default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_year integer := coalesce(yearly_giving_summary.year, ${yearOf("current_date")});
begin
  if not ${can("yearly_giving_summary.tenant", read)} then
    ${forbidden("not allowed to read donations")}
  end if;
  return jsonb_build_object(
    'year', v_year,
    'donorType', yearly_giving_summary.donor_type,
    'donorId', yearly_giving_summary.donor_id,
    'totals', (
      select coalesce(jsonb_agg(jsonb_build_object('currency', q.currency, 'amount', q.amount::text, 'gifts', q.gifts) order by q.currency), '[]'::jsonb)
      from (
        select g.${d("currency")} as currency, sum(g.${d("amount")}) as amount, count(*) as gifts
        from ${donations} g
        where g.${d("tenant")} = yearly_giving_summary.tenant and g.${d("donorType")} = yearly_giving_summary.donor_type
          and g.${d("donorId")} = yearly_giving_summary.donor_id and g.${d("status")} = 'posted'
          and ${yearOf(`g.${d("receivedOn")}`)} = v_year
        group by g.${d("currency")}
      ) q
    ),
    'funds', (
      select coalesce(jsonb_agg(jsonb_build_object('fundId', q.fund, 'name', coalesce(y.${f("name")}, 'General'), 'currency', q.currency, 'amount', q.amount::text)
        order by coalesce(y.${f("name")}, ''), q.currency), '[]'::jsonb)
      from (
        select g.${d("fund")} as fund, g.${d("currency")} as currency, sum(g.${d("amount")}) as amount
        from ${donations} g
        where g.${d("tenant")} = yearly_giving_summary.tenant and g.${d("donorType")} = yearly_giving_summary.donor_type
          and g.${d("donorId")} = yearly_giving_summary.donor_id and g.${d("status")} = 'posted'
          and ${yearOf(`g.${d("receivedOn")}`)} = v_year
        group by g.${d("fund")}, g.${d("currency")}
      ) q
      left join ${funds} y on y.${f("id")} = q.fund
    ),
    'receipts', (
      select coalesce(jsonb_agg(${receiptJson("x")} order by x.${r("issuedAt")}), '[]'::jsonb)
      from ${receipts} x
      where x.${r("tenant")} = yearly_giving_summary.tenant and x.${r("donorType")} = yearly_giving_summary.donor_type
        and x.${r("donorId")} = yearly_giving_summary.donor_id and x.${r("year")} = v_year
    )
  );
end;
$$;
${userGrant(`${fn("yearly_giving_summary")}(${idType}, text, text, integer)`)}
`;
}
