import type { InvoicesEvents } from "../../blocks/invoices/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";
import type { InvoiceNames } from "./invoices-names.ts";

import { sqlString } from "../../core/template.ts";
import {
  accountingContributions,
  accountingSourcesSql,
} from "../accounting-sources-sql.ts";
import { billingPartyReportSql } from "../billing-party-sql.ts";
import { guestOr } from "../guest-sql.ts";
import {
  lineExtraColumns,
  lineTableSpec,
  TOTAL_COLUMNS,
  totalColumnsSql,
} from "../line-items-sql.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { addExtraColumns, extraFieldsArg, schemaPreamble } from "../shared.ts";
import { invoiceAccountingSources } from "./invoices-accounting.ts";
import {
  APPROVAL_EVENTS,
  APPROVAL_LEVELS_TABLE,
  APPROVALS_TABLE,
  approvalContract,
  approvalNames,
  approvalTablesSql,
} from "./invoices-approval.ts";
import {
  COLLECTION_COLUMNS,
  COLLECTION_EVENTS,
  collectionColumnsSql,
  collectionContract,
  collectionNames,
  DUNNING_LEVELS_TABLE,
  dunningTableSql,
} from "./invoices-collections.ts";
import {
  DUNNING_HISTORY_TABLE,
  DUNNING_RUN_ITEMS_TABLE,
  DUNNING_RUNS_TABLE,
  dunningRunTablesSql,
} from "./invoices-dunning-runs.ts";
import {
  chargeExtraColumns,
  invoiceFunctions,
  invoiceOptIn,
  OPT_IN,
  invoiceParty,
  partyTypeSql,
} from "./invoices-functions.ts";
import {
  invoiceImportFunctions,
  invoiceImportTargets,
} from "./invoices-import.ts";
import { invoicePaymentsUpgrade } from "./invoices-ledger.ts";
import {
  ALLOCATIONS_TABLE,
  allocationTableSql,
  OPEN_ITEM_EVENTS,
  openItemContract,
} from "./invoices-open-items.ts";
import { PURCHASE_COLUMNS, purchaseNames } from "./invoices-purchase.ts";
import {
  HANDOVER_COLUMNS,
  TERMS_COLUMNS,
  termsColumnsSql,
} from "./invoices-terms.ts";
import { appUniqueIndex, lockModuleTable } from "./over-app.ts";
import { moduleOperations } from "./permissions-model.ts";

const INVOICE = [
  "organizationId",
  "invoiceId",
  "subjectType",
  "subjectId",
  "identifier",
] as const;

const EVENTS: BlockSqlEvents<InvoicesEvents> = {
  "invoice.created": { subject: "invoices", payload: [...INVOICE] },
  "invoice.updated": { subject: "invoices", payload: [...INVOICE] },
  "invoice.deleted": { subject: "invoices", payload: [...INVOICE] },
  "invoice.issued": {
    subject: "invoices",
    payload: [...INVOICE, "total", "currency", "dueOn"],
  },
  "invoice.payment_recorded": {
    subject: "invoices",
    payload: [...INVOICE, "paymentId", "amount", "balance"],
  },
  "invoice.paid": { subject: "invoices", payload: [...INVOICE, "total"] },
  "invoice.credited": {
    subject: "invoices",
    payload: [...INVOICE, "creditNoteId", "amount"],
  },
  "invoice.voided": { subject: "invoices", payload: [...INVOICE, "reason"] },
  "invoice.uncollected": {
    subject: "invoices",
    payload: [...INVOICE, "balance"],
  },
  "invoice.charged": {
    subject: "invoices",
    payload: [...INVOICE, "chargeId", "amount", "balance"],
  },
  "invoice.payment_reversed": {
    subject: "invoices",
    payload: [...INVOICE, "paymentId", "amount", "balance"],
  },
  "invoice.charge_removed": {
    subject: "invoices",
    payload: [...INVOICE, "chargeId", "amount", "balance"],
  },
  "invoice.match_checked": {
    subject: "invoices",
    payload: [...INVOICE, "purchaseOrderId", "status"],
  },
  ...COLLECTION_EVENTS,
  ...OPEN_ITEM_EVENTS,
  ...APPROVAL_EVENTS,
};

