import type { Money } from "../../commerce/money.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTenantOptions } from "../../core/block-tenant.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { RecordRef } from "../../schema/types.ts";
import type { BlockTemporalOptions } from "../shared.ts";
import type { ProjectCosts } from "./project-costs.ts";

import { bigintOf } from "../../core/block-helpers.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { AsyncResult } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  amountText,
  currencyMismatch,
  moneyOf,
  optionalAmountText,
  optionalMoneyOf,
} from "../money-codec.ts";
import {
  applyTemporal,
  blockCall,
  instantArg,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";
import { projectCostsOf } from "./project-costs.ts";

/** How `unbilled` and `invoice` turn entries into lines. */
export type BillableTimeGrouping = "subject" | "member" | "entry";

export interface BillableTimeOptions
  extends BlockTemporalOptions, BlockTenantOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<BillableTime>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

/**
 * An hourly rate on the rate card. Without `userId` and `subject` it is the
 * organization's rate.
 */
export interface TimeRate {
  readonly id: string;
  readonly organizationId: string;
  readonly userId?: string;
  readonly subject?: RecordRef;
  /** Per hour. */
  readonly rate: Money;
  /** What the hour costs the organization, for project costing. */
  readonly cost?: Money;
  readonly effectiveFrom: Temporal.PlainDate;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
}

export interface TimeRateInput {
  /** Per hour, in minor units. */
  readonly rate: Money;
  /** What the hour costs the organization, in the rate's currency. */
  readonly cost?: Money;
  /** The member the rate is for. */
  readonly userId?: string;
  /** The record the rate is for, such as a project. */
  readonly subject?: RecordRef;
  /** Default: today. The same key and day replaces the rate. */
  readonly effectiveFrom?: Temporal.PlainDate;
}

export interface TimeRateListOptions {
  readonly userId?: string;
  readonly subject?: RecordRef;
  readonly pageSize?: number;
}

export interface TimeRateLookup {
  readonly userId?: string;
  readonly subject?: RecordRef;
  /** Default: today. */
  readonly on?: Temporal.PlainDate;
}

/** Which unbilled entries to bill. Every field narrows the selection. */
export interface BillableTimeScope {
  readonly subject?: RecordRef;
  readonly userId?: string;
  /** Entries that started at or after this. */
  readonly starts?: Temporal.Instant;
  /** Entries that started before this. */
  readonly ends?: Temporal.Instant;
  readonly entryIds?: readonly string[];
}

export interface BillableTimeQuery extends BillableTimeScope {
  /** Default `subject`: one line per record and rate. */
  readonly groupBy?: BillableTimeGrouping;
}

/** One invoice line the unbilled time would become. */
export interface BillableTimeLine {
  readonly description: string;
  /** Hours, to four decimals, as text so no precision is lost. */
  readonly quantity: string;
  /** The hourly rate. */
  readonly unitAmount: Money;
  /** `quantity` times `unitAmount`, rounded to a minor unit. */
  readonly amount: Money;
  readonly entryIds: readonly string[];
  readonly subject?: RecordRef;
  /** Set when lines are grouped by member or entry. */
  readonly userId?: string;
}

/** What `unbilled` returns. */
export interface UnbilledTime {
  readonly lines: readonly BillableTimeLine[];
  /** One total per currency. */
  readonly totals: readonly Money[];
  /** Billable entries no rate covers; `invoice` fails while there are any. */
  readonly unrated: readonly string[];
}

/** What `wipValuation` returns: unbilled time valued on one day. */
export interface WipValuation {
  readonly asOf: Temporal.PlainDate;
  readonly hours: number;
  /** Hours the rate card has no cost for; they are left out of `cost`. */
  readonly uncostedHours: number;
  /** Hours no rate covers; they are left out of `billable`. */
  readonly unratedHours: number;
  /** Per currency: the time at the rate card's cost and at its billing rate. */
  readonly totals: readonly {
    readonly currency: string;
    readonly cost: bigint;
    readonly billable: bigint;
  }[];
}

export interface InvoiceFromTimeInput extends BillableTimeQuery {
  /** Picks the entries billed in this currency; required when they differ. */
  readonly currency?: string;
  /** Default `Time`. */
  readonly title?: string;
  /** The company billed, such as `{ type: "companies", id }`. */
  readonly company?: RecordRef;
  readonly contact?: RecordRef;
  readonly termsDays?: number;
  readonly note?: string;
}

/** The draft invoice `invoice` created. */
export interface TimeInvoice {
  readonly invoiceId: string;
  /** The lines' sum, before discounts and tax. */
  readonly total: Money;
  readonly entryIds: readonly string[];
}

/** A time entry on an invoice, with what it was billed at. */
export interface InvoicedTimeEntry {
  readonly entryId: string;
  readonly invoiceId: string;
  readonly userId: string;
  readonly subject?: RecordRef;
  readonly startedAt: Temporal.Instant;
  readonly seconds: number;
  /** The hourly rate it was billed at. */
  readonly rate: Money;
  readonly createdAt: Temporal.Instant;
}

export interface BillableTime {
  /** Sets an hourly rate. Needs `billable_time.manage`. */
  setRate(input: TimeRateInput): AsyncResult<TimeRate>;
  /** Needs `billable_time.manage`. */
  deleteRate(rateId: string): AsyncResult<TimeRate>;
  /** The rate card. Needs `billable_time.read`. */
  listRates(options?: TimeRateListOptions): AsyncResult<readonly TimeRate[]>;
  /**
   * The rate that applies to a member's time on a record: member and record
   * first, then the record, the member, the organization. `null` when none
   * does.
   */
  rateFor(lookup?: TimeRateLookup): AsyncResult<TimeRate | null>;
  /** What `invoice` would bill, without billing it. */
  unbilled(query?: BillableTimeQuery): AsyncResult<UnbilledTime>;
  /**
   * The work in progress of unbilled time on a day (today by default): the
   * finished, billable entries no invoice has billed, at cost and at the
   * billing rate. Needs `billable_time.read`.
   */
  wipValuation(asOf?: Temporal.PlainDate): AsyncResult<WipValuation>;
  /**
   * Bills the unbilled time the scope selects on a new draft invoice. Needs
   * `billable_time.invoice` and `invoices.write`. Fails with
   * `TIME_RATE_MISSING`, `BILLABLE_TIME_CURRENCIES` or `BILLABLE_TIME_EMPTY`.
   */
  invoice(input?: InvoiceFromTimeInput): AsyncResult<TimeInvoice>;
  /** The entries an invoice billed. */
  invoicedEntries(
    input: { invoiceId: string } & { readonly pageSize?: number },
  ): AsyncResult<readonly InvoicedTimeEntry[]>;
  /**
   * A tasks project's time at cost, billed time, accounting lines on its
   * `project` dimension, margin and budget use. Needs `billable_time.read`, and
   * the tasks block with projects.
   */
  projectCosts(projectId: string): AsyncResult<ProjectCosts>;
}

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: a one-key object literal for the key the caller names.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

function subjectOf(row: Record<string, unknown>): RecordRef | undefined {
  const type = optionalText(row["subjectType"]);
  const id = optionalText(row["subjectId"]);

  return type === undefined || id === undefined ? undefined : { type, id };
}

function idsOf(value: unknown, field: string): readonly string[] {
  if (!Array.isArray(value)) {
    throw new TypeError(`${field} is not a list`);
  }

  return value.map((item) => textOf(item));
}

function rateOf(value: unknown, fn: string): TimeRate {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    rate: moneyOf(row["rate"], row["currency"], "time rate"),
    effectiveFrom: temporal().PlainDate.from(textOf(row["effectiveFrom"])),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...optional("userId", optionalText(row["userId"])),
    ...optional("subject", subjectOf(row)),
    ...optional("createdBy", optionalText(row["createdBy"])),
    ...optional("cost", optionalMoneyOf(row["cost"], row["currency"], "cost")),
  };
}

