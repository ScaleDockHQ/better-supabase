import { describe, expect, it, vi } from "vitest";

import type {
  Payment,
  PaymentEvent,
  PaymentProvider,
} from "../../../src/commerce/payments.ts";

import {
  createDonations,
  donationFundInputSchema,
  donationsBlock,
  donationsEvents,
  giftInputSchema,
  givingSection,
  pledgeInputSchema,
} from "../../../src/blocks/donations/index.ts";
import { money } from "../../../src/commerce/money.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult } from "../../../src/core/result.ts";

const AT = "2026-10-22T10:00:00Z";
const DONOR = { type: "contact", id: "d1" };
const GIFT_ID = "00000000-0000-4000-8000-0000000000a1";
const FUND_ID = "00000000-0000-4000-8000-0000000000f1";
const PLEDGE_ID = "00000000-0000-4000-8000-0000000000b1";

const GIFT = {
  id: GIFT_ID,
  organizationId: "org-1",
  donorType: "contact",
  donorId: "d1",
  fundId: FUND_ID,
  pledgeId: PLEDGE_ID,
  periodStart: "2026-10-01",
  amount: "2500",
  currency: "EUR",
  receivedOn: "2026-10-22",
  method: "card",
  status: "posted",
  provider: "fake",
  paymentReference: "pi_1",
  transactionId: "t1",
  refundTransactionId: "t2",
  receiptId: "r1",
  note: "Thanks",
  createdBy: "u1",
  createdAt: AT,
  updatedAt: AT,
};

const BARE_GIFT = {
  ...GIFT,
  fundId: null,
  pledgeId: null,
  periodStart: null,
  method: null,
  status: "pending",
  provider: null,
  paymentReference: null,
  transactionId: null,
  refundTransactionId: null,
  receiptId: null,
  note: null,
  createdBy: null,
};

const FUND = {
  id: FUND_ID,
  organizationId: "org-1",
  key: "roof",
  name: "Roof appeal",
  kind: "campaign",
  goal: "1000000",
  raised: "2500",
  currency: "EUR",
  startsOn: "2026-10-01",
  endsOn: "2026-12-31",
  archivedAt: AT,
  createdAt: AT,
  updatedAt: AT,
};

const PLEDGE = {
  id: PLEDGE_ID,
  organizationId: "org-1",
  donorType: "contact",
  donorId: "d1",
  fundId: FUND_ID,
  amount: "2500",
  currency: "EUR",
  frequency: "monthly",
  startsOn: "2026-10-01",
  endsOn: "2027-09-30",
  status: "active",
  provider: "fake",
  providerCustomer: "cus_1",
  note: "Monthly",
  createdBy: "u1",
  createdAt: AT,
  updatedAt: AT,
};

const INSTALLMENT = {
  pledgeId: PLEDGE_ID,
  periodStart: "2026-10-01",
  donorType: "contact",
  donorId: "d1",
  fundId: FUND_ID,
  amount: "2500",
  currency: "EUR",
  provider: "fake",
  providerCustomer: "cus_1",
};

const RECEIPT = {
  id: "r1",
  organizationId: "org-1",
  donorType: "contact",
  donorId: "d1",
  sequence: "7",
  number: "R-7",
  kind: "gift",
  year: 2026,
  amount: "2500",
  currency: "EUR",
  issuedAt: AT,
  voidedAt: null,
  voidReason: null,
};

type Handler = (args: Record<string, unknown>) => unknown;

const raise = (hint: string) => () => {
  throw Object.assign(new Error(hint), { code: "P0001", hint });
};

function router(handlers: Record<string, Handler>) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    transport: {
      call(
        _schema: string,
        fn: string,
        args: Readonly<Record<string, unknown>>,
      ) {
        calls.push([fn, { ...args }]);

        const handler = handlers[fn];

        if (!handler) {
          return Promise.reject(new Error(`no handler for ${fn}`));
        }

        try {
          return Promise.resolve(handler({ ...args }));
        } catch (error) {
          return Promise.reject(error);
        }
      },
    },
  };
}

const payment = (overrides: Partial<Payment> = {}): Payment => ({
  id: "pi_1",
  provider: "fake",
  status: "succeeded",
  amount: money(2500n, "EUR"),
  captured: money(2500n, "EUR"),
  refunded: money(0n, "EUR"),
  reference: GIFT_ID,
  metadata: {},
  ...overrides,
});

