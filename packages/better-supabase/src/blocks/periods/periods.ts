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

import { plainDateOf } from "../../core/block-helpers.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { entityList } from "../../core/entity-list.ts";
import { temporal } from "../../core/temporal-required.ts";
import { PERIOD_STATUSES } from "../../sql/modules/periods-values.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  optionalInstant,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";
import { periodListSurface } from "./lists.ts";

/** Where a period stands: writes into it stop at `locked` and `closed`. */
export type PeriodStatus = (typeof PERIOD_STATUSES)[number];

/** A dated range of one kind, such as a fiscal month or a leave year. */
export interface Period {
  readonly id: string;
  readonly organizationId: string;
  /** What the range is for, such as `fiscal_period`. */
  readonly kind: string;
  readonly startsOn: Temporal.PlainDate;
  /** The last day of the range, inclusive. */
  readonly endsOn: Temporal.PlainDate;
  readonly status: PeriodStatus;
  readonly closedAt?: Temporal.Instant;
  readonly closedBy?: string;
  readonly createdAt: Temporal.Instant;
}

export interface CreatePeriodInput {
  readonly kind: string;
  readonly startsOn: Temporal.PlainDate;
  readonly endsOn: Temporal.PlainDate;
}

export interface PeriodListOptions {
  readonly kind?: string;
  readonly status?: PeriodStatus;
  /** At most 500; 100 by default. */
  readonly limit?: number;
}

export interface PeriodsOptions extends BlockOptions {
  readonly hooks?: BlockHooks<Periods>;
  readonly logger?: Logger;
}

export interface Periods {
  /** Creates a period. The range may not overlap another of the same kind. */
  createPeriod(input: CreatePeriodInput): AsyncResultType<Period>;
  /**
   * The period of a kind that holds a date, or `undefined`. A kind with a
   * calendar cadence is created the first time a date in it is asked for.
   */
  periodFor(input: {
    readonly kind: string;
    readonly date: Temporal.PlainDate;
  }): AsyncResultType<Period | undefined>;
  /** Whether writes dated on `date` may still land in the kind's period. */
  isOpen(input: {
    readonly kind: string;
    readonly date: Temporal.PlainDate;
  }): AsyncResultType<boolean>;
  /** What keeps a period from closing, from every contributing block. */
  closeBlockers(periodId: string): AsyncResultType<readonly string[]>;
  /** Stops writes into an open period without closing it. */
  lock(periodId: string): AsyncResultType<Period>;
  /**
   * Closes a period when no block names a blocker, and runs each block's
   * on-close step in the same transaction. A blocked close fails with the
   * `PERIOD_CLOSE_BLOCKED` hint.
   */
  close(periodId: string): AsyncResultType<Period>;
  /** Reopens a locked or closed period. On-close steps are not undone. */
  reopen(input: {
    readonly periodId: string;
    readonly reason?: string;
  }): AsyncResultType<Period>;
  listPeriods(list?: PeriodListOptions): AsyncResultType<readonly Period[]>;
  /**
   * One keyset page of periods, latest first or by `sort`, with `hasMore` and a
   * `nextCursor`.
   */
  periodPage(options?: PageOptions): AsyncResultType<ListPage<Period>>;
  /**
   * The values of each facet of periods and their counts, under the page's
   * filters.
   */
  periodFacets(options?: FacetOptions): AsyncResultType<readonly FacetResult[]>;
  /** How many of periods match the page's filters. */
  periodCount(options?: CountOptions): AsyncResultType<Count>;
}

function periodOf(value: unknown, fn: string): Period {
  const row = recordOf(value, fn);
  const closedAt = optionalInstant(row["closedAt"]);
  const closedBy = row["closedBy"];

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    kind: textOf(row["kind"]),
    startsOn: plainDateOf(row["startsOn"], "startsOn"),
    endsOn: plainDateOf(row["endsOn"], "endsOn"),
    status: enumOrThrow(row["status"], PERIOD_STATUSES, "period status"),
    createdAt: temporal().Instant.from(textOf(row["createdAt"])),
    ...(closedAt === undefined ? {} : { closedAt }),
    ...(typeof closedBy === "string" ? { closedBy } : {}),
  };
}

/**
 * Periods: dated ranges per kind with a status, a lookup by date and a close
 * protocol. Blocks that own a period kind (accounting fiscal periods, leave
 * years) contribute their blockers and their on-close step to it.
 */
export function createPeriods(options: PeriodsOptions): Periods {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResultType<string> => requireTenant(options.tenant);

  const periods = entityList({
    entity: "period",
    surface: periodListSurface,
    call,
    tenant,
    fn: "list_periods",
    rowOf: periodOf,
  });

  const client: Periods = {
    periodPage: periods.page,
    periodFacets: periods.facets,
    periodCount: periods.count,
    createPeriod: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "create_period",
          {
            tenant: organizationId,
            kind: input.kind,
            starts_on: input.startsOn.toString(),
            ends_on: input.endsOn.toString(),
          },
          (value) => periodOf(value, "create_period"),
        ),
      ),
    periodFor: ({ kind, date }) =>
      tenant().andThen((organizationId) =>
        call(
          "period_for",
          { tenant: organizationId, kind, on_date: date.toString() },
          (value) =>
            value === null || value === undefined
              ? undefined
              : periodOf(value, "period_for"),
        ),
      ),
    isOpen: ({ kind, date }) =>
      tenant().andThen((organizationId) =>
        call(
          "period_is_open",
          { tenant: organizationId, kind, on_date: date.toString() },
          (value) => value === true,
        ),
      ),
    closeBlockers: (periodId) =>
      call("period_close_blockers", { period_id: periodId }, (value) =>
        Array.isArray(value) ? value.map((item) => textOf(item)) : [],
      ),
    lock: (periodId) =>
      call("lock_period", { period_id: periodId }, (value) =>
        periodOf(value, "lock_period"),
      ),
    close: (periodId) =>
      call("close_period", { period_id: periodId }, (value) =>
        periodOf(value, "close_period"),
      ),
    reopen: ({ periodId, reason }) =>
      call(
        "reopen_period",
        { period_id: periodId, ...(reason === undefined ? {} : { reason }) },
        (value) => periodOf(value, "reopen_period"),
      ),
    listPeriods: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_periods",
          {
            tenant: organizationId,
            filters: Object.fromEntries(
              Object.entries(list).filter(([, value]) => value !== undefined),
            ),
          },
          (value) =>
            recordsOf(value, "list_periods").map((row) =>
              periodOf(row, "list_periods"),
            ),
        ),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "periods",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