function lineOf(value: unknown): BillableTimeLine {
  const row = recordOf(value, "unbilled_time");

  return {
    description: textOf(row["description"]),
    quantity: String(row["quantity"]),
    unitAmount: moneyOf(row["unitAmount"], row["currency"], "unitAmount"),
    amount: moneyOf(row["amount"], row["currency"], "amount"),
    entryIds: idsOf(row["entryIds"], "entryIds"),
    ...optional("subject", subjectOf(row)),
    ...optional("userId", optionalText(row["userId"])),
  };
}

function invoicedOf(value: unknown): InvoicedTimeEntry {
  const row = recordOf(value, "list_invoiced_time");
  const seconds = Number(row["seconds"]);

  if (!Number.isInteger(seconds)) {
    throw new TypeError("seconds is not an integer");
  }

  return {
    entryId: textOf(row["entryId"]),
    invoiceId: textOf(row["invoiceId"]),
    userId: textOf(row["userId"]),
    startedAt: requiredInstant(row["startedAt"], "startedAt"),
    seconds,
    rate: moneyOf(row["rate"], row["currency"], "rate"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...optional("subject", subjectOf(row)),
  };
}

/** A scope as the `jsonb` the SQL reads; absent fields stay absent. */
function scopeArg(scope: BillableTimeScope): Record<string, unknown> {
  return {
    ...optional("subject", scope.subject),
    ...optional("userId", scope.userId),
    ...optional("starts", instantArg(scope.starts) ?? undefined),
    ...optional("ends", instantArg(scope.ends) ?? undefined),
    ...optional("entryIds", scope.entryIds),
  };
}

/** A cost in another currency than the rate, as a failed result. */
function rateError(input: TimeRateInput): AsyncResult<never> | undefined {
  const error = currencyMismatch(input.rate.currency, [input.cost]);

  return error === undefined ? undefined : AsyncResult.err(error);
}

/** The `billable-time` SQL module as typed calls. */
export function createBillableTime(options: BillableTimeOptions): BillableTime {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const client: BillableTime = {
    setRate: (input) =>
      rateError(input) ??
      tenant().andThen((organizationId) =>
        call(
          "set_time_rate",
          {
            tenant: organizationId,
            rate: amountText(input.rate),
            currency: input.rate.currency,
            user_id: input.userId ?? null,
            subject_type: input.subject?.type ?? null,
            subject_id: input.subject?.id ?? null,
            effective_from: input.effectiveFrom?.toString() ?? null,
            cost_amount: optionalAmountText(input.cost),
          },
          (value) => rateOf(value, "set_time_rate"),
        ),
      ),
    deleteRate: (rateId) =>
      call("delete_time_rate", { rate_id: rateId }, (value) =>
        rateOf(value, "delete_time_rate"),
      ),
    listRates: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_time_rates",
          {
            tenant: organizationId,
            user_id: list.userId ?? null,
            subject_type: list.subject?.type ?? null,
            subject_id: list.subject?.id ?? null,
            page_size: list.pageSize ?? null,
          },
          (value) =>
            recordsOf(value, "list_time_rates").map((row) =>
              rateOf(row, "list_time_rates"),
            ),
        ),
      ),
    rateFor: (lookup = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "time_rate",
          {
            tenant: organizationId,
            user_id: lookup.userId ?? null,
            subject_type: lookup.subject?.type ?? null,
            subject_id: lookup.subject?.id ?? null,
            on_day: lookup.on?.toString() ?? null,
          },
          (value) => (value === null ? null : rateOf(value, "time_rate")),
        ),
      ),
    unbilled: (query = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "unbilled_time",
          {
            tenant: organizationId,
            scope: scopeArg(query),
            group_by: query.groupBy ?? "subject",
          },
          (value) => {
            const row = recordOf(value, "unbilled_time");

            return {
              lines: recordsOf(row["lines"], "unbilled_time").map(lineOf),
              totals: recordsOf(row["totals"], "unbilled_time").map((total) =>
                moneyOf(total["amount"], total["currency"], "total"),
              ),
              unrated: idsOf(row["unrated"], "unrated"),
            };
          },
        ),
      ),
    wipValuation: (asOf) =>
      tenant().andThen((organizationId) =>
        call(
          "wip_valuation",
          { tenant: organizationId, as_of: asOf?.toString() ?? null },
          (value) => {
            const row = recordOf(value, "wip_valuation");

            return {
              asOf: temporal().PlainDate.from(textOf(row["asOf"])),
              hours: Number(row["hours"]),
              uncostedHours: Number(row["uncostedHours"]),
              unratedHours: Number(row["unratedHours"]),
              totals: recordsOf(row["totals"], "wip_valuation").map(
                (total) => ({
                  currency: textOf(total["currency"]),
                  cost: bigintOf(total["cost"], "cost"),
                  billable: bigintOf(total["billable"], "billable"),
                }),
              ),
            };
          },
        ),
      ),
    invoice: (input = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "invoice_from_time",
          {
            tenant: organizationId,
            attrs: {
              ...optional("currency", input.currency),
              ...optional("title", input.title),
              ...optional("company", input.company),
              ...optional("contact", input.contact),
              ...optional("termsDays", input.termsDays),
              ...optional("note", input.note),
            },
            scope: scopeArg(input),
            group_by: input.groupBy ?? "subject",
          },
          (value) => {
            const row = recordOf(value, "invoice_from_time");

            return {
              invoiceId: textOf(row["invoiceId"]),
              total: moneyOf(row["total"], row["currency"], "total"),
              entryIds: idsOf(row["entryIds"], "entryIds"),
            };
          },
        ),
      ),
    invoicedEntries: ({ invoiceId, ...list }) =>
      call(
        "list_invoiced_time",
        { invoice: invoiceId, page_size: list.pageSize ?? null },
        (value) => recordsOf(value, "list_invoiced_time").map(invoicedOf),
      ),
    projectCosts: (projectId) =>
      call("project_costs", { project_id: projectId }, projectCostsOf),
  };

  return withBlockHooks(client, options.hooks, {
    block: "billable-time",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
