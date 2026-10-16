import type { AsyncResult } from "../core/result.ts";
import type { WebhookInput } from "../core/signatures.ts";

import { type DbError, dbError } from "../core/errors.ts";
import { isMoney, type Money } from "./money.ts";

/**
 * Where a payment stands. `requires_action`: the customer still has to act
 * (pick a method, confirm, pass 3-D Secure). `authorized`: the funds are
 * held and wait for `capture`.
 */
export type PaymentStatus =
  | "requires_action"
  | "processing"
  | "authorized"
  | "succeeded"
  | "failed"
  | "canceled";

export interface Payment {
  /** The provider's id, stored with the order as its payment reference. */
  readonly id: string;
  /** The provider's `name`. */
  readonly provider: string;
  readonly status: PaymentStatus;
  readonly amount: Money;
  /** What was captured so far; zero until the payment succeeds. */
  readonly captured: Money;
  /** What was refunded so far. */
  readonly refunded: Money;
  /** The order or cart the payment is for, as `createPayment` got it. */
  readonly reference: string;
  /**
   * The secret a client confirms the payment with (Stripe's
   * `client_secret`). Hand it to the paying browser only; never store or
   * log it.
   */
  readonly clientSecret?: string;
  /** Where to send the customer to finish, when the provider redirects. */
  readonly redirectUrl?: string;
  readonly metadata: Readonly<Record<string, string>>;
}

export interface CreatePaymentInput {
  /** More than zero, in a currency the provider charges. */
  readonly amount: Money;
  /** The order or cart this pays for. Webhook events carry it back. */
  readonly reference: string;
  /** `manual` holds the funds until `capture`. Defaults to `automatic`. */
  readonly capture?: "automatic" | "manual";
  /** The provider's customer id. */
  readonly customer?: string;
  readonly description?: string;
  /** Where a redirecting payment method returns the customer. */
  readonly returnUrl?: string;
  readonly metadata?: Readonly<Record<string, string>>;
}

export interface PaymentCallOptions {
  /** The same key returns the first call's result instead of paying twice. */
  readonly idempotencyKey?: string;
  readonly signal?: AbortSignal;
}

export type RefundStatus = "pending" | "succeeded" | "failed" | "canceled";

export interface Refund {
  readonly id: string;
  readonly paymentId: string;
  readonly amount: Money;
  readonly status: RefundStatus;
}

export interface RefundInput {
  /** Defaults to what is left of the captured amount. */
  readonly amount?: Money;
  readonly reason?: string;
}

export type PaymentEventType =
  | "payment.requires_action"
  | "payment.processing"
  | "payment.authorized"
  | "payment.succeeded"
  | "payment.failed"
  | "payment.canceled"
  | "refund.succeeded"
  | "refund.failed";

/** A provider's webhook event in one shape for every provider. */
export interface PaymentEvent {
  /**
   * The provider's event id. A redelivered event repeats it, so key the
   * handling on it (the webhook inbox and the `idempotency` module do).
   */
  readonly id: string;
  readonly type: PaymentEventType;
  readonly paymentId: string;
  /** The payment's `reference`, when the event carries it. */
  readonly reference?: string;
  /** The payment's amount, or the refund's for `refund.*`. */
  readonly amount?: Money;
  readonly refundId?: string;
  readonly occurredAt: Temporal.Instant;
}

/**
 * Takes payments for orders. Versioned: a breaking change ships a new
 * `apiVersion`. Every method returns a `Result`: `invalid_input` for an
 * amount the provider can't charge or a refund above what was captured,
 * `not_found` for an unknown payment, `unauthorized` for a webhook whose
 * signature fails, and `raised` with the hint `PAYMENT_DECLINED` when the
 * provider declines.
 */
export interface PaymentProvider {
  readonly apiVersion: 1;
  readonly name: string;
  createPayment(
    input: CreatePaymentInput,
    options?: PaymentCallOptions,
  ): AsyncResult<Payment>;
  /** Captures an authorized payment, all of it unless `amount` is less. */
  capture(
    paymentId: string,
    input?: { readonly amount?: Money },
    options?: PaymentCallOptions,
  ): AsyncResult<Payment>;
  refund(
    paymentId: string,
    input?: RefundInput,
    options?: PaymentCallOptions,
  ): AsyncResult<Refund>;
  /**
   * Verifies a webhook delivery with the provider's secret and returns its
   * events, none for types the contract doesn't cover.
   */
  parseWebhook(input: WebhookInput): AsyncResult<readonly PaymentEvent[]>;
  /** Releases a payment that was not captured yet. */
  cancel?(
    paymentId: string,
    options?: PaymentCallOptions,
  ): AsyncResult<Payment>;
  get?(
    paymentId: string,
    options?: { readonly signal?: AbortSignal },
  ): AsyncResult<Payment>;
}

/** Checks the provider's `apiVersion` before a block uses it. */
export function paymentProviderOf(provider: PaymentProvider): PaymentProvider {
  const version: unknown = provider.apiVersion;
  if (version !== 1)
    throw new TypeError(
      `payments "${provider.name}" targets payment provider API ${String(version)}; this better-supabase supports 1. Upgrade better-supabase or use a release of the provider for API 1.`,
    );
  return provider;
}

/** The error for an amount a payment can't carry: not money, or not above zero. */
export function invalidPaymentAmount(amount: unknown): DbError | undefined {
  if (!isMoney(amount))
    return dbError(
      "invalid_input",
      "A payment amount is Money: a bigint of minor units and an ISO 4217 currency",
      { hint: "PAYMENT_AMOUNT_INVALID" },
    );
  if (amount.amount <= 0n)
    return dbError("invalid_input", "A payment amount must be more than zero", {
      hint: "PAYMENT_AMOUNT_INVALID",
    });
  return undefined;
}
