import type { DealsEvents } from "../../blocks/deals/events.ts";
import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import { sqlString } from "../../core/template.ts";
import {
  lineTableSpec,
  TOTAL_COLUMNS,
  totalColumnsSql,
} from "../line-items-sql.ts";
import {
  addExtraColumns,
  fail,
  lockTable,
  schemaPreamble,
  triggerGrant,
} from "../shared.ts";
import { watchSql } from "../watch-sql.ts";
import { moduleOperations } from "./access-model.ts";
import { dealFunctions, type DealNames } from "./deals-functions.ts";

const DEAL = [
  "organizationId",
  "dealId",
  "subjectType",
  "subjectId",
  "name",
] as const;

const EVENTS: ModuleEvents<DealsEvents> = {
  "deal.created": { subject: "deals", payload: [...DEAL] },
  "deal.updated": { subject: "deals", payload: [...DEAL, "fields"] },
  "deal.closed": {
    subject: "deals",
    payload: [...DEAL, "outcome", "amount", "currency", "reason"],
  },
  "deal.reopened": { subject: "deals", payload: [...DEAL] },
  "deal.archived": { subject: "deals", payload: [...DEAL] },
  "deal.deleted": { subject: "deals", payload: [...DEAL] },
};

const NAMES: ModuleNames = {
  events: EVENTS,
  hooks: [
    "before_deal_create",
    "after_deal_create",
    "before_deal_update",
    "after_deal_update",
  ],
  options: [
    "company",
    "contact",
    "motions",
    "priorities",
    "prefix",
    "readAll",
    "extraColumns",
  ],
  tables: {
    deals: {
      name: "deals",
      lifecycle: { tenant: "tenant", user: "owner", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        number: "number",
        identifier: "identifier",
        name: "name",
        companyType: "company_type",
        companyId: "company_id",
        motion: "motion",
        priority: "priority",
        owner: "owner_user_id",
        product: "product",
        seats: "seats",
        amount: "amount",
        existingAmount: "existing_amount",
        currency: "currency",
        valuePeriod: "value_period",
        amountSource: "amount_source",
        pipeline: "pipeline_id",
        stage: "stage_id",
        stageEnteredAt: "stage_entered_at",
        outcome: "outcome",
        probability: "probability",
        forecast: "forecast_category",
        openedOn: "opened_on",
        closeOn: "expected_close_on",
        slippedFrom: "slipped_from",
        pushCount: "push_count",
        closedAt: "closed_at",
        nextStep: "next_step",
        nextAt: "next_at",
        nextKind: "next_kind",
        flags: "flags",
        source: "source",
        note: "note",
        lostReason: "lost_reason",
        locked: "locked",
        rank: "rank",
        archivedAt: "archived_at",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
        ...TOTAL_COLUMNS,
      },
    },
    contacts: {
      name: "deal_contacts",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        tenant: "tenant_id",
        deal: "deal_id",
        contactType: "contact_type",
        contactId: "contact_id",
        role: "role",
        isPrimary: "is_primary",
      },
    },
    members: {
      name: "deal_members",
      lifecycle: { tenant: "tenant", user: "user", export: true },
      columns: {
        tenant: "tenant_id",
        deal: "deal_id",
        user: "user_id",
        role: "role",
      },
    },
    lines: lineTableSpec("deal_lines"),
  },
};

const NAME = /^[a-z][a-z0-9_]{0,62}$/;

function names(
  ctx: ModuleContext,
  option: "motions" | "priorities",
  fallback: readonly string[],
): string {
  const list = ctx.list(option, fallback);

  if (list.length === 0 || list.some((item) => !NAME.test(item))) {
    throw new TypeError(
      `blocks.deals.options.${option} must be a non-empty list of lowercase names`,
    );
  }

  return `${sqlString(`{${list.join(",")}}`)}::text[]`;
}