const NAMES: BlockSqlNames = {
  entities: {
    invoice: {
      table: "invoices",
      singular: "invoice",
      primary: true,
      subject: {
        title: "title",
        permissions: { read: "read", write: "write" },
      },
    },
  },
  events: EVENTS,
  hooks: [
    "before_invoice_issue",
    "after_invoice_issue",
    "before_invoice_payment",
    "after_invoice_payment",
  ],
  options: [
    "company",
    "contact",
    "prefix",
    "creditPrefix",
    "termsDays",
    "extraColumns",
    "lineExtraColumns",
    "lineRates",
    "chargeExtraColumns",
    "totals",
    "providerPaymentMethods",
    "uniqueNumber",
    "linePositionKey",
    "paymentsAfterWriteOff",
    "depositKind",
    "depositLine",
    "quoteLineValues",
    "discountMatrix",
    "purchasePrefix",
    "purchaseCreditPrefix",
    "matchTolerance",
  ],
  tables: {
    invoices: {
      name: "invoices",
      app: {
        unused: (ctx) =>
          [
            "writeOffReason",
            ...OPT_IN,
            ...PURCHASE_COLUMNS,
            ...COLLECTION_COLUMNS,
            "buyer",
            ...TERMS_COLUMNS,
            ...HANDOVER_COLUMNS,
          ].filter(
            (column) =>
              typeof ctx.config.columns["invoices"]?.[column] !== "string",
          ),
      },
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        kind: "kind",
        number: "number",
        identifier: "identifier",
        original: "original_id",
        title: "title",
        companyType: "company_type",
        companyId: "company_id",
        contactType: "contact_type",
        contactId: "contact_id",
        currency: "currency",
        status: "status",
        termsDays: "terms_days",
        issuedOn: "issued_on",
        dueOn: "due_on",
        paidTotal: "paid_total",
        creditedTotal: "credited_total",
        paidAt: "paid_at",
        voidedAt: "voided_at",
        voidReason: "void_reason",
        writeOffReason: "write_off_reason",
        note: "note",
        originType: "origin_type",
        originId: "origin_id",
        depositBps: "deposit_bps",
        depositAmount: "deposit_amount",
        discountBps: "discount_bps",
        discountAmount: "discount_amount",
        pricesIncludeTax: "prices_include_tax",
        archivedAt: "archived_at",
        direction: "direction",
        supplierReference: "supplier_reference",
        purchaseOrder: "purchase_order_id",
        dimensions: "dimensions",
        dunningLevel: "dunning_level",
        dunningAt: "dunning_at",
        dunningPausedUntil: "dunning_paused_until",
        buyer: "buyer",
        paymentTermsId: "payment_terms_id",
        discountDueOn: "discount_due_on",
        discountAmountEarly: "discount_amount_early",
        collectionStatus: "collection_status",
        collectionAgencyId: "collection_agency_id",
        collectionHandedAt: "collection_handed_at",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
        ...TOTAL_COLUMNS,
      },
      optional: [
        "companyType",
        "companyId",
        "contactType",
        "contactId",
        "voidReason",
        "writeOffReason",
        "note",
        "originType",
        "originId",
        "depositBps",
        "depositAmount",
        "discountBps",
        "discountAmount",
        "pricesIncludeTax",
        "archivedAt",
        ...PURCHASE_COLUMNS,
        ...COLLECTION_COLUMNS,
        "buyer",
        ...TERMS_COLUMNS,
        ...HANDOVER_COLUMNS,
        "createdBy",
        "listTotal",
        "discountTotal",
      ],
      typed: ["status", "kind", "direction"],
    },
    lines: lineTableSpec("invoice_lines", {
      tax: true,
      sales: true,
      purchase: true,
    }),
    charges: {
      name: "invoice_charges",
      app: {},
      optionalTable: true,
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        invoice: "invoice_id",
        amount: "amount",
        currency: "currency",
        description: "description",
        createdBy: "created_by",
        createdAt: "created_at",
      },
      optional: ["currency", "description", "createdBy", "createdAt"],
    },
    dunningLevels: DUNNING_LEVELS_TABLE,
    dunningRuns: DUNNING_RUNS_TABLE,
    dunningRunItems: DUNNING_RUN_ITEMS_TABLE,
    dunningHistory: DUNNING_HISTORY_TABLE,
    allocations: ALLOCATIONS_TABLE,
    approvalLevels: APPROVAL_LEVELS_TABLE,
    approvals: APPROVALS_TABLE,
  },
};

