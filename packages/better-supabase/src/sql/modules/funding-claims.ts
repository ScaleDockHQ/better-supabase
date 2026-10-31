import type { BlockSqlContext } from "../context.ts";

import { isRecord } from "../../core/guards.ts";
import { sqlString } from "../../core/template.ts";
import { fail, SERVICE_CALLER, userGrant } from "../shared.ts";
import { funderCheck } from "./funding-functions.ts";
import {
  claimFormats,
  claimJson,
  claimRecord,
  FORMAT_PATTERN,
  fundingKeys,
  lineJson,
  sqlList,
} from "./funding-shared.ts";

/**
 * The format `numbering` assigns claim numbers in (a SQL expression), or
 * undefined when it has no `funding_claim` entity.
 */
function numberFormat(
  ctx: BlockSqlContext,
  tenant: string,
): string | undefined {
  if (!ctx.installed("numbering")) {
    return undefined;
  }

  const entities = ctx.of("numbering").option("entities");
  const entry = isRecord(entities) ? entities["funding_claim"] : undefined;

  if (!isRecord(entry) || typeof entry["format"] !== "string") {
    return undefined;
  }

  return isRecord(entry["formatFrom"])
    ? `${ctx.of("numbering").fn("number_format")}(${tenant}, 'funding_claim')`
    : sqlString(entry["format"]);
}

/** PL/pgSQL that sets `v_number` to the tenant's next claim number. */
function assignNumber(ctx: BlockSqlContext, tenant: string): string {
  const format = numberFormat(ctx, tenant);

  if (format !== undefined) {
    const next = ctx.of("numbering").fn("next_number");

    return `v_seq := ${next}(${tenant}, 'funding_claim', now());
  v_number := better_supabase.format_assigned_number(${format}, v_seq, now());`;
  }

  const c = (column: string): string => ctx.col("claims", column);

  return `select coalesce(max(x.${c("number")}::bigint) filter (where x.${c("number")} ~ '^[0-9]{1,18}$'), 0) + 1 into v_seq
  from ${ctx.table("claims")} x where x.${c("tenant")} = ${tenant};
  v_number := v_seq::text;`;
}

/** Whether `invoice_funding_claim` renders. */
export const invoicesClaims = (ctx: BlockSqlContext): boolean =>
  ctx.installed("invoices") &&
  ctx.of("invoices").mode !== "custom" &&
  ctx.has("claims", "invoice");

