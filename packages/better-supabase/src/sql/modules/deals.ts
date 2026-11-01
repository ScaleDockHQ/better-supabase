import type { DealsEvents } from "../../blocks/deals/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockContributes } from "../contributions.ts";
import type { BlockSqlDefinition } from "../module-types.ts";
import type { DealNames } from "./deals-functions.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  lineExtraColumns,
  lineTableSpec,
  totalColumnsSql,
} from "../line-items-sql.ts";
import { link } from "../links.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  addExtraColumns,
  fail,
  lockTable,
  schemaPreamble,
  triggerGrant,
} from "../shared.ts";
import { watchSql } from "../watch-sql.ts";
import { DEAL_COLUMNS, dealFunctions } from "./deals-functions.ts";
import { moduleOperations } from "./permissions-model.ts";

const DEAL = [
  "organizationId",
  "dealId",
  "subjectType",
  "subjectId",
  "name",
] as const;

const EVENTS: BlockSqlEvents<DealsEvents> = {
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

const NAMES: BlockSqlNames = {
  links: [
    link("contact", "reference", "deal", "contacts", "person"),
    link("company", "reference", "deal", "contacts", "company"),
  ],
  entities: {
    deal: {
      table: "deals",
      singular: "deal",
      primary: true,
      subject: {
        title: "name",
        deletedAt: "archivedAt",
        permissions: { read: "read", write: "write" },
        rank: { column: "rank", group: "stage" },
        search: { title: "name", body: ["identifier", "note"] },
      },
    },
  },
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
    "lineExtraColumns",
    "lineRates",
  ],
  tables: {
    deals: {
      name: "deals",
      app: {},
      lifecycle: { tenant: "tenant", user: "owner", export: true },
      columns: DEAL_COLUMNS,
      optional: [
        "motion",
        "priority",
        "product",
        "seats",
        "existingAmount",
        "slippedFrom",
        "pushCount",
        "nextStep",
        "nextAt",
        "nextKind",
        "flags",
        "source",
        "lostReason",
        "createdBy",
      ],
      typed: ["valuePeriod", "amountSource", "outcome", "forecast"],
    },
    contacts: {
      name: "deal_contacts",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        tenant: "tenant_id",
        deal: "deal_id",
        contactType: "contact_type",
        contactId: "contact_id",
        role: "role",
        isPrimary: "is_primary",
      },
      optional: ["role"],
    },
    members: {
      name: "deal_members",
      app: {},
      lifecycle: { tenant: "tenant", user: "user", export: true },
      columns: {
        tenant: "tenant_id",
        deal: "deal_id",
        user: "user_id",
        role: "role",
      },
      optional: ["role"],
    },
    lines: lineTableSpec("deal_lines"),
  },
};

const NAME = /^[a-z][a-z0-9_]{0,62}$/;