function tables(ctx: BlockSqlContext, n: InvoiceNames): string {
  if (!ctx.manages) {
    return "";
  }

  const { t, c } = n;
  const i = (column: string): string => c("invoices", column);
  const company = invoiceParty(ctx, "company");
  const contact = invoiceParty(ctx, "contact");
  const origin = invoiceParty(ctx, "origin");
  const uniqueNumber = invoiceUniqueNumber(ctx);

  // Sales invoices and purchase bills are numbered apart.
  const numberKey = [
    "tenant",
    ...(ctx.has("invoices", "direction") ? ["direction"] : []),
    "kind",
    ...(uniqueNumber === false ? [] : [uniqueNumber]),
  ];

  const ch = (column: string): string => c("charges", column);

  const chargeColumns = [
    `${ch("id")} uuid primary key default gen_random_uuid()`,
    `${ch("tenant")} ${ctx.idType} not null`,
    `${ch("invoice")} uuid not null references ${t("invoices")} (${i("id")}) on delete cascade`,
    `${ch("amount")} bigint not null check (${ch("amount")} > 0)`,
    ...(ctx.has("charges", "currency")
      ? [`${ch("currency")} char(3) check (${ch("currency")} ~ '^[A-Z]{3}$')`]
      : []),
    ...(ctx.has("charges", "description")
      ? [
          `${ch("description")} text check (length(${ch("description")}) <= 2000)`,
        ]
      : []),
    ...(ctx.has("charges", "createdBy") ? [`${ch("createdBy")} uuid`] : []),
    ...(ctx.has("charges", "createdAt")
      ? [`${ch("createdAt")} timestamptz not null default now()`]
      : []),
  ];

  const charges = ctx.hasTable("charges")
    ? `
create table if not exists ${t("charges")} (
  ${chargeColumns.join(",\n  ")}
);
create index if not exists ${ctx.naming.rename("invoice_charges_invoice_idx")} on ${t("charges")} (${ch("invoice")});${addExtraColumns(t("charges"), chargeExtraColumns(ctx))}
${lockModuleTable(ctx, "charges", { read: true })}
${renderPolicy(
  makePolicy({
    table: t("charges"),
    name: ctx.naming.rename("invoice_charges_read"),
    command: "select",
    roles: ["authenticated"],
    using: `exists (select 1 from ${t("invoices")} x where x.${i("id")} = ${ch("invoice")})`,
  }),
  { drop: true, target: t("charges") },
)}
`
    : "";

  // A column definition, left out when the app maps the column to null.
  const column = (
    logical: string,
    definition: string | ((name: string) => string),
  ): string =>
    ctx.has("invoices", logical)
      ? `\n  ${i(logical)} ${typeof definition === "string" ? definition : definition(i(logical))},`
      : "";

  // The columns a config opts into (archivedAt, depositAmount, discountBps, discountAmount).
  const optIn: Readonly<Record<string, (name: string) => string>> = {
    archivedAt: () => "timestamptz",
    depositAmount: (name) => `bigint check (${name} > 0)`,
    discountBps: (name) =>
      `integer not null default 0 check (${name} >= 0 and ${name} <= 10000)`,
    discountAmount: (name) => `bigint not null default 0 check (${name} >= 0)`,
  };

  const added = OPT_IN.filter((logical) => invoiceOptIn(ctx, logical))
    .map(
      (logical) =>
        `\nalter table ${t("invoices")} add column if not exists ${i(logical)} ${optIn[logical]!(i(logical))};`,
    )
    .join("");

  const index = (name: string, columns: readonly string[]): string =>
    `\ncreate index if not exists ${ctx.naming.rename(name)} on ${t("invoices")} (${columns.map(i).join(", ")});`;

  return `
create table if not exists ${t("invoices")} (
  ${i("id")} uuid primary key default gen_random_uuid(),
  ${i("tenant")} ${ctx.idType} not null,
  ${i("kind")} text not null default 'invoice' check (${i("kind")} in ('invoice', 'credit_note')),
  ${i("number")} bigint,
  ${i("identifier")} text,
  ${i("original")} uuid references ${t("invoices")} (${i("id")}),
  ${i("title")} text not null check (length(${i("title")}) between 1 and 300),${column("companyType", "text")}${column("companyId", "text")}${column("contactType", "text")}${column("contactId", "text")}
  ${i("currency")} char(3) not null check (${i("currency")} ~ '^[A-Z]{3}$'),
  ${i("status")} text not null default 'draft' check (${i("status")} in ('draft', 'issued', 'partially_paid', 'paid', 'void', 'uncollectible')),
  ${i("termsDays")} integer not null default 30 check (${i("termsDays")} >= 0),
  ${i("issuedOn")} date,
  ${i("dueOn")} date,
  ${i("paidTotal")} bigint not null default 0,
  ${i("creditedTotal")} bigint not null default 0,
  ${i("paidAt")} timestamptz,
  ${i("voidedAt")} timestamptz,${column("voidReason", "text")}${column("note", "text")}${column("originType", "text")}${column("originId", "text")}${ctx.has("invoices", "depositBps") ? `\n  ${i("depositBps")} integer check (${i("depositBps")} > 0 and ${i("depositBps")} < 10000),` : ""}${column("pricesIncludeTax", "boolean not null default false")}${column("direction", (name) => `text not null default 'sales' check (${name} in ('sales', 'purchase'))`)}${column("supplierReference", (name) => `text check (length(${name}) <= 200)`)}${column("purchaseOrder", "uuid")}${column("dimensions", (name) => `jsonb not null default '{}'::jsonb check (jsonb_typeof(${name}) = 'object')`)}${collectionColumnsSql(column)}${column("buyer", "jsonb")}${termsColumnsSql(column)}${column("createdBy", "uuid")}
  ${i("createdAt")} timestamptz not null default now(),
  ${i("updatedAt")} timestamptz not null default now(),
  ${totalColumnsSql(ctx, "invoices")},
${uniqueNumber === false ? "" : `  unique (${numberKey.map(i).join(", ")}),\n`}  check ((${i("kind")} = 'credit_note') = (${i("original")} is not null)),
  check (${i("status")} <> 'draft' or ${i("number")} is null),
  check (${i("status")} in ('draft', 'void') or ${i("number")} is not null)${company === "pair" ? `,\n  check ((${i("companyType")} is null) = (${i("companyId")} is null))` : ""}
);
${added === "" ? "" : `${added.slice(1)}\n`}create index if not exists ${ctx.naming.rename("invoices_tenant_status_idx")} on ${t("invoices")} (${i("tenant")}, ${i("status")}, ${i("dueOn")});${origin === undefined ? "" : index("invoices_origin_idx", origin === "pair" ? ["originType", "originId"] : ["originId"])}${index("invoices_original_idx", ["original"])}${company === undefined ? "" : index("invoices_company_idx", company === "pair" ? ["companyType", "companyId"] : ["companyId"])}${addExtraColumns(t("invoices"), n.extras)}${ctx.has("invoices", "purchaseOrder") ? index("invoices_purchase_order_idx", ["purchaseOrder"]) : ""}${uniqueNumber === false ? "" : appUniqueIndex(ctx, "invoices", numberKey)}
${lockModuleTable(ctx, "invoices", { read: true })}
${renderPolicy(
  makePolicy({
    table: t("invoices"),
    name: ctx.naming.rename("invoices_read"),
    command: "select",
    roles: ["authenticated"],
    using: guestOr(ctx.scope.check(i("tenant"), n.read), [
      ctx.scope.guest(i("tenant"), "'invoice'", `${i("id")}::text`, "read"),
      ...(company === undefined
        ? []
        : [
            ctx.scope.guestParty(
              i("tenant"),
              partyTypeSql(ctx, n, "company", ""),
              `${i("companyId")}::text`,
            ),
          ]),
      ...(contact === undefined
        ? []
        : [
            ctx.scope.guestParty(
              i("tenant"),
              partyTypeSql(ctx, n, "contact", ""),
              `${i("contactId")}::text`,
            ),
          ]),
    ]),
  }),
  { drop: true, target: t("invoices") },
)}
${charges}${dunningTableSql(ctx, n.read)}${dunningRunTablesSql(ctx, t("invoices"), i("id"), n.read)}${allocationTableSql(ctx, t("invoices"), i("id"), n.read)}${approvalTablesSql(ctx, t("invoices"), i("id"), n.read)}
`;
}

