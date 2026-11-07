import { describe, expect, it, vi } from "vitest";

import { createQuotes } from "../../../src/blocks/quotes/index.ts";
import { money } from "../../../src/commerce/money.ts";

const eur = (amount: bigint) => money(amount, "EUR");

type Handler = (args: Record<string, unknown>) => unknown;

function transport(results: Record<string, Handler>) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push([fn, args]);
      const result = results[fn];

      if (!result) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }

      return Promise.resolve(result(args));
    },
  };
}

const ROW = {
  id: "q1",
  tenant_id: "o",
  number: "1",
  identifier: "Q-1",
  title: "Rollout",
  currency: "EUR",
  status: "draft",
  created_at: "2026-10-15T09:00:00Z",
  list_total: "0",
  discount_total: "0",
  subtotal: "0",
  tax_total: "0",
  total: "0",
  lines: [],
};

const TOTALS = {
  listTotal: "1",
  discountTotal: "0",
  subtotal: "1",
  taxTotal: "0",
  total: "1",
  currency: "EUR",
};

const PUBLIC = {
  identifier: "Q-1",
  title: "Rollout",
  status: "sent",
  currency: "EUR",
  subtotal: "100",
  discountTotal: "0",
  taxTotal: "0",
  total: "100",
  lines: [],
};

const ACTOR = { type: "user", id: "u1" } as const;

describe("quote rows", () => {
  it("reads an open-ended line with its unit and discount kind", async () => {
    const t = transport({
      create_quote: () => ({
        ...ROW,
        lines: [
          {
            description: "Hosting",
            quantity: 1,
            unitAmount: "10",
            periods: null,
            unit: "month",
            discountKind: "fixed",
          },
          {
            description: "Setup",
            quantity: 1,
            unitAmount: "10",
            periods: 1,
            discountKind: "half",
          },
        ],
      }),
    });

    const quote = await createQuotes({ transport: t })
      .create({ organizationId: "o", input: { title: "Rollout" } })
      .orThrow();

    expect(quote.lines[0]).toMatchObject({
      openEnded: true,
      unit: "month",
      discountKind: "fixed",
    });
    expect(quote.lines[0]).not.toHaveProperty("periods");
    expect(quote.lines[1]).not.toHaveProperty("openEnded");
    expect(quote.lines[1]).not.toHaveProperty("discountKind");
  });

  it("reads periods, tax lines without a rate and the unpublished flag", async () => {
    const t = transport({
      create_quote: () => ({
        ...ROW,
        unpublished_changes: true,
        deposit_bps: 2500,
        deposit_amount: "40",
        lines: [
          {
            description: "Hosting",
            quantity: 1,
            unitAmount: "10",
            periods: 12,
          },
          { description: "Setup", quantity: 1, unitAmount: "10", periods: 1 },
        ],
        taxLines: [{ net: "10", tax: "2", gross: "12", discount: "0" }],
      }),
    });

    const quote = await createQuotes({ transport: t })
      .create({ organizationId: "o", input: { title: "Rollout" } })
      .orThrow();

    expect(quote.unpublishedChanges).toBe(true);
    expect(quote.revision).toBe(1);
    expect(quote.pricing).toMatchObject({
      depositBps: 2500,
      depositAmount: eur(40n),
    });
    expect(quote.lines[0]).toMatchObject({ periods: 12 });
    expect(quote.lines[1]).not.toHaveProperty("periods");
    expect(quote.taxLines).toEqual([
      {
        taxRateBps: 0,
        net: eur(10n),
        tax: eur(2n),
        gross: eur(12n),
        discount: eur(0n),
      },
    ]);
  });

  it("reads a public quote with a deposit and without a revision", async () => {
    const t = transport({
      public_quote: () => ({
        ...PUBLIC,
        depositAmount: "30",
        depositBps: null,
        depositRequired: true,
        depositDue: "30",
        taxLines: [
          { taxRateBps: 900, net: "1", tax: "0", gross: "1", discount: "0" },
        ],
      }),
      respond_to_quote: () => ({ status: "accepted", identifier: "Q-1" }),
    });

    const quotes = createQuotes({ transport: t });
    const view = await quotes.view("tok").orThrow();

    expect(view.revision).toBe(1);
    expect(view.pricing).toMatchObject({
      depositAmount: eur(30n),
      depositRequired: true,
      depositDue: eur(30n),
    });
    expect(view.pricing).not.toHaveProperty("depositBps");
    expect(view.taxLines).toHaveLength(1);

    expect(
      await quotes
        .respond({
          token: "tok",
          decision: "accepted",
          answer: { name: "Els" },
        })
        .orThrow(),
    ).toEqual({ status: "accepted", identifier: "Q-1", revision: 1 });
  });
});

