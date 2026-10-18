import type { ExtraColumn, ModuleContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { lineItemsSql, TOTAL_COLUMNS } from "../line-items-sql.ts";
import { int8Text } from "../money-sql.ts";
import { assignNumberSql } from "../numbering-sql.ts";
import { fail, userGrant, writeExtraColumns } from "../shared.ts";
import { subjectInTenant } from "../subject-check-sql.ts";
import { watchSql } from "../watch-sql.ts";

export interface DealNames {
  readonly fn: (name: string) => string;
  readonly t: (table: string) => string;
  readonly c: (table: string, column: string) => string;
  readonly read: string;
  readonly write: string;
  readonly manage: string;
  /** Members with deals.read see every deal, not only their own. */
  readonly readAll: boolean;
  /** `text[]` SQL of the allowed motions and priorities. */
  readonly motions: string;
  readonly priorities: string;
  /** The `config.subjects` types a deal's company and contacts default to. */
  readonly company: string;
  readonly contact: string;
  /** The identifier prefix without number-sequences, such as `DEAL-`. */
  readonly prefix: string;
  /** SQL that is true for the service role. */
  readonly service: string;
  /** `options.extraColumns`, which `create_deal` and `update_deals` write by name. */
  readonly extras: readonly ExtraColumn[];
}

interface Field {
  /** The camelCase field a change names. */
  readonly field: string;
  /** The `set` list for value `v` (the change's `value`, jsonb). */
  readonly set: (v: string) => string;
}

/** Every field `update_deals` writes, keyed by its camelCase name. */
function fields(d: (column: string) => string): readonly Field[] {
  const text = (column: string) => (v: string) =>
    `${d(column)} = nullif(trim(${v} #>> '{}'), '')`;

  const cast = (column: string, type: string) => (v: string) =>
    `${d(column)} = (${v} #>> '{}')::${type}`;

  return [
    { field: "name", set: (v) => `${d("name")} = trim(${v} #>> '{}')` },
    { field: "motion", set: text("motion") },
    { field: "priority", set: text("priority") },
    { field: "ownerId", set: cast("owner", "uuid") },
    { field: "product", set: text("product") },
    { field: "seats", set: cast("seats", "integer") },
    { field: "amount", set: cast("amount", "bigint") },
    { field: "existingAmount", set: cast("existingAmount", "bigint") },
    {
      field: "currency",
      set: (v) => `${d("currency")} = upper(${v} #>> '{}')`,
    },
    { field: "valuePeriod", set: text("valuePeriod") },
    { field: "amountSource", set: text("amountSource") },
    { field: "stageId", set: cast("stage", "uuid") },
    { field: "probability", set: cast("probability", "smallint") },
    { field: "forecast", set: text("forecast") },
    { field: "closeOn", set: cast("closeOn", "date") },
    { field: "nextStep", set: text("nextStep") },
    { field: "nextAt", set: cast("nextAt", "timestamptz") },
    { field: "nextKind", set: text("nextKind") },
    {
      field: "flags",
      set: (v) =>
        `${d("flags")} = coalesce(array(select jsonb_array_elements_text(case jsonb_typeof(${v}) when 'array' then ${v} else '[]' end)), '{}')`,
    },
    { field: "source", set: text("source") },
    { field: "note", set: text("note") },
    { field: "lostReason", set: text("lostReason") },
    {
      field: "company",
      set: (v) =>
        `${d("companyType")} = ${v} ->> 'type', ${d("companyId")} = ${v} ->> 'id'`,
    },
  ];
}

export function dealFunctions(ctx: ModuleContext, n: DealNames): string {
  const { fn, t, c } = n;
  const d = (column: string): string => c("deals", column);
  const k = (column: string): string => c("contacts", column);
  const m = (column: string): string => c("members", column);
  const pipelines = ctx.of("pipelines");
  const stages = pipelines.table("stages");
  const s = (column: string): string => pipelines.col("stages", column);

  const editable = (alias: string): string =>
    `(${n.service} or (${ctx.scope.can(`${alias}.${d("tenant")}`, n.write)} and (${
      n.readAll ? "true" : "false"
    } or ${alias}.${d("owner")} = auth.uid()
      or ${ctx.scope.can(`${alias}.${d("tenant")}`, n.manage)}
      or exists (select 1 from ${t("members")} mm where mm.${m("deal")} = ${alias}.${d("id")} and mm.${m("user")} = auth.uid()))))`;

  const int8 = [
    "number",
    "amount",
    "existingAmount",
    ...Object.keys(TOTAL_COLUMNS),
  ].map(d);

  const row = (alias: string): string =>
    `to_jsonb(${alias}) || ${int8Text(alias, int8)} || jsonb_build_object(
      'contacts', coalesce((select jsonb_agg(jsonb_build_object('type', ck.${k("contactType")}, 'id', ck.${k("contactId")}, 'role', ck.${k("role")}, 'primary', ck.${k("isPrimary")}) order by ck.${k("isPrimary")} desc, ck.${k("contactId")}) from ${t("contacts")} ck where ck.${k("deal")} = ${alias}.${d("id")}), '[]'::jsonb),
      'members', coalesce((select jsonb_agg(jsonb_build_object('userId', cm.${m("user")}, 'role', cm.${m("role")}) order by cm.${m("user")}) from ${t("members")} cm where cm.${m("deal")} = ${alias}.${d("id")}), '[]'::jsonb))`;

  const payload = (
    id: string,
    tenant: string,
    name: string,
    extra = "",
  ): string =>
    `jsonb_build_object('organizationId', ${tenant}, 'dealId', ${id}, 'subjectType', 'deal', 'subjectId', ${id}::text, 'name', ${name}${extra})`;

  const recordDeal = (
    type: string,
    id: string,
    tenant: string,
    name: string,
    extra = "",
  ): string =>
    ctx.record({
      type,
      payload: payload(id, tenant, name, extra),
      subject: `'deals/' || ${id}::text`,
      tenant: `${tenant}::text`,
      audit: false,
    });

  const checkCompany = (type: string, id: string, tenant: string): string => `
  if ${id} is not null and not ${subjectInTenant(ctx, type, id, tenant)} then
    ${fail("DEAL_COMPANY_FORBIDDEN", "the company is unknown or not readable in this organization", "42501")}
  end if;`;

  const checkValues = (alias: string): string => `
  if ${alias}.${d("motion")} is not null and not (${alias}.${d("motion")} = any (${n.motions})) then
    ${fail("DEAL_MOTION_INVALID", "unknown motion", "22023")}
  end if;
  if ${alias}.${d("priority")} is not null and not (${alias}.${d("priority")} = any (${n.priorities})) then
    ${fail("DEAL_PRIORITY_INVALID", "unknown priority", "22023")}
  end if;`;

  const writes = [
    ...fields(d).map(
      (field) => `      when ${sqlString(field.field)} then
        update ${t("deals")} x set ${field.set("v_change -> 'value'")} where x.${d("id")} = v_deal returning * into v_row;`,
    ),
    ...n.extras.map(
      (extra) => `      when ${sqlString(extra.name)} then
        update ${t("deals")} x set ${extra.ident} = (jsonb_populate_record(null::${t("deals")}, jsonb_build_object(${sqlString(extra.name)}, v_change -> 'value'))).${extra.ident} where x.${d("id")} = v_deal returning * into v_row;`,
    ),
  ].join("\n");

  const watchMember = watchSql(ctx, {
    tenant: "v_tenant",
    user: "v_user",
    subjectType: "'deal'",
    subjectId: "v_deal::text",
  });

  const next = ctx.installed("engagements")
    ? ctx.of("engagements").fn("next_engagement")
    : undefined;

  const nextJoin =
    next === undefined
      ? ""
      : `\n  left join lateral (select ${next}('deal', x.${d("id")}::text) as e) ne on true`;

  const noNextStep =
    next === undefined
      ? `x.${d("nextAt")} is null`
      : `x.${d("nextAt")} is null and ne.e is null`;

  const overdue =
    next === undefined
      ? `x.${d("nextAt")} < now()`
      : `(x.${d("nextAt")} < now() or coalesce((ne.e ->> 'overdue')::boolean, false))`;

  const sum = (filter: string): string =>
    `coalesce(sum(x.${d("amount")}) filter (where ${filter}), 0)::text`;

  const inWindow = `x.${d("closeOn")} >= deal_forecast.since and x.${d("closeOn")} <= deal_forecast.until`;
  const open = `x.${d("outcome")} = 'open' and x.${d("forecast")} is distinct from 'omit'`;

  const forecastSums = `
      'won', ${sum(`x.${d("outcome")} = 'won' and x.${d("closedAt")}::date >= deal_forecast.since and x.${d("closedAt")}::date <= deal_forecast.until`)},
      'commit', ${sum(`${open} and ${inWindow} and x.${d("forecast")} = 'commit'`)},
      'bestCase', ${sum(`${open} and ${inWindow} and x.${d("forecast")} = 'best_case'`)},
      'pipeline', ${sum(`${open} and ${inWindow} and x.${d("forecast")} = 'pipeline'`)},
      'notCalled', ${sum(`${open} and ${inWindow} and x.${d("forecast")} is null`)},
      'omit', ${sum(`x.${d("outcome")} = 'open' and ${inWindow} and x.${d("forecast")} = 'omit'`)},
      'later', ${sum(`${open} and x.${d("closeOn")} > deal_forecast.until`)}`;

  return `
-- Creates a deal. attrs: name, closeOn (required), amount (minor units),
-- currency, company { type, id }, ownerId, motion, priority, product, seats,
-- existingAmount, valuePeriod, pipelineId, stageId, probability, forecast,
-- nextStep, nextAt, nextKind, flags, source, note and the extra columns by
-- name. contacts: a list of { type, id, role, primary }.
create or replace function ${fn("create_deal")}(tenant ${ctx.idType}, attrs jsonb, contacts jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deal uuid;
  v_seq bigint;
  v_identifier text;
  v_row ${t("deals")};
  v_company_type text := coalesce(create_deal.attrs -> 'company' ->> 'type', ${sqlString(n.company)});
  v_company_id text := create_deal.attrs -> 'company' ->> 'id';
begin
  if not (${n.service} or ${ctx.scope.can("create_deal.tenant", n.write)}) then
    ${fail("DEAL_FORBIDDEN", "not allowed to change deals")}
  end if;
  if nullif(trim(create_deal.attrs ->> 'name'), '') is null or (create_deal.attrs ->> 'closeOn') is null then
    ${fail("DEAL_ATTRS_INVALID", "a deal needs a name and a close date", "23502")}
  end if;${checkCompany("v_company_type", "v_company_id", "create_deal.tenant")}
  ${ctx.hook("before_deal_create", [
    [ctx.idType, "create_deal.tenant"],
    ["jsonb", "create_deal.attrs"],
  ])}
  ${assignNumberSql(
    ctx,
    "deal",
    "create_deal.tenant",
    { seq: "v_seq", identifier: "v_identifier" },
    {
      table: t("deals"),
      seq: d("number"),
      tenant: d("tenant"),
      prefix: n.prefix,
    },
  )}
  begin
    insert into ${t("deals")} (${d("tenant")}, ${d("number")}, ${d("identifier")}, ${d("name")}, ${d("companyType")}, ${d("companyId")}, ${d("owner")},
      ${d("motion")}, ${d("priority")}, ${d("product")}, ${d("seats")}, ${d("amount")}, ${d("existingAmount")}, ${d("currency")}, ${d("valuePeriod")},
      ${d("pipeline")}, ${d("stage")}, ${d("probability")}, ${d("forecast")}, ${d("closeOn")}, ${d("nextStep")}, ${d("nextAt")}, ${d("nextKind")},
      ${d("flags")}, ${d("source")}, ${d("note")}, ${d("createdBy")})
    values (create_deal.tenant, v_seq, v_identifier, trim(create_deal.attrs ->> 'name'),
      case when v_company_id is null then null else v_company_type end, v_company_id,
      coalesce((create_deal.attrs ->> 'ownerId')::uuid, auth.uid()),
      create_deal.attrs ->> 'motion', create_deal.attrs ->> 'priority', create_deal.attrs ->> 'product', (create_deal.attrs ->> 'seats')::integer,
      coalesce((create_deal.attrs ->> 'amount')::bigint, 0), coalesce((create_deal.attrs ->> 'existingAmount')::bigint, 0),
      upper(coalesce(create_deal.attrs ->> 'currency', 'EUR')), coalesce(create_deal.attrs ->> 'valuePeriod', 'one_time'),
      (create_deal.attrs ->> 'pipelineId')::uuid, (create_deal.attrs ->> 'stageId')::uuid, (create_deal.attrs ->> 'probability')::smallint,
      create_deal.attrs ->> 'forecast', (create_deal.attrs ->> 'closeOn')::date, create_deal.attrs ->> 'nextStep',
      (create_deal.attrs ->> 'nextAt')::timestamptz, create_deal.attrs ->> 'nextKind',
      coalesce(array(select jsonb_array_elements_text(case jsonb_typeof(create_deal.attrs -> 'flags') when 'array' then create_deal.attrs -> 'flags' else '[]' end)), '{}'),
      create_deal.attrs ->> 'source', create_deal.attrs ->> 'note', auth.uid())
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    ${fail("DEAL_ATTRS_INVALID", "a deal field has an invalid value", "22023")}
  end;
  v_deal := v_row.${d("id")};${writeExtraColumns(t("deals"), n.extras, "create_deal.attrs", `x.${d("id")} = v_deal`)}${checkValues("v_row")}
  if create_deal.contacts is not null then
    perform ${fn("set_deal_contacts")}(v_deal, create_deal.contacts);
  end if;
  ${recordDeal("deal.created", "v_deal", "create_deal.tenant", `v_row.${d("name")}`)}
  ${ctx.hook("after_deal_create", [["uuid", "v_deal"]])}
  return (select ${row("x")} from ${t("deals")} x where x.${d("id")} = v_deal);
end;
$$;
${userGrant(`${fn("create_deal")}(${ctx.idType}, jsonb, jsonb)`)}

-- Applies a batch of { dealId, field, value } changes, each on its own:
-- a change that fails is rejected with its reason and the others stay.
-- Returns { accepted: [{ dealId, field }], rejected: [{ dealId, field, hint, reason }] }.
create or replace function ${fn("update_deals")}(changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_change jsonb;
  v_deal uuid;
  v_field text;
  v_row ${t("deals")};
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
  v_touched uuid[] := '{}';
begin
  if jsonb_typeof(coalesce(update_deals.changes, '[]')) <> 'array' then
    ${fail("DEAL_CHANGES_INVALID", "changes must be a list of { dealId, field, value }", "22023")}
  end if;
  for v_change in select value from jsonb_array_elements(update_deals.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_deal := (v_change ->> 'dealId')::uuid;
      select * into v_row from ${t("deals")} x where x.${d("id")} = v_deal and ${editable("x")} and x.${d("archivedAt")} is null;
      if v_row.${d("id")} is null then
        ${fail("DEAL_NOT_FOUND", "no such deal you can edit", "P0002")}
      end if;
      if v_field = 'company' and jsonb_typeof(v_change -> 'value') = 'object' then
        ${checkCompany("(v_change -> 'value' ->> 'type')", "(v_change -> 'value' ->> 'id')", `v_row.${d("tenant")}`).trim()}
      end if;
      if v_field in ('amount', 'existingAmount') and jsonb_typeof(v_change -> 'value') = 'object' then
        if upper(v_change -> 'value' ->> 'currency') is distinct from v_row.${d("currency")} then
          ${fail("DEAL_CURRENCY_MISMATCH", "an amount must be in the deal's currency", "22023")}
        end if;
        v_change := jsonb_set(v_change, '{value}', v_change -> 'value' -> 'amount');
      end if;
      ${ctx.hook("before_deal_update", [
        ["uuid", "v_deal"],
        ["text", "v_field"],
        ["jsonb", "v_change -> 'value'"],
      ])}
      case v_field
${writes}
      else
        ${fail("DEAL_FIELD_UNKNOWN", "that field can't be written", "22023")}
      end case;${checkValues("v_row")}
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('dealId', v_deal, 'field', v_field));
      v_touched := array_append(v_touched, v_deal);
      ${ctx.hook("after_deal_update", [
        ["uuid", "v_deal"],
        ["text", "v_field"],
      ])}
    exception when others then
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('dealId', v_change ->> 'dealId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from ${t("deals")} x where x.${d("id")} = any (v_touched) loop
    ${recordDeal("deal.updated", `v_row.${d("id")}`, `v_row.${d("tenant")}`, `v_row.${d("name")}`, `, 'fields', (select jsonb_agg(distinct a ->> 'field') from jsonb_array_elements(v_accepted) a where (a ->> 'dealId')::uuid = v_row.${d("id")})`)}
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$$;
${userGrant(`${fn("update_deals")}(jsonb)`)}

-- Closes a deal as won or lost: it moves to the first success or failure
-- stage of its pipeline, which sets its outcome.
create or replace function ${fn("close_deal")}(deal uuid, outcome text, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("deals")};
  v_stage uuid;
begin
  select * into v_row from ${t("deals")} x where x.${d("id")} = close_deal.deal and ${editable("x")};
  if v_row.${d("id")} is null then
    ${fail("DEAL_NOT_FOUND", "no such deal you can edit", "P0002")}
  end if;
  if close_deal.outcome not in ('won', 'lost') then
    ${fail("DEAL_OUTCOME_INVALID", "close a deal as won or lost", "22023")}
  end if;
  select st.${s("id")} into v_stage from ${stages} st
  where st.${s("pipeline")} = v_row.${d("pipeline")} and st.${s("archivedAt")} is null
    and st.${s("outcome")} = case close_deal.outcome when 'won' then 'success' else 'failure' end
  order by st.${s("rank")} collate "C" limit 1;
  if v_stage is null then
    ${fail("DEAL_STAGE_MISSING", "the pipeline has no stage for that outcome", "P0002")}
  end if;
  update ${t("deals")} x set ${d("stage")} = v_stage,
    ${d("lostReason")} = case when close_deal.outcome = 'lost' then nullif(trim(close_deal.reason), '') end,
    ${d("note")} = case when close_deal.outcome = 'won' then coalesce(nullif(trim(close_deal.reason), ''), x.${d("note")}) else x.${d("note")} end
  where x.${d("id")} = close_deal.deal;
  return (select ${row("x")} from ${t("deals")} x where x.${d("id")} = close_deal.deal);
end;
$$;
${userGrant(`${fn("close_deal")}(uuid, text, text)`)}

-- Opens a closed deal again in stage, or its pipeline's first open stage.
create or replace function ${fn("reopen_deal")}(deal uuid, stage uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("deals")};
  v_stage uuid := reopen_deal.stage;
begin
  select * into v_row from ${t("deals")} x where x.${d("id")} = reopen_deal.deal and ${editable("x")};
  if v_row.${d("id")} is null then
    ${fail("DEAL_NOT_FOUND", "no such deal you can edit", "P0002")}
  end if;
  if v_stage is null then
    select st.${s("id")} into v_stage from ${stages} st
    where st.${s("pipeline")} = v_row.${d("pipeline")} and st.${s("archivedAt")} is null and st.${s("outcome")} = 'open'
    order by st.${s("rank")} collate "C" limit 1;
  end if;
  update ${t("deals")} x set ${d("stage")} = v_stage where x.${d("id")} = reopen_deal.deal;
  return (select ${row("x")} from ${t("deals")} x where x.${d("id")} = reopen_deal.deal);
end;
$$;
${userGrant(`${fn("reopen_deal")}(uuid, uuid)`)}

-- Replaces a deal's contacts with a list of { type, id, role, primary }.
create or replace function ${fn("set_deal_contacts")}(deal uuid, contacts jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_deal uuid := set_deal_contacts.deal;
  v_item jsonb;
  v_count integer;
begin
  select x.${d("tenant")} into v_tenant from ${t("deals")} x where x.${d("id")} = v_deal and ${editable("x")};
  if v_tenant is null then
    ${fail("DEAL_NOT_FOUND", "no such deal you can edit", "P0002")}
  end if;
  if jsonb_typeof(coalesce(set_deal_contacts.contacts, '[]')) <> 'array' then
    ${fail("DEAL_CONTACTS_INVALID", "contacts must be a list of { type, id }", "22023")}
  end if;
  for v_item in select value from jsonb_array_elements(set_deal_contacts.contacts) loop
    if not ${subjectInTenant(ctx, `coalesce(v_item ->> 'type', ${sqlString(n.contact)})`, "(v_item ->> 'id')", "v_tenant")} then
      ${fail("DEAL_CONTACT_FORBIDDEN", "a contact is unknown or not readable in this organization", "42501")}
    end if;
  end loop;
  if (select count(*) from jsonb_array_elements(set_deal_contacts.contacts) x where coalesce((x.value ->> 'primary')::boolean, false)) > 1 then
    ${fail("DEAL_CONTACTS_INVALID", "a deal has one primary contact", "22023")}
  end if;
  delete from ${t("contacts")} x where x.${k("deal")} = v_deal;
  insert into ${t("contacts")} (${k("tenant")}, ${k("deal")}, ${k("contactType")}, ${k("contactId")}, ${k("role")}, ${k("isPrimary")})
  select v_tenant, v_deal, coalesce(x.value ->> 'type', ${sqlString(n.contact)}), x.value ->> 'id', x.value ->> 'role', coalesce((x.value ->> 'primary')::boolean, false)
  from jsonb_array_elements(set_deal_contacts.contacts) x
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${userGrant(`${fn("set_deal_contacts")}(uuid, jsonb)`)}

-- Replaces a deal's team with a list of { userId, role }. Each member
-- watches the deal.
create or replace function ${fn("set_deal_members")}(deal uuid, members jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_deal uuid := set_deal_members.deal;
  v_user uuid;
  v_count integer;
begin
  select x.${d("tenant")} into v_tenant from ${t("deals")} x where x.${d("id")} = v_deal and ${editable("x")};
  if v_tenant is null then
    ${fail("DEAL_NOT_FOUND", "no such deal you can edit", "P0002")}
  end if;
  if jsonb_typeof(coalesce(set_deal_members.members, '[]')) <> 'array' then
    ${fail("DEAL_MEMBERS_INVALID", "members must be a list of { userId, role }", "22023")}
  end if;
  delete from ${t("members")} x where x.${m("deal")} = v_deal;
  insert into ${t("members")} (${m("tenant")}, ${m("deal")}, ${m("user")}, ${m("role")})
  select v_tenant, v_deal, (x.value ->> 'userId')::uuid, x.value ->> 'role'
  from jsonb_array_elements(set_deal_members.members) x
  on conflict do nothing;
  get diagnostics v_count = row_count;${
    watchMember === ""
      ? ""
      : `
  for v_user in select (x.value ->> 'userId')::uuid from jsonb_array_elements(set_deal_members.members) x loop
    ${watchMember}
  end loop;`
  }
  return v_count;
end;
$$;
${userGrant(`${fn("set_deal_members")}(uuid, jsonb)`)}
${lineItemsSql(
  ctx,
  {
    lines: "lines",
    parent: "deals",
    frozen: `p.${d("locked")}`,
    afterTotals: `${d("amount")} = case when x.${d("amountSource")} = 'line_items' then v_list - v_discount else x.${d("amount")} end`,
  },
  {
    setter: "set_deal_lines",
    guard: `if not exists (select 1 from ${t("deals")} x where x.${d("id")} = v_parent and ${editable("x")}) then
    ${fail("DEAL_NOT_FOUND", "no such deal you can edit", "P0002")}
  end if;`,
  },
)}
create or replace function ${fn("archive_deal")}(deal uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("deals")};
begin
  update ${t("deals")} x set ${d("archivedAt")} = case when archive_deal.archived then coalesce(x.${d("archivedAt")}, now()) end
  where x.${d("id")} = archive_deal.deal and ${editable("x")}
  returning * into v_row;
  if v_row.${d("id")} is null then
    return false;
  end if;
  if archive_deal.archived then
    ${recordDeal("deal.archived", `v_row.${d("id")}`, `v_row.${d("tenant")}`, `v_row.${d("name")}`)}
  end if;
  return true;
end;
$$;
${userGrant(`${fn("archive_deal")}(uuid, boolean)`)}

-- Deletes a deal. Needs deals.manage, or the deal's owner.
create or replace function ${fn("delete_deal")}(deal uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("deals")};
begin
  delete from ${t("deals")} x
  where x.${d("id")} = delete_deal.deal
    and (${n.service} or x.${d("owner")} = auth.uid() or ${ctx.scope.can(`x.${d("tenant")}`, n.manage)})
  returning * into v_row;
  if v_row.${d("id")} is null then
    return false;
  end if;
  ${recordDeal("deal.deleted", `v_row.${d("id")}`, `v_row.${d("tenant")}`, `v_row.${d("name")}`)}
  return true;
end;
$$;
${userGrant(`${fn("delete_deal")}(uuid)`)}

-- The forecast call for one currency between since and until: won deals
-- closed in the window, open deals closing in it by forecast category
-- (notCalled for none), later for open deals closing after it, and each
-- owner's split. target is the period goal in minor units; attainment is
-- won plus commit over it. Runs as the caller, so it sums what they see.
create or replace function ${fn("deal_forecast")}(tenant ${ctx.idType}, pipeline uuid, since date, until date, currency text, target bigint, owner uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with scoped as (
    select * from ${t("deals")} x
    where x.${d("tenant")} = deal_forecast.tenant
      and x.${d("currency")} = upper(deal_forecast.currency)
      and x.${d("archivedAt")} is null
      and (deal_forecast.pipeline is null or x.${d("pipeline")} = deal_forecast.pipeline)
      and (deal_forecast.owner is null or x.${d("owner")} = deal_forecast.owner)
  ),
  totals as (
    select jsonb_build_object(${forecastSums}
    ) as sums
    from scoped x
  ),
  owners as (
    select coalesce(jsonb_agg(o.value order by o.owner_id), '[]'::jsonb) as list
    from (
      select x.${d("owner")} as owner_id, jsonb_build_object('ownerId', x.${d("owner")}, ${forecastSums}
      ) as value
      from scoped x group by x.${d("owner")}
    ) o
  )
  select totals.sums || jsonb_build_object(
    'currency', upper(deal_forecast.currency),
    'target', deal_forecast.target::text,
    'attainment', case when coalesce(deal_forecast.target, 0) = 0 then null
      else round(((totals.sums ->> 'won')::numeric + (totals.sums ->> 'commit')::numeric) / deal_forecast.target, 4) end,
    'gap', case when deal_forecast.target is null then null
      else greatest(deal_forecast.target - (totals.sums ->> 'won')::bigint - (totals.sums ->> 'commit')::bigint, 0)::text end,
    'owners', owners.list)
  from totals, owners;
$$;
${userGrant(`${fn("deal_forecast")}(${ctx.idType}, uuid, date, date, text, bigint, uuid)`)}

-- The open deals of a pipeline the caller can see, with the checks a
-- forecast review runs: days in stage and rotting, a slipped close date,
-- no next step, and an overdue next step.
create or replace function ${fn("deal_health")}(pipeline uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return (select coalesce(jsonb_agg(jsonb_build_object(
    'dealId', x.${d("id")}, 'identifier', x.${d("identifier")}, 'name', x.${d("name")},
    'daysInStage', (extract(epoch from now() - coalesce(x.${d("stageEnteredAt")}, x.${d("createdAt")})) / 86400)::integer,
    'rotting', st.${s("rottingAfterDays")} is not null and now() - coalesce(x.${d("stageEnteredAt")}, x.${d("createdAt")}) > make_interval(days => st.${s("rottingAfterDays")}),
    'slipped', x.${d("pushCount")} > 0 or x.${d("closeOn")} < current_date,
    'noNextStep', ${noNextStep},
    'overdue', coalesce(${overdue}, false)
  ) order by x.${d("closeOn")}, x.${d("id")}), '[]'::jsonb)
  from ${t("deals")} x
  left join ${stages} st on st.${s("id")} = x.${d("stage")}${nextJoin}
  where x.${d("pipeline")} = deal_health.pipeline and x.${d("outcome")} = 'open' and x.${d("archivedAt")} is null);
end;
$$;
${userGrant(`${fn("deal_health")}(uuid)`)}
`;
}
