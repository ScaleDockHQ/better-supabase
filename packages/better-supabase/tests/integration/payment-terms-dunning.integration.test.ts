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

describe.skipIf(!live)("payment terms, credit blocks and dunning runs", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  const setup = async (s: BlockSession) => {
    const owner = await s.user("owner");
    await s.install(
      ["organizations", "subjects", "contacts", "tax", "invoices"],
      { subjects: withBlockSubjects({}, ["contacts"], {}) },
    );
    const clerk = await s.user("clerk");
    const org = await s.organization(owner, { admin: clerk });
    const transport = sqlTransport(s.sql);
    const parties = createContacts({ transport });
    const invoices = createInvoices({ transport });
    await s.as(owner);

    return { owner, clerk, org, parties, invoices };
  };

  it("copies terms to the invoice and computes the early-payment discount on issue", async () => {
    const s = await BlockSession.open(pool);

    try {
      const { org, parties, invoices } = await setup(s);

      const terms = await parties
        .savePaymentTerm({
          organizationId: org,
          input: {
            code: "2/10N30",
            name: "2% in 10 days, net 30",
            days: 30,
            discountBps: 200,
            discountDays: 10,
          },
        })
        .orThrow();

      expect(terms).toMatchObject({ days: 30, discountBps: 200 });
      expect(
        hint(
          await parties.savePaymentTerm({
            organizationId: org,
            input: {
              code: "BAD",
              name: "Bad",
              days: 10,
              discountBps: 100,
              discountDays: 20,
            },
          }),
        ),
      ).not.toBe("ok");

      const customer = await parties
        .saveCompany({
          organizationId: org,
          input: { name: "Terms customer", customerTermsId: terms.id },
        })
        .orThrow();

      const draft = await invoices
        .create({
          organizationId: org,
          input: {
            title: "With terms",
            company: { type: "company", id: customer.id },
          },
          lines: [{ description: "Work", unitAmount: eur(12_345n) }],
        })
        .orThrow();

      expect(draft).toMatchObject({
        termsDays: 30,
        paymentTerms: { id: terms.id },
      });

      const issued = await invoices.issue({ invoiceId: draft.id }).orThrow();
      const today = Temporal.Now.plainDateISO();

      expect(issued.paymentTerms?.discountDueOn?.toString()).toBe(
        issued.issuedOn?.add({ days: 10 }).toString(),
      );
      // 12 345 * 2% = 246.9, rounded half up to 247 minor units.
      expect(issued.paymentTerms?.discountAmount).toEqual(eur(247n));
      expect(issued.dueOn?.toString()).toBe(today.add({ days: 30 }).toString());
      expect(
        hint(
          await invoices.create({
            organizationId: org,
            input: {
              title: "Missing terms",
              paymentTermsId: crypto.randomUUID(),
            },
            lines: [{ description: "Work", unitAmount: eur(1n) }],
          }),
        ),
      ).toBe("INVOICE_PAYMENT_TERMS_NOT_FOUND");
    } finally {
      await s.close();
    }
  });

  it("computes tax on the amount left after a credit restriction", async () => {
    const s = await BlockSession.open(pool);

    try {
      const { org, parties, invoices } = await setup(s);

      const terms = await parties
        .savePaymentTerm({
          organizationId: org,
          input: {
            code: "CR2",
            name: "2% credit restriction",
            creditRestrictionBps: 200,
          },
        })
        .orThrow();

      const plain = await parties
        .saveCompany({ organizationId: org, input: { name: "Plain" } })
        .orThrow();

      const restricted = await parties
        .saveCompany({
          organizationId: org,
          input: { name: "Restricted", customerTermsId: terms.id },
        })
        .orThrow();

      const taxOf = async (party: string): Promise<bigint> => {
        const draft = await invoices
          .create({
            organizationId: org,
            input: { title: "Taxed", company: { type: "company", id: party } },
            lines: [
              {
                description: "Work",
                unitAmount: eur(10_000n),
                taxRateBps: 2100,
              },
            ],
          })
          .orThrow();

        await invoices.issue({ invoiceId: draft.id }).orThrow();

        const [row] = await s.rows<{ tax: string }>(
          "select coalesce(sum(tax), 0)::text as tax from better_supabase.invoice_tax_lines where invoice_id = $1",
          [draft.id],
        );

        return BigInt(row!.tax);
      };

      expect(await taxOf(plain.id)).toBe(2100n);
      // The buyer deducts 2% of 10 000 first: 21% of 9 800 is 2 058.
      expect(await taxOf(restricted.id)).toBe(2058n);
    } finally {
      await s.close();
    }
  });

  it("warns on a soft credit block and refuses a hard one", async () => {
    const s = await BlockSession.open(pool);

    try {
      const { clerk, org, parties, invoices } = await setup(s);

      const soft = await parties
        .saveCompany({
          organizationId: org,
          input: { name: "Soft", creditLimit: eur(1000n), creditBlock: "soft" },
        })
        .orThrow();

      const hard = await parties
        .saveCompany({
          organizationId: org,
          input: { name: "Hard", creditLimit: eur(1000n), creditBlock: "hard" },
        })
        .orThrow();

      const draftFor = async (party: string) =>
        invoices
          .create({
            organizationId: org,
            input: { title: "Large", company: { type: "company", id: party } },
            lines: [{ description: "Work", unitAmount: eur(1500n) }],
          })
          .orThrow();

      // The owner may override a credit limit; a member may not.
      await s.as(clerk);

      const softDraft = await draftFor(soft.id);
      const hardDraft = await draftFor(hard.id);

      const warned = await invoices
        .issue({ invoiceId: softDraft.id })
        .orThrow();

      expect(warned.status).toBe("issued");
      expect(warned.warnings).toEqual([
        expect.objectContaining({
          code: "INVOICE_CREDIT_LIMIT_EXCEEDED",
          limit: 1000n,
        }),
      ]);
      expect(hint(await invoices.issue({ invoiceId: hardDraft.id }))).toBe(
        "INVOICE_CREDIT_LIMIT_EXCEEDED",
      );
    } finally {
      await s.close();
    }
  });

  it("picks open items per customer in a run, keeps history and hands over to collection", async () => {
    const s = await BlockSession.open(pool);

    try {
      const { owner, org, parties, invoices } = await setup(s);

      const customer = await parties
        .saveCompany({ organizationId: org, input: { name: "Late" } })
        .orThrow();

      const agency = await parties
        .saveCompany({ organizationId: org, input: { name: "Agency" } })
        .orThrow();

      await invoices
        .setDunningLevels({
          organizationId: org,
          levels: [
            {
              daysAfterDue: 7,
              templateKey: "reminder",
              textKey: "dunning.first",
            },
            { daysAfterDue: 21, templateKey: "second", fee: 500n },
          ],
        })
        .orThrow();

      const open = [];

      for (const title of ["One", "Two"]) {
        const draft = await invoices
          .create({
            organizationId: org,
            input: {
              title,
              company: { type: "company", id: customer.id },
              termsDays: 10,
            },
            lines: [{ description: "Work", unitAmount: eur(1000n) }],
          })
          .orThrow();

        open.push(await invoices.issue({ invoiceId: draft.id }).orThrow());
      }

      await s.service();

      const asOf = Temporal.Now.plainDateISO().add({ days: 20 });

      expect(
        await invoices.runDunning({ organizationId: org, asOf }).orThrow(),
      ).toBe(2);

      await s.as(owner);

      const [run] = await invoices
        .dunningRuns({ organizationId: org })
        .orThrow();

      expect(run).toMatchObject({ items: 2, customers: 1 });

      const customers = await invoices.dunningRunItems(run!.id).orThrow();

      expect(customers).toHaveLength(1);
      expect(customers[0]).toMatchObject({
        partyId: customer.id,
        balance: 2000n,
      });
      expect(customers[0]?.items.map((item) => item.textKey)).toEqual([
        "dunning.first",
        "dunning.first",
      ]);

      const history = await invoices.dunningHistory(open[0]!.id).orThrow();

      expect(history).toMatchObject([
        { kind: "reminder", level: 1, runId: run!.id },
      ]);

      const [handed] = await invoices
        .handOverToCollection({
          invoiceIds: [open[0]!.id],
          agencyPartyId: agency.id,
          note: "Sent",
        })
        .orThrow();

      expect(handed).toBe(open[0]!.id);
      expect(
        hint(
          await invoices.handOverToCollection({
            invoiceIds: [open[0]!.id],
            agencyPartyId: agency.id,
          }),
        ),
      ).toBe("INVOICE_ALREADY_HANDED_OVER");

      const after = await invoices
        .pauseDunning({ invoiceId: open[0]!.id, until: null })
        .orThrow();

      expect(after.collection).toMatchObject({ agencyPartyId: agency.id });
      expect(
        (await invoices.dunningHistory(open[0]!.id).orThrow()).map(
          (entry) => entry.kind,
        ),
      ).toEqual(["reminder", "handed_over"]);

      await s.service();
      expect(
        await invoices
          .runDunning({ organizationId: org, asOf: asOf.add({ days: 30 }) })
          .orThrow(),
      ).toBe(1);
    } finally {
      await s.close();
    }
  });

  it("keeps a language and one delivery preference per document type and channel", async () => {
    const s = await BlockSession.open(pool);

    try {
      const { org, parties } = await setup(s);

      const company = await parties
        .saveCompany({
          organizationId: org,
          input: { name: "Post only", language: "de-DE" },
        })
        .orThrow();

      expect(company.language).toBe("de-DE");
      expect(
        hint(
          await parties.saveCompany({
            organizationId: org,
            input: { id: company.id, language: "not a tag" },
          }),
        ),
      ).not.toBe("ok");

      const saved = await parties
        .setDeliveryPreferences({
          partyId: company.id,
          preferences: [
            { documentType: "invoice", channel: "post", copies: 2 },
            {
              documentType: "invoice",
              channel: "email",
              email: "ap@example.test",
            },
          ],
        })
        .orThrow();

      expect(saved).toHaveLength(2);
      expect(
        await parties.deliveryPreferences(company.id).orThrow(),
      ).toHaveLength(2);
      expect(
        hint(
          await parties.setDeliveryPreferences({
            partyId: company.id,
            preferences: [
              { documentType: "invoice", channel: "post" },
              { documentType: "invoice", channel: "post" },
            ],
          }),
        ),
      ).toBe("DELIVERY_PREFERENCE_INVALID");

      const replaced = await parties
        .setDeliveryPreferences({
          partyId: company.id,
          preferences: [{ documentType: "reminder", channel: "portal" }],
        })
        .orThrow();

      expect(replaced).toMatchObject([{ documentType: "reminder", copies: 1 }]);
    } finally {
      await s.close();
    }
  });
});
