import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { AsyncResult } from "../../core/result.ts";

import {
  blockCall,
  DEFAULT_BLOCK_SCHEMA,
  isRecord,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
  toInstant,
  type BlockTemporalOptions,
  applyTemporal,
} from "../shared.ts";
import { lazyStripe, type StripeSource } from "../stripe.ts";

export interface UsageOptions extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /** The module schema (`sql.modules.usage.schema`), default `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface RecordUsageOptions {
  /** Default 1. */
  readonly quantity?: number;
  /** A retried call with the same key counts once. */
  readonly idempotencyKey?: string;
  /**
   * What used it, such as `feature:summary` or `api:/v1/search`, kept in the
   * history with `sql.modules.usage.options.history`.
   */
  readonly source?: string;
  /** More detail for the history entry, such as a document id. */
  readonly metadata?: Readonly<Record<string, unknown>>;
  /**
   * Who used it, for a service transport recording on a user's behalf.
   * Ignored for other callers, whose own user id is recorded.
   */
  readonly actor?: string;
}

/** One meter of a batch. */
export interface UsageEntry {
  readonly meter: string;
  /** Default 1. */
  readonly quantity?: number;
}

export interface UsageBatchRecorded {
  /** False when the idempotency key was seen before for every meter. */
  readonly recorded: boolean;
  /** Today's usage per meter (UTC). */
  readonly today: Readonly<Record<string, number>>;
}

/** One entry of the usage history. */
export interface UsageHistoryEntry {
  readonly id: number;
  readonly meter: string;
  readonly quantity: number;
  /** The user who used it, or `undefined` for service usage without one. */
  readonly actor: string | undefined;
  readonly source: string | undefined;
  readonly metadata: Readonly<Record<string, unknown>>;
  readonly recordedAt: Temporal.Instant;
}

/** Usage of a meter in its current window per actor and source. */
export interface UsageBreakdownEntry {
  readonly actor: string | undefined;
  readonly source: string | undefined;
  readonly quantity: number;
}

export interface UsageHistoryOptions {
  readonly meter?: string;
  /** Defaults to 100, at most 1000. */
  readonly limit?: number;
  /** Only entries with a lower id, for the next page. */
  readonly before?: number;
}

export interface UsageRecorded {
  /** False when the idempotency key was seen before. */
  readonly recorded: boolean;
  /** Today's usage of the meter (UTC). */
  readonly today: number;
}

/**
 * A quota period: a UTC calendar period, or `billing` for the window the
 * app's `usage_billing_period(tenant)` function returns.
 */
export type UsagePeriod = "day" | "week" | "month" | "year" | "billing";

/** One meter of `sql.modules.usage.options.meters`. */
export interface UsageMeterInfo {
  readonly unit?: string;
  readonly category?: string;
  readonly label?: string;
}

export interface UsageStatus {
  readonly meter: string;
  /** Usage in the current period. */
  readonly used: number;
  /** `undefined` without a quota and for an unlimited one. */
  readonly limit: number | undefined;
  readonly remaining: number | undefined;
  readonly unlimited: boolean;
  readonly period: UsagePeriod;
  /** When the current period started. */
  readonly startsAt: Temporal.Instant | undefined;
  readonly resetsAt: Temporal.Instant;
  /** From the meter catalog, when the module has one. */
  readonly unit?: string;
  readonly category?: string;
  readonly label?: string;
}

export interface Usage {
  /** Adds usage without checking the quota (metering only). */
  record(
    organizationId: string,
    meter: string,
    options?: RecordUsageOptions,
  ): AsyncResult<UsageRecorded>;
  /** Adds usage when it fits the quota, or returns `quota_exceeded`. */
  consume(
    organizationId: string,
    meter: string,
    options?: RecordUsageOptions,
  ): AsyncResult<UsageRecorded>;
  /**
   * Adds several meters in one transaction, all or none, such as input and
   * output tokens of one call. The idempotency key covers the batch.
   */
  recordMany(
    organizationId: string,
    entries: readonly UsageEntry[],
    options?: Omit<RecordUsageOptions, "quantity">,
  ): AsyncResult<UsageBatchRecorded>;
  /**
   * Like `recordMany`, but checks each meter's quota first; when one doesn't
   * fit, nothing is recorded and the result is `quota_exceeded`.
   */
  consumeMany(
    organizationId: string,
    entries: readonly UsageEntry[],
    options?: Omit<RecordUsageOptions, "quantity">,
  ): AsyncResult<UsageBatchRecorded>;
  current(organizationId: string, meter: string): AsyncResult<UsageStatus>;
  overview(organizationId: string): AsyncResult<readonly UsageStatus[]>;
  /** Units left in the period, or `undefined` without a quota. */
  remaining(
    organizationId: string,
    meter: string,
  ): AsyncResult<number | undefined>;
  /** The meter catalog (`options.meters`), empty without one. */
  meters(): AsyncResult<Readonly<Record<string, UsageMeterInfo>>>;
  /**
   * The tenant's usage entries, newest first, with who and what used each
   * (`usage.read`). Empty without `sql.modules.usage.options.history`.
   */
  history(
    organizationId: string,
    options?: UsageHistoryOptions,
  ): AsyncResult<readonly UsageHistoryEntry[]>;
  /**
   * The meter's usage in its current quota window per actor and source,
   * largest first (`usage.read`). Empty without the history option.
   */
  breakdown(
    organizationId: string,
    meter: string,
  ): AsyncResult<readonly UsageBreakdownEntry[]>;
}