describe("quote writes", () => {
  it("rejects a currency the quote cannot hold before calling the database", async () => {
    const t = transport({ create_quote: () => ROW, update_quote: () => ROW });
    const quotes = createQuotes({ transport: t });

    const created = await quotes.create({
      organizationId: "o",
      input: { title: "x", currency: "ZZZ" },
    });

    expect(created.ok).toBe(false);

    const mixed = await quotes.create({
      organizationId: "o",
      input: { title: "x", currency: "EUR" },
      lines: [
        { description: "Dollars", quantity: 1, unitAmount: money(1n, "USD") },
      ],
    });

    expect(mixed.ok).toBe(false);

    const updated = await quotes.update({
      quoteId: "q1",
      input: { currency: "ZZZ" },
    });

    expect(updated.ok).toBe(false);

    const lines = await quotes.setLines({
      quoteId: "q1",
      lines: [
        { description: "a", unitAmount: money(1n, "USD") },
        { description: "b", unitAmount: eur(1n) },
      ],
    });

    expect(lines.ok).toBe(false);
    expect(t.calls).toHaveLength(0);
  });

  it("sends the amounts of an update, including a removed deposit", async () => {
    const t = transport({ update_quote: () => ROW });
    const quotes = createQuotes({ transport: t });

    await quotes
      .update({
        quoteId: "q1",
        input: {
          currency: "EUR",
          discountAmount: eur(5n),
          depositAmount: null,
        },
      })
      .orThrow();

    await quotes
      .update({ quoteId: "q1", input: { depositAmount: eur(7n) } })
      .orThrow();

    expect(t.calls[0]![1]["attrs"]).toMatchObject({
      currency: "EUR",
      discountAmount: "5",
      depositAmount: null,
    });
    expect(t.calls[1]![1]["attrs"]).toMatchObject({ depositAmount: "7" });
  });

  it("duplicates every optional part of a quote", async () => {
    const t = transport({
      create_quote: () => ({
        ...ROW,
        company_type: "company",
        company_id: "c1",
        contact_type: "contact",
        contact_id: "p1",
        owner_id: "u1",
        terms: "Net 30",
        note: "Careful",
        deposit_bps: 1000,
        deposit_amount: "9",
        deposit_required: true,
        region: "eu",
        lines: [
          {
            description: "Licences",
            quantity: 1,
            unitAmount: "5",
            position: 3,
          },
        ],
      }),
    });

    const quotes = createQuotes({ transport: t });

    const source = await quotes
      .create({ organizationId: "o", input: { title: "Rollout" } })
      .orThrow();

    t.calls.length = 0;
    await quotes.duplicate({ quote: source }).orThrow();

    expect(t.calls[0]![1]["attrs"]).toMatchObject({
      company: { type: "company", id: "c1" },
      contact: { type: "contact", id: "p1" },
      ownerId: "u1",
      terms: "Net 30",
      note: "Careful",
      depositBps: 1000,
      depositAmount: "9",
      depositRequired: true,
      fields: { region: "eu" },
    });
  });

  it("carries the actor and the withdrawal reason", async () => {
    const t = transport({
      send_quote: () => ({ ...ROW, token: "tok" }),
      decide_quote: () => ROW,
      revise_quote: () => ROW,
      withdraw_quote: () => ROW,
      portal_quote: () => PUBLIC,
      respond_to_portal_quote: () => ({
        status: "accepted",
        identifier: "Q-1",
        revision: 2,
      }),
    });

    const quotes = createQuotes({ transport: t });

    await quotes.send({ quoteId: "q1", actor: ACTOR }).orThrow();
    await quotes.publish({ quoteId: "q1", actor: ACTOR }).orThrow();
    await quotes.revise({ quoteId: "q1", actor: ACTOR }).orThrow();
    await quotes
      .decide({
        quoteId: "q1",
        decision: "accepted",
        options: { actor: ACTOR, note: "ok", selected: ["l1"] },
      })
      .orThrow();
    await quotes
      .withdraw({ quoteId: "q1", options: { actor: ACTOR, reason: "mistake" } })
      .orThrow();
    await quotes.withdraw({ quoteId: "q1" }).orThrow();
    await quotes.portalView({ quoteId: "q1", actor: ACTOR }).orThrow();

    const sent = t.calls.filter(([fn]) => fn === "send_quote");
    expect(sent.map(([, args]) => args["actor"])).toEqual([ACTOR, ACTOR]);
    expect(t.calls.find(([fn]) => fn === "decide_quote")![1]).toMatchObject({
      actor: ACTOR,
      note: "ok",
      selected: ["l1"],
    });

    const withdrawn = t.calls.filter(([fn]) => fn === "withdraw_quote");
    expect(withdrawn[0]![1]).toMatchObject({ actor: ACTOR, reason: "mistake" });
    expect(withdrawn[1]![1]).toEqual({ quote: "q1" });
    expect(t.calls.find(([fn]) => fn === "portal_quote")![1]).toMatchObject({
      actor: ACTOR,
    });

    expect(
      await quotes
        .portalRespond({ quoteId: "q1", decision: "accepted" })
        .orThrow(),
    ).toMatchObject({ revision: 2 });
    expect(t.calls.at(-1)![1]).toMatchObject({ name: null, note: null });

    await quotes
      .portalRespond({
        quoteId: "q1",
        decision: "rejected",
        answer: { name: "Els", note: "no", selected: ["l2"] },
      })
      .orThrow();
    expect(t.calls.at(-1)![1]).toMatchObject({
      name: "Els",
      note: "no",
      selected: ["l2"],
    });
  });
});

