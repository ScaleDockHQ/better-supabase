import { Pool } from "pg";
import { Temporal } from "temporal-polyfill";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";

import { createContacts } from "../../src/blocks/contacts/index.ts";
import { createInvoices } from "../../src/blocks/invoices/index.ts";
import { money } from "../../src/commerce/money.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();
const eur = (amount: bigint) => money(amount, "EUR");

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

describe.skipIf(!live)("invoice collections", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  const issued = async (s: BlockSession, count: number) => {
    const owner = await s.user("owner");
    const outsider = await s.user("outsider");
    await s.install(["organizations", "subjects", "contacts", "invoices"], {
      subjects: withBlockSubjects({}, ["contacts"], {}),
    });
    const org = await s.organization(owner);
    await s.organization(outsider);
    const transport = sqlTransport(s.sql);
    const invoices = createInvoices({ transport });
    await s.as(owner);

    const { id: party } = await createContacts({ transport })
      .saveCompany({
        organizationId: org,
        input: { name: "Collections customer" },
      })
      .orThrow();

    const list = [];

    for (let index = 0; index < count; index += 1) {
      const draft = await invoices
        .create({
          organizationId: org,
          input: {
            title: `Retainer ${index + 1}`,
            company: { type: "company", id: party },
            termsDays: 10,
          },
          lines: [{ description: "Work", unitAmount: eur(1000n) }],
        })
        .orThrow();

      list.push(await invoices.issue({ invoiceId: draft.id }).orThrow());
    }

    return { owner, outsider, org, party, invoices, list };
  };

  it("splits a payment over invoices and keeps the rest as credit", async () => {
    const s = await BlockSession.open(pool);

    try {
      const { org, party, invoices, list } = await issued(s, 3);
      const [first, second, third] = list;

      const payment = await invoices
        .recordPartyPayment({
          organizationId: org,
          payment: {
            partyId: party,
            amount: eur(1500n),
            allocations: [
              { invoiceId: first!.id, amount: eur(1000n) },
              { invoiceId: second!.id, amount: eur(300n) },
            ],
            reference: "bank-1",
          },
        })
        .orThrow();

      expect(payment).toMatchObject({
        allocated: eur(1300n),
        credited: eur(200n),
        credit: eur(200n),
      });

      const replay = await invoices
        .recordPartyPayment({
          organizationId: org,
          payment: {
            partyId: party,
            amount: eur(1500n),
            allocations: [
              { invoiceId: first!.id, amount: eur(1000n) },
              { invoiceId: second!.id, amount: eur(300n) },
            ],
            reference: "bank-1",
          },
        })
        .orThrow();

      expect(replay.credit).toEqual(eur(200n));

      const paid = await invoices
        .applyPartyCredit({
          partyId: party,
          invoiceId: third!.id,
          amount: eur(200n),
        })
        .orThrow();

      expect(paid).toMatchObject({ balance: eur(800n) });
      expect(paid.payments.at(-1)?.method).toBe("credit");
      expect(
        await invoices
          .partyCredits({ organizationId: org, partyId: party })
          .orThrow(),
      ).toEqual([eur(0n)]);
      expect(
        hint(
          await invoices.applyPartyCredit({
            partyId: party,
            invoiceId: third!.id,
            amount: eur(1n),
          }),
        ),
      ).toBe("INVOICE_CREDIT_INSUFFICIENT");
    } finally {
      await s.close();
    }
  });

  it("raises overdue invoices through the dunning levels and pauses them", async () => {
    const s = await BlockSession.open(pool);

    try {
      const { owner, outsider, org, invoices, list } = await issued(s, 2);
      const [first, second] = list;

      await invoices
        .setDunningLevels({
          organizationId: org,
          levels: [
            { daysAfterDue: 7, templateKey: "reminder" },
            { daysAfterDue: 21, templateKey: "second", fee: 500n },
          ],
        })
        .orThrow();
      await invoices
        .pauseDunning({
          invoiceId: second!.id,
          until: Temporal.Now.plainDateISO().add({ days: 60 }),
          reason: "Disputed",
        })
        .orThrow();

      await s.asRole(owner);
      expect(hint(await invoices.runDunning())).not.toBe("ok");

      await s.service();
      const asOf = Temporal.Now.plainDateISO().add({ days: 20 });

      expect(
        await invoices.runDunning({ organizationId: org, asOf }).orThrow(),
      ).toBe(1);
      expect(
        await invoices.runDunning({ organizationId: org, asOf }).orThrow(),
      ).toBe(0);
      expect(
        await invoices
          .runDunning({ organizationId: org, asOf: asOf.add({ days: 14 }) })
          .orThrow(),
      ).toBe(1);

      await s.as(owner);

      const [raised] = await s.rows<{ dunning_level: number }>(
        "select dunning_level from better_supabase.invoices where id = $1",
        [first!.id],
      );

      expect(raised?.dunning_level).toBe(2);

      const charged = await invoices
        .pauseDunning({ invoiceId: first!.id, until: null })
        .orThrow();

      expect(charged.dunning).toMatchObject({ level: 2 });
      expect(charged.balance).toEqual(eur(1500n));

      await s.as(outsider);
      expect(hint(await invoices.dunningLevels(org))).toBe("INVOICE_FORBIDDEN");
    } finally {
      await s.close();
    }
  });
});
