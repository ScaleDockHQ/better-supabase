import type { Money } from "../../commerce/money.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { DealForecast } from "../deal-forecast.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult } from "../../core/result.ts";
import { forecastOf } from "../deal-forecast.ts";
import {
  amountsError,
  optionalAmountText,
  optionalMoneyOf,
  moneyOf,
} from "../money-codec.ts";
import { plainDate } from "../sales-shared.ts";
import {
  applyTemporal,
  blockCall,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

/** A stored forecast call. */
export interface ForecastSnapshot {
  readonly id: string;
  readonly organizationId: string;
  /** `undefined` for a snapshot of every pipeline. */
  readonly pipelineId: string | undefined;
  readonly since: Temporal.PlainDate;
  readonly until: Temporal.PlainDate;
  readonly currency: string;
  readonly target: Money | undefined;
  /** The totals by forecast category, as `deals.forecast` returned them. */
  readonly totals: DealForecast;
  readonly dealCount: number;
  readonly takenBy: string | undefined;
  readonly takenAt: Temporal.Instant;
}

/** A deal as a snapshot counted it. */
export interface ForecastSnapshotDeal {
  readonly dealId: string;
  readonly name: string;
  readonly ownerId: string | undefined;
  readonly stageId: string | undefined;
  /** `undefined` when the deal was not called. */
  readonly forecast: string | undefined;
  readonly outcome: string;
  readonly amount: Money;
  readonly closeOn: Temporal.PlainDate | undefined;
  readonly closedAt: Temporal.Instant | undefined;
}

/** How a deal moved between two snapshots. */
export type ForecastChangeKind =
  | "added"
  | "removed"
  | "won"
  | "lost"
  | "changed";

export interface ForecastDealChange {
  readonly dealId: string;
  readonly name: string;
  readonly change: ForecastChangeKind;
  /** `undefined` for an added deal. */
  readonly before: ForecastSnapshotDeal | undefined;
  /** `undefined` for a removed deal. */
  readonly after: ForecastSnapshotDeal | undefined;
}

export interface ForecastChanges {
  readonly from: ForecastSnapshot;
  readonly to: ForecastSnapshot;
  /** The deals that changed, the largest amount first. */
  readonly deals: readonly ForecastDealChange[];
}

export interface Forecasts {
  /**
   * Stores the forecast call for the period with every deal it counted. Needs
   * `forecasts.snapshot`; a cron calls it with the service role.
   */
  snapshot(input: {
    organizationId: string;
    period: {
      readonly since: Temporal.PlainDate;
      readonly until: Temporal.PlainDate;
      readonly currency: string;
      /** In `currency`. */
      readonly target?: Money;
      readonly pipelineId?: string;
    };
  }): AsyncResult<ForecastSnapshot>;
  /** Snapshots, newest first, of one pipeline or period when given. */
  list(input: {
    organizationId: string;
    filter?:
      | {
          readonly pipelineId?: string;
          readonly since?: Temporal.PlainDate;
          readonly until?: Temporal.PlainDate;
          /** At most this many. Default: 50, at most 200. */
          readonly limit?: number;
        }
      | undefined;
  }): AsyncResult<ForecastSnapshot[]>;
  /** One snapshot with the deals it counted, the largest amount first. */
  get(
    snapshotId: string,
  ): AsyncResult<
    ForecastSnapshot & { readonly deals: readonly ForecastSnapshotDeal[] }
  >;
  /**
   * The deals that were added, removed, won, lost or changed between two
   * snapshots of one organization and currency.
   */
  changes(input: {
    fromSnapshotId: string;
    toSnapshotId: string;
  }): AsyncResult<ForecastChanges>;
}

export interface ForecastsOptions extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  readonly hooks?: NoInfer<BlockHooks<Forecasts>>;
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

function requiredDate(value: unknown, field: string): Temporal.PlainDate {
  const date = plainDate(value);

  if (date === undefined) {
    throw new TypeError(`${field} is missing`);
  }

  return date;
}

function snapshotOf(value: unknown): ForecastSnapshot {
  const row = recordOf(value, "forecast_snapshot");
  const currency = textOf(row["currency"]);
  const count = row["dealCount"];

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    pipelineId: optionalText(row["pipelineId"]),
    since: requiredDate(row["since"], "since"),
    until: requiredDate(row["until"], "until"),
    currency,
    target: optionalMoneyOf(
      row["target"],
      currency,
      "forecast_snapshot target",
    ),
    totals: forecastOf(row["totals"], "forecast_snapshot totals"),
    dealCount: typeof count === "number" ? count : 0,
    takenBy: optionalText(row["takenBy"]),
    takenAt: requiredInstant(row["takenAt"], "takenAt"),
  };
}

