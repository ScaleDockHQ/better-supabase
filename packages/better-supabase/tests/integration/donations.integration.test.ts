import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { PaymentProvider } from "../../src/commerce/payments.ts";
import type { Result } from "../../src/core/result.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createContacts } from "../../src/blocks/contacts/index.ts";
import {
  createDonations,
  sqlTransport,
} from "../../src/blocks/donations/index.ts";
import { money } from "../../src/commerce/money.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { dbError } from "../../src/core/errors.ts";
import { AsyncResult } from "../../src/core/result.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = [
  "organizations",
  "outbox",
  "audit",
  "subjects",
  "relations",
  "contacts",
  "ledger",
  "donations",
];

const layout: BlockSqlLayout = {
  subjects: withBlockSubjects({}, ["parties"], {}),
};

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

const day = (text: string): Temporal.PlainDate => Temporal.PlainDate.from(text);

/** A provider that accepts every charge as processing, numbering payments. */
function processingProvider(): PaymentProvider & { readonly keys: string[] } {
  const keys: string[] = [];

  return {
    apiVersion: 1,
    name: "fake",
    keys,
    createPayment: (input, options) => {
      keys.push(options?.idempotencyKey ?? "");

      return AsyncResult.ok({
        id: `pi_${String(keys.length)}`,
        provider: "fake",
        status: "processing",
        amount: input.amount,
        captured: money(0n, input.amount.currency),
        refunded: money(0n, input.amount.currency),
        reference: input.reference,
        metadata: {},
      });
    },
    capture: () => AsyncResult.err(dbError("invalid_request", "not used")),
    refund: () => AsyncResult.err(dbError("invalid_request", "not used")),
    parseWebhook: () => AsyncResult.ok([]),
  };
}

describe.skipIf(!live)("donations", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("charges gifts and pledge installments through the provider and posts them on the ledger", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const ada = await s.user("ada");
      await s.install(MODULES, layout);
      const tenant = await s.organization(owner, { member: ada });
      const transport = sqlTransport(s.sql);
      const payments = processingProvider();
      const donations = createDonations({ transport, tenant, payments });

      await s.as(owner);

      const company = await createContacts({ transport })
        .saveCompany(tenant, { name: "Acme" })
        .orThrow();

      const donor = { type: "company", id: company.id };

      const roof = await donations
        .saveFund({
          key: "roof",
          name: "New roof",
          kind: "campaign",
          goal: money(1_000_000n, "EUR"),
        })
        .orThrow();

      const cash = await donations
        .recordGift({
          donor,
          amount: money(25_000n, "EUR"),
          fundId: roof.id,
          receivedOn: day("2026-03-01"),
          method: "bank",
        })
        .orThrow();

      expect(cash.status).toBe("posted");
      expect(
        await donations
          .recordGift({
            donor: { type: "company", id: crypto.randomUUID() },
            amount: money(100n, "EUR"),
          })
          .then(hint),
      ).toBe("DONATION_DONOR_INVALID");

      const online = await donations
        .give({ donor, amount: money(10_000n, "EUR"), fundId: roof.id })
        .orThrow();

      expect(online.gift).toMatchObject({
        status: "pending",
        paymentReference: "pi_1",
      });

      const settled = await donations
        .handlePaymentEvent({
          id: "evt_1",
          type: "payment.succeeded",
          paymentId: "pi_1",
          reference: online.gift.id,
          occurredAt: Temporal.Now.instant(),
        })
        .orThrow();

      expect(settled).toMatchObject({
        kind: "gift",
        gift: { status: "posted" },
      });
      expect(
        (await donations.funds().orThrow()).find((fund) => fund.id === roof.id)
          ?.raised,
      ).toEqual(money(35_000n, "EUR"));

      const pledge = await donations
        .createPledge({
          donor,
          amount: money(5000n, "EUR"),
          startsOn: day("2026-01-01"),
          provider: "fake",
          providerCustomer: "cus_1",
        })
        .orThrow();

      await donations
        .createPledge({
          donor,
          amount: money(1000n, "EUR"),
          frequency: "yearly",
          startsOn: day("2026-01-01"),
        })
        .orThrow();

      const outcomes = await donations
        .chargeDuePledges({ through: day("2026-03-15") })
        .orThrow();

      expect(outcomes.map((outcome) => outcome.kind).toSorted()).toEqual([
        "charged",
        "charged",
        "charged",
        "skipped",
      ]);
      expect(payments.keys.slice(1).toSorted()).toEqual([
        `pledge:${pledge.id}:2026-01-01`,
        `pledge:${pledge.id}:2026-02-01`,
        `pledge:${pledge.id}:2026-03-01`,
      ]);
      expect(
        (
          await donations
            .chargeDuePledges({ through: day("2026-03-15") })
            .orThrow()
        ).map((outcome) => outcome.kind),
      ).toEqual(["skipped"]);

      const receipt = await donations.issueGiftReceipt(cash.id).orThrow();

      expect(receipt).toMatchObject({ kind: "gift", number: "R-1" });
      expect((await donations.issueGiftReceipt(cash.id).orThrow()).id).toBe(
        receipt.id,
      );

      const summary = await donations.givingSummary(donor, 2026).orThrow();

      expect(summary.totals).toEqual([
        { amount: money(35_000n, "EUR"), gifts: 2 },
      ]);
      expect(summary.receipts.map((r) => r.number)).toEqual(["R-1"]);

      const refunded = await donations
        .handlePaymentEvent({
          id: "evt_2",
          type: "refund.succeeded",
          paymentId: "pi_1",
          occurredAt: Temporal.Now.instant(),
        })
        .orThrow();

      expect(refunded).toMatchObject({
        kind: "gift",
        gift: { status: "refunded" },
      });

      await s.as(ada);
      expect(await donations.gifts().then(hint)).toBe("DONATIONS_FORBIDDEN");

      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where organization_id = $1 and type in ('donation.received', 'donation.refunded', 'donation_receipt.issued') order by position",
        [tenant],
      );

      expect(events.map((event) => event.type)).toEqual([
        "donation.received",
        "donation.received",
        "donation_receipt.issued",
        "donation.refunded",
      ]);
    } finally {
      await s.close();
    }
  });
});
