import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { ModuleLayout } from "../../src/sql/module-types.ts";

import { createDeals, dealsSubjects } from "../../src/blocks/deals/index.ts";
import { createInvoices } from "../../src/blocks/invoices/index.ts";
import {
  createParties,
  partiesSubjects,
} from "../../src/blocks/parties/index.ts";
import { createQuotes } from "../../src/blocks/quotes/index.ts";
import { createRelations } from "../../src/blocks/relations/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = [
  "organizations",
  "outbox",
  "subjects",
  "relations",
  "parties",
  "pipelines",
  "deals",
  "quotes",
  "invoices",
];

const layout: ModuleLayout = {
  subjects: {
    ...partiesSubjects(),
    ...dealsSubjects(),
    quote: {
      table: "better_supabase.quotes",
      idType: "uuid",
      tenant: "tenant_id",
    },
    invoice: {
      table: "better_supabase.invoices",
      idType: "uuid",
      tenant: "tenant_id",
    },
  },
};

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

describe.skipIf(!live)("quotes and invoices", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("turns a deal into a quote the customer accepts, then a deposit and a final invoice", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const rep = await s.user("rep");
      await s.install(MODULES, layout);
      const org = await s.organization(owner, { member: rep });
      const transport = sqlTransport(s.sql);
      const quotes = createQuotes({ transport });
      const invoices = createInvoices({ transport });

      await s.as(rep);

      const acme = await createParties({ transport })
        .saveCompany(org, { name: "Acme" })
        .orThrow();

      const deal = await createDeals({ transport })
        .create(org, {
          name: "Rollout",
          closeOn: Temporal.PlainDate.from("2026-12-01"),
          amount: 1_000_000n,
          currency: "EUR",
          company: { type: "company", id: acme.id },
        })
        .orThrow();

      const quote = await quotes.fromDeal(deal.id).orThrow();
      expect(quote).toMatchObject({
        identifier: "Q-1",
        status: "draft",
        origin: { type: "deal", id: deal.id },
        company: { type: "company", id: acme.id },
      });
      expect(quote.lines).toEqual([
        expect.objectContaining({
          description: "Rollout",
          unitAmount: 1_000_000n,
        }),
      ]);
      expect((await quotes.fromDeal(deal.id).orThrow()).id).toBe(quote.id);

      await quotes
        .setLines(quote.id, [
          {
            description: "Licences",
            quantity: 10,
            unitAmount: 100_000n,
            taxRateBps: 2100,
          },
          {
            description: "Setup",
            unitAmount: 50_000n,
            discountBps: 2000,
            taxRateBps: 2100,
          },
        ])
        .orThrow();
      const { quote: sent, token } = await quotes.send(quote.id).orThrow();
      expect(sent.status).toBe("sent");
      expect(
        hint(
          await quotes.setLines(quote.id, [
            { description: "x", unitAmount: 1n },
          ]),
        ),
      ).toBe("LINES_RECORD_INVALID");

      await s.as("anon");
      const seen = await quotes.view(token).orThrow();
      expect(seen).toMatchObject({
        identifier: "Q-1",
        status: "viewed",
        subtotal: 1_040_000n,
        taxTotal: 218_400n,
        total: 1_258_400n,
      });
      expect(hint(await quotes.view("nope"))).toBe("QUOTE_LINK_INVALID");
      expect(
        (
          await quotes
            .respond(token, "changes_requested", {
              name: "Els",
              note: "Fewer licences",
            })
            .orThrow()
        ).status,
      ).toBe("changes_requested");

      await s.as(rep);
      const revised = await quotes.revise(quote.id).orThrow();
      expect(revised).toMatchObject({
        identifier: "Q-1",
        revision: 2,
        supersedesId: quote.id,
        status: "draft",
      });
      expect(revised.lines).toHaveLength(2);
      const { token: token2 } = await quotes.send(revised.id).orThrow();
      await s.as("anon");
      expect(
        hint(await quotes.respond(token, "accepted", { name: "Els" })),
      ).toBe("QUOTE_LINK_INVALID");
      expect(
        (
          await quotes
            .respond(token2, "accepted", { name: "Els Jansen" })
            .orThrow()
        ).status,
      ).toBe("accepted");

      await s.as(rep);
      expect(hint(await invoices.fromQuote(revised.id))).toBe(
        "INVOICE_ORIGIN_NOT_FOUND",
      );
      await s.as(owner);

      const deposit = await invoices
        .fromQuote(revised.id, { depositBps: 3000 })
        .orThrow();

      expect(deposit).toMatchObject({
        status: "draft",
        depositBps: 3000,
        totals: { subtotal: 312_000n, taxTotal: 65_520n, total: 377_520n },
      });

      const issuedDeposit = await invoices
        .issue(deposit.id, Temporal.PlainDate.from("2026-10-15"))
        .orThrow();

      expect(issuedDeposit).toMatchObject({
        identifier: "INV-1",
        status: "issued",
        dueOn: Temporal.PlainDate.from("2026-11-14"),
      });

      const final = await invoices.fromQuote(revised.id).orThrow();
      expect(final.totals).toMatchObject({
        subtotal: 728_000n,
        taxTotal: 152_880n,
        total: 880_880n,
      });
      expect((await invoices.fromQuote(revised.id).orThrow()).id).toBe(
        final.id,
      );
      const issuedFinal = await invoices.issue(final.id).orThrow();
      expect(issuedFinal.identifier).toBe("INV-2");

      const partly = await invoices
        .recordPayment(issuedFinal.id, {
          amount: 500_000n,
          reference: "bank-1",
        })
        .orThrow();

      expect(partly).toMatchObject({
        status: "partially_paid",
        balance: 380_880n,
      });
      expect(
        (
          await invoices
            .recordPayment(issuedFinal.id, {
              amount: 500_000n,
              reference: "bank-1",
            })
            .orThrow()
        ).paidTotal,
      ).toBe(500_000n);

      const credit = await invoices
        .credit(issuedFinal.id, {
          lines: [{ description: "Goodwill", unitAmount: 80_880n }],
        })
        .orThrow();

      expect(credit).toMatchObject({
        kind: "credit_note",
        originalId: issuedFinal.id,
        status: "draft",
      });
      expect((await invoices.issue(credit.id).orThrow()).identifier).toBe(
        "CN-1",
      );

      const paid = await invoices
        .recordPayment(issuedFinal.id, { amount: 300_000n })
        .orThrow();

      expect(paid).toMatchObject({
        status: "paid",
        balance: 0n,
        creditedTotal: 80_880n,
      });
      expect(
        hint(
          await invoices
            .credit(issuedFinal.id, {
              lines: [{ description: "x", unitAmount: 1n }],
            })
            .then(async (r) => (r.ok ? invoices.issue(r.data.id) : r)),
        ),
      ).toBe("INVOICE_CREDIT_TOO_LARGE");

      const aging = await invoices
        .aging(org, "EUR", Temporal.PlainDate.from("2026-12-20"))
        .orThrow();

      expect(aging).toMatchObject({
        days31To60: 377_520n,
        outstanding: 377_520n,
        overdueCount: 1,
      });

      await s.as(rep);
      expect(hint(await invoices.void(issuedDeposit.id))).toBe(
        "INVOICE_NOT_FOUND",
      );
      await s.as(owner);
      const written = await invoices.writeOff(issuedDeposit.id).orThrow();
      expect(written.status).toBe("uncollectible");

      await s.as(owner);

      const lineage = await createRelations({ transport })
        .lineage(org, { type: "quote", id: quote.id })
        .orThrow();

      expect(lineage.origins).toEqual([
        expect.objectContaining({ type: "deal", id: deal.id }),
      ]);
    } finally {
      await s.close();
    }
  });

  it("rounds line totals half away from zero in numeric, past 2^53", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      await s.install(MODULES, layout);
      const org = await s.organization(owner);
      const transport = sqlTransport(s.sql);
      const quotes = createQuotes({ transport });
      const invoices = createInvoices({ transport });
      await s.as(owner);

      const large = 9_007_199_254_740_993n;

      const invoice = await invoices
        .create(org, { title: "Precision" }, [
          { description: "Half", unitAmount: 1n, taxRateBps: 5000 },
          { description: "Hours", quantity: 1.2345, unitAmount: 1999n },
          { description: "Large", unitAmount: large },
        ])
        .orThrow();

      // A row result sends int8 as a JSON number, so read the stored totals
      // as text to check them past 2^53.
      const [stored] = await s.sql.queryRaw<Record<string, string>>(
        "select subtotal::text, tax_total::text, total::text from better_supabase.invoices where id = $1",
        [invoice.id],
      );

      expect(stored).toEqual({
        subtotal: String(1n + 2468n + large),
        tax_total: "1",
        total: String(2n + 2468n + large),
      });

      const quote = await quotes
        .create(
          org,
          {
            title: "Large",
            validUntil: Temporal.Now.plainDateISO().add({ days: 30 }),
          },
          [{ description: "Large", unitAmount: large }],
        )
        .orThrow();

      const { token } = await quotes.send(quote.id).orThrow();
      await s.as("anon");
      await quotes.respond(token, "accepted", { name: "Els" }).orThrow();
      await s.as(owner);

      const deposit = await invoices
        .fromQuote(quote.id, { depositBps: 3000 })
        .orThrow();

      expect(deposit.totals.subtotal).toBe(2_702_159_776_422_298n);
    } finally {
      await s.close();
    }
  });

  it("voids drafts, expires sent quotes and refuses quotes that aren't accepted", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      await s.install(MODULES, layout);
      const org = await s.organization(owner);
      const transport = sqlTransport(s.sql);
      const quotes = createQuotes({ transport });
      const invoices = createInvoices({ transport });
      await s.as(owner);

      const quote = await quotes
        .create(
          org,
          {
            title: "Old offer",
            validUntil: Temporal.PlainDate.from("2020-01-01"),
          },
          [{ description: "x", unitAmount: 100n }],
        )
        .orThrow();

      expect(hint(await invoices.fromQuote(quote.id))).toBe(
        "INVOICE_QUOTE_NOT_ACCEPTED",
      );
      const { token } = await quotes.send(quote.id).orThrow();
      await s.as("anon");
      expect(
        (await quotes.respond(token, "accepted", { name: "Late" }).orThrow())
          .status,
      ).toBe("expired");
      await s.as(owner);
      expect(
        hint(
          await quotes.send(
            (await quotes.create(org, { title: "Empty" }).orThrow()).id,
          ),
        ),
      ).toBe("QUOTE_EMPTY");

      const other = await quotes
        .create(
          org,
          { title: "Other", validUntil: Temporal.PlainDate.from("2020-01-01") },
          [{ description: "x", unitAmount: 1n }],
        )
        .orThrow();

      await quotes.send(other.id).orThrow();
      await s.service();
      expect(await quotes.expire().orThrow()).toBe(1);
      await s.as(owner);

      const draft = await invoices
        .create(org, { title: "Mistake" }, [
          { description: "x", unitAmount: 5n },
        ])
        .orThrow();

      const voided = await invoices.void(draft.id, "Duplicate").orThrow();
      expect(voided).toMatchObject({ status: "void", voidReason: "Duplicate" });
      expect(voided.identifier).toBeUndefined();

      const next = await invoices
        .issue(
          (
            await invoices
              .create(org, { title: "Real" }, [
                { description: "x", unitAmount: 5n },
              ])
              .orThrow()
          ).id,
        )
        .orThrow();

      expect(next.identifier).toBe("INV-1");
      expect(hint(await invoices.recordPayment(draft.id, { amount: 1n }))).toBe(
        "INVOICE_NOT_PAYABLE",
      );
    } finally {
      await s.close();
    }
  });
});