function fakePayments(overrides: Partial<PaymentProvider> = {}) {
  const createPayment = vi.fn<PaymentProvider["createPayment"]>(() =>
    AsyncResult.ok(payment()),
  );

  const provider: PaymentProvider = {
    apiVersion: 1,
    name: "fake",
    createPayment,
    capture: () => AsyncResult.ok(payment()),
    refund: () =>
      AsyncResult.ok({
        id: "re_1",
        paymentId: "pi_1",
        amount: money(2500n, "EUR"),
        status: "succeeded",
      }),
    parseWebhook: () => AsyncResult.ok([]),
    ...overrides,
  };

  return { provider, createPayment };
}

const event = (overrides: Partial<PaymentEvent> = {}): PaymentEvent => ({
  id: "evt_1",
  type: "payment.succeeded",
  paymentId: "pi_1",
  reference: GIFT_ID,
  occurredAt: Temporal.Instant.from(AT),
  ...overrides,
});

const validate = (
  schema: { "~standard": { validate: (value: unknown) => unknown } },
  value: unknown,
) => schema["~standard"].validate(value) as { issues?: unknown[] };

describe("createDonations", () => {
  it("saves, archives and lists funds", async () => {
    const plain = {
      ...FUND,
      kind: "fund",
      goal: null,
      raised: null,
      currency: null,
      startsOn: null,
      endsOn: null,
      archivedAt: null,
    };

    const { calls, transport } = router({
      save_donation_fund: () => FUND,
      archive_donation_fund: () => plain,
      list_donation_funds: () => [FUND, plain],
    });

    const donations = createDonations({ transport, tenant: "org-1" });

    const saved = await donations
      .saveFund({
        key: "roof",
        name: "Roof appeal",
        kind: "campaign",
        goal: money(1_000_000n, "EUR"),
        startsOn: Temporal.PlainDate.from("2026-10-01"),
        endsOn: Temporal.PlainDate.from("2026-12-31"),
      })
      .orThrow();

    await donations.saveFund({ key: "general", name: "General" }).orThrow();

    const archived = await donations.archiveFund(FUND_ID).orThrow();
    await donations.funds({ includeArchived: true }).orThrow();
    const listed = await donations.funds().orThrow();

    expect(saved).toMatchObject({
      kind: "campaign",
      goal: money(1_000_000n, "EUR"),
      raised: money(2500n, "EUR"),
    });
    expect(saved.endsOn?.toString()).toBe("2026-12-31");
    expect(saved.archivedAt?.toString()).toBe(AT);
    expect(archived).not.toHaveProperty("goal");
    expect(archived).not.toHaveProperty("startsOn");
    expect(listed).toHaveLength(2);
    expect(calls).toEqual([
      [
        "save_donation_fund",
        {
          tenant: "org-1",
          key: "roof",
          name: "Roof appeal",
          kind: "campaign",
          goal: "1000000",
          currency: "EUR",
          starts_on: "2026-10-01",
          ends_on: "2026-12-31",
        },
      ],
      [
        "save_donation_fund",
        {
          tenant: "org-1",
          key: "general",
          name: "General",
          kind: "fund",
          goal: null,
          currency: null,
          starts_on: null,
          ends_on: null,
        },
      ],
      ["archive_donation_fund", { fund_id: FUND_ID }],
      ["list_donation_funds", { tenant: "org-1", include_archived: true }],
      ["list_donation_funds", { tenant: "org-1", include_archived: false }],
    ]);
  });

  it("records gifts received outside the provider and reads them", async () => {
    const { calls, transport } = router({
      record_gift: () => GIFT,
      get_gift: () => BARE_GIFT,
      list_gifts: () => [GIFT],
    });

    const donations = createDonations({ transport, tenant: "org-1" });

    const recorded = await donations
      .recordGift({
        donor: DONOR,
        amount: money(2500n, "EUR"),
        fundId: FUND_ID,
        receivedOn: Temporal.PlainDate.from("2026-10-22"),
        method: "check",
        note: "Thanks",
        pledgeId: PLEDGE_ID,
        periodStart: Temporal.PlainDate.from("2026-10-01"),
      })
      .orThrow();

    await donations
      .recordGift({ donor: DONOR, amount: money(100n, "EUR") })
      .orThrow();

    const bare = await donations.getGift(GIFT_ID).orThrow();
    await donations
      .gifts({
        donor: DONOR,
        fundId: FUND_ID,
        pledgeId: PLEDGE_ID,
        status: "posted",
        pageSize: 5,
      })
      .orThrow();
    await donations.gifts().orThrow();

    expect(recorded).toMatchObject({
      donor: DONOR,
      amount: money(2500n, "EUR"),
      status: "posted",
      fundId: FUND_ID,
      pledgeId: PLEDGE_ID,
      method: "card",
      provider: "fake",
      paymentReference: "pi_1",
      transactionId: "t1",
      refundTransactionId: "t2",
      receiptId: "r1",
      note: "Thanks",
      createdBy: "u1",
    });
    expect(recorded.periodStart?.toString()).toBe("2026-10-01");
    expect(bare).not.toHaveProperty("fundId");
    expect(bare).not.toHaveProperty("transactionId");
    expect(calls).toEqual([
      [
        "record_gift",
        {
          tenant: "org-1",
          donor_type: "contact",
          donor_id: "d1",
          amount: "2500",
          currency: "EUR",
          fund_id: FUND_ID,
          received_on: "2026-10-22",
          method: "check",
          note: "Thanks",
          pledge_id: PLEDGE_ID,
          period_start: "2026-10-01",
        },
      ],
      [
        "record_gift",
        {
          tenant: "org-1",
          donor_type: "contact",
          donor_id: "d1",
          amount: "100",
          currency: "EUR",
          fund_id: null,
          received_on: null,
          method: null,
          note: null,
          pledge_id: null,
          period_start: null,
        },
      ],
      ["get_gift", { gift_id: GIFT_ID }],
      [
        "list_gifts",
        {
          tenant: "org-1",
          donor_type: "contact",
          donor_id: "d1",
          fund_id: FUND_ID,
          pledge_id: PLEDGE_ID,
          status: "posted",
          page_size: 5,
        },
      ],
      [
        "list_gifts",
        {
          tenant: "org-1",
          donor_type: null,
          donor_id: null,
          fund_id: null,
          pledge_id: null,
          status: null,
          page_size: null,
        },
      ],
    ]);
  });

  it("charges a gift through the provider and stores the payment on the service transport", async () => {
    const user = router({ open_gift: () => BARE_GIFT });
    const service = router({ record_gift_payment: () => GIFT });
    const { provider, createPayment } = fakePayments();

    const donations = createDonations({
      transport: user.transport,
      service: service.transport,
      tenant: "org-1",
      payments: provider,
    });

    const outcome = await donations
      .give({
        donor: DONOR,
        amount: money(2500n, "EUR"),
        fundId: FUND_ID,
        note: "Thanks",
        customer: "cus_1",
        description: "Roof appeal",
        returnUrl: "https://example.test/thanks",
      })
      .orThrow();

    await donations
      .give({ donor: DONOR, amount: money(2500n, "EUR") })
      .orThrow();

    expect(outcome.gift.status).toBe("posted");
    expect(outcome.payment.id).toBe("pi_1");
    expect(user.calls[0]).toEqual([
      "open_gift",
      {
        tenant: "org-1",
        donor_type: "contact",
        donor_id: "d1",
        amount: "2500",
        currency: "EUR",
        fund_id: FUND_ID,
        pledge_id: null,
        period_start: null,
        provider: "fake",
        note: "Thanks",
      },
    ]);
    expect(createPayment.mock.calls[0]).toEqual([
      {
        amount: money(2500n, "EUR"),
        reference: GIFT_ID,
        customer: "cus_1",
        description: "Roof appeal",
        returnUrl: "https://example.test/thanks",
        metadata: { giftId: GIFT_ID },
      },
      { idempotencyKey: `gift:${GIFT_ID}:payment` },
    ]);
    expect(createPayment.mock.calls[1]?.[0]).toEqual({
      amount: money(2500n, "EUR"),
      reference: GIFT_ID,
      description: "Donation",
      metadata: { giftId: GIFT_ID },
    });
    expect(service.calls[0]).toEqual([
      "record_gift_payment",
      {
        gift_id: GIFT_ID,
        provider: "fake",
        payment_id: "pi_1",
        status: "succeeded",
      },
    ]);
  });

  it("maps every payment status a charge returns", async () => {
    const statuses: [Payment["status"], string][] = [
      ["succeeded", "succeeded"],
      ["failed", "failed"],
      ["canceled", "failed"],
      ["requires_action", "pending"],
      ["processing", "pending"],
      ["authorized", "pending"],
    ];

    for (const [status, expected] of statuses) {
      const { calls, transport } = router({
        open_gift: () => BARE_GIFT,
        record_gift_payment: () => BARE_GIFT,
      });

      const donations = createDonations({
        transport,
        tenant: "org-1",
        payments: fakePayments({
          createPayment: () => AsyncResult.ok(payment({ status })),
        }).provider,
      });

      await donations
        .give({ donor: DONOR, amount: money(2500n, "EUR") })
        .orThrow();

      expect(calls[1]?.[1]["status"]).toBe(expected);
    }

    const { transport } = router({
      open_gift: () => BARE_GIFT,
      record_gift_payment: () => BARE_GIFT,
    });

    const odd = createDonations({
      transport,
      tenant: "org-1",
      payments: fakePayments({
        createPayment: () =>
          AsyncResult.ok(
            // SAFETY: a status outside the union, to reach the never branch.
            payment({ status: "lost" as Payment["status"] }),
          ),
      }).provider,
    });

    const lost = await odd.give({ donor: DONOR, amount: money(2500n, "EUR") });

    expect(lost.ok ? undefined : lost.error.message).toContain(
      "unknown payment status lost",
    );
  });

  it("passes errors from each step of give through", async () => {
    const noPayments = createDonations({
      transport: router({}).transport,
      tenant: "org-1",
    });

    const input = { donor: DONOR, amount: money(2500n, "EUR") };

    expect(
      await noPayments.give(input).then((r) => !r.ok && r.error.hint),
    ).toBe("DONATIONS_NO_PAYMENTS");

    const noTenant = createDonations({
      transport: router({}).transport,
      payments: fakePayments().provider,
    });

    expect((await noTenant.give(input)).ok).toBe(false);

    const refused = createDonations({
      transport: router({ open_gift: raise("DONATION_FUND_INVALID") })
        .transport,
      tenant: "org-1",
      payments: fakePayments().provider,
    });

    expect(await refused.give(input).then((r) => !r.ok && r.error.hint)).toBe(
      "DONATION_FUND_INVALID",
    );

    const declined = createDonations({
      transport: router({ open_gift: () => BARE_GIFT }).transport,
      tenant: "org-1",
      payments: fakePayments({
        createPayment: () =>
          AsyncResult.err(
            dbError("raised", "declined", { hint: "PAYMENT_DECLINED" }),
          ),
      }).provider,
    });

    expect(await declined.give(input).then((r) => !r.ok && r.error.hint)).toBe(
      "PAYMENT_DECLINED",
    );

    const unstored = createDonations({
      transport: router({
        open_gift: () => BARE_GIFT,
        record_gift_payment: raise("DONATION_STATE"),
      }).transport,
      tenant: "org-1",
      payments: fakePayments().provider,
    });

    expect(await unstored.give(input).then((r) => !r.ok && r.error.hint)).toBe(
      "DONATION_STATE",
    );
  });

  it("creates, updates and lists pledges", async () => {
    const bare = {
      ...PLEDGE,
      fundId: null,
      endsOn: null,
      provider: null,
      providerCustomer: null,
      note: null,
      createdBy: null,
    };

    const { calls, transport } = router({
      create_pledge: () => PLEDGE,
      update_pledge: () => bare,
      list_pledges: () => [PLEDGE],
    });

    const donations = createDonations({ transport, tenant: "org-1" });

    const created = await donations
      .createPledge({
        donor: DONOR,
        amount: money(2500n, "EUR"),
        frequency: "monthly",
        fundId: FUND_ID,
        startsOn: Temporal.PlainDate.from("2026-10-01"),
        endsOn: Temporal.PlainDate.from("2027-09-30"),
        provider: "fake",
        providerCustomer: "cus_1",
        note: "Monthly",
      })
      .orThrow();

    await donations
      .createPledge({ donor: DONOR, amount: money(2500n, "EUR") })
      .orThrow();

    const updated = await donations
      .updatePledge(PLEDGE_ID, {
        status: "paused",
        endsOn: Temporal.PlainDate.from("2027-03-31"),
        amount: money(3000n, "EUR"),
      })
      .orThrow();

    await donations.updatePledge(PLEDGE_ID, {}).orThrow();
    await donations
      .pledges({ donor: DONOR, status: "active", pageSize: 5 })
      .orThrow();
    await donations.pledges().orThrow();

    expect(created).toMatchObject({
      frequency: "monthly",
      provider: "fake",
      providerCustomer: "cus_1",
      note: "Monthly",
      createdBy: "u1",
      fundId: FUND_ID,
    });
    expect(created.endsOn?.toString()).toBe("2027-09-30");
    expect(updated).not.toHaveProperty("provider");
    expect(updated).not.toHaveProperty("endsOn");
    expect(calls).toEqual([
      [
        "create_pledge",
        {
          tenant: "org-1",
          donor_type: "contact",
          donor_id: "d1",
          amount: "2500",
          currency: "EUR",
          frequency: "monthly",
          fund_id: FUND_ID,
          starts_on: "2026-10-01",
          ends_on: "2027-09-30",
          provider: "fake",
          provider_customer: "cus_1",
          note: "Monthly",
        },
      ],
      [
        "create_pledge",
        {
          tenant: "org-1",
          donor_type: "contact",
          donor_id: "d1",
          amount: "2500",
          currency: "EUR",
          frequency: "monthly",
          fund_id: null,
          starts_on: null,
          ends_on: null,
          provider: null,
          provider_customer: null,
          note: null,
        },
      ],
      [
        "update_pledge",
        {
          pledge_id: PLEDGE_ID,
          status: "paused",
          ends_on: "2027-03-31",
          amount: "3000",
        },
      ],
      [
        "update_pledge",
        { pledge_id: PLEDGE_ID, status: null, ends_on: null, amount: null },
      ],
      [
        "list_pledges",
        {
          tenant: "org-1",
          donor_type: "contact",
          donor_id: "d1",
          status: "active",
          page_size: 5,
        },
      ],
      [
        "list_pledges",
        {
          tenant: "org-1",
          donor_type: null,
          donor_id: null,
          status: null,
          page_size: null,
        },
      ],
    ]);
  });

  it("lists due installments", async () => {
    const { calls, transport } = router({
      due_pledge_installments: () => [
        INSTALLMENT,
        {
          ...INSTALLMENT,
          fundId: null,
          provider: null,
          providerCustomer: null,
        },
      ],
    });

    const donations = createDonations({ transport, tenant: "org-1" });

    const [charged, byHand] = await donations
      .dueInstallments({
        through: Temporal.PlainDate.from("2026-10-31"),
        maxRows: 10,
      })
      .orThrow();

    await donations.dueInstallments().orThrow();

    expect(charged).toMatchObject({
      pledgeId: PLEDGE_ID,
      donor: DONOR,
      fundId: FUND_ID,
      provider: "fake",
      providerCustomer: "cus_1",
      amount: money(2500n, "EUR"),
    });
    expect(byHand).not.toHaveProperty("provider");
    expect(calls).toEqual([
      [
        "due_pledge_installments",
        { tenant: "org-1", through: "2026-10-31", max_rows: 10 },
      ],
      [
        "due_pledge_installments",
        { tenant: "org-1", through: null, max_rows: null },
      ],
    ]);
  });

  it("charges due pledges once per period and skips the ones it doesn't charge", async () => {
    const other = { ...INSTALLMENT, provider: "other" };

    const byHand = { ...INSTALLMENT, provider: null, providerCustomer: null };

    const noCustomer = {
      ...INSTALLMENT,
      periodStart: "2026-11-01",
      providerCustomer: null,
    };

    const { calls, transport } = router({
      due_pledge_installments: () => [INSTALLMENT, other, byHand, noCustomer],
      open_gift: () => BARE_GIFT,
      record_gift_payment: () => GIFT,
    });

    const { provider, createPayment } = fakePayments();

    const donations = createDonations({
      transport,
      tenant: "org-1",
      payments: provider,
    });

    const outcomes = await donations.chargeDuePledges().orThrow();

    expect(outcomes.map((outcome) => outcome.kind)).toEqual([
      "charged",
      "skipped",
      "skipped",
      "charged",
    ]);
    expect(
      outcomes.flatMap((outcome) =>
        outcome.kind === "skipped" ? [outcome.reason] : [],
      ),
    ).toEqual([
      "the pledge is charged by other",
      "the pledge is recorded by hand",
    ]);
    expect(createPayment.mock.calls[0]).toEqual([
      {
        amount: money(2500n, "EUR"),
        reference: GIFT_ID,
        customer: "cus_1",
        description: "Pledge installment from 2026-10-01",
        metadata: {
          giftId: GIFT_ID,
          pledgeId: PLEDGE_ID,
          periodStart: "2026-10-01",
        },
      },
      { idempotencyKey: `pledge:${PLEDGE_ID}:2026-10-01` },
    ]);
    expect(createPayment.mock.calls[1]?.[0]).not.toHaveProperty("customer");
    expect(calls[1]).toEqual([
      "open_gift",
      {
        tenant: "org-1",
        donor_type: "contact",
        donor_id: "d1",
        amount: "2500",
        currency: "EUR",
        fund_id: FUND_ID,
        pledge_id: PLEDGE_ID,
        period_start: "2026-10-01",
        provider: "fake",
        note: null,
      },
    ]);
  });

  it("marks a declined installment failed and leaves other errors pending", async () => {
    const declinedError = dbError("raised", "declined", {
      hint: "PAYMENT_DECLINED",
    });

    const run = async (
      handlers: Record<string, Handler>,
      createPayment: PaymentProvider["createPayment"],
    ) => {
      const route = router({
        due_pledge_installments: () => [{ ...INSTALLMENT, fundId: null }],
        ...handlers,
      });

      const donations = createDonations({
        transport: route.transport,
        tenant: "org-1",
        payments: fakePayments({ createPayment }).provider,
      });

      return {
        calls: route.calls,
        outcomes: await donations.chargeDuePledges().orThrow(),
      };
    };

    const declined = await run(
      { open_gift: () => BARE_GIFT, record_gift_payment: () => BARE_GIFT },
      () => AsyncResult.err(declinedError),
    );

    expect(declined.outcomes[0]).toMatchObject({
      kind: "failed",
      error: { hint: "PAYMENT_DECLINED" },
    });
    expect(declined.calls.at(-1)).toEqual([
      "record_gift_payment",
      {
        gift_id: GIFT_ID,
        provider: "fake",
        payment_id: null,
        status: "failed",
      },
    ]);

    const unrecorded = await run(
      {
        open_gift: () => BARE_GIFT,
        record_gift_payment: raise("DONATION_STATE"),
      },
      () => AsyncResult.err(declinedError),
    );

    expect(unrecorded.outcomes[0]).toMatchObject({
      kind: "failed",
      error: { hint: "DONATION_STATE" },
    });

    const transient = await run({ open_gift: () => BARE_GIFT }, () =>
      AsyncResult.err(dbError("network", "timeout")),
    );

    expect(transient.outcomes[0]?.kind).toBe("failed");
    expect(transient.calls.map(([fn]) => fn)).toEqual([
      "due_pledge_installments",
      "open_gift",
    ]);

    const unopened = await run(
      { open_gift: raise("DONATION_PLEDGE_INVALID") },
      () => AsyncResult.ok(payment()),
    );

    expect(unopened.outcomes[0]).toMatchObject({
      kind: "failed",
      error: { hint: "DONATION_PLEDGE_INVALID" },
    });

    const unstored = await run(
      {
        open_gift: () => BARE_GIFT,
        record_gift_payment: raise("DONATION_STATE"),
      },
      () => AsyncResult.ok(payment()),
    );

    expect(unstored.outcomes[0]).toMatchObject({
      kind: "failed",
      error: { hint: "DONATION_STATE" },
    });
  });

  it("refuses to charge pledges without a provider, a tenant or due installments", async () => {
    const noPayments = createDonations({
      transport: router({}).transport,
      tenant: "org-1",
    });

    expect(
      await noPayments.chargeDuePledges().then((r) => !r.ok && r.error.hint),
    ).toBe("DONATIONS_NO_PAYMENTS");

    const noTenant = createDonations({
      transport: router({}).transport,
      payments: fakePayments().provider,
    });

    expect((await noTenant.chargeDuePledges()).ok).toBe(false);

    const failing = createDonations({
      transport: router({ due_pledge_installments: raise("DONATIONS_DENIED") })
        .transport,
      tenant: "org-1",
      payments: fakePayments().provider,
    });

    expect(
      await failing.chargeDuePledges().then((r) => !r.ok && r.error.hint),
    ).toBe("DONATIONS_DENIED");
  });

  it("applies provider events to their gifts", async () => {
    const { calls, transport } = router({
      record_gift_payment: (args) => {
        if (args["payment_id"] === "pi_unknown") {
          throw Object.assign(new Error("not found"), {
            code: "P0001",
            hint: "DONATION_NOT_FOUND",
          });
        }

        if (args["payment_id"] === "pi_broken") {
          throw Object.assign(new Error("state"), {
            code: "P0001",
            hint: "DONATION_STATE",
          });
        }

        return GIFT;
      },
    });

    const donations = createDonations({
      transport,
      tenant: "org-1",
      payments: fakePayments().provider,
    });

    const { reference, ...canceled } = event({ type: "payment.canceled" });

    expect(reference).toBe(GIFT_ID);

    const outcomes = await Promise.all([
      donations.handlePaymentEvent(event()).orThrow(),
      donations
        .handlePaymentEvent(event({ type: "payment.failed", reference: "o1" }))
        .orThrow(),
      donations.handlePaymentEvent(canceled).orThrow(),
      donations
        .handlePaymentEvent(event({ type: "payment.processing" }))
        .orThrow(),
      donations
        .handlePaymentEvent(event({ type: "refund.succeeded" }))
        .orThrow(),
      donations.handlePaymentEvent(event({ type: "refund.failed" })).orThrow(),
      donations
        .handlePaymentEvent(event({ paymentId: "pi_unknown" }))
        .orThrow(),
    ]);

    expect(outcomes.map((outcome) => outcome.kind)).toEqual([
      "gift",
      "gift",
      "gift",
      "gift",
      "gift",
      "ignored",
      "ignored",
    ]);
    expect(calls.map(([, args]) => [args["gift_id"], args["status"]])).toEqual([
      [GIFT_ID, "succeeded"],
      [null, "failed"],
      [null, "failed"],
      [GIFT_ID, "pending"],
      [null, "refunded"],
      [GIFT_ID, "succeeded"],
    ]);

    expect(
      await donations
        .handlePaymentEvent(event({ paymentId: "pi_broken" }))
        .then((r) => !r.ok && r.error.hint),
    ).toBe("DONATION_STATE");

    const anonymous = createDonations({ transport });
    await anonymous.handlePaymentEvent(event()).orThrow();

    expect(calls.at(-1)?.[1]["provider"]).toBe("unknown");
  });

  it("verifies webhooks and applies their events in order", async () => {
    const { calls, transport } = router({
      record_gift_payment: (args) => {
        if (args["payment_id"] === "pi_broken") {
          throw Object.assign(new Error("state"), {
            code: "P0001",
            hint: "DONATION_STATE",
          });
        }

        return GIFT;
      },
    });

    const parsed = fakePayments({
      parseWebhook: () =>
        AsyncResult.ok([
          event(),
          event({ id: "evt_2", type: "refund.failed" }),
        ]),
    }).provider;

    const donations = createDonations({
      transport,
      tenant: "org-1",
      payments: parsed,
    });

    const input = { body: "{}", headers: new Headers() };

    const outcomes = await donations.webhook(input).orThrow();

    expect(outcomes.map((outcome) => outcome.event)).toEqual([
      "evt_1",
      "evt_2",
    ]);
    expect(calls).toHaveLength(1);

    const broken = createDonations({
      transport,
      payments: fakePayments({
        parseWebhook: () =>
          AsyncResult.ok([event({ paymentId: "pi_broken" }), event()]),
      }).provider,
    });

    expect(await broken.webhook(input).then((r) => !r.ok && r.error.hint)).toBe(
      "DONATION_STATE",
    );

    const unsigned = createDonations({
      transport,
      payments: fakePayments({
        parseWebhook: () =>
          AsyncResult.err(dbError("unauthorized", "bad signature")),
      }).provider,
    });

    expect((await unsigned.webhook(input)).ok).toBe(false);

    const noPayments = createDonations({ transport });

    expect(
      await noPayments.webhook(input).then((r) => !r.ok && r.error.hint),
    ).toBe("DONATIONS_NO_PAYMENTS");
  });

  it("issues, voids and lists receipts", async () => {
    const yearly = {
      ...RECEIPT,
      id: "r2",
      kind: "yearly",
      sequence: "8",
      number: "R-8",
      amount: "30000",
      voidedAt: AT,
      voidReason: "duplicate",
    };

    const { calls, transport } = router({
      issue_gift_receipt: () => RECEIPT,
      issue_yearly_receipt: () => yearly,
      void_donation_receipt: () => yearly,
      list_donation_receipts: () => [RECEIPT, yearly],
    });

    const donations = createDonations({ transport, tenant: "org-1" });

    const issued = await donations.issueGiftReceipt(GIFT_ID).orThrow();
    await donations.issueYearlyReceipt(DONOR, 2026, "EUR").orThrow();

    const voided = await donations.voidReceipt("r2", "duplicate").orThrow();
    await donations.voidReceipt("r2").orThrow();
    await donations
      .receipts({ donor: DONOR, year: 2026, pageSize: 5 })
      .orThrow();
    await donations.receipts().orThrow();

    expect(issued).toMatchObject({
      sequence: 7n,
      number: "R-7",
      kind: "gift",
      year: 2026,
      amount: money(2500n, "EUR"),
    });
    expect(issued).not.toHaveProperty("voidedAt");
    expect(voided.voidReason).toBe("duplicate");
    expect(voided.voidedAt?.toString()).toBe(AT);
    expect(calls).toEqual([
      ["issue_gift_receipt", { gift_id: GIFT_ID }],
      [
        "issue_yearly_receipt",
        {
          tenant: "org-1",
          donor_type: "contact",
          donor_id: "d1",
          year: 2026,
          currency: "EUR",
        },
      ],
      ["void_donation_receipt", { receipt_id: "r2", reason: "duplicate" }],
      ["void_donation_receipt", { receipt_id: "r2", reason: null }],
      [
        "list_donation_receipts",
        {
          tenant: "org-1",
          donor_type: "contact",
          donor_id: "d1",
          year: 2026,
          page_size: 5,
        },
      ],
      [
        "list_donation_receipts",
        {
          tenant: "org-1",
          donor_type: null,
          donor_id: null,
          year: null,
          page_size: null,
        },
      ],
    ]);
  });

  it("summarizes a donor's giving in a year", async () => {
    const { calls, transport } = router({
      yearly_giving_summary: (args) =>
        args["year"] === 2025
          ? {
              year: 2025,
              donorType: "contact",
              donorId: "d1",
              totals: null,
              funds: null,
              receipts: null,
            }
          : {
              year: 2026,
              donorType: "contact",
              donorId: "d1",
              totals: [{ amount: "30000", currency: "EUR", gifts: 12 }],
              funds: [
                {
                  fundId: FUND_ID,
                  name: "Roof appeal",
                  amount: "25000",
                  currency: "EUR",
                },
                {
                  fundId: null,
                  name: "General",
                  amount: "5000",
                  currency: "EUR",
                },
              ],
              receipts: [RECEIPT],
            },
    });

    const donations = createDonations({ transport, tenant: "org-1" });

    const summary = await donations.givingSummary(DONOR).orThrow();
    const empty = await donations.givingSummary(DONOR, 2025).orThrow();

    expect(summary).toEqual({
      year: 2026,
      donor: DONOR,
      totals: [{ amount: money(30_000n, "EUR"), gifts: 12 }],
      funds: [
        { fundId: FUND_ID, name: "Roof appeal", amount: money(25_000n, "EUR") },
        { name: "General", amount: money(5000n, "EUR") },
      ],
      receipts: [expect.objectContaining({ number: "R-7" })],
    });
    expect(empty).toEqual({
      year: 2025,
      donor: DONOR,
      totals: [],
      funds: [],
      receipts: [],
    });
    expect(calls.map(([, args]) => args["year"])).toEqual([null, 2025]);
  });

  it("refuses a provider for another payments API", () => {
    expect(() =>
      createDonations({
        transport: router({}).transport,
        payments: {
          ...fakePayments().provider,
          // SAFETY: a provider for a future API, to reach the version check.
          apiVersion: 2 as 1,
        },
      }),
    ).toThrow("payment provider API 2");
  });

  it("runs hooks with the logger it gets", async () => {
    const seen: string[] = [];

    const donations = createDonations({
      transport: router({ get_gift: () => GIFT }).transport,
      hooks: {
        getGift: {
          before: (_args, info) => {
            seen.push(info.method);
          },
        },
      },
      logger: console,
    });

    await donations.getGift(GIFT_ID).orThrow();

    expect(seen).toEqual(["getGift"]);
  });
});

