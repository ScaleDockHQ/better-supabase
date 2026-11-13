import type { AsyncResult } from "../../core/result.ts";
import type { BlockOptions } from "../shared.ts";

import { blockCall, recordOf, textOf } from "../shared.ts";

/** A subscription kept in Postgres, with no Stripe object behind it. */
export interface NativeSubscription {
  readonly id: string;
  readonly plan: string;
  readonly currency: string;
  /** The price of one unit for one interval, in minor units as text (ADR 0037). */
  readonly unitAmount: string;
  readonly quantity: number;
  readonly interval: "week" | "month" | "year";
  readonly periodStart: string;
  readonly periodEnd: string;
}

export interface NativeSubscriptionInput {
  readonly organizationId: string;
  readonly plan: string;
  readonly currency: string;
  /** Minor units of `currency`. */
  readonly unitAmount: string;
  readonly quantity?: number;
  readonly interval?: "week" | "month" | "year";
  readonly startedAt?: string;
}

/** What a mid-period change adds, in minor units of `currency` as text. */
export interface Proration {
  readonly subscriptionId: string;
  /** The unused part of the old price. */
  readonly credit: string;
  /** The remaining part of the new price. */
  readonly charge: string;
  /** `charge` minus `credit`; negative for a downgrade. */
  readonly net: string;
  readonly currency: string;
  /**
   * The ledger transaction, when the ledger block is installed and net is not
   * zero.
   */
  readonly transactionId: string | null;
}

export interface ProrationInput {
  readonly subscriptionId: string;
  readonly unitAmount?: string;
  readonly quantity?: number;
  /** The instant of the change. Default: now. */
  readonly at?: string;
}

export interface NativeSubscriptions {
  create(input: NativeSubscriptionInput): AsyncResult<NativeSubscription>;
  /**
   * Changes the price or quantity inside the current period and returns the
   * proration, posted once per subscription and instant.
   */
  prorateChange(input: ProrationInput): AsyncResult<Proration>;
  cancel(subscriptionId: string): AsyncResult<boolean>;
}

function intervalOf(value: unknown): NativeSubscription["interval"] {
  return value === "week" || value === "year" ? value : "month";
}

/** Subscriptions that live in Postgres; the `service` transport runs them. */
export function createNativeSubscriptions(
  options: BlockOptions,
): NativeSubscriptions {
  const service = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );

  return {
    create: (input) =>
      service(
        "create_native_subscription",
        {
          tenant: input.organizationId,
          plan: input.plan,
          currency: input.currency,
          unit_amount: input.unitAmount,
          quantity: input.quantity ?? 1,
          billing_interval: input.interval ?? "month",
          started_at: input.startedAt ?? null,
        },
        (value) => {
          const row = recordOf(value, "create_native_subscription");

          return {
            id: textOf(row["id"]),
            plan: textOf(row["plan"]),
            currency: textOf(row["currency"]),
            unitAmount: textOf(row["unit_amount"]),
            quantity: Number(row["quantity"]),
            interval: intervalOf(row["interval"]),
            periodStart: textOf(row["period_starts_at"]),
            periodEnd: textOf(row["period_ends_at"]),
          };
        },
      ),
    prorateChange: (input) =>
      service(
        "prorate_change",
        {
          subscription_id: input.subscriptionId,
          unit_amount: input.unitAmount ?? null,
          quantity: input.quantity ?? null,
          at: input.at ?? null,
        },
        (value) => {
          const row = recordOf(value, "prorate_change");
          const transaction = row["transaction_id"];

          return {
            subscriptionId: textOf(row["subscription_id"]),
            credit: textOf(row["credit"]),
            charge: textOf(row["charge"]),
            net: textOf(row["net"]),
            currency: textOf(row["currency"]),
            transactionId: typeof transaction === "string" ? transaction : null,
          };
        },
      ),
    cancel: (subscriptionId) =>
      service(
        "cancel_native_subscription",
        { subscription_id: subscriptionId },
        (value) => value === true,
      ),
  };
}
