import type { Money } from "./money.ts";

import { lazyStripe, type StripeSource } from "../blocks/stripe.ts";
import { verifyStripeWebhook } from "../blocks/webhooks/verify.ts";
import { dbError } from "../core/errors.ts";
import { err, ok, type Result } from "../core/result.ts";
import { temporal } from "../core/temporal-required.ts";
import {
  invalidPaymentAmount,
  type Payment,
  type PaymentEvent,
  type PaymentEventType,
  type PaymentProvider,
  type PaymentStatus,
  type Refund,
  type RefundStatus,
} from "./payments.ts";
import {
  fromStripeAmount,
  idempotency,
  stripeResult,
  toStripeAmount,
} from "./stripe-shared.ts";

type Params = Readonly<Record<string, unknown>>;

type RequestOptions = { readonly idempotencyKey?: string };

/** A PaymentIntent, as far as the adapter reads it. */
export interface StripePaymentIntent {
  readonly id: string;
  readonly status: string;
  readonly amount: number;
  readonly amount_received?: number;
  readonly currency: string;
  readonly client_secret?: string | null;
  readonly metadata?: Readonly<Record<string, string>> | null;
  readonly next_action?: {
    readonly redirect_to_url?: { readonly url?: string | null } | null;
  } | null;
  readonly latest_charge?:
    | string
    | { readonly amount_refunded?: number }
    | null;
}

export interface StripeRefund {
  readonly id: string;
  readonly amount: number;
  readonly currency: string;
  readonly status?: string | null;
  readonly payment_intent?: string | { readonly id: string } | null;
}

/**
 * The part of the Stripe SDK `stripePayments` calls, typed structurally so the
 * block never imports `stripe`.
 */
export interface StripePaymentsClient {
  readonly paymentIntents: {
    create(
      params: {
        readonly amount: number;
        readonly currency: string;
        readonly [key: string]: unknown;
      },
      options?: RequestOptions,
    ): Promise<StripePaymentIntent>;
    retrieve(id: string, params?: Params): Promise<StripePaymentIntent>;
    capture(
      id: string,
      params?: Params,
      options?: RequestOptions,
    ): Promise<StripePaymentIntent>;
    cancel(
      id: string,
      params?: Params,
      options?: RequestOptions,
    ): Promise<StripePaymentIntent>;
  };
  readonly refunds: {
    create(params: Params, options?: RequestOptions): Promise<StripeRefund>;
  };
}

export interface StripePaymentsOptions {
  /**
   * A client, a factory such as `stripeFromKey()` from
   * `better-supabase/stripe`, or `{ secretKey }` to create one from `stripe` in
   * plain Node.
   */
  readonly stripe: StripeSource<StripePaymentsClient>;
  /** The endpoint's `whsec_` secret; several while it rotates. */
  readonly webhookSecret: string | readonly string[];
  /** Defaults to `stripe`. */
  readonly name?: string;
  /**
   * Extra PaymentIntent parameters, such as `{ automatic_payment_methods: {
   * enabled: true } }` (the default) or `payment_method_types`.
   */
  readonly paymentIntent?: Params;
  /** Seconds a webhook timestamp may be off. Defaults to 300. */
  readonly tolerance?: number;
}

const EXPAND = { expand: ["latest_charge"] } as const;

const STATUS: Readonly<Record<string, PaymentStatus>> = {
  requires_payment_method: "requires_action",
  requires_confirmation: "requires_action",
  requires_action: "requires_action",
  processing: "processing",
  requires_capture: "authorized",
  succeeded: "succeeded",
  canceled: "canceled",
};

const REFUND_STATUS: Readonly<Record<string, RefundStatus>> = {
  pending: "pending",
  requires_action: "pending",
  succeeded: "succeeded",
  failed: "failed",
  canceled: "canceled",
};

const EVENTS: Readonly<Record<string, PaymentEventType>> = {
  "payment_intent.requires_action": "payment.requires_action",
  "payment_intent.processing": "payment.processing",
  "payment_intent.amount_capturable_updated": "payment.authorized",
  "payment_intent.succeeded": "payment.succeeded",
  "payment_intent.payment_failed": "payment.failed",
  "payment_intent.canceled": "payment.canceled",
};