/** The claim functions. */
export function fundingClaimFunctions(ctx: BlockSqlContext): string {
  const products = ctx.table("products");
  const awards = ctx.table("awards");
  const deliveries = ctx.table("deliveries");
  const claims = ctx.table("claims");
  const lines = ctx.table("claimLines");
  const p = (column: string): string => ctx.col("products", column);
  const w = (column: string): string => ctx.col("awards", column);
  const d = (column: string): string => ctx.col("deliveries", column);
  const c = (column: string): string => ctx.col("claims", column);
  const l = (column: string): string => ctx.col("claimLines", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const { read, claim } = fundingKeys(ctx);
  const formats = claimFormats(ctx);

  const insertCol = (table: string, column: string): string =>
    ctx.has(table, column) ? `, ${ctx.col(table, column)}` : "";

  const insertVal = (table: string, column: string, value: string): string =>
    ctx.has(table, column) ? `, ${value}` : "";

  const touch = ctx.has("claims", "updatedAt")
    ? `, ${c("updatedAt")} = now()`
    : "";

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`;

  const forbidden = (message: string): string =>
    fail("FUNDING_FORBIDDEN", message);

  const invalid = (message: string): string =>
    fail("FUNDING_INVALID", message, "22023");

  const claimNotFound = fail(
    "FUNDING_CLAIM_NOT_FOUND",
    "funding claim not found",
    "P0002",
  );

  const notDraft = fail(
    "FUNDING_CLAIM_STATUS_INVALID",
    "the funding claim was sent already",
    "22023",
  );

  const formatList =
    formats.length === 0 ? "" : ` or v_format not in ${sqlList(formats)}`;

  // The approved deliveries of `funder` from `start` to `end` no claim holds.
  const claimable = (
    tenant: string,
    funder: string,
    start: string,
    end: string,
  ): string => `from ${deliveries} x
    join ${awards} a on a.${w("tenant")} = x.${d("tenant")} and a.${w("id")} = x.${d("award")}
    join ${products} y on y.${p("tenant")} = a.${w("tenant")} and y.${p("id")} = a.${w("product")}
    where x.${d("tenant")} = ${tenant} and a.${w("funder")} = ${funder}
      and x.${d("status")} = 'approved' and x.${d("claimLine")} is null
      and x.${d("deliveredOn")} >= ${start} and x.${d("deliveredOn")} <= ${end}`;

  const scope = claimable(
    "build_funding_claim.tenant",
    "build_funding_claim.funder_id",
    "build_funding_claim.period_start",
    "build_funding_claim.period_end",
  );

  // Puts the deliveries of the claim's lines that match `lineFilter` back to
  // approved, out of the claim.
  const release = (
    lineFilter: string,
  ): string => `update ${deliveries} x set ${d("status")} = 'approved', ${d("claimLine")} = null
  where x.${d("claimLine")} in (select z.${l("id")} from ${lines} z where z.${l("tenant")} = v_claim.${c("tenant")} and z.${l("claim")} = v_claim.${c("id")}${lineFilter});`;

  const claimBody = (
    row: string,
  ): string => `${claimJson(ctx, row)} || jsonb_build_object('lines', coalesce((
    select jsonb_agg(${lineJson(ctx, "z")} || jsonb_build_object(
      'award', jsonb_build_object('subjectType', a.${w("subjectType")}, 'subjectId', a.${w("subjectId")}, 'reference', a.${w("reference")}, 'period', a.${w("period")}),
      'product', jsonb_build_object('code', y.${p("code")}, 'title', y.${p("title")}, 'unit', y.${p("unit")}, 'rate', y.${p("rate")}::text),
      'deliveries', coalesce((
        select jsonb_agg(jsonb_build_object('id', x.${d("id")}, 'deliveredOn', x.${d("deliveredOn")}, 'units', x.${d("units")}, 'sourceType', x.${d("sourceType")}, 'sourceId', x.${d("sourceId")}, 'performerId', x.${d("performer")}) order by x.${d("deliveredOn")}, x.${d("id")})
        from ${deliveries} x where x.${d("claimLine")} = z.${l("id")}
      ), '[]'::jsonb)
    ) order by y.${p("code")}, a.${w("subjectId")}, z.${l("id")})
    from ${lines} z
    join ${awards} a on a.${w("tenant")} = z.${l("tenant")} and a.${w("id")} = z.${l("award")}
    join ${products} y on y.${p("tenant")} = z.${l("tenant")} and y.${p("id")} = z.${l("product")}
    where z.${l("tenant")} = ${row}.${c("tenant")} and z.${l("claim")} = ${row}.${c("id")}
  ), '[]'::jsonb))`;

  const lookup = (
    fnName: string,
  ): string => `select * into v_claim from ${claims} x where x.${c("id")} = ${fnName}.claim_id for update;
  if not found then
    ${claimNotFound}
  end if;
  if not ${allowed(`v_claim.${c("tenant")}`, claim)} then
    ${forbidden("not allowed to claim funding")}
  end if;`;

  const invoice = invoicesClaims(ctx) ? invoiceFunction(ctx) : "";

  return `
-- Gathers the approved deliveries of a funder from period_start to
-- period_end into a draft claim in format (a FundingClaimFormat key), one
-- line per award, priced at the product rate. The deliveries become claimed.
create or replace function ${fn("build_funding_claim")}(tenant ${idType}, funder_id uuid, period_start date, period_end date, format text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim ${claims}%rowtype;
  v_format text := nullif(trim(build_funding_claim.format), '');
  v_currencies integer;
  v_currency text;
  v_seq bigint;
  v_number text;
begin
  if not ${allowed("build_funding_claim.tenant", claim)} then
    ${forbidden("not allowed to claim funding")}
  end if;
  if v_format is null or v_format !~ ${sqlString(FORMAT_PATTERN)}${formatList} then
    ${fail("FUNDING_FORMAT_UNKNOWN", "the claim format isn't one this organization claims in", "22023")}
  end if;
  if build_funding_claim.funder_id is null or not ${funderCheck(ctx, "build_funding_claim.funder_id", "build_funding_claim.tenant")} then
    ${fail("FUNDING_FUNDER_INVALID", "the funder is a company or person in this organization's contacts with the funder role", "22023")}
  end if;
  if build_funding_claim.period_start is null or build_funding_claim.period_end is null
    or build_funding_claim.period_end < build_funding_claim.period_start then
    ${invalid("a claim period ends on or after it starts")}
  end if;
  ${ctx.hook("before_funding_claim_build", [
    [idType, "build_funding_claim.tenant"],
    ["uuid", "build_funding_claim.funder_id"],
    ["date", "build_funding_claim.period_start"],
    ["date", "build_funding_claim.period_end"],
  ])}
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bsb_funding_claim:' || build_funding_claim.tenant::text, 0));
  perform 1 ${scope}
  for update of x;
  select count(distinct y.${p("currency")}), min(y.${p("currency")}) into v_currencies, v_currency
  ${scope};
  if v_currencies = 0 then
    ${fail("FUNDING_CLAIM_EMPTY", "no approved deliveries of this funder in the period", "22023")}
  end if;
  if v_currencies > 1 then
    ${invalid("the deliveries are priced in several currencies; claim each product's currency apart")}
  end if;
  ${assignNumber(ctx, "build_funding_claim.tenant")}
  insert into ${claims} (${c("tenant")}, ${c("funder")}, ${c("number")}, ${c("periodStart")}, ${c("periodEnd")}, ${c("format")}, ${c("currency")}${insertCol("claims", "createdBy")})
  values (build_funding_claim.tenant, build_funding_claim.funder_id, v_number, build_funding_claim.period_start, build_funding_claim.period_end, v_format, v_currency${insertVal("claims", "createdBy", "(select auth.uid())")})
  returning * into v_claim;
  insert into ${lines} (${l("tenant")}, ${l("claim")}, ${l("award")}, ${l("product")}, ${l("units")}, ${l("amount")})
  select build_funding_claim.tenant, v_claim.${c("id")}, a.${w("id")}, y.${p("id")}, sum(x.${d("units")}), round(sum(x.${d("units")}) * y.${p("rate")})::bigint
  ${scope}
  group by a.${w("id")}, y.${p("id")}, y.${p("rate")};
  update ${deliveries} x set ${d("status")} = 'claimed', ${d("claimLine")} = z.${l("id")}
  from ${lines} z
  where z.${l("tenant")} = v_claim.${c("tenant")} and z.${l("claim")} = v_claim.${c("id")}
    and x.${d("tenant")} = z.${l("tenant")} and x.${d("award")} = z.${l("award")}
    and x.${d("status")} = 'approved' and x.${d("claimLine")} is null
    and x.${d("deliveredOn")} >= build_funding_claim.period_start and x.${d("deliveredOn")} <= build_funding_claim.period_end;
  update ${claims} x set ${c("total")} = (
    select coalesce(sum(z.${l("amount")}), 0) from ${lines} z where z.${l("tenant")} = v_claim.${c("tenant")} and z.${l("claim")} = v_claim.${c("id")}
  )
  where x.${c("id")} = v_claim.${c("id")}
  returning x.* into v_claim;
  ${claimRecord(ctx, "funding_claim.created", "v_claim", "", "Funding claim built")}
  ${ctx.hook("after_funding_claim_build", [["uuid", `v_claim.${c("id")}`]])}
  return ${claimBody("v_claim")};
end;
$$;
${userGrant(`${fn("build_funding_claim")}(${idType}, uuid, date, date, text)`)}

-- A claim with its lines, each with its award, product and deliveries: what a
-- FundingClaimFormat renders.
create or replace function ${fn("get_funding_claim")}(claim_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim ${claims}%rowtype;
begin
  select * into v_claim from ${claims} x where x.${c("id")} = get_funding_claim.claim_id;
  if not found then
    ${claimNotFound}
  end if;
  if not ${allowed(`v_claim.${c("tenant")}`, read)} then
    ${forbidden("not allowed to read funding claims")}
  end if;
  return ${claimBody("v_claim")};
end;
$$;
${userGrant(`${fn("get_funding_claim")}(uuid)`)}

-- Marks a draft claim sent, with the channel's reference and the SHA-256 of
-- the file that was sent.
create or replace function ${fn("mark_funding_claim_sent")}(claim_id uuid, external_ref text default null, payload_sha256 text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim ${claims}%rowtype;
  v_ref text := nullif(trim(mark_funding_claim_sent.external_ref), '');
  v_sha text := lower(nullif(trim(mark_funding_claim_sent.payload_sha256), ''));
begin
  ${lookup("mark_funding_claim_sent")}
  if v_claim.${c("status")} <> 'draft' then
    ${notDraft}
  end if;
  if v_ref is not null and length(v_ref) > 200 then
    ${invalid("external_ref is at most 200 characters")}
  end if;
  if v_sha is not null and v_sha !~ '^[0-9a-f]{64}$' then
    ${invalid("payload_sha256 is a SHA-256 in hex")}
  end if;
  update ${claims} x set ${c("status")} = 'sent', ${c("sentAt")} = now(), ${c("externalRef")} = v_ref, ${c("payloadSha256")} = v_sha${touch}
  where x.${c("id")} = v_claim.${c("id")}
  returning x.* into v_claim;
  ${claimRecord(ctx, "funding_claim.sent", "v_claim", `, 'externalRef', v_claim.${c("externalRef")}`, "Funding claim sent")}
  return ${claimJson(ctx, "v_claim")};
end;
$$;
${userGrant(`${fn("mark_funding_claim_sent")}(uuid, text, text)`)}

-- Records the funder's response to a sent claim: lines is an array of
-- { lineId, status (accepted or rejected), rejectionCode }, or null for
-- none. A line the response leaves out is accepted. The deliveries of a rejected line go back
-- to approved, for correction and a later claim.
create or replace function ${fn("record_funding_claim_response")}(claim_id uuid, lines jsonb, response jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim ${claims}%rowtype;
  v_line jsonb;
  v_status text;
  v_code text;
  v_accepted integer;
  v_rejected integer;
begin
  ${lookup("record_funding_claim_response")}
  if v_claim.${c("status")} <> 'sent' then
    ${fail("FUNDING_CLAIM_STATUS_INVALID", "only a sent claim takes a response", "22023")}
  end if;
  if jsonb_typeof(coalesce(record_funding_claim_response.lines, '[]'::jsonb)) <> 'array' then
    ${invalid("lines is an array")}
  end if;
  for v_line in select value from jsonb_array_elements(coalesce(record_funding_claim_response.lines, '[]'::jsonb)) loop
    v_status := v_line ->> 'status';
    v_code := nullif(trim(v_line ->> 'rejectionCode'), '');
    if jsonb_typeof(v_line) <> 'object' or v_status is null or v_status not in ('accepted', 'rejected') then
      ${invalid("each line has a lineId and a status of accepted or rejected")}
    end if;
    if v_code is not null and length(v_code) > 100 then
      ${invalid("a rejection code is at most 100 characters")}
    end if;
    update ${lines} x set ${l("status")} = v_status, ${l("rejectionCode")} = case when v_status = 'rejected' then v_code end
    where x.${l("tenant")} = v_claim.${c("tenant")} and x.${l("claim")} = v_claim.${c("id")}
      and x.${l("id")}::text = v_line ->> 'lineId';
    if not found then
      ${invalid("a line in the response isn't a line of this claim")}
    end if;
  end loop;
  update ${lines} x set ${l("status")} = 'accepted'
  where x.${l("tenant")} = v_claim.${c("tenant")} and x.${l("claim")} = v_claim.${c("id")} and x.${l("status")} = 'pending';
  ${release(` and z.${l("status")} = 'rejected'`)}
  select count(*) filter (where z.${l("status")} = 'accepted'), count(*) filter (where z.${l("status")} = 'rejected')
  into v_accepted, v_rejected
  from ${lines} z where z.${l("tenant")} = v_claim.${c("tenant")} and z.${l("claim")} = v_claim.${c("id")};
  update ${claims} x set
    ${c("status")} = case when v_rejected = 0 then 'accepted' when v_accepted = 0 then 'rejected' else 'partially_accepted' end,
    ${c("response")} = record_funding_claim_response.response${touch}
  where x.${c("id")} = v_claim.${c("id")}
  returning x.* into v_claim;
  ${claimRecord(ctx, "funding_claim.responded", "v_claim", "", "Funding claim response recorded")}
  return ${claimBody("v_claim")};
end;
$$;
${userGrant(`${fn("record_funding_claim_response")}(uuid, jsonb, jsonb)`)}

-- Deletes a draft claim; its deliveries go back to approved.
create or replace function ${fn("delete_funding_claim")}(claim_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim ${claims}%rowtype;
begin
  ${lookup("delete_funding_claim")}
  if v_claim.${c("status")} <> 'draft' then
    ${notDraft}
  end if;
  ${release("")}
  delete from ${claims} x where x.${c("id")} = v_claim.${c("id")};
  ${claimRecord(ctx, "funding_claim.deleted", "v_claim", "", "Draft funding claim deleted")}
  return true;
end;
$$;
${userGrant(`${fn("delete_funding_claim")}(uuid)`)}
${invoice}
create or replace function ${fn("list_funding_claims")}(tenant ${idType}, status text default null, funder_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${claimJson(ctx, "x")} order by x.${c("periodStart")} desc, x.${c("number")} desc), '[]'::jsonb)
  from ${claims} x
  where x.${c("tenant")} = list_funding_claims.tenant
    and (list_funding_claims.status is null or x.${c("status")} = list_funding_claims.status)
    and (list_funding_claims.funder_id is null or x.${c("funder")} = list_funding_claims.funder_id)
$$;
${userGrant(`${fn("list_funding_claims")}(${idType}, text, uuid)`)}
`;
}

/** `invoice_funding_claim`: an invoice to the funder for the accepted lines. */
function invoiceFunction(ctx: BlockSqlContext): string {
  const invoices = ctx.of("invoices");
  const contacts = ctx.of("contacts");
  const products = ctx.table("products");
  const claims = ctx.table("claims");
  const lines = ctx.table("claimLines");
  const p = (column: string): string => ctx.col("products", column);
  const c = (column: string): string => ctx.col("claims", column);
  const l = (column: string): string => ctx.col("claimLines", column);
  const fn = (name: string): string => ctx.fn(name);
  const { claim } = fundingKeys(ctx);

  const touch = ctx.has("claims", "updatedAt")
    ? `, ${c("updatedAt")} = now()`
    : "";

  const allowed = `(${SERVICE_CALLER} or ${ctx.can("tenant", `v_claim.${c("tenant")}`, claim)})`;

  return `
-- Invoices the funder for the accepted lines of a claim, through
-- create_invoice: one invoice line per claim line at the product rate. attrs
-- goes to create_invoice (title, termsDays, note); a claim is invoiced once.
create or replace function ${fn("invoice_funding_claim")}(claim_id uuid, attrs jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim ${claims}%rowtype;
  v_party jsonb;
  v_lines jsonb;
  v_invoice jsonb;
begin
  select * into v_claim from ${claims} x where x.${c("id")} = invoice_funding_claim.claim_id for update;
  if not found then
    ${fail("FUNDING_CLAIM_NOT_FOUND", "funding claim not found", "P0002")}
  end if;
  if not ${allowed} then
    ${fail("FUNDING_FORBIDDEN", "not allowed to claim funding")}
  end if;
  if v_claim.${c("status")} not in ('accepted', 'partially_accepted') then
    ${fail("FUNDING_CLAIM_STATUS_INVALID", "only a claim the funder accepted is invoiced", "22023")}
  end if;
  if v_claim.${c("invoice")} is not null then
    ${fail("FUNDING_INVALID", "the funding claim is invoiced already", "22023")}
  end if;
  v_party := case
    when exists (select 1 from ${contacts.table("companies")} x where x.${contacts.col("companies", "id")} = v_claim.${c("funder")})
      then jsonb_build_object('company', jsonb_build_object('id', v_claim.${c("funder")}))
    else jsonb_build_object('contact', jsonb_build_object('id', v_claim.${c("funder")}))
  end;
  select coalesce(jsonb_agg(jsonb_build_object(
    'description', y.${p("code")} || ' ' || y.${p("title")},
    'quantity', z.${l("units")},
    'unitAmount', y.${p("rate")}::text
  ) order by y.${p("code")}, z.${l("id")}), '[]'::jsonb) into v_lines
  from ${lines} z
  join ${products} y on y.${p("tenant")} = z.${l("tenant")} and y.${p("id")} = z.${l("product")}
  where z.${l("tenant")} = v_claim.${c("tenant")} and z.${l("claim")} = v_claim.${c("id")} and z.${l("status")} = 'accepted';
  v_invoice := ${invoices.fn("create_invoice")}(v_claim.${c("tenant")},
    v_party || (coalesce(invoice_funding_claim.attrs, '{}'::jsonb) - 'origin' - 'company' - 'contact') || jsonb_build_object('currency', v_claim.${c("currency")},
      'title', coalesce(nullif(trim(invoice_funding_claim.attrs ->> 'title'), ''), 'Funding claim ' || v_claim.${c("number")})),
    v_lines);
  update ${claims} x set ${c("invoice")} = (v_invoice ->> 'id')::uuid${touch}
  where x.${c("id")} = v_claim.${c("id")}
  returning x.* into v_claim;
  return jsonb_build_object('claim', ${claimJson(ctx, "v_claim")}, 'invoice', v_invoice);
end;
$$;
${userGrant(`${fn("invoice_funding_claim")}(uuid, jsonb)`)}
`;
}
