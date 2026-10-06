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
} from "../shared.ts";
import { lazyStripe, type StripeSource } from "../stripe.ts";

export interface UsageOptions {
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
  /** `undefined` without a quota. */
  readonly limit: number | undefined;
  readonly remaining: number | undefined;
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
  current(organizationId: string, meter: string): AsyncResult<UsageStatus>;
  /** Units left in the period, or `undefined` without a quota. */
  remaining(
    organizationId: string,
    meter: string,
  ): AsyncResult<number | undefined>;
  /** The meter catalog (`options.meters`), empty without one. */
  meters(): AsyncResult<Readonly<Record<string, UsageMeterInfo>>>;
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
  });
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
    current,
    remaining: (organizationId, meter) =>
      current(organizationId, meter).map((status) => status.remaining),
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
}

export interface ReportUsageResult {
  /** Meter events sent. */
  readonly reported: number;
  /** Counters left for a later run: no customer, or no event name. */
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
  const rows = recordsOf(
    await transport.call(schema, "unreported_usage", {
      max_rows: options.batch ?? 500,
    }),
    "unreported_usage",
  );
  let reported = 0;
  let skipped = 0;
  for (const row of rows) {
    const organizationId = textOf(row["organization_id"]);
    const meter = textOf(row["meter"]);
    const day = textOf(row["day"]).slice(0, 10);
    const value = numberOf(row["value"]);
    const delta = value - numberOf(row["reported_value"]);
    const eventName = options.eventName ? options.eventName(meter) : meter;
    if (!customers.has(organizationId)) {
      customers.set(organizationId, await customerOf(organizationId));
    }
    const customer = customers.get(organizationId);
    if (eventName === undefined || customer === undefined) {
      skipped += 1;
      continue;
    }
    const identifier = `${organizationId}:${meter}:${day}:${String(value)}`;
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
    await transport.call(schema, "mark_usage_reported", {
      tenant: organizationId,
      meter,
      day,
      value,
    });
    reported += 1;
  }
  return { reported, skipped };
}
