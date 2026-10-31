import type { BlockSqlContext, BlockSqlTableSpec } from "../context.ts";
import type { CollectionHelpers } from "./invoices-collections.ts";
import type { InvoiceNames } from "./invoices-names.ts";

import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { fail, userGrant } from "../shared.ts";
import { lockModuleTable } from "./over-app.ts";

/**
 * The `invoice_dunning_runs` table: one run of `run_invoice_dunning` per
 * organization.
 */
export const DUNNING_RUNS_TABLE: BlockSqlTableSpec = {
  name: "invoice_dunning_runs",
  app: {},
  optionalTable: true,
  lifecycle: { tenant: "tenant", export: true },
  columns: {
    id: "id",
    tenant: "tenant_id",
    asOf: "as_of",
    createdBy: "created_by",
    createdAt: "created_at",
  },
  optional: ["createdBy"],
};

/**
 * The `invoice_dunning_run_items` table: the open items a run picked, per
 * customer.
 */
export const DUNNING_RUN_ITEMS_TABLE: BlockSqlTableSpec = {
  name: "invoice_dunning_run_items",
  app: {},
  optionalTable: true,
  lifecycle: { tenant: "tenant", export: true },
  columns: {
    id: "id",
    tenant: "tenant_id",
    run: "run_id",
    party: "party_id",
    invoice: "invoice_id",
    level: "level",
    textKey: "text_key",
    templateKey: "template_key",
    fee: "fee",
    balance: "balance",
    dueOn: "due_on",
    createdAt: "created_at",
  },
  optional: ["party", "textKey"],
};

/**
 * The `invoice_dunning_history` table: what happened to an invoice in
 * collections.
 */
export const DUNNING_HISTORY_TABLE: BlockSqlTableSpec = {
  name: "invoice_dunning_history",
  app: {},
  optionalTable: true,
  lifecycle: { tenant: "tenant", export: true },
  columns: {
    id: "id",
    tenant: "tenant_id",
    invoice: "invoice_id",
    run: "run_id",
    kind: "kind",
    level: "level",
    textKey: "text_key",
    templateKey: "template_key",
    fee: "fee",
    balance: "balance",
    note: "note",
    createdAt: "created_at",
  },
  optional: ["run", "textKey", "templateKey", "note"],
};

/** Whether the three run tables exist next to the levels. */
export function hasRuns(ctx: BlockSqlContext): boolean {
  return (
    ctx.hasTable("dunningLevels") &&
    ctx.hasTable("dunningRuns") &&
    ctx.hasTable("dunningRunItems") &&
    ctx.hasTable("dunningHistory")
  );
}

/** Whether invoices keep a collection status for hand-overs. */
export function hasHandOver(ctx: BlockSqlContext): boolean {
  return (
    hasRuns(ctx) &&
    ctx.has("invoices", "collectionStatus") &&
    ctx.has("invoices", "collectionAgencyId") &&
    ctx.has("invoices", "collectionHandedAt")
  );
}

