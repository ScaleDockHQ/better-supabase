import { Stripe } from "stripe";
import { describe, expect, expectTypeOf, it } from "vitest";

import type {
  Payment,
  PaymentProvider,
  StripePaymentIntent,
  StripePaymentsClient,
  StripeRefund,
} from "../../src/commerce/index.ts";

import { signStripeWebhook } from "../../src/blocks/webhooks/verify.ts";
import {
  fromStripeAmount,
  money,
  paymentProviderOf,
  stripePaymentEvents,
  stripePayments,
  toStripeAmount,
} from "../../src/commerce/index.ts";
import { stripeError } from "../../src/commerce/stripe-shared.ts";
import {
  ConformanceError,
  testPaymentProvider,
} from "../../src/testing/index.ts";

const SECRET = "whsec_conformance";

type Intent = {
  -readonly [K in keyof StripePaymentIntent]: StripePaymentIntent[K];
} & { capture_method: string; refunded: number };

const missing = (id: string) =>
  new Stripe.errors.StripeInvalidRequestError({
    message: `No such payment_intent: '${id}'`,
    code: "resource_missing",
    statusCode: 404,
  });

const invalid = (message: string) =>
  new Stripe.errors.StripeInvalidRequestError({ message, statusCode: 400 });

/** PaymentIntents and refunds in memory, as far as `stripePayments` uses them. */
function fakeStripe() {
  const intents = new Map<string, Intent>();
  const keys = new Map<string, unknown>();
  const calls: { method: string; params: unknown }[] = [];
  let next = 0;

  const view = (intent: Intent): StripePaymentIntent => ({
    ...intent,
    latest_charge: { amount_refunded: intent.refunded },
  });

  const find = (id: string): Intent => {
    const intent = intents.get(id);

    if (!intent) {
      throw missing(id);
    }

    return intent;
  };

  const once = <T>(
    options: { readonly idempotencyKey?: string } | undefined,
    work: () => T,
  ): T => {
    const key = options?.idempotencyKey;

    if (key !== undefined && keys.has(key)) {
      return keys.get(key) as T;
    }

    const result = work();

    if (key !== undefined) {
      keys.set(key, result);
    }

    return result;
  };

  const client: StripePaymentsClient = {
    paymentIntents: {
      create: async (params, options) =>
        once(options, () => {
          calls.push({ method: "create", params });
          const id = `pi_${(next += 1)}`;

          const intent: Intent = {
            id,
            status: "requires_payment_method",
            amount: params.amount,
            amount_received: 0,
            currency: params.currency,
            client_secret: `${id}_secret`,
            metadata: params["metadata"] as Record<string, string>,
            capture_method: String(params["capture_method"]),
            refunded: 0,
          };

          intents.set(id, intent);

          return view(intent);
        }),
      retrieve: async (id) => view(find(id)),
      capture: async (id, params = {}, options) =>
        once(options, () => {
          calls.push({ method: "capture", params });
          const intent = find(id);

          if (intent.status !== "requires_capture") {
            throw invalid("This PaymentIntent could not be captured");
          }

          intent.status = "succeeded";
          intent.amount_received = Number(
            params["amount_to_capture"] ?? intent.amount,
          );

          return view(intent);
        }),
      cancel: async (id) => {
        const intent = find(id);
        intent.status = "canceled";

        return view(intent);
      },
    },
    refunds: {
      create: async (params, options) =>
        once(options, () => {
          calls.push({ method: "refund", params });
          const intent = find(String(params["payment_intent"]));
          const left = (intent.amount_received ?? 0) - intent.refunded;
          const amount = Number(params["amount"] ?? left);

          if (amount > left) {
            throw invalid("Refund amount is greater than unrefunded amount");
          }

          intent.refunded += amount;

          const refund: StripeRefund = {
            id: `re_${(next += 1)}`,
            amount,
            currency: intent.currency,
            status: "succeeded",
            payment_intent: intent.id,
          };

          return refund;
        }),
    },
  };

  const authorize = (payment: Payment): void => {
    const intent = find(payment.id);

    if (intent.capture_method === "manual") {
      intent.status = "requires_capture";
    } else {
      intent.status = "succeeded";
      intent.amount_received = intent.amount;
    }
  };

  return { client, intents, calls, authorize };
}

const event = (type: string, object: Record<string, unknown>) =>
  JSON.stringify({
    id: `evt_${crypto.randomUUID()}`,
    type,
    created: 1_790_000_000,
    data: { object },
  });

const delivery = async (body: string, secret = SECRET) => ({
  headers: { "stripe-signature": await signStripeWebhook(secret, body) },
  body,
});

const setup = () => {
  const fake = fakeStripe();

  const provider = stripePayments({
    stripe: fake.client,
    webhookSecret: SECRET,
  });

  return { ...fake, provider };
};