function tables(ctx: ModuleContext, n: DealNames): string {
  if (!ctx.manages) {
    return "";
  }

  const { t, c } = n;
  const d = (column: string): string => c("deals", column);
  const k = (column: string): string => c("contacts", column);
  const m = (column: string): string => c("members", column);
  const canSubject = ctx.of("subjects").fn("can_subject");

  const visible = n.readAll
    ? ctx.scope.check(d("tenant"), n.read)
    : `${ctx.scope.check(d("tenant"), n.read)} and (${d("owner")} = (select auth.uid())
      or ${ctx.scope.check(d("tenant"), n.manage)}
      or exists (select 1 from ${t("members")} x where x.${m("deal")} = ${d("id")} and x.${m("user")} = (select auth.uid())))`;

  return `
create table if not exists ${t("deals")} (
  ${d("id")} uuid primary key default gen_random_uuid(),
  ${d("tenant")} ${ctx.idType} not null,
  ${d("number")} bigint not null,
  ${d("identifier")} text not null,
  ${d("name")} text not null check (length(${d("name")}) between 1 and 300),
  ${d("companyType")} text,
  ${d("companyId")} text,
  ${d("motion")} text,
  ${d("priority")} text,
  ${d("owner")} uuid,
  ${d("product")} text,
  ${d("seats")} integer check (${d("seats")} >= 0),
  ${d("amount")} bigint not null default 0 check (${d("amount")} >= 0),
  ${d("existingAmount")} bigint not null default 0 check (${d("existingAmount")} >= 0),
  ${d("currency")} char(3) not null check (${d("currency")} ~ '^[A-Z]{3}$'),
  ${d("valuePeriod")} text not null default 'one_time' check (${d("valuePeriod")} in ('one_time', 'monthly', 'annual')),
  ${d("amountSource")} text not null default 'manual' check (${d("amountSource")} in ('manual', 'line_items')),
  ${d("pipeline")} uuid,
  ${d("stage")} uuid,
  ${d("stageEnteredAt")} timestamptz,
  ${d("outcome")} text not null default 'open' check (${d("outcome")} in ('open', 'won', 'lost')),
  ${d("probability")} smallint check (${d("probability")} >= 0 and ${d("probability")} <= 100),
  ${d("forecast")} text check (${d("forecast")} in ('commit', 'best_case', 'pipeline', 'omit')),
  ${d("openedOn")} date not null default current_date,
  ${d("closeOn")} date not null,
  ${d("slippedFrom")} date,
  ${d("pushCount")} integer not null default 0,
  ${d("closedAt")} timestamptz,
  ${d("nextStep")} text,
  ${d("nextAt")} timestamptz,
  ${d("nextKind")} text,
  ${d("flags")} text[] not null default '{}',
  ${d("source")} text,
  ${d("note")} text,
  ${d("lostReason")} text,
  ${d("locked")} boolean not null default false,
  ${d("rank")} text collate "C" not null default 'V',
  ${d("archivedAt")} timestamptz,
  ${d("createdBy")} uuid,
  ${d("createdAt")} timestamptz not null default now(),
  ${d("updatedAt")} timestamptz not null default now(),
  ${totalColumnsSql(ctx, "deals")},
  unique (${d("tenant")}, ${d("number")}),
  check ((${d("companyType")} is null) = (${d("companyId")} is null))
);
create index if not exists deals_pipeline_stage_idx on ${t("deals")} (${d("pipeline")}, ${d("stage")}, ${d("rank")});
create index if not exists deals_tenant_close_idx on ${t("deals")} (${d("tenant")}, ${d("closeOn")}) where ${d("outcome")} = 'open';
create index if not exists deals_owner_idx on ${t("deals")} (${d("owner")});
create index if not exists deals_company_idx on ${t("deals")} (${d("companyType")}, ${d("companyId")});${addExtraColumns(t("deals"), n.extras)}
${lockTable(t("deals"), { read: true })}

create table if not exists ${t("contacts")} (
  ${k("tenant")} ${ctx.idType} not null,
  ${k("deal")} uuid not null references ${t("deals")} (${d("id")}) on delete cascade,
  ${k("contactType")} text not null,
  ${k("contactId")} text not null,
  ${k("role")} text,
  ${k("isPrimary")} boolean not null default false,
  primary key (${k("deal")}, ${k("contactType")}, ${k("contactId")})
);
create index if not exists deal_contacts_contact_idx on ${t("contacts")} (${k("contactType")}, ${k("contactId")});
create unique index if not exists deal_contacts_primary_idx on ${t("contacts")} (${k("deal")}) where ${k("isPrimary")};
${lockTable(t("contacts"), { read: true })}

create table if not exists ${t("members")} (
  ${m("tenant")} ${ctx.idType} not null,
  ${m("deal")} uuid not null references ${t("deals")} (${d("id")}) on delete cascade,
  ${m("user")} uuid not null,
  ${m("role")} text,
  primary key (${m("deal")}, ${m("user")})
);
create index if not exists deal_members_user_idx on ${t("members")} (${m("user")});
${lockTable(t("members"), { read: true })}

-- A deal is visible to members with deals.read; with readAll off, only to
-- its owner, its team and members with deals.manage. The team policy reads
-- no deal, so the two policies don't recurse.
drop policy if exists deals_read on ${t("deals")};
create policy deals_read on ${t("deals")} for select to authenticated
using (${visible});
drop policy if exists deal_contacts_read on ${t("contacts")};
create policy deal_contacts_read on ${t("contacts")} for select to authenticated
using (exists (select 1 from ${t("deals")} x where x.${d("id")} = ${k("deal")}) and ${canSubject}(${k("contactType")}, ${k("contactId")}, 'read'));
drop policy if exists deal_members_read on ${t("members")};
create policy deal_members_read on ${t("members")} for select to authenticated
using (${m("user")} = (select auth.uid()) or ${ctx.scope.check(m("tenant"), n.read)});
`;
}