describe("drafting from a deal", () => {
  const drafting = () =>
    transport({
      quote_from_deal: () => ROW,
      set_quote_lines: () => TOTALS,
      update_quote: () => ({ ...ROW, title: "Renamed" }),
    });

  it("returns the draft as it is without overrides", async () => {
    const t = drafting();

    const quote = await createQuotes({ transport: t })
      .draftFromDeal({ dealId: "d1" })
      .orThrow();

    expect(quote.title).toBe("Rollout");
    expect(t.calls.map(([fn]) => fn)).toEqual(["quote_from_deal"]);
  });

  it("sets lines, a title and a valid-until date on the draft", async () => {
    const t = drafting();

    const quote = await createQuotes({ transport: t })
      .draftFromDeal({
        dealId: "d1",
        title: "Renamed",
        validUntil: Temporal.PlainDate.from("2026-12-01"),
        lines: [{ description: "a", unitAmount: eur(1n) }],
      })
      .orThrow();

    expect(quote.title).toBe("Renamed");
    expect(t.calls.map(([fn]) => fn)).toEqual([
      "quote_from_deal",
      "set_quote_lines",
      "update_quote",
    ]);
    expect(t.calls[2]![1]["attrs"]).toEqual({
      title: "Renamed",
      validUntil: "2026-12-01",
    });
  });

  it("updates only the title, or only the lines", async () => {
    const titled = drafting();

    await createQuotes({ transport: titled })
      .draftFromDeal({ dealId: "d1", title: "T" })
      .orThrow();
    expect(titled.calls[1]![1]["attrs"]).toEqual({ title: "T" });

    const lined = drafting();

    await createQuotes({ transport: lined })
      .draftFromDeal({ dealId: "d1", lines: [] })
      .orThrow();
    expect(lined.calls.map(([fn]) => fn)).toEqual([
      "quote_from_deal",
      "set_quote_lines",
      "update_quote",
    ]);
    expect(lined.calls[2]![1]["attrs"]).toEqual({});
  });

  it("stops when the draft or its lines fail", async () => {
    const noDraft = transport({
      quote_from_deal: () => {
        throw new Error("no deal");
      },
    });

    const failed = await createQuotes({ transport: noDraft }).draftFromDeal({
      dealId: "d1",
      title: "T",
    });

    expect(failed.ok).toBe(false);

    const badLines = drafting();

    const mixed = await createQuotes({ transport: badLines }).draftFromDeal({
      dealId: "d1",
      lines: [
        { description: "a", unitAmount: money(1n, "USD") },
        { description: "b", unitAmount: eur(1n) },
      ],
    });

    expect(mixed.ok).toBe(false);
    expect(badLines.calls.map(([fn]) => fn)).toEqual(["quote_from_deal"]);
  });
});

describe("quote housekeeping", () => {
  it("counts expired quotes, with zero for an empty answer", async () => {
    const quotes = (answer: unknown) =>
      createQuotes({ transport: transport({ expire_quotes: () => answer }) });

    expect(await quotes(3).expire().orThrow()).toBe(3);
    expect(await quotes(null).expire().orThrow()).toBe(0);
  });

  it("hands the logger to the hooks", async () => {
    const error = vi.fn();

    const quotes = createQuotes({
      transport: transport({ expire_quotes: () => 1 }),
      logger: { debug() {}, info() {}, warn() {}, error },
      hooks: {
        expire: {
          after: () => {
            throw new Error("after failed");
          },
        },
      },
    });

    await quotes.expire().orThrow();
    expect(error).toHaveBeenCalledExactlyOnceWith(
      "quotes.expire after hook threw",
      { cause: new Error("after failed") },
    );
  });
});