describe("stripePayments", () => {
  it("passes the PaymentProvider conformance kit", async () => {
    const { provider, authorize, intents } = setup();

    const report = await testPaymentProvider(provider, {
      authorize,
      webhook: async (payment) => {
        const intent = intents.get(payment.id);
        const body = event("payment_intent.succeeded", { ...intent });

        return {
          valid: await delivery(body),
          tampered: {
            ...(await delivery(body)),
            body: body.replace("pi_", "pi_x"),
          },
        };
      },
    });

    expect(report.subject).toBe('PaymentProvider "stripe"');
    expect(report.checks).toHaveLength(10);
  });

  it("runs the kit on a currency Stripe counts differently", async () => {
    const { provider, authorize } = setup();
    await testPaymentProvider(provider, {
      amount: money(5000n, "KWD"),
      authorize,
    });
  });

  it("creates a PaymentIntent with the reference, capture method and Stripe units", async () => {
    const { provider, calls } = setup();

    const payment = await provider
      .createPayment(
        {
          amount: money(1000n, "ISK"),
          reference: "order-1",
          capture: "manual",
          customer: "cus_1",
          description: "Order 1",
          metadata: { channel: "web" },
        },
        { idempotencyKey: "k1" },
      )
      .orThrow();

    expect(calls[0]?.params).toEqual({
      automatic_payment_methods: { enabled: true },
      amount: 100_000,
      currency: "isk",
      capture_method: "manual",
      metadata: { channel: "web", better_supabase_reference: "order-1" },
      customer: "cus_1",
      description: "Order 1",
      expand: ["latest_charge"],
    });
    expect(payment).toMatchObject({
      provider: "stripe",
      status: "requires_action",
      amount: money(1000n, "ISK"),
      reference: "order-1",
      clientSecret: `${payment.id}_secret`,
      metadata: { channel: "web" },
    });
  });

  it("refuses a PaymentIntent whose ISK amounts have a fraction of a krona", async () => {
    const { provider, intents } = setup();

    const payment = await provider
      .createPayment({ amount: money(1000n, "ISK"), reference: "r" })
      .orThrow();

    const intent = intents.get(payment.id)!;

    for (const change of [
      { amount: 100_050 },
      { amount_received: 50 },
      { refunded: 50 },
    ]) {
      intents.set(payment.id, { ...intent, ...change });

      const result = await provider.get!(payment.id);

      expect(result.ok ? undefined : result.error.hint).toBe(
        "STRIPE_AMOUNT_PRECISION",
      );
    }
  });

  it("passes extra PaymentIntent parameters instead of the default", async () => {
    const fake = fakeStripe();

    const provider = stripePayments({
      stripe: fake.client,
      webhookSecret: SECRET,
      name: "stripe-eu",
      paymentIntent: { payment_method_types: ["ideal"] },
    });

    const payment = await provider
      .createPayment({ amount: money(500n, "EUR"), reference: "r" })
      .orThrow();

    expect(payment.provider).toBe("stripe-eu");
    expect(fake.calls[0]?.params).toMatchObject({
      payment_method_types: ["ideal"],
      capture_method: "automatic",
    });
    expect(fake.calls[0]?.params).not.toHaveProperty(
      "automatic_payment_methods",
    );
  });

  it("refuses an amount Stripe can't charge exactly", async () => {
    const { provider } = setup();

    const kwd = await provider.createPayment({
      amount: money(1005n, "KWD"),
      reference: "r",
    });

    expect(kwd.ok ? undefined : kwd.error.hint).toBe("STRIPE_AMOUNT_PRECISION");

    const mga = await provider.createPayment({
      amount: money(150n, "MGA"),
      reference: "r",
    });

    expect(mga.ok ? undefined : mga.error.hint).toBe("STRIPE_AMOUNT_PRECISION");
  });

  it("captures part of a payment and refuses another currency", async () => {
    const { provider, authorize } = setup();

    const payment = await provider
      .createPayment({
        amount: money(1000n, "EUR"),
        reference: "r",
        capture: "manual",
      })
      .orThrow();

    authorize(payment);

    const other = await provider.capture(payment.id, {
      amount: money(500n, "USD"),
    });

    expect(other.ok ? undefined : other.error.hint).toBe(
      "PAYMENT_CURRENCY_MISMATCH",
    );

    const zero = await provider.capture(payment.id, {
      amount: money(0n, "EUR"),
    });

    expect(zero.ok ? undefined : zero.error.hint).toBe(
      "PAYMENT_AMOUNT_INVALID",
    );

    const captured = await provider
      .capture(payment.id, { amount: money(600n, "EUR") })
      .orThrow();

    expect(captured.captured).toEqual(money(600n, "EUR"));

    const refund = await provider
      .refund(payment.id, { reason: "damaged" })
      .orThrow();

    expect(refund.amount).toEqual(money(600n, "EUR"));
    const read = await provider.get?.(payment.id).orThrow();
    expect(read?.refunded).toEqual(money(600n, "EUR"));
  });

  it("reports a redirect and maps every PaymentIntent status", async () => {
    const { provider, intents } = setup();

    const payment = await provider
      .createPayment({ amount: money(100n, "EUR"), reference: "r" })
      .orThrow();

    const intent = intents.get(payment.id)!;
    intent.next_action = { redirect_to_url: { url: "https://bank.test/pay" } };

    const statuses: Record<string, string> = {
      requires_confirmation: "requires_action",
      requires_action: "requires_action",
      processing: "processing",
      requires_capture: "authorized",
      succeeded: "succeeded",
      canceled: "canceled",
      something_new: "failed",
    };

    for (const [stripe, ours] of Object.entries(statuses)) {
      intent.status = stripe;
      const read = await provider.get?.(payment.id).orThrow();
      expect(read?.status).toBe(ours);
      expect(read?.redirectUrl).toBe("https://bank.test/pay");
    }
  });

  it("loads the client lazily from a factory", async () => {
    const fake = fakeStripe();
    let made = 0;

    const provider = stripePayments({
      stripe: () => {
        made += 1;

        return fake.client;
      },
      webhookSecret: [SECRET],
      tolerance: 60,
    });

    expect(made).toBe(0);
    await provider.createPayment({ amount: money(1n, "EUR"), reference: "r" });
    expect(made).toBe(1);
  });

  it("checks its apiVersion", () => {
    const { provider } = setup();
    expect(paymentProviderOf(provider)).toBe(provider);
    const old = { ...provider, apiVersion: 0 } as unknown as PaymentProvider;
    expect(() => paymentProviderOf(old)).toThrow(/payment provider API 0/);
  });
});