function dealOf(value: unknown, currency: string): ForecastSnapshotDeal {
  const row = recordOf(value, "forecast_snapshot deal");

  return {
    dealId: textOf(row["dealId"]),
    name: textOf(row["name"]),
    ownerId: optionalText(row["ownerId"]),
    stageId: optionalText(row["stageId"]),
    forecast: optionalText(row["forecast"]),
    outcome: textOf(row["outcome"]),
    amount: moneyOf(row["amount"], currency, "forecast_snapshot deal amount"),
    closeOn: plainDate(row["closeOn"]),
    closedAt: optionalInstant(row["closedAt"]),
  };
}

const CHANGES: readonly ForecastChangeKind[] = [
  "added",
  "removed",
  "won",
  "lost",
];

const isChangeKind = (value: unknown): value is ForecastChangeKind =>
  CHANGES.some((kind) => kind === value);

const changeKind = (value: unknown): ForecastChangeKind =>
  isChangeKind(value) ? value : "changed";

function changesOf(value: unknown): ForecastChanges {
  const row = recordOf(value, "forecast_changes");
  const from = snapshotOf(row["from"]);

  const side = (entry: unknown): ForecastSnapshotDeal | undefined =>
    entry === null || entry === undefined
      ? undefined
      : dealOf(entry, from.currency);

  return {
    from,
    to: snapshotOf(row["to"]),
    deals: recordsOf(row["deals"], "forecast_changes deals").map((deal) => ({
      dealId: textOf(deal["dealId"]),
      name: textOf(deal["name"]),
      change: changeKind(deal["change"]),
      before: side(deal["before"]),
      after: side(deal["after"]),
    })),
  };
}

/**
 * The forecasts block: snapshots of the deals forecast call over time, each
 * with the deals it counted, and what moved between two of them.
 */
export function createForecasts(options: ForecastsOptions): Forecasts {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const forecasts: Forecasts = {
    snapshot: ({ organizationId, period }) => {
      const invalid = amountsError(period.currency, [period.target]);

      return invalid === undefined
        ? call(
            "take_forecast_snapshot",
            {
              tenant: organizationId,
              pipeline: period.pipelineId ?? null,
              since: period.since.toString(),
              until: period.until.toString(),
              currency: period.currency,
              target: optionalAmountText(period.target),
            },
            snapshotOf,
          )
        : AsyncResult.err(invalid);
    },
    list: ({ organizationId, filter = {} }) =>
      call(
        "forecast_snapshots",
        {
          tenant: organizationId,
          pipeline: filter.pipelineId ?? null,
          since: filter.since?.toString() ?? null,
          until: filter.until?.toString() ?? null,
          max_count: filter.limit ?? null,
        },
        (value) =>
          recordsOf(value, "forecast_snapshots").map((row) => snapshotOf(row)),
      ),
    get: (snapshotId) =>
      call("forecast_snapshot", { snapshot: snapshotId }, (value) => {
        const snapshot = snapshotOf(value);
        const row = recordOf(value, "forecast_snapshot");

        return {
          ...snapshot,
          deals: recordsOf(row["deals"], "forecast_snapshot deals").map(
            (deal) => dealOf(deal, snapshot.currency),
          ),
        };
      }),
    changes: ({ fromSnapshotId, toSnapshotId }) =>
      call(
        "forecast_changes",
        { from_snapshot: fromSnapshotId, to_snapshot: toSnapshotId },
        changesOf,
      ),
  };

  return withBlockHooks(forecasts, options.hooks, {
    block: "forecasts",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