/** The run, item and history tables, their indexes and read policies. */
export function dunningRunTablesSql(
  ctx: BlockSqlContext,
  invoices: string,
  invoiceId: string,
  read: string,
): string {
  if (!hasRuns(ctx)) {
    return "";
  }

  const runs = ctx.table("dunningRuns");
  const items = ctx.table("dunningRunItems");
  const history = ctx.table("dunningHistory");
  const r = (column: string): string => ctx.col("dunningRuns", column);
  const m = (column: string): string => ctx.col("dunningRunItems", column);
  const h = (column: string): string => ctx.col("dunningHistory", column);

  const has = (table: string, column: string): boolean =>
    ctx.has(table, column);

  const maybe = (table: string, column: string, definition: string): string =>
    has(table, column) ? `\n  ${ctx.col(table, column)} ${definition},` : "";

  const readPolicy = (name: string, tenant: string, target: string): string =>
    renderPolicy(
      makePolicy({
        table: target,
        name: ctx.naming.rename(name),
        command: "select",
        roles: ["authenticated"],
        using: ctx.scope.check(tenant, read),
      }),
      { drop: true, target },
    );

  return `
create table if not exists ${runs} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("asOf")} date not null,${maybe("dunningRuns", "createdBy", "uuid")}
  ${r("createdAt")} timestamptz not null default now()
);
create index if not exists ${ctx.naming.rename("invoice_dunning_runs_tenant_idx")} on ${runs} (${r("tenant")}, ${r("createdAt")} desc);
${lockModuleTable(ctx, "dunningRuns", { read: true })}
${readPolicy("invoice_dunning_runs_read", r("tenant"), runs)}

create table if not exists ${items} (
  ${m("id")} uuid primary key default gen_random_uuid(),
  ${m("tenant")} ${ctx.idType} not null,
  ${m("run")} uuid not null references ${runs} (${r("id")}) on delete cascade,${maybe("dunningRunItems", "party", "text")}
  ${m("invoice")} uuid not null references ${invoices} (${invoiceId}) on delete cascade,
  ${m("level")} integer not null check (${m("level")} >= 1),${maybe("dunningRunItems", "textKey", "text")}
  ${m("templateKey")} text not null,
  ${m("fee")} bigint not null default 0 check (${m("fee")} >= 0),
  ${m("balance")} bigint not null,
  ${m("dueOn")} date not null,
  ${m("createdAt")} timestamptz not null default now(),
  unique (${m("run")}, ${m("invoice")})
);
create index if not exists ${ctx.naming.rename("invoice_dunning_run_items_run_idx")} on ${items} (${m("run")}${has("dunningRunItems", "party") ? `, ${m("party")}` : ""});
create index if not exists ${ctx.naming.rename("invoice_dunning_run_items_invoice_idx")} on ${items} (${m("invoice")});
${lockModuleTable(ctx, "dunningRunItems", { read: true })}
${readPolicy("invoice_dunning_run_items_read", m("tenant"), items)}

create table if not exists ${history} (
  ${h("id")} uuid primary key default gen_random_uuid(),
  ${h("tenant")} ${ctx.idType} not null,
  ${h("invoice")} uuid not null references ${invoices} (${invoiceId}) on delete cascade,${maybe("dunningHistory", "run", `uuid references ${runs} (${r("id")}) on delete set null`)}
  ${h("kind")} text not null check (${h("kind")} in ('reminder', 'handed_over')),
  ${h("level")} integer not null default 0,${maybe("dunningHistory", "textKey", "text")}${maybe("dunningHistory", "templateKey", "text")}
  ${h("fee")} bigint not null default 0,
  ${h("balance")} bigint not null default 0,${maybe("dunningHistory", "note", "text")}
  ${h("createdAt")} timestamptz not null default clock_timestamp()
);
create index if not exists ${ctx.naming.rename("invoice_dunning_history_invoice_idx")} on ${history} (${h("invoice")}, ${h("createdAt")});
${has("dunningHistory", "run") ? `create index if not exists ${ctx.naming.rename("invoice_dunning_history_run_idx")} on ${history} (${h("run")}) where ${h("run")} is not null;\n` : ""}${lockModuleTable(ctx, "dunningHistory", { read: true })}
${readPolicy("invoice_dunning_history_read", h("tenant"), history)}
`;
}

/**
 * What `run_invoice_dunning` adds: the run row, the picked item and the history
 * row.
 */
export interface RunSql {
  readonly declare: string;
  readonly record: string;
}

/**
 * The run bookkeeping inside the `run_invoice_dunning` loop; empty without the
 * tables.
 */