const numberOf = (value: unknown): number =>
  typeof value === "number" ? value : Number(value);

const optionalNumber = (value: unknown): number | undefined =>
  value === null || value === undefined ? undefined : numberOf(value);

const PERIODS: ReadonlySet<string> = new Set([
  "day",
  "week",
  "month",
  "year",
  "billing",
]);

const periodOf = (value: unknown): UsagePeriod => {
  const text = textOf(value);
  // SAFETY: checked against the periods the usage_quotas check allows.
  return PERIODS.has(text) ? (text as UsagePeriod) : "month";
};

function recordedOf(value: unknown): UsageRecorded {
  const row = recordOf(value, "record_usage");
  return { recorded: row["recorded"] === true, today: numberOf(row["used"]) };
}

function statusOf(value: unknown): UsageStatus {
  const row = recordOf(value, "usage_status");
  return {
    meter: textOf(row["meter"]),
    used: numberOf(row["used"]),
    limit: optionalNumber(row["limit"]),
    remaining: optionalNumber(row["remaining"]),
    unlimited: row["unlimited"] === true,
    period: periodOf(row["period"]),
    startsAt:
      row["starts_at"] === undefined || row["starts_at"] === null
        ? undefined
        : toInstant(textOf(row["starts_at"])),
    resetsAt: toInstant(textOf(row["resets_at"])),
    ...meterInfo(row),
  };
}

function meterInfo(row: Readonly<Record<string, unknown>>): UsageMeterInfo {
  const unit = optionalText(row["unit"]);
  const category = optionalText(row["category"]);
  const label = optionalText(row["label"]);
  return {
    ...(unit === undefined ? {} : { unit }),
    ...(category === undefined ? {} : { category }),
    ...(label === undefined ? {} : { label }),
  };
}

/** Usage metering and quotas over the `usage` module's functions. */
export function createUsage(options: UsageOptions): Usage {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const args = (
    organizationId: string,
    meter: string,
    record: RecordUsageOptions = {},
  ): Record<string, unknown> => ({
    tenant: organizationId,
    meter,
    quantity: record.quantity ?? 1,
    idempotency_key: record.idempotencyKey,
    source: record.source,
    metadata: record.metadata,
    actor: record.actor,
  });
  const batch =
    (check: boolean) =>
    (
      organizationId: string,
      entries: readonly UsageEntry[],
      record: Omit<RecordUsageOptions, "quantity"> = {},
    ): AsyncResult<UsageBatchRecorded> =>
      call(
        "record_usage_batch",
        {
          tenant: organizationId,
          entries: JSON.stringify(
            entries.map((entry) => ({
              meter: entry.meter,
              quantity: entry.quantity ?? 1,
            })),
          ),
          idempotency_key: record.idempotencyKey,
          check,
          source: record.source,
          metadata: record.metadata,
          actor: record.actor,
        },
        (value) => {
          const row = recordOf(value, "record_usage_batch");
          const used = isRecord(row["used"]) ? row["used"] : {};
          return {
            recorded: row["recorded"] === true,
            today: Object.fromEntries(
              Object.entries(used).map(([meter, today]) => [
                meter,
                numberOf(today),
              ]),
            ),
          };
        },
      );
  const current = (
    organizationId: string,
    meter: string,
  ): AsyncResult<UsageStatus> =>
    call("usage_status", { tenant: organizationId, meter }, statusOf);
  return {
    record: (organizationId, meter, record) =>
      call("record_usage", args(organizationId, meter, record), recordedOf),
    consume: (organizationId, meter, record) =>
      call("consume_quota", args(organizationId, meter, record), recordedOf),
    recordMany: batch(false),
    consumeMany: batch(true),
    current,
    overview: (organizationId) =>
      call("usage_overview", { tenant: organizationId }, (value) =>
        (Array.isArray(value) ? value : []).map(statusOf),
      ),
    remaining: (organizationId, meter) =>
      current(organizationId, meter).map((status) => status.remaining),
    history: (organizationId, list = {}) =>
      call(
        "usage_history",
        {
          tenant: organizationId,
          meter: list.meter,
          max_rows: list.limit ?? 100,
          before_id: list.before,
        },
        (value) =>
          (Array.isArray(value) ? value.filter(isRecord) : []).map((row) => ({
            id: numberOf(row["id"]),
            meter: textOf(row["meter"]),
            quantity: numberOf(row["quantity"]),
            actor: optionalText(row["actor"]),
            source: optionalText(row["source"]),
            metadata: isRecord(row["metadata"]) ? row["metadata"] : {},
            recordedAt: toInstant(textOf(row["recorded_at"])),
          })),
      ),
    breakdown: (organizationId, meter) =>
      call("usage_breakdown", { tenant: organizationId, meter }, (value) =>
        (Array.isArray(value) ? value.filter(isRecord) : []).map((row) => ({
          actor: optionalText(row["actor"]),
          source: optionalText(row["source"]),
          quantity: numberOf(row["quantity"]),
        })),
      ),
    meters: () =>
      call("usage_meters", {}, (value) => {
        const row = isRecord(value) ? value : {};
        return Object.fromEntries(
          Object.entries(row).map(([meter, info]) => [
            meter,
            meterInfo(isRecord(info) ? info : {}),
          ]),
        );
      }),
  };
}