const REFERENCE = "better_supabase_reference";

function paymentOf(name: string, intent: StripePaymentIntent): Result<Payment> {
  const charge = intent.latest_charge;

  const refundedAmount =
    typeof charge === "object" && charge !== null
      ? (charge.amount_refunded ?? 0)
      : 0;

  const amount = fromStripeAmount(intent.amount, intent.currency);

  const captured = fromStripeAmount(
    intent.amount_received ?? 0,
    intent.currency,
  );

  const refunded = fromStripeAmount(refundedAmount, intent.currency);

  if (!amount.ok) {
    return amount;
  }

  if (!captured.ok) {
    return captured;
  }

  if (!refunded.ok) {
    return refunded;
  }

  const { [REFERENCE]: reference = "", ...metadata } = intent.metadata ?? {};
  const redirect = intent.next_action?.redirect_to_url?.url;

  return ok({
    id: intent.id,
    provider: name,
    status: STATUS[intent.status] ?? "failed",
    amount: amount.data,
    captured: captured.data,
    refunded: refunded.data,
    reference,
    ...(intent.client_secret ? { clientSecret: intent.client_secret } : {}),
    ...(redirect ? { redirectUrl: redirect } : {}),
    metadata,
  });
}

function refundOf(refund: StripeRefund, paymentId: string): Result<Refund> {
  const amount = fromStripeAmount(refund.amount, refund.currency);

  if (!amount.ok) {
    return amount;
  }

  return ok({
    id: refund.id,
    paymentId,
    amount: amount.data,
    status: REFUND_STATUS[refund.status ?? "pending"] ?? "pending",
  });
}

const objectOf = (value: unknown): Readonly<Record<string, unknown>> =>
  typeof value === "object" && value !== null ? { ...value } : {};

const text = (value: unknown): string | undefined =>
  typeof value === "string" && value.length > 0 ? value : undefined;

/**
 * The payment events in a verified Stripe event, such as one the webhook inbox
 * stored with `stripeInboxVerify`. Event types the contract doesn't cover give
 * none. Needs `Temporal`.
 */
export function stripePaymentEvents(event: unknown): readonly PaymentEvent[] {
  const envelope = objectOf(event);
  const id = text(envelope["id"]);
  const type = text(envelope["type"]);
  const object = objectOf(objectOf(envelope["data"])["object"]);
  const created = envelope["created"];

  if (id === undefined || type === undefined || typeof created !== "number") {
    return [];
  }

  const occurredAt = temporal().Instant.fromEpochMilliseconds(created * 1000);
  const currency = text(object["currency"]);

  const amountOf = (key: string): Money | undefined => {
    const value = object[key];

    if (currency === undefined || typeof value !== "number") {
      return undefined;
    }

    const parsed = fromStripeAmount(value, currency);

    return parsed.ok ? parsed.data : undefined;
  };

  const mapped = EVENTS[type];

  if (mapped !== undefined) {
    const paymentId = text(object["id"]);

    if (paymentId === undefined) {
      return [];
    }

    const reference = text(objectOf(object["metadata"])[REFERENCE]);

    const amount = amountOf(
      mapped === "payment.succeeded" ? "amount_received" : "amount",
    );

    return [
      {
        id,
        type: mapped,
        paymentId,
        occurredAt,
        ...(reference === undefined ? {} : { reference }),
        ...(amount === undefined ? {} : { amount }),
      },
    ];
  }

  if (type.startsWith("refund.")) {
    const status = object["status"];
    const intent = object["payment_intent"];
    const paymentId = text(intent) ?? text(objectOf(intent)["id"]);
    const refundId = text(object["id"]);
    const amount = amountOf("amount");

    if (
      paymentId === undefined ||
      refundId === undefined ||
      (status !== "succeeded" && status !== "failed")
    ) {
      return [];
    }

    return [
      {
        id,
        type: status === "succeeded" ? "refund.succeeded" : "refund.failed",
        paymentId,
        refundId,
        occurredAt,
        ...(amount === undefined ? {} : { amount }),
      },
    ];
  }

  return [];
}