export function dunningRunSql(
  ctx: BlockSqlContext,
  h: CollectionHelpers,
  partyExpression: string,
): RunSql {
  if (!hasRuns(ctx)) {
    return { declare: "", record: "" };
  }

  const { i } = h;
  const r = (column: string): string => ctx.col("dunningRuns", column);
  const m = (column: string): string => ctx.col("dunningRunItems", column);
  const y = (column: string): string => ctx.col("dunningHistory", column);
  const d = (column: string): string => ctx.col("dunningLevels", column);

  const optional = (
    table: string,
    column: string,
    value: string,
  ): { c: string; v: string } =>
    ctx.has(table, column)
      ? { c: `, ${ctx.col(table, column)}`, v: `, ${value}` }
      : { c: "", v: "" };

  const party = optional("dunningRunItems", "party", partyExpression);

  const itemText = optional(
    "dunningRunItems",
    "textKey",
    `v_level.${d("textKey")}`,
  );

  const histRun = optional("dunningHistory", "run", "v_run");

  const histText = optional(
    "dunningHistory",
    "textKey",
    `v_level.${d("textKey")}`,
  );

  const histTemplate = optional(
    "dunningHistory",
    "templateKey",
    `v_level.${d("templateKey")}`,
  );

  const createdBy = optional("dunningRuns", "createdBy", "auth.uid()");

  return {
    declare: `\n  v_run uuid;\n  v_run_tenant ${ctx.idType};`,
    record: `
    if v_run is null or v_run_tenant is distinct from v_row.${i("tenant")} then
      insert into ${ctx.table("dunningRuns")} (${r("tenant")}, ${r("asOf")}${createdBy.c})
      values (v_row.${i("tenant")}, v_today${createdBy.v})
      returning ${r("id")} into v_run;
      v_run_tenant := v_row.${i("tenant")};
    end if;
    insert into ${ctx.table("dunningRunItems")} (${m("tenant")}, ${m("run")}${party.c}, ${m("invoice")}, ${m("level")}${itemText.c}, ${m("templateKey")}, ${m("fee")}, ${m("balance")}, ${m("dueOn")})
    values (v_row.${i("tenant")}, v_run${party.v}, v_row.${i("id")}, v_level.${d("level")}${itemText.v}, v_level.${d("templateKey")}, v_level.${d("fee")}, ${h.balance("v_row")}, v_row.${i("dueOn")});
    insert into ${ctx.table("dunningHistory")} (${y("tenant")}, ${y("invoice")}${histRun.c}, ${y("kind")}, ${y("level")}${histText.c}${histTemplate.c}, ${y("fee")}, ${y("balance")})
    values (v_row.${i("tenant")}, v_row.${i("id")}${histRun.v}, 'reminder', v_level.${d("level")}${histText.v}${histTemplate.v}, v_level.${d("fee")}, ${h.balance("v_row")});`,
  };
}