/**
 * `options.uniqueNumber`: the column that is unique per tenant and kind, or
 * `false` when the app keeps numbers unique itself.
 */
function invoiceUniqueNumber(
  ctx: BlockSqlContext,
): "number" | "identifier" | false {
  const value = ctx.option("uniqueNumber") ?? "number";

  if (value !== "number" && value !== "identifier" && value !== false) {
    throw new TypeError(
      'blocks.invoices.options.uniqueNumber must be "number", "identifier" or false',
    );
  }

  return value;
}

/** `options.totals`: who keeps an invoice's totals. */
function invoiceTotals(ctx: BlockSqlContext): "block" | "app" {
  const totals = ctx.text("totals", "block");

  if (totals !== "block" && totals !== "app") {
    throw new TypeError(
      'blocks.invoices.options.totals must be "block" or "app"',
    );
  }

  return totals;
}

/**
 * `options.depositKind`: the app value of the kind column that marks a deposit
 * invoice. It must be one the `invoice` label maps to, so the block treats a
 * deposit invoice as an invoice everywhere else.
 */
function depositKind(ctx: BlockSqlContext): string | undefined {
  const kind = ctx.option("depositKind");

  if (kind === undefined) {
    return undefined;
  }

  if (
    typeof kind !== "string" ||
    !ctx.appValues("invoices", "kind", "invoice").includes(kind)
  ) {
    throw new TypeError(
      "blocks.invoices.options.depositKind must be one of the values blocks.invoices.values.invoices.kind.invoice maps to",
    );
  }

  return kind;
}

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