/**
 * The guard trigger on deals: a locked deal takes only its note, the open date
 * never moves, a later close date counts as a slip, a closed deal's forecast
 * stays, and an outcome change stamps or clears closed_at and records
 * deal.closed or deal.reopened.
 */
function guard(ctx: ModuleContext, n: DealNames): string {
  const { t, c } = n;
  const d = (column: string): string => c("deals", column);

  const payload = (extra: string): string =>
    `jsonb_build_object('organizationId', new.${d("tenant")}, 'dealId', new.${d("id")}, 'subjectType', 'deal', 'subjectId', new.${d("id")}::text, 'name', new.${d("name")}${extra})`;

  const subject = `'deals/' || new.${d("id")}::text`;
  const tenant = `new.${d("tenant")}::text`;

  const outcomeNotify = ctx.installed("notifications")
    ? `
    ${ctx.notify(
      `jsonb_build_object(
      'type', 'deal.closed',
      'tenant', new.${d("tenant")},
      'actor', auth.uid(),
      'subject_type', 'deal',
      'subject_id', new.${d("id")}::text,
      'summary', new.${d("name")},
      'key', 'deal.outcome:' || new.${d("id")}::text || ':' || new.${d("outcome")} || ':' || extract(epoch from now())::text,
      'data', jsonb_build_object('dealId', new.${d("id")}, 'outcome', new.${d("outcome")})
    )`,
      { indent: "    " },
    )}`
    : "";

  const watchOwner = watchSql(ctx, {
    tenant: `new.${d("tenant")}`,
    user: `new.${d("owner")}`,
    subjectType: "'deal'",
    subjectId: `new.${d("id")}::text`,
  });

  const locked = Object.values({
    name: d("name"),
    companyType: d("companyType"),
    companyId: d("companyId"),
    motion: d("motion"),
    priority: d("priority"),
    owner: d("owner"),
    product: d("product"),
    seats: d("seats"),
    amount: d("amount"),
    existingAmount: d("existingAmount"),
    currency: d("currency"),
    valuePeriod: d("valuePeriod"),
    pipeline: d("pipeline"),
    stage: d("stage"),
    probability: d("probability"),
    forecast: d("forecast"),
    closeOn: d("closeOn"),
    nextStep: d("nextStep"),
    nextAt: d("nextAt"),
    nextKind: d("nextKind"),
    flags: d("flags"),
    source: d("source"),
    lostReason: d("lostReason"),
  })
    .map((column) => `new.${column} is distinct from old.${column}`)
    .join("\n      or ");

  return `
create or replace function better_supabase.bs_deal_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claims text;
begin
  if tg_op = 'INSERT' then
    new.${d("closedAt")} := case when new.${d("outcome")} <> 'open' then now() end;
    ${watchOwner === "" ? "" : `if new.${d("owner")} is not null then\n      ${watchOwner}\n    end if;`}
    return new;
  end if;
  if old.${d("locked")} and not ${n.service} and (
      ${locked}
    ) then
    ${fail("DEAL_LOCKED", "the deal is locked; only its note can change", "55000")}
  end if;
  if new.${d("openedOn")} is distinct from old.${d("openedOn")} and not ${n.service} then
    ${fail("DEAL_OPENED_ON_FIXED", "the open date never moves", "22023")}
  end if;
  if new.${d("closeOn")} > old.${d("closeOn")} and old.${d("outcome")} = 'open' then
    new.${d("slippedFrom")} := coalesce(old.${d("slippedFrom")}, old.${d("closeOn")});
    new.${d("pushCount")} := old.${d("pushCount")} + 1;
  end if;
  if new.${d("forecast")} is distinct from old.${d("forecast")} and new.${d("outcome")} <> 'open' and old.${d("outcome")} <> 'open' then
    ${fail("DEAL_FORECAST_CLOSED", "a closed deal is called by its stage, not a forecast", "22023")}
  end if;
  if new.${d("outcome")} is distinct from old.${d("outcome")} then
    new.${d("closedAt")} := case when new.${d("outcome")} <> 'open' then now() end;
    if new.${d("outcome")} = 'open' then
      new.${d("lostReason")} := null;
      ${ctx.record({ type: "deal.reopened", payload: payload(""), subject, tenant, audit: false })}
    else
      ${ctx.record({ type: "deal.closed", payload: payload(`, 'outcome', new.${d("outcome")}, 'amount', new.${d("amount")}::text, 'currency', new.${d("currency")}, 'reason', new.${d("lostReason")}`), subject, tenant, audit: false })}
    end if;${outcomeNotify}
  end if;${
    watchOwner === ""
      ? ""
      : `
  if new.${d("owner")} is not null and new.${d("owner")} is distinct from old.${d("owner")} then
    ${watchOwner}
  end if;`
  }
  new.${d("updatedAt")} := now();
  return new;
end;
$$;
${triggerGrant("better_supabase.bs_deal_guard()")}
drop trigger if exists bs_deal_guard on ${t("deals")};
create trigger bs_deal_guard before insert or update on ${t("deals")}
for each row execute function better_supabase.bs_deal_guard();
`;
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const keys = moduleOperations("deals");
  const readAll = ctx.flag("readAll", true);

  const n: DealNames = {
    fn: (name) => ctx.fn(name),
    t: (table) => ctx.table(table),
    c: (table, column) => ctx.col(table, column),
    read: ctx.permission("read", keys.read),
    write: ctx.permission("write", keys.write),
    manage: ctx.permission("manage", keys.manage),
    readAll,
    motions: names(ctx, "motions", ["new_logo", "expansion", "renewal"]),
    priorities: names(ctx, "priorities", ["hot", "warm", "cold"]),
    company: ctx.text("company", "company"),
    contact: ctx.text("contact", "person"),
    prefix: ctx.text("prefix", "DEAL-"),
    service: "(auth.role() = 'service_role')",
    extras: ctx.extraColumns("deals", ["contacts", "members"]),
  };

  return `${schemaPreamble(ctx)}
-- Deals on pipelines: an amount in minor units, a company and contacts, a
-- forecast call, close-date slips, a next step and line items.
${tables(ctx, n)}${guard(ctx, n)}${dealFunctions(ctx, n)}`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    { name: "create_deal", args: ["{id}", "jsonb", "jsonb"], returns: "jsonb" },
    { name: "update_deals", args: ["jsonb"], returns: "jsonb" },
    { name: "close_deal", args: ["uuid", "text", "text"], returns: "jsonb" },
    { name: "reopen_deal", args: ["uuid", "uuid"], returns: "jsonb" },
    { name: "set_deal_contacts", args: ["uuid", "jsonb"], returns: "integer" },
    { name: "set_deal_members", args: ["uuid", "jsonb"], returns: "integer" },
    { name: "set_deal_lines", args: ["uuid", "jsonb"], returns: "jsonb" },
    { name: "archive_deal", args: ["uuid", "boolean"], returns: "boolean" },
    { name: "delete_deal", args: ["uuid"], returns: "boolean" },
    {
      name: "deal_forecast",
      args: ["{id}", "uuid", "date", "date", "text", "bigint", "uuid"],
      returns: "jsonb",
    },
    { name: "deal_health", args: ["uuid"], returns: "jsonb" },
  ];
}

export const DEALS: ModuleDefinition = {
  name: "deals",
  scopes: ["tenant"],
  title: "Deals",
  description:
    "Deals on pipelines: amounts in minor units, a company and contacts, a deal team, line items, forecast calls with attainment, close-date slips, a next step, locking and batched edits with per-change rejections.",
  requires: ["tenant", "access", "subjects", "pipelines"],
  // The pipelines module binds the deals table, so the table comes first.
  before: "pipelines",
  integrates: ["outbox", "notifications", "number-sequences", "engagements"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