/** The read functions of runs and history, and `hand_over_to_collection`. */
export function dunningRunFunctions(
  ctx: BlockSqlContext,
  n: InvoiceNames,
  h: CollectionHelpers,
): string {
  if (!hasRuns(ctx)) {
    return "";
  }

  const { fn, t } = n;
  const { i } = h;
  const runs = ctx.table("dunningRuns");
  const items = ctx.table("dunningRunItems");
  const history = ctx.table("dunningHistory");
  const r = (column: string): string => ctx.col("dunningRuns", column);
  const m = (column: string): string => ctx.col("dunningRunItems", column);
  const y = (column: string): string => ctx.col("dunningHistory", column);
  const sales = ctx.has("invoices", "direction");
  const idType = ctx.idType;

  const itemParty = ctx.has("dunningRunItems", "party")
    ? `x.${m("party")}`
    : "null::text";

  const itemText = ctx.has("dunningRunItems", "textKey")
    ? `x.${m("textKey")}`
    : "null::text";

  const histText = ctx.has("dunningHistory", "textKey")
    ? `x.${y("textKey")}`
    : "null::text";

  const histTemplate = ctx.has("dunningHistory", "templateKey")
    ? `x.${y("templateKey")}`
    : "null::text";

  const histNote = ctx.has("dunningHistory", "note")
    ? `x.${y("note")}`
    : "null::text";

  const histRunId = ctx.has("dunningHistory", "run")
    ? `x.${y("run")}`
    : "null::uuid";

  const allowed = (tenant: string, permission: string): string =>
    `(${n.service} or ${ctx.scope.can(tenant, permission)})`;

  const reads = `
-- The dunning runs of an organization, newest first: { id, asOf, items,
-- customers }.
create or replace function ${fn("list_invoice_dunning_runs")}(tenant ${idType}, max integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${allowed("list_invoice_dunning_runs.tenant", n.read)} then
    ${fail("INVOICE_FORBIDDEN", "not allowed to read this organization's invoices", "42501")}
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', z.id, 'asOf', z.as_of, 'createdAt', z.created_at, 'items', z.items, 'customers', z.customers) order by z.created_at desc)
    from (
      select a.${r("id")} as id, a.${r("asOf")} as as_of, a.${r("createdAt")} as created_at,
        (select count(*) from ${items} x where x.${m("run")} = a.${r("id")}) as items,
        (select count(distinct ${itemParty}) from ${items} x where x.${m("run")} = a.${r("id")}) as customers
      from ${runs} a where a.${r("tenant")} = list_invoice_dunning_runs.tenant
      order by a.${r("createdAt")} desc limit least(greatest(coalesce(list_invoice_dunning_runs.max, 50), 1), 500)
    ) z
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_invoice_dunning_runs")}(${idType}, integer)`)}

-- The items a run picked, grouped by customer: [{ partyId, balance, fee,
-- items: [{ invoiceId, level, textKey, templateKey, fee, balance, dueOn }] }].
-- Amounts are text.
create or replace function ${fn("list_invoice_dunning_run_items")}(run uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant ${idType};
begin
  select a.${r("tenant")} into v_tenant from ${runs} a where a.${r("id")} = list_invoice_dunning_run_items.run;
  if v_tenant is null then
    ${fail("INVOICE_DUNNING_RUN_NOT_FOUND", "no such dunning run", "P0002")}
  end if;
  if not ${allowed("v_tenant", n.read)} then
    ${fail("INVOICE_FORBIDDEN", "not allowed to read this organization's invoices", "42501")}
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('partyId', g.party, 'balance', g.balance::text, 'fee', g.fee::text, 'items', g.items) order by g.party nulls last)
    from (
      select ${itemParty} as party, sum(x.${m("balance")}) as balance, sum(x.${m("fee")}) as fee,
        jsonb_agg(jsonb_build_object('invoiceId', x.${m("invoice")}, 'level', x.${m("level")}, 'textKey', ${itemText}, 'templateKey', x.${m("templateKey")},
          'fee', x.${m("fee")}::text, 'balance', x.${m("balance")}::text, 'dueOn', x.${m("dueOn")}) order by x.${m("dueOn")}, x.${m("invoice")}) as items
      from ${items} x where x.${m("run")} = list_invoice_dunning_run_items.run
      group by ${itemParty}
    ) g
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_invoice_dunning_run_items")}(uuid)`)}

-- What happened to an invoice in collections, oldest first: [{ kind
-- (reminder or handed_over), level, textKey, templateKey, fee, balance, note,
-- runId, at }].
create or replace function ${fn("list_invoice_dunning_history")}(invoice uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant ${idType};
begin
  select x.${i("tenant")} into v_tenant from ${t("invoices")} x where x.${i("id")} = list_invoice_dunning_history.invoice;
  if v_tenant is null then
    ${fail("INVOICE_NOT_FOUND", "no such invoice you can read", "P0002")}
  end if;
  if not ${allowed("v_tenant", n.read)} then
    ${fail("INVOICE_FORBIDDEN", "not allowed to read this organization's invoices", "42501")}
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('kind', x.${y("kind")}, 'level', x.${y("level")}, 'textKey', ${histText}, 'templateKey', ${histTemplate},
      'fee', x.${y("fee")}::text, 'balance', x.${y("balance")}::text, 'note', ${histNote}, 'runId', ${histRunId}, 'at', x.${y("createdAt")})
      order by x.${y("createdAt")}, x.${y("id")})
    from ${history} x where x.${y("invoice")} = list_invoice_dunning_history.invoice
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_invoice_dunning_history")}(uuid)`)}
`;

  if (!hasHandOver(ctx)) {
    return reads;
  }

  const kd = (alias: string): string =>
    h.kd(`${alias}.${i("kind")}`, ["invoice"]);

  return `${reads}
