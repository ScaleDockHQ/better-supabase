import type { Money } from "../../commerce/money.ts";
import type {
  Count,
  FacetResult,
  ListPage,
  PageOptions,
} from "../../core/block-helpers.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { CountOptions, FacetOptions } from "../../core/entity-list.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult as AsyncResultType } from "../../core/result.ts";
import type { BlockOptions } from "../shared.ts";

import { money } from "../../commerce/money.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { entityList } from "../../core/entity-list.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  COMMISSION_PLAN_KINDS,
  COMMISSION_STATEMENT_STATUSES,
  COMMISSION_STATUSES,
} from "../../sql/modules/commissions-values.ts";
import {
  applyTemporal,
  bigintOf,
  blockCall,
  enumOrThrow,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";
import {
  commissionListSurface,
  commissionPlanListSurface,
  commissionStatementListSurface,
} from "./lists.ts";

/** How a plan turns a sale into a commission. */
export type CommissionPlanKind = (typeof COMMISSION_PLAN_KINDS)[number];

/** Where one accrued commission stands. */
export type CommissionStatus = (typeof COMMISSION_STATUSES)[number];

/** Where a seller's statement for a period stands. */
export type CommissionStatementStatus =
  (typeof COMMISSION_STATEMENT_STATUSES)[number];

/**
 * One marginal tier: `bps` applies to the part of a seller's monthly sales up
 * to `upTo` minor units. The last tier has no `upTo`.
 */
export interface CommissionTier {
  readonly upTo?: number;
  /** Basis points: 100 is 1%. */
  readonly bps: number;
}

export interface CommissionPlan {
  readonly id: string;
  readonly organizationId: string;
  readonly name: string;
  readonly kind: CommissionPlanKind;
  readonly rateBps?: number;
  readonly tiers?: readonly CommissionTier[];
  readonly archivedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface CommissionAssignment {
  readonly id: string;
  readonly organizationId: string;
  readonly planId: string;
  readonly sellerId: string;
  readonly subjectType?: string;
  readonly subjectId?: string;
  readonly startsOn: Temporal.PlainDate;
  readonly endsOn?: Temporal.PlainDate;
  readonly createdAt: Temporal.Instant;
}

/** A plan with the assignments it has. */
export interface CommissionPlanWithAssignments extends CommissionPlan {
  readonly assignments: readonly CommissionAssignment[];
}

/** A commission a seller earned on one record. */
export interface Commission {
  readonly id: string;
  readonly organizationId: string;
  readonly planId: string;
  readonly sellerId: string;
  /** The kind of record the commission was earned on, such as `invoices`. */
  readonly sourceType: string;
  readonly sourceId: string;
  /** What the plan took its percentage of. */
  readonly basis: Money;
  /** What the commission came to. */
  readonly amount: Money;
  readonly occurredOn: Temporal.PlainDate;
  readonly status: CommissionStatus;
  readonly statementId?: string;
  readonly ledgerTransactionId?: string;
  readonly reversedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
}

export interface CommissionStatement {
  readonly id: string;
  readonly organizationId: string;
  readonly sellerId: string;
  readonly startsOn: Temporal.PlainDate;
  /** The last day of the range, inclusive. */
  readonly endsOn: Temporal.PlainDate;
  readonly status: CommissionStatementStatus;
  readonly total: Money;
  readonly ledgerTransactionId?: string;
  readonly finalizedAt?: Temporal.Instant;
  readonly paidAt?: Temporal.Instant;
  readonly paidBy?: string;
  readonly createdAt: Temporal.Instant;
}

/** A statement with the commissions on it. */
export interface CommissionStatementDetail extends CommissionStatement {
  readonly entries: readonly Commission[];
}

/** What payroll adds for one seller and currency over a range. */
export interface CommissionPayrollLine {
  readonly userId: string;
  readonly amount: Money;
  readonly statementIds: readonly string[];
}

export interface SaveCommissionPlanInput {
  readonly name: string;
  readonly kind: CommissionPlanKind;
  /** A flat plan's rate in basis points. */
  readonly rateBps?: number;
  /** A tiered plan's marginal tiers. */
  readonly tiers?: readonly CommissionTier[];
  /** Updates the plan with this id instead of creating one. */
  readonly planId?: string;
  /** Hides the plan from new assignments. */
  readonly archived?: boolean;
}

export interface AssignCommissionPlanInput {
  readonly planId: string;
  readonly sellerId: string;
  /** Applies the plan to sales on this record only. */
  readonly subject?: { readonly type: string; readonly id: string };
  readonly startsOn?: Temporal.PlainDate;
  readonly endsOn?: Temporal.PlainDate;
}

export interface AccrueCommissionInput {
  readonly sellerId: string;
  /** The record sold, such as `{ type: "orders", id: "o_1" }`. */
  readonly source: { readonly type: string; readonly id: string };
  /** What the plan takes its percentage of, in minor units. */
  readonly basis: Money;
  readonly occurredOn?: Temporal.PlainDate;
  /** A record with its own plan, such as the customer. */
  readonly subject?: { readonly type: string; readonly id: string };
}

export interface CommissionListOptions {
  readonly sellerId?: string;
  readonly status?: CommissionStatus;
  /** At most 500; 100 by default. */
  readonly limit?: number;
}

export interface CommissionStatementListOptions {
  readonly sellerId?: string;
  readonly status?: CommissionStatementStatus;
  /** At most 500; 100 by default. */
  readonly limit?: number;
}

export interface CommissionsOptions extends BlockOptions {
  readonly hooks?: BlockHooks<Commissions>;
  readonly logger?: Logger;
}

export interface Commissions {
  /** Creates a commission plan, or changes the one named by `planId`. */
  savePlan(input: SaveCommissionPlanInput): AsyncResultType<CommissionPlan>;
  /** Puts a seller on a plan. A subject plan wins over the seller's own. */
  assignPlan(
    input: AssignCommissionPlanInput,
  ): AsyncResultType<CommissionAssignment>;
  /** Ends an assignment today. */
  endAssignment(assignmentId: string): AsyncResultType<CommissionAssignment>;
  listPlans(list?: {
    readonly archived?: boolean;
    readonly limit?: number;
  }): AsyncResultType<readonly CommissionPlanWithAssignments[]>;
  /** One keyset page of plans with their assignments, newest first or by `sort`. */
  planPage(
    options?: PageOptions,
  ): AsyncResultType<ListPage<CommissionPlanWithAssignments>>;
  /** The values of each plan facet and their counts. */
  planFacets(options?: FacetOptions): AsyncResultType<readonly FacetResult[]>;
  /** How many plans match the page's filters. */
  planCount(options?: CountOptions): AsyncResultType<Count>;
  /**
   * Accrues a commission on a sold record and posts it to the ledger. Calling
   * it again for the same seller and record returns the first commission, and a
   * seller without a plan gets `undefined`.
   */
  accrue(input: AccrueCommissionInput): AsyncResultType<Commission | undefined>;
  /** Reverses an accrued commission, for example after a refund. */
  reverse(input: {
    readonly commissionId: string;
    readonly reason?: string;
  }): AsyncResultType<Commission>;
  listCommissions(
    list?: CommissionListOptions,
  ): AsyncResultType<readonly Commission[]>;
  /** One keyset page of accrued commissions, newest first or by `sort`. */
  commissionPage(options?: PageOptions): AsyncResultType<ListPage<Commission>>;
  /** The values of each commission facet and their counts. */
  commissionFacets(
    options?: FacetOptions,
  ): AsyncResultType<readonly FacetResult[]>;
  /** How many commissions match the page's filters. */
  commissionCount(options?: CountOptions): AsyncResultType<Count>;
  /** Collects a seller's accrued commissions of a range into a statement. */
  buildStatement(input: {
    readonly sellerId: string;
    readonly currency: string;
    readonly startsOn: Temporal.PlainDate;
    readonly endsOn: Temporal.PlainDate;
  }): AsyncResultType<CommissionStatement>;
  /** Locks a statement: its commissions can't be reversed afterwards. */
  finalizeStatement(statementId: string): AsyncResultType<CommissionStatement>;
  /** Pays a finalized statement out on the ledger. */
  payStatement(statementId: string): AsyncResultType<CommissionStatement>;
  getStatement(statementId: string): AsyncResultType<CommissionStatementDetail>;
  listStatements(
    list?: CommissionStatementListOptions,
  ): AsyncResultType<readonly CommissionStatement[]>;
  /** One keyset page of statements, latest period first or by `sort`. */
  statementPage(
    options?: PageOptions,
  ): AsyncResultType<ListPage<CommissionStatement>>;
  /** The values of each statement facet and their counts. */
  statementFacets(
    options?: FacetOptions,
  ): AsyncResultType<readonly FacetResult[]>;
  /** How many statements match the page's filters. */
  statementCount(options?: CountOptions): AsyncResultType<Count>;
  /**
   * What payroll adds for commissions: the totals of the finalized and paid
   * statements that end in the range, one line per seller and currency.
   */
  payrollLines(input: {
    readonly from: Temporal.PlainDate;
    readonly to: Temporal.PlainDate;
  }): AsyncResultType<readonly CommissionPayrollLine[]>;
}

function plainDate(value: unknown, name: string): Temporal.PlainDate {
  if (typeof value !== "string") {
    throw new TypeError(`${name} is not a date`);
  }

  return temporal().PlainDate.from(value);
}

function optionalDate(
  value: unknown,
  name: string,
): Temporal.PlainDate | undefined {
  return value === null || value === undefined
    ? undefined
    : plainDate(value, name);
}

function tierOf(value: unknown): CommissionTier {
  const row = recordOf(value, "tier");
  const upTo = row["upTo"];

  return {
    bps: Number(row["bps"]),
    ...(upTo === null || upTo === undefined ? {} : { upTo: Number(upTo) }),
  };
}

function planOf(value: unknown, fn: string): CommissionPlan {
  const row = recordOf(value, fn);
  const tiers = row["tiers"];
  const archivedAt = optionalInstant(row["archivedAt"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    name: textOf(row["name"]),
    kind: enumOrThrow(
      row["kind"],
      COMMISSION_PLAN_KINDS,
      "commission plan kind",
    ),
    createdAt: temporal().Instant.from(textOf(row["createdAt"])),
    updatedAt: temporal().Instant.from(textOf(row["updatedAt"])),
    ...(typeof row["rateBps"] === "number" ? { rateBps: row["rateBps"] } : {}),
    ...(Array.isArray(tiers)
      ? { tiers: tiers.map((tier) => tierOf(tier)) }
      : {}),
    ...(archivedAt === undefined ? {} : { archivedAt }),
  };
}

function assignmentOf(value: unknown, fn: string): CommissionAssignment {
  const row = recordOf(value, fn);
  const endsOn = optionalDate(row["endsOn"], "endsOn");
  const subjectType = optionalText(row["subjectType"]);
  const subjectId = optionalText(row["subjectId"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    planId: textOf(row["planId"]),
    sellerId: textOf(row["sellerId"]),
    startsOn: plainDate(row["startsOn"], "startsOn"),
    createdAt: temporal().Instant.from(textOf(row["createdAt"])),
    ...(endsOn === undefined ? {} : { endsOn }),
    ...(subjectType === undefined ? {} : { subjectType }),
    ...(subjectId === undefined ? {} : { subjectId }),
  };
}

function commissionOf(value: unknown, fn: string): Commission {
  const row = recordOf(value, fn);
  const currency = textOf(row["currency"]);
  const reversedAt = optionalInstant(row["reversedAt"]);
  const statementId = optionalText(row["statementId"]);
  const ledgerTransactionId = optionalText(row["ledgerTransactionId"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    planId: textOf(row["planId"]),
    sellerId: textOf(row["sellerId"]),
    sourceType: textOf(row["sourceType"]),
    sourceId: textOf(row["sourceId"]),
    basis: money(bigintOf(row["basis"], "basis"), currency),
    amount: money(bigintOf(row["amount"], "amount"), currency),
    occurredOn: plainDate(row["occurredOn"], "occurredOn"),
    status: enumOrThrow(
      row["status"],
      COMMISSION_STATUSES,
      "commission status",
    ),
    createdAt: temporal().Instant.from(textOf(row["createdAt"])),
    ...(statementId === undefined ? {} : { statementId }),
    ...(ledgerTransactionId === undefined ? {} : { ledgerTransactionId }),
    ...(reversedAt === undefined ? {} : { reversedAt }),
  };
}

function statementOf(value: unknown, fn: string): CommissionStatement {
  const row = recordOf(value, fn);
  const currency = textOf(row["currency"]);
  const finalizedAt = optionalInstant(row["finalizedAt"]);
  const paidAt = optionalInstant(row["paidAt"]);
  const paidBy = optionalText(row["paidBy"]);
  const ledgerTransactionId = optionalText(row["ledgerTransactionId"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    sellerId: textOf(row["sellerId"]),
    startsOn: plainDate(row["startsOn"], "startsOn"),
    endsOn: plainDate(row["endsOn"], "endsOn"),
    status: enumOrThrow(
      row["status"],
      COMMISSION_STATEMENT_STATUSES,
      "commission statement status",
    ),
    total: money(bigintOf(row["total"], "total"), currency),
    createdAt: temporal().Instant.from(textOf(row["createdAt"])),
    ...(ledgerTransactionId === undefined ? {} : { ledgerTransactionId }),
    ...(finalizedAt === undefined ? {} : { finalizedAt }),
    ...(paidAt === undefined ? {} : { paidAt }),
    ...(paidBy === undefined ? {} : { paidBy }),
  };
}

function planWithAssignmentsOf(
  row: Record<string, unknown>,
  fn: string,
): CommissionPlanWithAssignments {
  return {
    ...planOf(row, fn),
    assignments: Array.isArray(row["assignments"])
      ? row["assignments"].map((each) => assignmentOf(each, fn))
      : [],
  };
}

const definedOf = (input: object): Record<string, unknown> =>
  Object.fromEntries(
    Object.entries(input).filter(([, value]) => value !== undefined),
  );

/**
 * Commissions: plans assigned to sellers, commissions accrued on the ledger
 * from sold records (and from paid invoices with the `invoices` option),
 * statements per period and the lines payroll adds.
 */
export function createCommissions(options: CommissionsOptions): Commissions {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResultType<string> => requireTenant(options.tenant);

  const listOf = <Item>(
    entity: string,
    surface: typeof commissionListSurface,
    fn: string,
    rowOf: (row: Record<string, unknown>, name: string) => Item,
  ) => entityList({ entity, surface, call, tenant, fn, rowOf });

  const plans = listOf(
    "commission_plan",
    commissionPlanListSurface,
    "list_commission_plans",
    planWithAssignmentsOf,
  );

  const commissions = listOf(
    "commission",
    commissionListSurface,
    "list_commissions",
    commissionOf,
  );

  const statements = listOf(
    "commission_statement",
    commissionStatementListSurface,
    "list_commission_statements",
    statementOf,
  );

  const client: Commissions = {
    planPage: plans.page,
    planFacets: plans.facets,
    planCount: plans.count,
    commissionPage: commissions.page,
    commissionFacets: commissions.facets,
    commissionCount: commissions.count,
    statementPage: statements.page,
    statementFacets: statements.facets,
    statementCount: statements.count,
    savePlan: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "save_commission_plan",
          {
            tenant: organizationId,
            name: input.name,
            kind: input.kind,
            ...definedOf({
              rate_bps: input.rateBps,
              tiers: input.tiers,
              plan_id: input.planId,
              archived: input.archived,
            }),
          },
          (value) => planOf(value, "save_commission_plan"),
        ),
      ),
    assignPlan: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "assign_commission_plan",
          {
            tenant: organizationId,
            plan_id: input.planId,
            seller_id: input.sellerId,
            ...definedOf({
              subject_type: input.subject?.type,
              subject_id: input.subject?.id,
              starts_on: input.startsOn?.toString(),
              ends_on: input.endsOn?.toString(),
            }),
          },
          (value) => assignmentOf(value, "assign_commission_plan"),
        ),
      ),
    endAssignment: (assignmentId) =>
      call(
        "end_commission_assignment",
        { assignment_id: assignmentId },
        (value) => assignmentOf(value, "end_commission_assignment"),
      ),
    listPlans: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_commission_plans",
          { tenant: organizationId, filters: definedOf(list) },
          (value) =>
            recordsOf(value, "list_commission_plans").map((row) => ({
              ...planOf(row, "list_commission_plans"),
              assignments: Array.isArray(row["assignments"])
                ? row["assignments"].map((each) =>
                    assignmentOf(each, "list_commission_plans"),
                  )
                : [],
            })),
        ),
      ),
    accrue: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "accrue_commission",
          {
            tenant: organizationId,
            seller_id: input.sellerId,
            source_type: input.source.type,
            source_id: input.source.id,
            basis: input.basis.amount.toString(),
            currency: input.basis.currency,
            ...definedOf({
              occurred_on: input.occurredOn?.toString(),
              subject_type: input.subject?.type,
              subject_id: input.subject?.id,
            }),
          },
          (value) =>
            value === null || value === undefined
              ? undefined
              : commissionOf(value, "accrue_commission"),
        ),
      ),
    reverse: ({ commissionId, reason }) =>
      call(
        "reverse_commission",
        { commission_id: commissionId, ...definedOf({ reason }) },
        (value) => commissionOf(value, "reverse_commission"),
      ),
    listCommissions: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_commissions",
          {
            tenant: organizationId,
            filters: definedOf({
              seller: list.sellerId,
              status: list.status,
              limit: list.limit,
            }),
          },
          (value) =>
            recordsOf(value, "list_commissions").map((row) =>
              commissionOf(row, "list_commissions"),
            ),
        ),
      ),
    buildStatement: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "build_commission_statement",
          {
            tenant: organizationId,
            seller_id: input.sellerId,
            currency: input.currency,
            starts_on: input.startsOn.toString(),
            ends_on: input.endsOn.toString(),
          },
          (value) => statementOf(value, "build_commission_statement"),
        ),
      ),
    finalizeStatement: (statementId) =>
      call(
        "finalize_commission_statement",
        { statement_id: statementId },
        (value) => statementOf(value, "finalize_commission_statement"),
      ),
    payStatement: (statementId) =>
      call("pay_commission_statement", { statement_id: statementId }, (value) =>
        statementOf(value, "pay_commission_statement"),
      ),
    getStatement: (statementId) =>
      call(
        "get_commission_statement",
        { statement_id: statementId },
        (value) => {
          const row = recordOf(value, "get_commission_statement");
          const entries = row["entries"];

          return {
            ...statementOf(row, "get_commission_statement"),
            entries: Array.isArray(entries)
              ? entries.map((each) =>
                  commissionOf(each, "get_commission_statement"),
                )
              : [],
          };
        },
      ),
    listStatements: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_commission_statements",
          {
            tenant: organizationId,
            filters: definedOf({
              seller: list.sellerId,
              status: list.status,
              limit: list.limit,
            }),
          },
          (value) =>
            recordsOf(value, "list_commission_statements").map((row) =>
              statementOf(row, "list_commission_statements"),
            ),
        ),
      ),
    payrollLines: ({ from, to }) =>
      tenant().andThen((organizationId) =>
        call(
          "commission_payroll_lines",
          {
            tenant: organizationId,
            from_date: from.toString(),
            to_date: to.toString(),
          },
          (value) =>
            recordsOf(value, "commission_payroll_lines").map((row) => ({
              userId: textOf(row["userId"]),
              amount: money(
                bigintOf(row["amount"], "amount"),
                textOf(row["currency"]),
              ),
              statementIds:
                Array.isArray(row["statementIds"]) &&
                row["statementIds"].every((id) => typeof id === "string")
                  ? row["statementIds"]
                  : [],
            })),
        ),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "commissions",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
