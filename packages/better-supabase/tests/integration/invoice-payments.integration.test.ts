import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";

import { createInvoices } from "../../src/blocks/invoices/index.ts";
import { createLedger } from "../../src/blocks/ledger/index.ts";
import { money } from "../../src/commerce/money.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();
const eur = (amount: bigint) => money(amount, "EUR");

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

describe.skipIf(!live)("invoice payments", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  const issued = async (s: BlockSession, paymentsAfterWriteOff?: boolean) => {
    const owner = await s.user("owner");
    const outsider = await s.user("outsider");
    await s.install(
      ["organizations", "invoices"],
      paymentsAfterWriteOff === undefined
        ? {}
        : { modules: { invoices: { options: { paymentsAfterWriteOff } } } },
    );
    const org = await s.organization(owner);
    await s.organization(outsider);
    const transport = sqlTransport(s.sql);
    const invoices = createInvoices({ transport });
    await s.as(owner);

    const draft = await invoices
      .create({
        organizationId: org,
        input: { title: "Late" },
        lines: [{ description: "Work", unitAmount: eur(1000n) }],
      })
      .orThrow();

    const invoice = await invoices.issue({ invoiceId: draft.id }).orThrow();

    return { owner, outsider, invoices, invoice, transport };
  };

  it("refuses a payment on a written-off invoice by default", async () => {
    const s = await BlockSession.open(pool);

    try {
      const { invoices, invoice } = await issued(s);
      await invoices
        .writeOff({ invoiceId: invoice.id, reason: "gone" })
        .orThrow();

      expect(
        hint(
          await invoices.recordPayment({
            invoiceId: invoice.id,
            payment: { amount: eur(1000n) },
          }),
        ),
      ).toBe("INVOICE_NOT_PAYABLE");
    } finally {
      await s.close();
    }
  });

  it("books a late payment on a written-off invoice and settles it to paid", async () => {
    const s = await BlockSession.open(pool);

    try {
      const { invoices, invoice } = await issued(s, true);
      await invoices
        .writeOff({ invoiceId: invoice.id, reason: "gone" })
        .orThrow();

      const part = await invoices
        .recordPayment({
          invoiceId: invoice.id,
          payment: { amount: eur(400n), reference: "pi_1" },
        })
        .orThrow();

      expect(part).toMatchObject({
        status: "uncollectible",
        paidTotal: eur(400n),
        balance: eur(600n),
      });

      const paid = await invoices
        .recordPayment({
          invoiceId: invoice.id,
          payment: { amount: eur(600n), reference: "pi_2" },
        })
        .orThrow();

      expect(paid).toMatchObject({
        status: "paid",
        paidTotal: eur(1000n),
        balance: eur(0n),
      });
      expect(paid.paidAt).toBeDefined();

      const replay = await invoices
        .recordPayment({
          invoiceId: invoice.id,
          payment: { amount: eur(600n), reference: "pi_2" },
        })
        .orThrow();

      expect(replay.paidTotal).toEqual(eur(1000n));
    } finally {
      await s.close();
    }
  });

  it("still refuses payments on a void invoice with the option on", async () => {
    const s = await BlockSession.open(pool);

    try {
      const { invoices, invoice } = await issued(s, true);
      await invoices
        .void({ invoiceId: invoice.id, reason: "mistake" })
        .orThrow();

      expect(
        hint(
          await invoices.recordPayment({
            invoiceId: invoice.id,
            payment: { amount: eur(1000n) },
          }),
        ),
      ).toBe("INVOICE_NOT_PAYABLE");
    } finally {
      await s.close();
    }
  });

  it("reads an invoice's payments with who recorded them, for readers only", async () => {
    const s = await BlockSession.open(pool);

    try {
      const { owner, outsider, invoices, invoice, transport } = await issued(s);

      const paid = await invoices
        .recordPayment({
          invoiceId: invoice.id,
          payment: { amount: eur(1000n), method: "bank", reference: "b1" },
        })
        .orThrow();

      expect(await invoices.payments(invoice.id).orThrow()).toEqual([
        expect.objectContaining({
          id: paid.payments[0]!.id,
          amount: eur(1000n),
          method: "bank",
          reference: "b1",
          recordedBy: owner.id,
        }),
      ]);

      const [account] = await s.rows<{ id: string }>(
        "select id from better_supabase.ledger_accounts where code = 'invoice:' || $1",
        [invoice.id],
      );

      const [entry] = await createLedger({ transport })
        .entries({ accountId: account!.id })
        .orThrow();

      expect(entry?.actorId).toBe(owner.id);

      await s.as(outsider);
      expect(hint(await invoices.payments(invoice.id))).toBe(
        "INVOICE_NOT_FOUND",
      );
      await s.as("anon");
      expect(hint(await invoices.payments(invoice.id))).not.toBe("ok");
    } finally {
      await s.close();
    }
  });
});