export interface ReportUsageOptions {
  /** A service-role transport: the reporting functions are granted to `service_role` only. */
  readonly transport: BlockTransport;
  readonly stripe: StripeSource;
  readonly schema?: string;
  /** The Stripe meter's `event_name` for a meter; default the meter itself. */
  readonly eventName?: (meter: string) => string | undefined;
  /**
   * The tenant's Stripe customer. Default: `tenant_stripe_customer()` from
   * the `entitlements` module (`config.entitlements.customer`).
   */
  readonly customer?: (organizationId: string) => Promise<string | undefined>;
  /** Counters per run, default 500. */
  readonly batch?: number;
  /**
   * Send only the usage above the tenant's quota (the allowance its plan
   * includes) in each quota window, instead of every unit. A meter without
   * a quota sends everything, and one with an unlimited quota sends nothing.
   */
  readonly overage?: boolean;
}

export interface ReportUsageResult {
  /** Meter events sent; usage inside the quota with `overage` is marked without one. */
  readonly reported: number;
  /**
   * Counters left for a later run: no customer, or no event name. They don't
   * hold up the other counters of the batch.
   */
  readonly skipped: number;
}

/**
 * Sends unreported usage to Stripe as meter events, one per counter and
 * delta. The event `identifier` is the tenant, meter, day and new total, so
 * a run that fails after sending and before marking resends the same event,
 * and Stripe drops the duplicate. Run it from a job or a cron route.
 */
export async function reportUsageToStripe(
  options: ReportUsageOptions,
): Promise<ReportUsageResult> {
  const transport = options.transport;
  const schema = options.schema ?? DEFAULT_BLOCK_SCHEMA;
  const stripe = await lazyStripe(options.stripe)();
  const customers = new Map<string, string | undefined>();
  const customerOf =
    options.customer ??
    (async (organizationId: string) =>
      optionalText(
        await transport.call(DEFAULT_BLOCK_SCHEMA, "tenant_stripe_customer", {
          tenant: organizationId,
        }),
      ));
  const limit = options.batch ?? 500;
  const skipMeters = new Set<string>();
  const skipTenants = new Set<string>();
  let reported = 0;
  let skipped = 0;
  let handled = 0;
  for (;;) {
    const rows = recordsOf(
      await transport.call(schema, "unreported_usage", {
        max_rows: limit - handled,
        skip_meters: [...skipMeters],
        skip_tenants: [...skipTenants],
      }),
      "unreported_usage",
    );
    let passedOver = false;
    for (const row of rows) {
      const organizationId = textOf(row["organization_id"]);
      const meter = textOf(row["meter"]);
      if (skipMeters.has(meter) || skipTenants.has(organizationId)) {
        skipped += 1;
        continue;
      }
      const eventName = options.eventName ? options.eventName(meter) : meter;
      if (eventName === undefined) {
        skipMeters.add(meter);
        skipped += 1;
        passedOver = true;
        continue;
      }
      if (!customers.has(organizationId)) {
        customers.set(organizationId, await customerOf(organizationId));
      }
      const customer = customers.get(organizationId);
      if (customer === undefined) {
        skipTenants.add(organizationId);
        skipped += 1;
        passedOver = true;
        continue;
      }
      handled += 1;
      const day = textOf(row["day"]).slice(0, 10);
      const value = numberOf(row["value"]);
      const previous = numberOf(row["reported_value"]);
      const included = optionalNumber(row["included"]);
      const before = numberOf(row["window_before"] ?? 0);
      const delta =
        options.overage === true && row["unlimited"] === true
          ? 0
          : options.overage === true && included !== undefined
            ? Math.max(0, before + value - included) -
              Math.max(0, before + previous - included)
            : value - previous;
      const identifier = `${organizationId}:${meter}:${day}:${String(value)}`;
      if (delta > 0) {
        await stripe.billing.meterEvents.create(
          {
            event_name: eventName,
            payload: { stripe_customer_id: customer, value: String(delta) },
            identifier,
            timestamp: Math.floor(
              Math.min(Date.now(), Date.parse(`${day}T23:59:59Z`)) / 1000,
            ),
          },
          { idempotencyKey: identifier },
        );
        reported += 1;
      }
      await transport.call(schema, "mark_usage_reported", {
        tenant: organizationId,
        meter,
        day,
        value,
      });
    }
    if (!passedOver || handled >= limit || rows.length === 0) break;
  }
  return { reported, skipped };
}
