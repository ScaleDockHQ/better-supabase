import type { TaxEvents } from "../../blocks/tax/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { schemaPreamble } from "../shared.ts";
import { taxCompute } from "./tax-compute.ts";
import { taxFunctions, taxImportTargets } from "./tax-functions.ts";
import { taxReturns } from "./tax-returns.ts";
import { taxSeeds } from "./tax-seeds.ts";
import { taxTables } from "./tax-tables.ts";

const CODE = ["organizationId", "id", "code", "type", "legalEntityId"] as const;

const EVENTS: BlockSqlEvents<TaxEvents> = {
  "tax_code.created": { subject: "tax-codes", payload: CODE },
  "tax_code.updated": { subject: "tax-codes", payload: CODE },
  "tax_return.prepared": {
    subject: "tax-returns",
    payload: [
      "organizationId",
      "id",
      "period",
      "periodStart",
      "periodEnd",
      "legalEntityId",
      "netTax",
      "currency",
    ],
  },
};

const tenantTable = { tenant: "tenant", export: true } as const;

const NAMES: BlockSqlNames = {
  entities: {
    tax_code: {
      table: "codes",
      singular: "tax_code",
      primary: true,
      subject: {
        title: "name",
        deletedAt: "archivedAt",
        permissions: { read: "read", write: "manage" },
      },
    },
    tax_rate: { table: "rates", singular: "tax_rate" },
    tax_return: { table: "returns", singular: "tax_return" },
  },
  events: EVENTS,
  hooks: [],
  options: [],
  tables: {
    codes: {
      name: "tax_codes",
      app: {},
      lifecycle: tenantTable,
      columns: {
        id: "id",
        tenant: "tenant_id",
        legalEntity: "legal_entity_id",
        code: "code",
        name: "name",
        type: "type",
        salesAccount: "sales_account_id",
        purchaseAccount: "purchase_account_id",
        returnBoxes: "return_boxes",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: [
        "legalEntity",
        "salesAccount",
        "purchaseAccount",
        "archivedAt",
      ],
    },
    rates: {
      name: "tax_rates",
      app: {},
      lifecycle: tenantTable,
      columns: {
        id: "id",
        tenant: "tenant_id",
        taxCode: "tax_code_id",
        rateBps: "rate_bps",
        validFrom: "valid_from",
        validTo: "valid_to",
        createdAt: "created_at",
      },
      optional: ["validTo"],
    },
    invoiceTaxLines: {
      name: "invoice_tax_lines",
      app: {},
      lifecycle: tenantTable,
      columns: {
        id: "id",
        tenant: "tenant_id",
        parent: "invoice_id",
        taxRateBps: "tax_rate_bps",
        taxCode: "tax_code",
        taxCodeId: "tax_code_id",
        net: "net",
        tax: "tax",
        gross: "gross",
        discount: "discount",
        customerVat: "customer_vat_number",
        showTax: "show_tax",
      },
      optional: ["taxCode", "taxCodeId", "customerVat"],
    },
    returns: {
      name: "tax_returns",
      app: {},
      lifecycle: tenantTable,
      columns: {
        id: "id",
        tenant: "tenant_id",
        legalEntity: "legal_entity_id",
        period: "period",
        periodStart: "period_start",
        periodEnd: "period_end",
        status: "status",
        currency: "currency",
        boxes: "boxes",
        preparedBy: "prepared_by",
        preparedAt: "prepared_at",
        filedAt: "filed_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["legalEntity", "currency", "preparedBy", "filedAt"],
      typed: ["status"],
    },
    euSalesLines: {
      name: "eu_sales_list_lines",
      app: {},
      lifecycle: tenantTable,
      columns: {
        id: "id",
        tenant: "tenant_id",
        taxReturn: "tax_return_id",
        customerVat: "customer_vat_number",
        country: "country",
        kind: "kind",
        amount: "amount",
        currency: "currency",
        invoiceCount: "invoice_count",
      },
    },
  },
};

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  return `${schemaPreamble(ctx)}
-- Tax per organization and optional legal entity: tax codes with a rate
-- history, the tax of a document computed per code (the margin scheme and a
-- credit restriction included), the tax lines of issued invoices, and the
-- returns and EU sales lists prepared from them.
${taxTables(ctx)}
${taxFunctions(ctx)}
${taxCompute(ctx)}
${taxReturns(ctx)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "save_tax_code",
      args: ["{id}", "jsonb", "uuid"],
      returns: "jsonb",
    },
    {
      name: "save_tax_rate",
      args: ["{id}", "uuid", "integer", "date", "date"],
      returns: "jsonb",
    },
    {
      name: "list_tax_codes",
      args: ["{id}", "boolean", "uuid"],
      returns: "jsonb",
    },
    { name: "tax_rate_on", args: ["uuid", "date"], returns: "integer" },
    {
      name: "compute_document_tax",
      args: ["jsonb", "date", "boolean", "integer"],
      returns: "jsonb",
    },
    {
      name: "prepare_tax_return",
      args: ["{id}", "date", "date", "uuid", "text", "text"],
      returns: "jsonb",
    },
    { name: "file_tax_return", args: ["uuid"], returns: "jsonb" },
    { name: "list_tax_returns", args: ["{id}"], returns: "jsonb" },
  ];
}

export const TAX: BlockSqlDefinition = {
  name: "tax",
  scopes: ["tenant"],
  title: "Tax",
  description:
    "Tax codes per organization and legal entity with a rate history, the tax of a document per code on its date (margin scheme and credit restriction included), invoice tax lines written when an invoice is issued, tax returns with box totals, and the EU sales list per customer VAT number.",
  requires: ["memberships", "permissions"],
  integrates: [
    "accounting",
    "invoices",
    "contacts",
    "legal-entities",
    "outbox",
    "audit",
  ],
  before: "accounting",
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
  contributes: { imports: taxImportTargets },
  seeds: taxSeeds,
};
