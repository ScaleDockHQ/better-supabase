import type { DonationsEvents } from "../../blocks/donations/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { addExtraColumns, extraFieldsArg, schemaPreamble } from "../shared.ts";
import { moveSubjectRows, subjectMergeHandler } from "../subject-merge-sql.ts";
import { registeredSubjects } from "../subject-registry.ts";
import { donationsFunctions, GIFT_RESERVED } from "./donations-functions.ts";
import { sequencesTable } from "./numbering.ts";
import { appUniqueIndex, lockModuleTable } from "./over-app.ts";
import { moduleOperations } from "./permissions-model.ts";

const GIFT_PAYLOAD = [
  "organizationId",
  "id",
  "donorType",
  "donorId",
  "fundId",
  "pledgeId",
  "amount",
  "currency",
  "status",
] as const;

const PLEDGE_PAYLOAD = [
  "organizationId",
  "id",
  "donorType",
  "donorId",
  "fundId",
  "amount",
  "currency",
  "frequency",
  "status",
] as const;

const RECEIPT_PAYLOAD = [
  "organizationId",
  "id",
  "number",
  "kind",
  "donorType",
  "donorId",
  "amount",
  "currency",
] as const;

const EVENTS: BlockSqlEvents<DonationsEvents> = {
  "donation.received": { subject: "donations", payload: GIFT_PAYLOAD },
  "donation.failed": { subject: "donations", payload: GIFT_PAYLOAD },
  "donation.refunded": { subject: "donations", payload: GIFT_PAYLOAD },
  "pledge.created": { subject: "pledges", payload: PLEDGE_PAYLOAD },
  "pledge.updated": { subject: "pledges", payload: PLEDGE_PAYLOAD },
  "donation_receipt.issued": {
    subject: "donation-receipts",
    payload: RECEIPT_PAYLOAD,
  },
  "donation_receipt.voided": {
    subject: "donation-receipts",
    payload: RECEIPT_PAYLOAD,
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    donation: { table: "donations", singular: "donation", primary: true },
    pledge: { table: "pledges", singular: "pledge" },
    donation_fund: {
      table: "funds",
      singular: "donation_fund",
      subject: {
        title: "name",
        permissions: { read: "read", write: "manage" },
      },
    },
    donation_receipt: { table: "receipts", singular: "donation_receipt" },
  },
  events: EVENTS,
  options: ["extraColumns"],
  tables: {
    funds: {
      name: "donation_funds",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        key: "key",
        name: "name",
        kind: "kind",
        goal: "goal",
        currency: "currency",
        startsOn: "starts_on",
        endsOn: "ends_on",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["goal", "startsOn", "endsOn"],
      typed: ["kind"],
    },
    pledges: {
      name: "pledges",
      app: {},
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        donorType: "donor_type",
        donorId: "donor_id",
        fund: "fund_id",
        amount: "amount",
        currency: "currency",
        frequency: "frequency",
        startsOn: "starts_on",
        endsOn: "ends_on",
        status: "status",
        provider: "provider",
        providerCustomer: "provider_customer",
        note: "note",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["note"],
      typed: ["frequency", "status"],
    },
    receipts: {
      name: "donation_receipts",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        donorType: "donor_type",
        donorId: "donor_id",
        sequence: "sequence",
        number: "number",
        kind: "kind",
        year: "year",
        amount: "amount",
        currency: "currency",
        issuedAt: "issued_at",
        voidedAt: "voided_at",
        voidReason: "void_reason",
      },
      optional: ["voidReason"],
      typed: ["kind"],
    },
    donations: {
      name: "donations",
      app: {},
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        donorType: "donor_type",
        donorId: "donor_id",
        fund: "fund_id",
        pledge: "pledge_id",
        periodStart: "period_start",
        amount: "amount",
        currency: "currency",
        receivedOn: "received_on",
        method: "method",
        status: "status",
        provider: "provider",
        paymentReference: "payment_reference",
        transaction: "transaction_id",
        refundTransaction: "refund_transaction_id",
        receipt: "receipt_id",
        note: "note",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["method", "refundTransaction", "note"],
      typed: ["status"],
    },
  },
};