describe("donations block", () => {
  it("loads a donor's giving through the section", async () => {
    const { calls, transport } = router({
      yearly_giving_summary: () => ({
        year: 2026,
        donorType: "contact",
        donorId: "d1",
        totals: [],
        funds: [],
        receipts: [],
      }),
    });

    const donations = createDonations({ transport, tenant: "org-1" });

    expect((await givingSection.load(donations, DONOR, undefined)).ok).toBe(
      true,
    );
    expect(calls[0]?.[1]).toMatchObject({ donor_type: "contact" });
    expect(donationsBlock.name).toBe("donations");
    expect(donationsBlock.sql).toEqual(["donations"]);
    expect(donationsEvents.types).toContain("donation.received");
  });

  it("validates the inputs", () => {
    expect(
      validate(giftInputSchema, {
        donor: DONOR,
        amount: { amount: 2500n, currency: "EUR" },
      }).issues,
    ).toBeUndefined();
    expect(validate(giftInputSchema, { donor: DONOR }).issues).toBeDefined();
    expect(
      validate(pledgeInputSchema, {
        donor: DONOR,
        amount: { amount: 2500n, currency: "EUR" },
        frequency: "daily",
      }).issues,
    ).toBeDefined();
    expect(
      validate(donationFundInputSchema, { key: "roof", name: "Roof" }).issues,
    ).toBeUndefined();
  });
});