describe("stripePayments webhooks", () => {
  const intent = {
    id: "pi_1",
    amount: 1000,
    amount_received: 1000,
    currency: "eur",
    metadata: { better_supabase_reference: "order-1" },
  };

  it("maps PaymentIntent events with the reference and amount", async () => {
    const { provider } = setup();

    const events = await provider
      .parseWebhook(await delivery(event("payment_intent.succeeded", intent)))
      .orThrow();

    expect(events).toEqual([
      expect.objectContaining({
        type: "payment.succeeded",
        paymentId: "pi_1",
        reference: "order-1",
        amount: money(1000n, "EUR"),
      }),
    ]);
    expect(events[0]?.occurredAt.epochMilliseconds).toBe(1_790_000_000_000);

    for (const [stripe, ours] of [
      ["payment_intent.amount_capturable_updated", "payment.authorized"],
      ["payment_intent.payment_failed", "payment.failed"],
      ["payment_intent.canceled", "payment.canceled"],
      ["payment_intent.processing", "payment.processing"],
      ["payment_intent.requires_action", "payment.requires_action"],
    ] as const) {
      expect(stripePaymentEvents(JSON.parse(event(stripe, intent)))).toEqual([
        expect.objectContaining({ type: ours, paymentId: "pi_1" }),
      ]);
    }
  });

  it("maps refunds that succeeded or failed, and nothing else", () => {
    const refund = {
      id: "re_1",
      amount: 300,
      currency: "eur",
      payment_intent: "pi_1",
    };

    expect(
      stripePaymentEvents(
        JSON.parse(event("refund.updated", { ...refund, status: "succeeded" })),
      ),
    ).toEqual([
      expect.objectContaining({
        type: "refund.succeeded",
        paymentId: "pi_1",
        refundId: "re_1",
        amount: money(300n, "EUR"),
      }),
    ]);
    expect(
      stripePaymentEvents(
        JSON.parse(
          event("refund.failed", {
            ...refund,
            payment_intent: { id: "pi_1" },
            status: "failed",
          }),
        ),
      ),
    ).toEqual([expect.objectContaining({ type: "refund.failed" })]);
    expect(
      stripePaymentEvents(
        JSON.parse(event("refund.created", { ...refund, status: "pending" })),
      ),
    ).toEqual([]);
    expect(
      stripePaymentEvents(JSON.parse(event("customer.created", { id: "c" }))),
    ).toEqual([]);
    expect(
      stripePaymentEvents(JSON.parse(event("payment_intent.succeeded", {}))),
    ).toEqual([]);
    expect(stripePaymentEvents({ type: "payment_intent.succeeded" })).toEqual(
      [],
    );
    expect(stripePaymentEvents(null)).toEqual([]);
  });

  it("refuses a delivery signed with another secret", async () => {
    const { provider } = setup();

    const result = await provider.parseWebhook(
      await delivery(event("payment_intent.succeeded", intent), "whsec_other"),
    );

    expect(result.ok ? undefined : result.error.kind).toBe("unauthorized");
  });
});