function tables(ctx: BlockSqlContext): string {
  if (!ctx.manages) {
    return "";
  }

  const funds = ctx.table("funds");
  const pledges = ctx.table("pledges");
  const receipts = ctx.table("receipts");
  const donations = ctx.table("donations");
  const f = (column: string): string => ctx.col("funds", column);
  const p = (column: string): string => ctx.col("pledges", column);
  const r = (column: string): string => ctx.col("receipts", column);
  const d = (column: string): string => ctx.col("donations", column);
  const ops = moduleOperations("donations");
  const read = ctx.permission("read", ops.read);

  const index = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  // A column definition, left out when the app maps the column to null.
  const column = (
    table: string,
    logical: string,
    definition: (name: string) => string,
  ): string =>
    ctx.has(table, logical)
      ? `\n  ${definition(ctx.col(table, logical))},`
      : "";

  const fundChecks = [
    ...(ctx.has("funds", "goal")
      ? [`check (${f("goal")} is null or ${f("currency")} is not null)`]
      : []),
    ...(ctx.has("funds", "startsOn") && ctx.has("funds", "endsOn")
      ? [
          `check (${f("endsOn")} is null or ${f("startsOn")} is null or ${f("endsOn")} >= ${f("startsOn")})`,
        ]
      : []),
  ].map((check) => `,\n  ${check}`);

  const policy = (logical: string, table: string, tenant: string): string => `
${lockModuleTable(ctx, logical, { read: true })}
drop policy if exists ${index(logical, "read")} on ${table};
${renderPolicy(makePolicy({ table, name: index(logical, "read"), command: "select", roles: ["authenticated"], using: ctx.scope.check(tenant, read) }), { target: table })}`;

  return `
-- A fund or campaign gifts go to; goal is in minor units of currency.
create table if not exists ${funds} (
  ${f("id")} uuid primary key default gen_random_uuid(),
  ${f("tenant")} ${ctx.idType} not null,
  ${f("key")} text not null check (${f("key")} ~ '^[a-z][a-z0-9_]{0,62}$'),
  ${f("name")} text not null check (length(${f("name")}) between 1 and 200),
  ${f("kind")} text not null default 'fund' check (${f("kind")} in ('fund', 'campaign')),${column("funds", "goal", (name) => `${name} bigint check (${name} is null or ${name} > 0)`)}
  ${f("currency")} char(3) check (${f("currency")} is null or ${f("currency")} ~ '^[A-Z]{3}$'),${column("funds", "startsOn", (name) => `${name} date`)}${column("funds", "endsOn", (name) => `${name} date`)}
  ${f("archivedAt")} timestamptz,
  ${f("createdAt")} timestamptz not null default now(),
  ${f("updatedAt")} timestamptz not null default now(),
  unique (${f("tenant")}, ${f("key")}),
  unique (${f("tenant")}, ${f("id")})${fundChecks.join("")}
);${appUniqueIndex(ctx, "funds", ["tenant", "key"])}${appUniqueIndex(ctx, "funds", ["tenant", "id"])}${policy("funds", funds, f("tenant"))}

-- A recurring gift: amount every period of frequency, charged through the
-- payments provider when provider is set, recorded by hand otherwise.
create table if not exists ${pledges} (
  ${p("id")} uuid primary key default gen_random_uuid(),
  ${p("tenant")} ${ctx.idType} not null,
  ${p("donorType")} text not null,
  ${p("donorId")} text not null,
  ${p("fund")} uuid,
  ${p("amount")} bigint not null check (${p("amount")} > 0),
  ${p("currency")} char(3) not null check (${p("currency")} ~ '^[A-Z]{3}$'),
  ${p("frequency")} text not null default 'monthly' check (${p("frequency")} in ('weekly', 'monthly', 'quarterly', 'yearly')),
  ${p("startsOn")} date not null,
  ${p("endsOn")} date,
  ${p("status")} text not null default 'active' check (${p("status")} in ('active', 'paused', 'ended')),
  ${p("provider")} text,
  ${p("providerCustomer")} text,${column("pledges", "note", (name) => `${name} text check (${name} is null or length(${name}) <= 2000)`)}
  ${p("createdBy")} uuid,
  ${p("createdAt")} timestamptz not null default now(),
  ${p("updatedAt")} timestamptz not null default now(),
  foreign key (${p("tenant")}, ${p("fund")}) references ${funds} (${f("tenant")}, ${f("id")}) on delete restrict,
  check (${p("endsOn")} is null or ${p("endsOn")} > ${p("startsOn")})
);
create index if not exists ${index("pledges", "tenant_idx")} on ${pledges} (${p("tenant")}, ${p("status")});
create index if not exists ${index("pledges", "donor_idx")} on ${pledges} (${p("tenant")}, ${p("donorType")}, ${p("donorId")});
create index if not exists ${index("pledges", "fund_idx")} on ${pledges} (${p("tenant")}, ${p("fund")}) where ${p("fund")} is not null;${policy("pledges", pledges, p("tenant"))}

-- A tax receipt: one gift, or a donor's posted gifts in a year and currency.
create table if not exists ${receipts} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("donorType")} text not null,
  ${r("donorId")} text not null,
  ${r("sequence")} bigint not null,
  ${r("number")} text not null,
  ${r("kind")} text not null check (${r("kind")} in ('gift', 'yearly')),
  ${r("year")} integer not null,
  ${r("amount")} bigint not null check (${r("amount")} > 0),
  ${r("currency")} char(3) not null,
  ${r("issuedAt")} timestamptz not null default now(),
  ${r("voidedAt")} timestamptz,${column("receipts", "voidReason", (name) => `${name} text check (${name} is null or length(${name}) <= 2000)`)}
  unique (${r("tenant")}, ${r("number")})
);
create index if not exists ${index("receipts", "donor_idx")} on ${receipts} (${r("tenant")}, ${r("donorType")}, ${r("donorId")}, ${r("year")});
create unique index if not exists ${index("receipts", "yearly_key")} on ${receipts} (${r("tenant")}, ${r("donorType")}, ${r("donorId")}, ${r("year")}, ${r("currency")})
  where ${r("kind")} = 'yearly' and ${r("voidedAt")} is null;${policy("receipts", receipts, r("tenant"))}

create table if not exists ${donations} (
  ${d("id")} uuid primary key default gen_random_uuid(),
  ${d("tenant")} ${ctx.idType} not null,
  ${d("donorType")} text not null,
  ${d("donorId")} text not null,
  ${d("fund")} uuid,
  ${d("pledge")} uuid references ${pledges} (${p("id")}) on delete set null,
  -- The pledge period this gift pays; unique per pledge.
  ${d("periodStart")} date,
  ${d("amount")} bigint not null check (${d("amount")} > 0),
  ${d("currency")} char(3) not null check (${d("currency")} ~ '^[A-Z]{3}$'),
  ${d("receivedOn")} date not null default current_date,${column("donations", "method", (name) => `${name} text check (${name} is null or length(${name}) <= 40)`)}
  ${d("status")} text not null default 'pending' check (${d("status")} in ('pending', 'posted', 'failed', 'refunded')),
  ${d("provider")} text,
  ${d("paymentReference")} text,
  ${d("transaction")} uuid,${column("donations", "refundTransaction", (name) => `${name} uuid`)}
  ${d("receipt")} uuid references ${receipts} (${r("id")}) on delete set null,${column("donations", "note", (name) => `${name} text check (${name} is null or length(${name}) <= 2000)`)}
  ${d("createdBy")} uuid,
  ${d("createdAt")} timestamptz not null default now(),
  ${d("updatedAt")} timestamptz not null default now(),
  foreign key (${d("tenant")}, ${d("fund")}) references ${funds} (${f("tenant")}, ${f("id")}) on delete restrict,
  unique (${d("pledge")}, ${d("periodStart")})
);${appUniqueIndex(ctx, "donations", ["pledge", "periodStart"])}${addExtraColumns(donations, ctx.extraColumns("donations", GIFT_RESERVED))}
create index if not exists ${index("donations", "tenant_idx")} on ${donations} (${d("tenant")}, ${d("receivedOn")} desc);
create index if not exists ${index("donations", "donor_idx")} on ${donations} (${d("tenant")}, ${d("donorType")}, ${d("donorId")}, ${d("receivedOn")});
create index if not exists ${index("donations", "fund_idx")} on ${donations} (${d("tenant")}, ${d("fund")}) where ${d("fund")} is not null;
create index if not exists ${index("donations", "receipt_idx")} on ${donations} (${d("receipt")}) where ${d("receipt")} is not null;
create index if not exists ${index("donations", "transaction_idx")} on ${donations} (${d("transaction")}) where ${d("transaction")} is not null;
${ctx.has("donations", "refundTransaction") ? `create index if not exists ${index("donations", "refund_idx")} on ${donations} (${d("refundTransaction")}) where ${d("refundTransaction")} is not null;\n` : ""}create unique index if not exists ${index("donations", "payment_key")} on ${donations} (${d("provider")}, ${d("paymentReference")})
  where ${d("paymentReference")} is not null;${policy("donations", donations, d("tenant"))}
`;
}