function names(
  ctx: BlockSqlContext,
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

function tables(ctx: BlockSqlContext, n: DealNames): string {
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

  const definitions: readonly (readonly [string, (name: string) => string])[] =
    [
      ["id", () => "uuid primary key default gen_random_uuid()"],
      ["tenant", () => `${ctx.idType} not null`],
      ["number", () => "bigint not null"],
      ["identifier", () => "text not null"],
      [
        "name",
        (name) => `text not null check (length(${name}) between 1 and 300)`,
      ],
      ["companyType", () => "text"],
      ["companyId", () => "text"],
      ["motion", () => "text"],
      ["priority", () => "text"],
      ["owner", () => "uuid"],
      ["product", () => "text"],
      ["seats", (name) => `integer check (${name} >= 0)`],
      ["amount", (name) => `bigint not null default 0 check (${name} >= 0)`],
      [
        "existingAmount",
        (name) => `bigint not null default 0 check (${name} >= 0)`,
      ],
      ["currency", (name) => `char(3) not null check (${name} ~ '^[A-Z]{3}$')`],
      [
        "valuePeriod",
        (name) =>
          `text not null default 'one_time' check (${name} in ('one_time', 'monthly', 'annual'))`,
      ],
      [
        "amountSource",
        (name) =>
          `text not null default 'manual' check (${name} in ('manual', 'line_items'))`,
      ],
      ["pipeline", () => "uuid"],
      ["stage", () => "uuid"],
      ["stageEnteredAt", () => "timestamptz"],
      [
        "outcome",
        (name) =>
          `text not null default 'open' check (${name} in ('open', 'won', 'lost'))`,
      ],
      [
        "probability",
        (name) => `smallint check (${name} >= 0 and ${name} <= 100)`,
      ],
      [
        "forecast",
        (name) =>
          `text check (${name} in ('commit', 'best_case', 'pipeline', 'omit'))`,
      ],
      ["openedOn", () => "date not null default current_date"],
      ["closeOn", () => "date not null"],
      ["slippedFrom", () => "date"],
      ["pushCount", () => "integer not null default 0"],
      ["closedAt", () => "timestamptz"],
      ["nextStep", () => "text"],
      ["nextAt", () => "timestamptz"],
      ["nextKind", () => "text"],
      ["flags", () => "text[] not null default '{}'"],
      ["source", () => "text"],
      ["note", () => "text"],
      ["lostReason", () => "text"],
      ["locked", () => "boolean not null default false"],
      ["rank", () => `text collate "C" not null default 'V'`],
      ["archivedAt", () => "timestamptz"],
      ["createdBy", () => "uuid"],
      ["createdAt", () => "timestamptz not null default now()"],
      ["updatedAt", () => "timestamptz not null default now()"],
    ];

  const columns = definitions
    .filter(([logical]) => n.has("deals", logical))
    .map(([logical, type]) => `${d(logical)} ${type(d(logical))}`)
    .join(",\n  ");

  // Contacts and members are replaced with `on conflict do nothing`, which
  // needs the key the module's own primary key gives.
  const appKey = (
    table: string,
    what: string,
    keys: readonly string[],
  ): string =>
    ctx.owns(table)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(table).name}_${what}_key`)} on ${t(table)} (${keys.map((key) => c(table, key)).join(", ")});`;

  return `
create table if not exists ${t("deals")} (
  ${columns},
  ${totalColumnsSql(ctx, "deals")},
  unique (${d("tenant")}, ${d("number")}),
  check ((${d("companyType")} is null) = (${d("companyId")} is null))
);
create index if not exists ${ctx.naming.rename("deals_pipeline_stage_idx")} on ${t("deals")} (${d("pipeline")}, ${d("stage")}, ${d("rank")});
create index if not exists ${ctx.naming.rename("deals_tenant_close_idx")} on ${t("deals")} (${d("tenant")}, ${d("closeOn")}) where ${d("outcome")} = 'open';
create index if not exists ${ctx.naming.rename("deals_owner_idx")} on ${t("deals")} (${d("owner")});
create index if not exists ${ctx.naming.rename("deals_company_idx")} on ${t("deals")} (${d("companyType")}, ${d("companyId")});${addExtraColumns(t("deals"), n.extras)}
${lockTable(t("deals"), { read: true })}

create table if not exists ${t("contacts")} (
  ${k("tenant")} ${ctx.idType} not null,
  ${k("deal")} uuid not null references ${t("deals")} (${d("id")}) on delete cascade,
  ${k("contactType")} text not null,
  ${k("contactId")} text not null,
  ${n.has("contacts", "role") ? `${k("role")} text,\n  ` : ""}${k("isPrimary")} boolean not null default false,
  primary key (${k("deal")}, ${k("contactType")}, ${k("contactId")})
);${appKey("contacts", "contact", ["deal", "contactType", "contactId"])}
create index if not exists ${ctx.naming.rename("deal_contacts_contact_idx")} on ${t("contacts")} (${k("contactType")}, ${k("contactId")});
create unique index if not exists ${ctx.naming.rename("deal_contacts_primary_idx")} on ${t("contacts")} (${k("deal")}) where ${k("isPrimary")};
${lockTable(t("contacts"), { read: true })}

create table if not exists ${t("members")} (
  ${m("tenant")} ${ctx.idType} not null,
  ${m("deal")} uuid not null references ${t("deals")} (${d("id")}) on delete cascade,
  ${m("user")} uuid not null,
  ${n.has("members", "role") ? `${m("role")} text,\n  ` : ""}primary key (${m("deal")}, ${m("user")})
);${appKey("members", "user", ["deal", "user"])}
create index if not exists ${ctx.naming.rename("deal_members_user_idx")} on ${t("members")} (${m("user")});
${lockTable(t("members"), { read: true })}

-- A deal is visible to members with deals.read; with readAll off, only to
-- its owner, its team and members with deals.manage. The team policy reads
-- no deal, so the two policies don't recurse.
${renderPolicy(makePolicy({ table: t("deals"), name: ctx.naming.rename("deals_read"), command: "select", roles: ["authenticated"], using: visible }), { drop: true, target: t("deals") })}
${renderPolicy(makePolicy({ table: t("contacts"), name: ctx.naming.rename("deal_contacts_read"), command: "select", roles: ["authenticated"], using: `exists (select 1 from ${t("deals")} x where x.${d("id")} = ${k("deal")}) and ${canSubject}(${k("contactType")}, ${k("contactId")}, 'read')` }), { drop: true, target: t("contacts") })}
${renderPolicy(makePolicy({ table: t("members"), name: ctx.naming.rename("deal_members_read"), command: "select", roles: ["authenticated"], using: `${m("user")} = (select auth.uid()) or ${ctx.scope.check(m("tenant"), n.read)}` }), { drop: true, target: t("members") })}
`;
}

/**
 * The guard trigger on deals: a locked deal takes only its note, the open date
 * never moves, a later close date counts as a slip, a closed deal's forecast
 * stays, and an outcome change stamps or clears closed_at and records
 * deal.closed or deal.reopened.
 */