describe("Stripe errors", () => {
  it("map to DbError kinds", () => {
    const raw = { message: "m" };
    expect(stripeError(new Stripe.errors.StripeCardError(raw))).toMatchObject({
      kind: "raised",
      hint: "PAYMENT_DECLINED",
    });
    expect(stripeError(missing("pi_1")).kind).toBe("not_found");
    expect(
      stripeError(new Stripe.errors.StripeIdempotencyError(raw)).kind,
    ).toBe("conflict");
    expect(stripeError(new Stripe.errors.StripeRateLimitError(raw)).kind).toBe(
      "rate_limited",
    );
    expect(
      stripeError(new Stripe.errors.StripeAuthenticationError(raw)).kind,
    ).toBe("unauthorized");
    expect(stripeError(new Stripe.errors.StripePermissionError(raw)).kind).toBe(
      "forbidden",
    );
    expect(stripeError(invalid("bad")).kind).toBe("invalid_input");
    expect(stripeError(new Stripe.errors.StripeConnectionError(raw)).kind).toBe(
      "network",
    );
    expect(stripeError(new Stripe.errors.StripeAPIError(raw)).kind).toBe(
      "unexpected",
    );
    expect(stripeError({ statusCode: 429, message: "slow" })).toMatchObject({
      kind: "rate_limited",
      message: "slow",
    });
    expect(stripeError("boom").kind).toBe("unexpected");
  });

  it("come back as results from the adapter", async () => {
    const fake = fakeStripe();
    fake.client.paymentIntents.create = async () => {
      throw new Stripe.errors.StripeCardError({
        message: "Your card was declined.",
        code: "card_declined",
      });
    };

    const provider = stripePayments({
      stripe: fake.client,
      webhookSecret: SECRET,
    });

    const result = await provider.createPayment({
      amount: money(100n, "EUR"),
      reference: "r",
    });

    expect(result.ok ? undefined : result.error).toMatchObject({
      kind: "raised",
      hint: "PAYMENT_DECLINED",
    });
  });
});

describe("Stripe amounts", () => {
  it("follow Stripe's decimals where they differ from ISO 4217", () => {
    expect(toStripeAmount(money(1999n, "EUR"))).toMatchObject({
      ok: true,
      data: 1999,
    });
    expect(toStripeAmount(money(500n, "JPY"))).toMatchObject({
      ok: true,
      data: 500,
    });
    expect(toStripeAmount(money(500n, "ISK"))).toMatchObject({
      ok: true,
      data: 50_000,
    });
    expect(toStripeAmount(money(500n, "UGX"))).toMatchObject({
      ok: true,
      data: 50_000,
    });
    expect(toStripeAmount(money(500n, "MGA"))).toMatchObject({
      ok: true,
      data: 5,
    });
    expect(toStripeAmount(money(1230n, "KWD"))).toMatchObject({
      ok: true,
      data: 1230,
    });
    expect(toStripeAmount(money(1231n, "IQD")).ok).toBe(true);
    expect(toStripeAmount(money(2n ** 60n, "EUR")).ok).toBe(false);
    expect(fromStripeAmount(50_000, "isk")).toMatchObject({
      ok: true,
      data: money(500n, "ISK"),
    });
    expect(fromStripeAmount(5, "mga")).toMatchObject({
      ok: true,
      data: money(500n, "MGA"),
    });
    expect(fromStripeAmount(1999, "eur")).toMatchObject({
      ok: true,
      data: money(1999n, "EUR"),
    });
  });

  it("refuses a Stripe amount that would lose a fraction of a minor unit", () => {
    for (const [amount, currency] of [
      [50_050, "isk"],
      [199, "ugx"],
      [19.5, "eur"],
    ] as const) {
      expect(fromStripeAmount(amount, currency)).toMatchObject({
        ok: false,
        error: { kind: "invalid_input", hint: "STRIPE_AMOUNT_PRECISION" },
      });
    }
  });
});

describe("StripePaymentsClient", () => {
  it("is satisfied by the Stripe SDK", () => {
    expectTypeOf<Stripe>().toExtend<StripePaymentsClient>();
  });
});

describe("testPaymentProvider", () => {
  it("fails a provider that loses the reference", async () => {
    const { provider } = setup();

    const lossy: PaymentProvider = {
      ...provider,
      createPayment: (input, options) =>
        provider
          .createPayment(input, options)
          .map((payment) => ({ ...payment, reference: "" })),
    };

    await expect(testPaymentProvider(lossy)).rejects.toThrow(ConformanceError);
  });
});