/**
 * A `PaymentProvider` on Stripe PaymentIntents. `stripe` is an optional peer,
 * loaded on first use when `stripe` is `{ secretKey }`; webhooks are verified
 * with WebCrypto, without it.
 */
export function stripePayments(
  options: StripePaymentsOptions,
): PaymentProvider {
  const name = options.name ?? "stripe";
  const client = lazyStripe<StripePaymentsClient>(options.stripe);

  const extra = options.paymentIntent ?? {
    automatic_payment_methods: { enabled: true },
  };

  const sameCurrency = async (
    paymentId: string,
    value: Money | undefined,
  ): Promise<Result<number | undefined>> => {
    if (value === undefined) {
      return ok(undefined);
    }

    const problem = invalidPaymentAmount(value);

    if (problem) {
      return err(problem);
    }

    const intent = await (await client()).paymentIntents.retrieve(paymentId);

    if (intent.currency.toUpperCase() !== value.currency) {
      return err(
        dbError(
          "invalid_input",
          `The payment is in ${intent.currency.toUpperCase()}, not ${value.currency}`,
          { hint: "PAYMENT_CURRENCY_MISMATCH" },
        ),
      );
    }

    return toStripeAmount(value);
  };

  return {
    apiVersion: 1,
    name,
    createPayment: (input, call = {}) =>
      stripeResult(async () => {
        const problem = invalidPaymentAmount(input.amount);

        if (problem) {
          return err(problem);
        }

        const amount = toStripeAmount(input.amount);

        if (!amount.ok) {
          return amount;
        }

        const stripe = await client();

        const intent = await stripe.paymentIntents.create(
          {
            ...extra,
            amount: amount.data,
            currency: input.amount.currency.toLowerCase(),
            capture_method: input.capture === "manual" ? "manual" : "automatic",
            metadata: { ...input.metadata, [REFERENCE]: input.reference },
            ...(input.customer === undefined
              ? {}
              : { customer: input.customer }),
            ...(input.description === undefined
              ? {}
              : { description: input.description }),
            ...EXPAND,
          },
          idempotency(call.idempotencyKey),
        );

        return paymentOf(name, intent);
      }),
    capture: (paymentId, input = {}, call = {}) =>
      stripeResult(async () => {
        const amount = await sameCurrency(paymentId, input.amount);

        if (!amount.ok) {
          return amount;
        }

        const intent = await (
          await client()
        ).paymentIntents.capture(
          paymentId,
          {
            ...(amount.data === undefined
              ? {}
              : { amount_to_capture: amount.data }),
            ...EXPAND,
          },
          idempotency(call.idempotencyKey),
        );

        return paymentOf(name, intent);
      }),
    refund: (paymentId, input = {}, call = {}) =>
      stripeResult(async () => {
        const amount = await sameCurrency(paymentId, input.amount);

        if (!amount.ok) {
          return amount;
        }

        const refund = await (
          await client()
        ).refunds.create(
          {
            payment_intent: paymentId,
            ...(amount.data === undefined ? {} : { amount: amount.data }),
            ...(input.reason === undefined
              ? {}
              : { metadata: { reason: input.reason } }),
          },
          idempotency(call.idempotencyKey),
        );

        return refundOf(refund, paymentId);
      }),
    cancel: (paymentId, call = {}) =>
      stripeResult(async () => {
        const intent = await (
          await client()
        ).paymentIntents.cancel(
          paymentId,
          { ...EXPAND },
          idempotency(call.idempotencyKey),
        );

        return paymentOf(name, intent);
      }),
    get: (paymentId) =>
      stripeResult(async () =>
        paymentOf(
          name,
          await (
            await client()
          ).paymentIntents.retrieve(paymentId, { ...EXPAND }),
        ),
      ),
    parseWebhook: (input) =>
      stripeResult(async () => {
        const verified = await verifyStripeWebhook(
          input,
          options.webhookSecret,
          options.tolerance === undefined
            ? {}
            : { tolerance: options.tolerance },
        );

        if (!verified.ok) {
          return verified;
        }

        return ok(stripePaymentEvents(verified.data.payload));
      }),
  };
}