function depositLine(ctx: BlockSqlContext): InvoiceNames["depositLine"] {
  const value = ctx.option("depositLine") ?? {};
  const at = "blocks.invoices.options.depositLine";

  if (!isObject(value)) {
    throw new TypeError(`${at} must be an object`);
  }

  const { description = "Deposit {identifier}", fields = {} } = value;

  if (typeof description !== "string" || description.trim() === "") {
    throw new TypeError(`${at}.description must be a non-empty string`);
  }

  const lineColumns = new Set(lineExtraColumns(ctx).map((extra) => extra.name));

  if (
    !isObject(fields) ||
    !Object.keys(fields).every((key) => lineColumns.has(key))
  ) {
    throw new TypeError(
      `${at}.fields must be an object of blocks.invoices.options.lineExtraColumns`,
    );
  }

  return { description, fields };
}

function quoteLineValues(
  ctx: BlockSqlContext,
): InvoiceNames["quoteLineValues"] {
  const value = ctx.option("quoteLineValues") ?? {};

  const invalid = new TypeError(
    "blocks.invoices.options.quoteLineValues must map column names to objects of string values",
  );

  if (!isObject(value)) {
    throw invalid;
  }

  return Object.fromEntries(
    Object.entries(value).map(([column, map]) => {
      if (!isObject(map)) {
        throw invalid;
      }

      return [
        column,
        Object.fromEntries(
          Object.entries(map).map(([from, to]) => {
            if (typeof to !== "string") {
              throw invalid;
            }

            return [from, to];
          }),
        ),
      ];
    }),
  );
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const keys = moduleOperations("invoices");
  const termsDays = ctx.number("termsDays", 30);

  if (!Number.isInteger(termsDays) || termsDays < 0) {
    throw new TypeError(
      "blocks.invoices.options.termsDays must be 0 or a positive integer",
    );
  }

  const finer = (action: string, base: "write" | "manage"): string =>
    sqlString(
      ctx.config.permissions[action] ?? ctx.permissionKey(base, keys[base]),
    );

  const n: InvoiceNames = {
    fn: (name) => ctx.fn(name),
    t: (table) => ctx.table(table),
    c: (table, column) => ctx.col(table, column),
    read: ctx.permission("read", keys.read),
    write: ctx.permission("write", keys.write),
    manage: ctx.permission("manage", keys.manage),
    create: finer("create", "write"),
    update: finer("update", "write"),
    issue: finer("issue", "write"),
    payment: finer("payment", "write"),
    credit: finer("credit", "write"),
    charge: finer("charge", "write"),
    void: finer("void", "manage"),
    writeOff: finer("writeOff", "manage"),
    reverse: finer("reverse", "manage"),
    remove: sqlString(
      ctx.config.permissions["delete"] ??
        ctx.config.permissions["update"] ??
        ctx.permissionKey("write", keys.write),
    ),
    company: ctx.text("company", "company"),
    contact: ctx.text("contact", "person"),
    prefix: ctx.text("prefix", "INV-"),
    creditPrefix: ctx.text("creditPrefix", "CN-"),
    termsDays,
    providerMethods: ctx.list("providerPaymentMethods", ["stripe", "order"]),
    service: "(auth.role() = 'service_role')",
    extras: ctx.extraColumns("invoices", [
      "lines",
      "payments",
      "balance",
      "overdue",
      "charges",
      "charged_total",
    ]),
    lineExtras: lineExtraColumns(ctx),
    chargeExtras: chargeExtraColumns(ctx),
    appTotals: invoiceTotals(ctx) === "app",
    depositKind: depositKind(ctx),
    depositLine: depositLine(ctx),
    quoteLineValues: quoteLineValues(ctx),
    ...purchaseNames(ctx, keys),
    ...collectionNames(ctx, keys),
    ...approvalNames(ctx, keys),
  };

  return `${schemaPreamble(ctx)}
-- Invoices an organization sends its own customers and the bills its
-- suppliers send it: drafts with lines, a number on issue, payments, credit
-- notes, void and write-off, aging and the three-way match of a bill.
${tables(ctx, n)}${invoiceFunctions(ctx, n)}${invoiceImportFunctions(ctx, n)}${billingPartyReportSql(ctx, { name: n.fn("document_totals_by_billing_party"), argument: "document", lines: "lines" })}${accountingSourcesSql(ctx, invoiceAccountingSources(ctx))}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "create_invoice",
      args: ["{id}", "jsonb", "jsonb"],
      returns: "jsonb",
    },
    { name: "update_invoice", args: ["uuid", "jsonb"], returns: "jsonb" },
    { name: "delete_invoice", args: ["uuid"], returns: "boolean" },
    { name: "set_invoice_lines", args: ["uuid", "jsonb"], returns: "jsonb" },
    {
      name: "issue_invoice",
      args: ["uuid", "date", "date", "jsonb", "text"],
      returns: "jsonb",
    },
    {
      name: "record_invoice_payment",
      args: [
        "uuid",
        "bigint",
        "text",
        "timestamptz",
        "text",
        "text",
        "text",
        "jsonb",
        "text",
      ],
      returns: "jsonb",
    },
    {
      name: "credit_invoice",
      args: ["uuid", "jsonb", "text", "text", "date"],
      returns: "jsonb",
    },
    { name: "void_invoice", args: ["uuid", "text", "jsonb"], returns: "jsonb" },
    {
      name: "document_totals_by_billing_party",
      args: ["uuid"],
      returns: "jsonb",
    },
    {
      name: "write_off_invoice",
      args: ["uuid", "text", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "reverse_invoice_payment",
      args: ["uuid", "text", "jsonb"],
      returns: "jsonb",
    },
    ...(ctx.hasTable("charges")
      ? [
          {
            name: "add_invoice_charge",
            args: [
              "uuid",
              "bigint",
              "text",
              "text",
              ...extraFieldsArg(chargeExtraColumns(ctx)).contract,
              "jsonb",
            ],
            returns: "jsonb",
          },
          {
            name: "remove_invoice_charge",
            args: ["uuid", "jsonb"],
            returns: "jsonb",
          },
        ]
      : []),
    ...(ctx.has("invoices", "direction")
      ? [
          {
            name: "invoice_aging",
            args: ["{id}", "text", "date", "text"],
            returns: "jsonb",
          },
          { name: "purchase_bill_match", args: ["uuid"], returns: "jsonb" },
        ]
      : [
          {
            name: "invoice_aging",
            args: ["{id}", "text", "date"],
            returns: "jsonb",
          },
        ]),
    { name: "list_invoice_payments", args: ["uuid"], returns: "jsonb" },
    ...(ctx.installed("quotes")
      ? [
          {
            name: "invoice_from_quote",
            args: ["uuid", "integer", "bigint", "text"],
            returns: "jsonb",
          },
        ]
      : []),
    ...collectionContract(ctx),
    ...openItemContract(ctx),
    ...approvalContract(ctx),
  ];
}

export const INVOICES: BlockSqlDefinition = {
  name: "invoices",
  scopes: ["tenant"],
  title: "Invoices",
  description:
    "Invoices an organization sends its own customers and bills from its suppliers: drafts with lines, a gapless number per direction on issue, payments, credit notes, void and write-off, overdue and aging per currency, credit limits, the three-way match of a purchase bill, party payments split over invoices with the rest kept as credit, dunning levels, and invoices from accepted quotes.",
  requires: ["memberships", "permissions", "subjects", "ledger"],
  integrates: [
    "outbox",
    "audit",
    "catalog",
    "notifications",
    "numbering",
    "legal-entities",
    "quotes",
    "relations",
    "accounting",
    "tax",
    "inventory",
    "contacts",
    "orders",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  version: 2,
  upgrades: [
    {
      from: 1,
      description:
        "Moves invoice_payments onto ledger transactions with the same ids and drops the table.",
      sql: invoicePaymentsUpgrade,
    },
  ],
  names: NAMES,
  contributes: {
    accounting: (own) =>
      accountingContributions(own, invoiceAccountingSources(own)),
    imports: invoiceImportTargets,
  },
  contract,
  build,
};
