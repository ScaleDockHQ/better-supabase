import type { CommissionsEvents } from "../../blocks/commissions/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { schemaPreamble } from "../shared.ts";
import { commissionAccrual } from "./commissions-accrual.ts";
import {
  accruesInvoices,
  invoiceCommissionSql,
} from "./commissions-invoices.ts";
import { commissionSql } from "./commissions-sql.ts";
import { commissionStatements } from "./commissions-statements.ts";
import { commissionTables } from "./commissions-tables.ts";
import { COMMISSION_PERIOD_KIND } from "./commissions-values.ts";

const plan = {
  subject: "commission-plans",
  payload: ["organizationId", "id", "name", "kind"],
} as const;

const entry = {
  subject: "commissions",
  payload: [
    "organizationId",
    "id",
    "planId",
    "sellerId",
    "sourceType",
    "sourceId",
    "amount",
    "currency",
  ],
} as const;

const statement = {
  subject: "commission-statements",
  payload: [
    "organizationId",
    "id",
    "sellerId",
    "currency",
    "startsOn",
    "endsOn",
    "total",
    "status",
  ],
} as const;

const EVENTS: BlockSqlEvents<CommissionsEvents> = {
  "commission_plan.created": plan,
  "commission_plan.updated": plan,
  "commission.accrued": entry,
  "commission.reversed": entry,
  "commission_statement.finalized": statement,
  "commission_statement.paid": statement,
};

const NAMES: BlockSqlNames = {
  entities: {
    commission_plan: {
      table: "plans",
      singular: "commission_plan",
      primary: true,
    },
    commission_assignment: {
      table: "assignments",
      singular: "commission_assignment",
    },
    commission: { table: "entries", singular: "commission" },
    commission_statement: {
      table: "statements",
      singular: "commission_statement",
    },
  },
  events: EVENTS,
  hooks: [],
  options: ["invoices"],
  tables: {
    plans: {
      name: "commission_plans",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        kind: "kind",
        rateBps: "rate_bps",
        tiers: "tiers",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    assignments: {
      name: "commission_assignments",
      app: {},
      lifecycle: { tenant: "tenant", user: "seller", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        plan: "plan_id",
        seller: "seller_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        startsOn: "starts_on",
        endsOn: "ends_on",
        createdAt: "created_at",
      },
    },
    entries: {
      name: "commissions",
      app: {},
      lifecycle: { tenant: "tenant", user: "seller", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        plan: "plan_id",
        seller: "seller_id",
        sourceType: "source_type",
        sourceId: "source_id",
        basis: "basis",
        amount: "amount",
        currency: "currency",
        occurredOn: "occurred_on",
        status: "status",
        statement: "statement_id",
        ledgerTransaction: "ledger_transaction_id",
        reversedAt: "reversed_at",
        createdAt: "created_at",
      },
    },
    statements: {
      name: "commission_statements",
      app: {},
      lifecycle: { tenant: "tenant", user: "seller", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        seller: "seller_id",
        currency: "currency",
        startsOn: "starts_on",
        endsOn: "ends_on",
        status: "status",
        total: "total",
        ledgerTransaction: "ledger_transaction_id",
        finalizedAt: "finalized_at",
        paidAt: "paid_at",
        paidBy: "paid_by",
        createdAt: "created_at",
      },
    },
  },
};

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const k = commissionSql(ctx);

  return `${schemaPreamble(ctx)}${commissionTables(k)}${commissionAccrual(k)}${commissionStatements(k)}${accruesInvoices(ctx) ? invoiceCommissionSql(ctx, k) : ""}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "save_commission_plan",
      args: ["{id}", "text", "text", "integer", "jsonb", "uuid", "boolean"],
      returns: "jsonb",
    },
    {
      name: "assign_commission_plan",
      args: ["{id}", "uuid", "uuid", "text", "text", "date", "date"],
      returns: "jsonb",
    },
    { name: "end_commission_assignment", args: ["uuid"], returns: "jsonb" },
    {
      name: "accrue_commission",
      args: [
        "{id}",
        "uuid",
        "text",
        "text",
        "bigint",
        "text",
        "date",
        "text",
        "text",
      ],
      returns: "jsonb",
    },
    { name: "reverse_commission", args: ["uuid", "text"], returns: "jsonb" },
    {
      name: "build_commission_statement",
      args: ["{id}", "uuid", "text", "date", "date"],
      returns: "jsonb",
    },
    { name: "finalize_commission_statement", args: ["uuid"], returns: "jsonb" },
    { name: "pay_commission_statement", args: ["uuid"], returns: "jsonb" },
    { name: "get_commission_statement", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_commission_statements",
      args: ["{id}", "jsonb"],
      returns: "jsonb",
    },
    { name: "list_commissions", args: ["{id}", "jsonb"], returns: "jsonb" },
    {
      name: "list_commission_plans",
      args: ["{id}", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "commission_payroll_lines",
      args: ["{id}", "date", "date"],
      returns: "jsonb",
    },
  ];
}

export const COMMISSIONS: BlockSqlDefinition = {
  name: "commissions",
  scopes: ["tenant"],
  title: "Commissions",
  description:
    "Commission plans (flat or marginal tiers) assigned to sellers, commissions accrued on the ledger from paid records, statements per period with a payout, and the lines payroll adds.",
  requires: ["memberships", "permissions", "ledger"],
  integrates: ["outbox", "audit", "invoices", "periods"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
  contributes: {
    periods: (own) => [
      {
        kind: COMMISSION_PERIOD_KIND,
        cadence: "month",
        onClose: own.fn("commission_close_range"),
      },
    ],
  },
};