function guard(ctx: BlockSqlContext, n: DealNames): string {
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

  const locked = [
    "name",
    "companyType",
    "companyId",
    "motion",
    "priority",
    "owner",
    "product",
    "seats",
    "amount",
    "existingAmount",
    "currency",
    "valuePeriod",
    "pipeline",
    "stage",
    "probability",
    "forecast",
    "closeOn",
    "nextStep",
    "nextAt",
    "nextKind",
    "flags",
    "source",
    "lostReason",
  ]
    .filter((column) => n.has("deals", column))
    .map(d)
    .map((column) => `new.${column} is distinct from old.${column}`)
    .join("\n      or ");

  const slips = [
    n.has("deals", "slippedFrom")
      ? `\n    new.${d("slippedFrom")} := coalesce(old.${d("slippedFrom")}, old.${d("closeOn")});`
      : "",
    n.has("deals", "pushCount")
      ? `\n    new.${d("pushCount")} := old.${d("pushCount")} + 1;`
      : "",
  ].join("");

  const slip =
    slips === ""
      ? ""
      : `
  if new.${d("closeOn")} > old.${d("closeOn")} and old.${d("outcome")} = 'open' then${slips}
  end if;`;

  const guardName = ctx.naming.rename("bsb_deal_guard");

  return `
create or replace function better_supabase.${guardName}()
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
  end if;${slip}
  if new.${d("forecast")} is distinct from old.${d("forecast")} and new.${d("outcome")} <> 'open' and old.${d("outcome")} <> 'open' then
    ${fail("DEAL_FORECAST_CLOSED", "a closed deal is called by its stage, not a forecast", "22023")}
  end if;
  if new.${d("outcome")} is distinct from old.${d("outcome")} then
    new.${d("closedAt")} := case when new.${d("outcome")} <> 'open' then now() end;
    if new.${d("outcome")} = 'open' then
${n.has("deals", "lostReason") ? `      new.${d("lostReason")} := null;\n` : ""}      ${ctx.record({ type: "deal.reopened", payload: payload(""), subject, tenant, audit: false })}
    else
      ${ctx.record({ type: "deal.closed", payload: payload(`, 'outcome', new.${d("outcome")}, 'amount', new.${d("amount")}::text, 'currency', new.${d("currency")}, 'reason', ${n.has("deals", "lostReason") ? `new.${d("lostReason")}` : "null::text"}`), subject, tenant, audit: false })}
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
${triggerGrant(`better_supabase.${guardName}()`)}
drop trigger if exists ${guardName} on ${t("deals")};
create trigger ${guardName} before insert or update on ${t("deals")}
for each row execute function better_supabase.${guardName}();
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const keys = moduleOperations("deals");
  const readAll = ctx.flag("readAll", true);

  const n: DealNames = {
    fn: (name) => ctx.fn(name),
    t: (table) => ctx.table(table),
    c: (table, column) => ctx.col(table, column),
    has: (table, column) => ctx.has(table, column),
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
    lineExtras: lineExtraColumns(ctx),
  };

  return `${schemaPreamble(ctx)}
-- Deals on pipelines: an amount in minor units, a company and contacts, a
-- forecast call, close-date slips, a next step and line items.
${tables(ctx, n)}${guard(ctx, n)}${dealFunctions(ctx, n)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
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

/** How deals run on pipelines, under the deal column names `column` gives. */
const dealPipeline = (
  column: (logical: string) => string,
): Readonly<Record<string, unknown>> => ({
  enteredAt: column("stageEnteredAt"),
  amount: column("amount"),
  currency: column("currency"),
  probability: column("probability"),
  owner: column("owner"),
  categories: { open: "open", won: "success", lost: "failure" },
  status: {
    column: column("outcome"),
    values: { open: "open", won: "won", lost: "lost" },
  },
  stages: [
    { key: "qualified", name: "Qualified", category: "open", probability: 20 },
    { key: "discovery", name: "Discovery", category: "open", probability: 35 },
    { key: "proposal", name: "Proposal", category: "open", probability: 55 },
    {
      key: "negotiation",
      name: "Negotiation",
      category: "open",
      probability: 75,
    },
    {
      key: "closed_won",
      name: "Closed won",
      category: "won",
      probability: 100,
    },
    {
      key: "closed_lost",
      name: "Closed lost",
      category: "lost",
      probability: 0,
    },
  ],
});

const CONTRIBUTES: BlockContributes = {
  pipelines: (own) => {
    const { schema, name } = own.tableName("deals");

    return [
      {
        type: own.resolved.entityNaming.rename("deal"),
        table: `${schema}.${name}`,
        tenant: own.colName("deals", "tenant"),
        entry: dealPipeline((logical) => own.colName("deals", logical)),
      },
    ];
  },
};

export const DEALS: BlockSqlDefinition = {
  contributes: CONTRIBUTES,
  name: "deals",
  scopes: ["tenant"],
  title: "Deals",
  description:
    "Deals on pipelines: amounts in minor units, a company and contacts, a deal team, line items, forecast calls with attainment, close-date slips, a next step, locking and batched edits with per-change rejections.",
  requires: ["memberships", "permissions", "subjects", "pipelines"],
  // The pipelines module binds the deals table, so the table comes first.
  before: "pipelines",
  integrates: ["outbox", "notifications", "numbering", "activities"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