-- Hands open sales invoices over to a collection agency, a company or person
-- (agency_party_id). Their dunning stops, collection_status becomes
-- handed_over, and each invoice records invoice.collection_started and
-- a history row. At most 500 invoices; one that isn't an open sales invoice,
-- or was handed over already, refuses the whole call. Needs invoices.collect.
-- Returns the invoices.
create or replace function ${fn("hand_over_to_collection")}(invoice_ids uuid[], agency_party_id text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("invoices")};
  v_id uuid;
  v_result jsonb := '[]'::jsonb;
begin
  if nullif(trim(hand_over_to_collection.agency_party_id), '') is null or length(hand_over_to_collection.agency_party_id) > 150
    or coalesce(array_length(hand_over_to_collection.invoice_ids, 1), 0) not between 1 and 500
    or length(hand_over_to_collection.note) > 2000 then
    ${fail("INVOICE_HAND_OVER_INVALID", "hand over 1 to 500 invoices to an agency party, with a note of at most 2000 characters", "22023")}
  end if;
  for v_id in select distinct x from unnest(hand_over_to_collection.invoice_ids) x order by x loop
    select * into v_row from ${t("invoices")} x where x.${i("id")} = v_id and ${h.can("x", n.collect)} for update;
    if v_row.${i("id")} is null then
      ${fail("INVOICE_NOT_FOUND", "no such invoice you can edit", "P0002")}
    end if;
    if not ${kd("v_row")} or ${h.st(`v_row.${i("status")}`, ["issued", "partially_paid"], true)}${sales ? ` or v_row.${i("direction")} <> 'sales'` : ""} then
      ${fail("INVOICE_NOT_PAYABLE", "only an open sales invoice goes to collection", "55000")}
    end if;
    if v_row.${i("collectionStatus")} is not null then
      ${fail("INVOICE_ALREADY_HANDED_OVER", "the invoice was handed over to collection already", "55000")}
    end if;
    update ${t("invoices")} x set
      ${i("collectionStatus")} = 'handed_over',
      ${i("collectionAgencyId")} = trim(hand_over_to_collection.agency_party_id),
      ${i("collectionHandedAt")} = now(),
      ${i("updatedAt")} = now()
    where x.${i("id")} = v_row.${i("id")}
    returning * into v_row;
    insert into ${history} (${y("tenant")}, ${y("invoice")}, ${y("kind")}, ${y("level")}, ${y("balance")}${ctx.has("dunningHistory", "note") ? `, ${y("note")}` : ""})
    values (v_row.${i("tenant")}, v_row.${i("id")}, 'handed_over', v_row.${i("dunningLevel")}, ${h.balance("v_row")}${ctx.has("dunningHistory", "note") ? ", nullif(trim(hand_over_to_collection.note), '')" : ""});
    ${h.record("invoice.collection_started", "v_row", `, 'agencyPartyId', trim(hand_over_to_collection.agency_party_id), 'balance', ${h.balance("v_row")}::text, 'level', v_row.${i("dunningLevel")}`, true)}
    v_result := v_result || ${h.row("v_row")};
  end loop;
  return v_result;
end;
$$;
${userGrant(`${fn("hand_over_to_collection")}(uuid[], text, text)`)}
`;
}
