import type { Money } from "../../blocks/commerce/money.ts";
import type {
  Payment,
  PaymentProvider,
} from "../../blocks/commerce/payments.ts";
import type { Result } from "../../core/result.ts";
import type { WebhookInput } from "../../core/signatures.ts";

import { money } from "../../blocks/commerce/money.ts";
import { type ConformanceReport, conform, expect } from "../conformance.ts";

export interface TestPaymentProviderOptions {
  /** What the kit charges. Defaults to 10.00 EUR. */
  readonly amount?: Money;
  /**
   * Has the customer approve a `manual` payment, so it reaches
   * `authorized` (with Stripe, confirm it with a test card). Without it
   * the capture and refund checks are skipped.
   */
  readonly authorize?: (payment: Payment) => Promise<void>;
  /**
   * A delivery the provider's endpoint would receive for `payment`, signed
   * with the provider's secret, and the same delivery with its body
   * changed. Without it the webhook checks are skipped.
   */
  readonly webhook?: (payment: Payment) => Promise<{
    readonly valid: WebhookInput;
    readonly tampered: WebhookInput;
  }>;
}

const kindOf = (result: Result<unknown>): string =>
  result.ok ? "ok" : result.error.kind;

const half = (value: Money): Money => ({
  amount: value.amount / 2n,
  currency: value.currency,
});

/**
 * Runs the `PaymentProvider` contract against `provider`: the API version,
 * refused amounts, a created payment and its fields, an idempotency key
 * that pays once, `not_found` for an unknown payment, and, with the
 * options that drive them, capture and refunds of an authorized payment
 * and webhook verification. Every call carries a fresh reference, so the
 * kit runs against a test account without cleanup.
 */
export function testPaymentProvider(
  provider: PaymentProvider,
  options: TestPaymentProviderOptions = {},
): Promise<ConformanceReport> {
  const amount = options.amount ?? money(1000n, "EUR");
  const reference = (): string => `conformance-${crypto.randomUUID()}`;
  const { authorize, webhook } = options;
  const authorized = async (): Promise<Payment> => {
    const created = await provider
      .createPayment({ amount, reference: reference(), capture: "manual" })
      .orThrow();
    await authorize?.(created);
    return created;
  };
  return conform(`PaymentProvider "${provider.name}"`, [
    [
      "has apiVersion 1 and a name",
      () => {
        const version: unknown = provider.apiVersion;
        expect(version === 1, `apiVersion is ${String(version)}`);
        expect(provider.name.length > 0, "name is empty");
      },
    ],
    [
      "refuses a zero amount and a number instead of Money",
      async () => {
        const zero = await provider.createPayment({
          amount: { amount: 0n, currency: amount.currency },
          reference: reference(),
        });
        expect(kindOf(zero) === "invalid_input", `zero gave ${kindOf(zero)}`);
        const plain = await provider.createPayment({
          // @ts-expect-error -- a plain number is what the check refuses
          amount: 1000,
          reference: reference(),
        });
        expect(
          kindOf(plain) === "invalid_input",
          `a number gave ${kindOf(plain)}`,
        );
      },
    ],
    [
      "creates a payment with its amount, reference and provider",
      async () => {
        const ref = reference();
        const payment = await provider
          .createPayment({ amount, reference: ref })
          .orThrow();
        expect(payment.id.length > 0, "the payment has no id");
        expect(
          payment.provider === provider.name,
          `provider is ${payment.provider}`,
        );
        expect(payment.reference === ref, `reference is ${payment.reference}`);
        expect(
          payment.amount.amount === amount.amount &&
            payment.amount.currency === amount.currency,
          `amount is ${String(payment.amount.amount)} ${payment.amount.currency}`,
        );
        expect(payment.refunded.amount === 0n, "a new payment has refunds");
        expect(
          typeof payment.amount.amount === "bigint",
          "the amount is not a bigint",
        );
      },
    ],
    [
      "pays once for one idempotency key",
      async () => {
        const key = crypto.randomUUID();
        const input = { amount, reference: reference() };
        const first = await provider
          .createPayment(input, { idempotencyKey: key })
          .orThrow();
        const again = await provider
          .createPayment(input, { idempotencyKey: key })
          .orThrow();
        expect(first.id === again.id, "the same key created a second payment");
      },
    ],
    [
      "returns not_found for an unknown payment",
      async () => {
        const id = `conformance_missing_${crypto.randomUUID()}`;
        const captured = await provider.capture(id);
        expect(
          kindOf(captured) === "not_found",
          `capture gave ${kindOf(captured)}`,
        );
        const refunded = await provider.refund(id);
        expect(
          kindOf(refunded) === "not_found",
          `refund gave ${kindOf(refunded)}`,
        );
      },
    ],
    provider.get !== undefined && [
      "reads a payment back",
      async () => {
        const created = await provider
          .createPayment({ amount, reference: reference() })
          .orThrow();
        const read = await provider.get?.(created.id).orThrow();
        expect(read?.id === created.id, "get returned another payment");
        expect(read.reference === created.reference, "get lost the reference");
      },
    ],
    authorize !== undefined && [
      "captures an authorized payment",
      async () => {
        const payment = await authorized();
        const captured = await provider.capture(payment.id).orThrow();
        expect(captured.status === "succeeded", `status is ${captured.status}`);
        expect(
          captured.captured.amount === amount.amount,
          `captured ${String(captured.captured.amount)}`,
        );
      },
    ],
    authorize !== undefined && [
      "refunds part of a payment and refuses more than is left",
      async () => {
        const payment = await authorized();
        await provider.capture(payment.id).orThrow();
        const part = half(amount);
        const refund = await provider
          .refund(payment.id, { amount: part })
          .orThrow();
        expect(
          refund.paymentId === payment.id,
          "the refund names another payment",
        );
        expect(
          refund.amount.amount === part.amount,
          `refunded ${String(refund.amount.amount)}`,
        );
        expect(
          refund.status === "succeeded" || refund.status === "pending",
          `refund status is ${refund.status}`,
        );
        const tooMuch = await provider.refund(payment.id, { amount });
        expect(
          kindOf(tooMuch) === "invalid_input",
          `refunding more than is left gave ${kindOf(tooMuch)}`,
        );
      },
    ],
    provider.cancel !== undefined && [
      "cancels a payment that was not captured",
      async () => {
        const created = await provider
          .createPayment({ amount, reference: reference(), capture: "manual" })
          .orThrow();
        const canceled = await provider.cancel?.(created.id).orThrow();
        expect(
          canceled?.status === "canceled",
          `status is ${String(canceled?.status)}`,
        );
      },
    ],
    webhook !== undefined && [
      "parses a signed webhook and refuses a tampered one",
      async () => {
        const payment = await provider
          .createPayment({ amount, reference: reference() })
          .orThrow();
        const { valid, tampered } = await webhook(payment);
        const events = await provider.parseWebhook(valid).orThrow();
        expect(events.length > 0, "a signed delivery gave no events");
        for (const event of events) {
          expect(event.id.length > 0, "an event has no id");
          expect(
            event.paymentId === payment.id,
            `an event names payment ${event.paymentId}`,
          );
        }
        const refused = await provider.parseWebhook(tampered);
        expect(
          kindOf(refused) === "unauthorized",
          `a tampered delivery gave ${kindOf(refused)}`,
        );
      },
    ],
  ]);
}