/** Moves a merged donor's gifts, pledges and receipts to the record kept. */
function donorMerges(ctx: BlockSqlContext): string {
  const subjects = registeredSubjects(ctx.subjects, ctx.naming).map(
    (subject) =>
      [
        subject.type,
        { table: `${subject.schema}.${subject.table}`, extra: {} },
      ] as const,
  );

  const move = (logical: string): string =>
    moveSubjectRows(
      {
        table: ctx.table(logical),
        type: ctx.col(logical, "donorType"),
        id: ctx.col(logical, "donorId"),
      },
      "v_type",
    );

  return subjectMergeHandler(
    ctx,
    subjects,
    [move("donations"), move("pledges"), move("receipts")].join("\n    "),
  );
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  if (ctx.of("ledger").mode === "custom") {
    throw new TypeError(
      "blocks.donations needs the ledger tables; ledger can't be in custom mode",
    );
  }

  return `${schemaPreamble(ctx)}
-- Donations: gifts and pledges from donors (registered subjects) to funds
-- and campaigns, each posted gift on the ledger, and numbered tax receipts.
${tables(ctx)}${donationsFunctions(ctx)}${donorMerges(ctx)}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  const extra = extraFieldsArg(
    ctx.extraColumns("donations", GIFT_RESERVED),
  ).contract;

  return [
    {
      name: "save_donation_fund",
      args: ["{id}", "text", "text", "text", "bigint", "text", "date", "date"],
      returns: "jsonb",
    },
    { name: "archive_donation_fund", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_donation_funds",
      args: ["{id}", "boolean"],
      returns: "jsonb",
    },
    {
      name: "record_gift",
      args: [
        "{id}",
        "text",
        "text",
        "bigint",
        "text",
        "uuid",
        "date",
        "text",
        "text",
        "uuid",
        "date",
        ...extra,
      ],
      returns: "jsonb",
    },
    {
      name: "open_gift",
      args: [
        "{id}",
        "text",
        "text",
        "bigint",
        "text",
        "uuid",
        "uuid",
        "date",
        "text",
        "text",
        ...extra,
      ],
      returns: "jsonb",
    },
    {
      name: "record_gift_payment",
      args: ["uuid", "text", "text", "text"],
      returns: "jsonb",
    },
    { name: "get_gift", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_gifts",
      args: ["{id}", "text", "text", "uuid", "uuid", "text", "integer"],
      returns: "jsonb",
    },
    {
      name: "create_pledge",
      args: [
        "{id}",
        "text",
        "text",
        "bigint",
        "text",
        "text",
        "uuid",
        "date",
        "date",
        "text",
        "text",
        "text",
      ],
      returns: "jsonb",
    },
    {
      name: "update_pledge",
      args: ["uuid", "text", "date", "bigint"],
      returns: "jsonb",
    },
    {
      name: "list_pledges",
      args: ["{id}", "text", "text", "text", "integer"],
      returns: "jsonb",
    },
    {
      name: "due_pledge_installments",
      args: ["{id}", "date", "integer"],
      returns: "jsonb",
    },
    { name: "issue_gift_receipt", args: ["uuid"], returns: "jsonb" },
    {
      name: "issue_yearly_receipt",
      args: ["{id}", "text", "text", "integer", "text"],
      returns: "jsonb",
    },
    { name: "void_donation_receipt", args: ["uuid", "text"], returns: "jsonb" },
    {
      name: "list_donation_receipts",
      args: ["{id}", "text", "text", "integer", "integer"],
      returns: "jsonb",
    },
    {
      name: "yearly_giving_summary",
      args: ["{id}", "text", "text", "integer"],
      returns: "jsonb",
    },
  ];
}

function receiptEntity(ctx: BlockSqlContext): string {
  return ctx.resolved.entityNaming.rename("donation_receipt");
}

function receiptNumbersUpgrade(ctx: BlockSqlContext): string {
  const numbering = ctx.of("numbering");
  const sequences = numbering.table("sequences");
  const seq = (column: string): string => numbering.col("sequences", column);
  const receipt = (column: string): string => ctx.col("receipts", column);

  return `${sequencesTable(numbering)}
insert into ${sequences} (${seq("tenant")}, ${seq("entity")}, ${seq("period")}, ${seq("lastNumber")})
select r.${receipt("tenant")}, ${numbering.cast("sequences", "entity", sqlString(receiptEntity(ctx)))}, '', max(r.${receipt("sequence")})
from ${ctx.table("receipts")} r
group by r.${receipt("tenant")}
on conflict (${seq("tenant")}, ${seq("entity")}, ${seq("period")})
do update set ${seq("lastNumber")} = greatest(${sequences}.${seq("lastNumber")}, excluded.${seq("lastNumber")});`;
}

export const DONATIONS: BlockSqlDefinition = {
  name: "donations",
  scopes: ["tenant"],
  title: "Donations",
  description:
    "Gifts and pledges from donors (registered subjects) to funds and campaigns, each posted gift on the ledger in bigint minor units, charges through the versioned payments provider interface, and tax receipts numbered per organization with a yearly summary.",
  requires: ["memberships", "permissions", "subjects", "ledger", "numbering"],
  integrates: ["outbox", "audit"],
  contributes: {
    numbering: (own) => [
      {
        entity: receiptEntity(own),
        entry: { period: "none", format: "R-{n}" },
      },
    ],
  },
  target: "schema",
  modes: ["managed", "custom"],
  version: 2,
  upgrades: [
    {
      from: 1,
      description:
        "Numbers receipts with the numbering block, starting after each organization's highest receipt.",
      sql: receiptNumbersUpgrade,
    },
  ],
  names: NAMES,
  contract,
  internal: ["donation_settle"],
  build,
};
