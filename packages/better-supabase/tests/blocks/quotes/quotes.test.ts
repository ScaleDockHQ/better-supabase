import * as v from "valibot";
import { describe, expect, expectTypeOf, it } from "vitest";

import { createQuotes } from "../../../src/blocks/quotes/index.ts";
import { money } from "../../../src/commerce/money.ts";

const eur = (amount: bigint) => money(amount, "EUR");

function transport(
  results: Record<string, (args: Record<string, unknown>) => unknown>,
) {
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

const LINE = {
  description: "Licences",
  quantity: 10,
  unitAmount: "100000",
  discountBps: 0,
  taxRateBps: 2100,
  taxCode: null,
  product: { type: "product", id: "p1" },
};

const ROW = {
  id: "q1",
  tenant_id: "o",
  number: "1",
  identifier: "Q-1",
  revision: 2,
  title: "Rollout",
  company_type: "company",
  company_id: "c1",
  contact_type: null,
  contact_id: null,
  owner_user_id: "u1",
  currency: "EUR",
  status: "sent",
  valid_until: "2026-11-14",
  terms: "Net 30",
  note: null,
  origin_type: "deal",
  origin_id: "d1",
  sent_at: "2026-10-15T09:00:00Z",
  viewed_at: null,
  decided_at: null,
  decided_by: null,
  decision_note: null,
  created_by: "u1",
  created_at: "2026-10-15T09:00:00Z",
  updated_at: "2026-10-15T09:00:00Z",
  list_total: "1000000",
  discount_total: "0",
  subtotal: "1000000",
  tax_total: "210000",
  total: "1210000",
  lines: [LINE],
  region: "eu",
};

describe("quotes block", () => {
  it("duplicates a quote into a new draft through create", async () => {
    const t = transport({
      create_quote: () => ({ ...ROW, id: "q2", status: "draft" }),
    });

    const quotes = createQuotes({ transport: t });

    const source = await quotes
      .create({ organizationId: "o", input: { title: "Rollout" } })
      .orThrow();

    t.calls.length = 0;

    const copy = await quotes.duplicate({ quote: source }).orThrow();

    expect(copy.id).toBe("q2");
    expect(t.calls).toHaveLength(1);

    const [fn, args] = t.calls[0]!;
    const attrs = args["attrs"] as Record<string, unknown>;

    expect(fn).toBe("create_quote");
    expect(args["tenant"]).toBe("o");
    expect(attrs).toMatchObject({
      title: "Rollout (copy)",
      currency: "EUR",
      terms: "Net 30",
    });
    expect(attrs).not.toHaveProperty("validUntil");
    expect(attrs).not.toHaveProperty("origin");
    expect(args["lines"]).toEqual([
      expect.objectContaining({
        description: "Licences",
        unitAmount: "100000",
        currency: "EUR",
      }),
    ]);
    expect((args["lines"] as Record<string, unknown>[])[0]).not.toHaveProperty(
      "position",
    );

    await quotes
      .duplicate({ quote: source, title: "Second", input: { note: "again" } })
      .orThrow();

    expect(t.calls[1]![1]["attrs"]).toMatchObject({
      title: "Second",
      note: "again",
    });
  });

  it("creates with lines and dates as the database reads them", async () => {
    const t = transport({ create_quote: () => ROW });

    const quote = await createQuotes({ transport: t })
      .create({
        organizationId: "o",
        input: {
          title: "Rollout",
          validUntil: Temporal.PlainDate.from("2026-11-14"),
        },
        lines: [
          { description: "Licences", quantity: 10, unitAmount: eur(100_000n) },
        ],
      })
      .orThrow();

    expect(t.calls[0]?.[1]).toEqual({
      tenant: "o",
      attrs: { title: "Rollout", validUntil: "2026-11-14", currency: "EUR" },
      lines: [
        {
          description: "Licences",
          quantity: 10,
          unitAmount: "100000",
          currency: "EUR",
        },
      ],
    });
    expect(quote).toMatchObject({
      revision: 2,
      company: { type: "company", id: "c1" },
      origin: { type: "deal", id: "d1" },
      totals: { total: eur(1_210_000n) },
      lines: [
        {
          unitAmount: eur(100_000n),
          taxRateBps: 2100,
          product: { type: "product", id: "p1" },
        },
      ],
      fields: { region: "eu" },
    });
    expect(quote.contact).toBeUndefined();
    expect(quote.validUntil?.toString()).toBe("2026-11-14");
  });

  it("sends, decides, revises and converts deals", async () => {
    const t = transport({
      send_quote: () => ({ ...ROW, token: "tok" }),
      decide_quote: () => ({ ...ROW, status: "accepted" }),
      revise_quote: () => ROW,
      quote_from_deal: () => ROW,
      update_quote: () => ROW,
      set_quote_lines: () => ({
        listTotal: "1",
        discountTotal: "0",
        subtotal: "1",
        taxTotal: "0",
        total: "1",
        currency: "EUR",
      }),
    });

    const quotes = createQuotes({ transport: t });
    expect((await quotes.send({ quoteId: "q1" }).orThrow()).token).toBe("tok");
    expect(
      (
        await quotes
          .decide({
            quoteId: "q1",
            decision: "accepted",
            options: { by: "Els" },
          })
          .orThrow()
      ).status,
    ).toBe("accepted");
    await quotes.revise({ quoteId: "q1" }).orThrow();
    await quotes.fromDeal("d1").orThrow();
    await quotes.update({ quoteId: "q1", input: { note: null } }).orThrow();
    expect(
      (await quotes.setLines({ quoteId: "q1", lines: [] }).orThrow()).total,
    ).toEqual(eur(1n));
    expect(t.calls[1]?.[1]).toEqual({
      quote: "q1",
      decision: "accepted",
      note: null,
      by: "Els",
      selected: null,
    });
  });

  it("leaves a catalog line's price and title to the database", async () => {
    const t = transport({
      set_quote_lines: () => ({
        listTotal: "5000",
        discountTotal: "0",
        subtotal: "5000",
        taxTotal: "0",
        total: "5000",
        currency: "EUR",
      }),
    });

    const quotes = createQuotes({ transport: t });
    await quotes
      .setLines({
        quoteId: "q1",
        lines: [
          { product: { type: "product_variant", id: "v1" }, quantity: 2 },
          { description: "Setup", unitAmount: eur(1000n) },
        ],
      })
      .orThrow();

    expect(t.calls[0]?.[1]).toEqual({
      parent: "q1",
      lines: [
        { product: { type: "product_variant", id: "v1" }, quantity: 2 },
        { description: "Setup", unitAmount: "1000", currency: "EUR" },
      ],
    });
  });

  it("serves the customer's page and answers", async () => {
    const t = transport({
      public_quote: () => ({
        identifier: "Q-1",
        revision: 1,
        title: "Rollout",
        status: "viewed",
        currency: "EUR",
        validUntil: null,
        terms: null,
        subtotal: "10",
        discountTotal: "0",
        taxTotal: "2",
        total: "12",
        lines: [LINE],
      }),
      respond_to_quote: () => ({ status: "accepted", identifier: "Q-1" }),
      expire_quotes: () => 3,
    });

    const quotes = createQuotes({ transport: t });
    expect(await quotes.view("tok").orThrow()).toMatchObject({
      status: "viewed",
      totals: { listTotal: eur(10n), total: eur(12n) },
      pricing: { pricesIncludeTax: false, depositDue: eur(0n) },
      taxLines: [],
    });
    expect(
      await quotes
        .respond({
          token: "tok",
          decision: "accepted",
          answer: { name: "Els" },
        })
        .orThrow(),
    ).toEqual({ status: "accepted", identifier: "Q-1", revision: 1 });
    expect(await quotes.expire().orThrow()).toBe(3);
    expect(t.calls[1]?.[1]).toEqual({
      token: "tok",
      decision: "accepted",
      name: "Els",
      note: null,
      selected: null,
    });
  });
});

describe("quotes block, defaults", () => {
  it("decides without options, reads a decided quote and a dated public page", async () => {
    const decided = {
      ...ROW,
      status: "rejected",
      contact_type: "person",
      contact_id: "p1",
      origin_type: null,
      origin_id: null,
      viewed_at: "2026-10-16T09:00:00Z",
      decided_at: "2026-10-17T09:00:00Z",
      decided_by: "Els",
      decision_note: "Too high",
      lines: [
        {
          ...LINE,
          product: null,
          quantity: null,
          discountBps: null,
          taxRateBps: null,
        },
      ],
    };

    const t = transport({
      decide_quote: () => decided,
      public_quote: () => ({
        identifier: "Q-1",
        revision: null,
        title: "Rollout",
        status: "sent",
        currency: "EUR",
        validUntil: "2026-11-14",
        terms: "Net 30",
        subtotal: "10",
        discountTotal: "0",
        taxTotal: "2",
        total: "12",
        lines: [],
      }),
      respond_to_quote: () => ({
        status: "changes_requested",
        identifier: "Q-1",
        revision: 1,
      }),
    });

    const quotes = createQuotes({ transport: t });

    const quote = await quotes
      .decide({ quoteId: "q1", decision: "rejected" })
      .orThrow();

    expect(quote).toMatchObject({
      contact: { type: "person", id: "p1" },
      decidedBy: "Els",
      decisionNote: "Too high",
    });
    expect(quote.origin).toBeUndefined();
    expect(quote.lines[0]).toMatchObject({
      quantity: 1,
      discountBps: 0,
      taxRateBps: 0,
    });
    expect(quote.lines[0]?.product).toBeUndefined();
    expect(t.calls[0]?.[1]).toEqual({
      quote: "q1",
      decision: "rejected",
      note: null,
      by: null,
      selected: null,
    });
    const page = await quotes.view("tok").orThrow();
    expect(page).toMatchObject({ revision: 1, terms: "Net 30" });
    expect(page.validUntil?.toString()).toBe("2026-11-14");
    await quotes
      .respond({
        token: "tok",
        decision: "changes_requested",
        answer: { name: "Els", note: "Fewer seats" },
      })
      .orThrow();
    expect(t.calls[2]?.[1]).toMatchObject({ note: "Fewer seats" });
  });
});

describe("quote fields", () => {
  const schema = v.object({ region: v.picklist(["eu", "us"]) });

  it("sends checked fields inside attrs and parses the row's fields", async () => {
    const t = transport({
      create_quote: () => ({ ...ROW, fields: { region: "us" } }),
      update_quote: () => ROW,
    });

    const quotes = createQuotes({ transport: t, fields: schema });

    const bad = await quotes.create({
      organizationId: "o",
      input: {
        title: "Rollout",
        // @ts-expect-error not one of the regions
        fields: { region: "apac" },
      },
    });

    expect(bad).toMatchObject({ ok: false, error: { kind: "validation" } });
    expect(t.calls).toHaveLength(0);

    const quote = await quotes
      .create({
        organizationId: "o",
        input: { title: "Rollout", fields: { region: "us" } },
      })
      .orThrow();

    expect(t.calls[0]?.[1]).toMatchObject({
      attrs: { title: "Rollout", fields: { region: "us" } },
    });
    expectTypeOf(quote.fields.region).toEqualTypeOf<"eu" | "us">();
    expect(quote.fields).toEqual({ region: "us" });

    const updated = await quotes
      .update({ quoteId: "q1", input: { note: "x" } })
      .orThrow();

    expect(t.calls[1]?.[1]).toEqual({ quote: "q1", attrs: { note: "x" } });
    expect(updated.fields).toEqual({ region: "eu" });
  });
});

describe("quote documents", () => {
  const DOCUMENT = {
    ...ROW,
    prices_include_tax: true,
    discount_bps: 0,
    discount_amount: "1000",
    deposit_bps: 3000,
    deposit_due: "6600",
    decided_user_id: "g1",
    decided_ip: "10.0.0.1",
    decided_user_agent: "Browser/1",
    lines: [
      {
        ...LINE,
        position: 1,
        section: "Work",
        optional: false,
        selected: true,
      },
      { ...LINE, position: 2, optional: true, selected: false },
      { ...LINE, position: 3, optional: true },
    ],
    taxLines: [
      {
        taxRateBps: 2100,
        taxCode: "S",
        net: "9565",
        tax: "2009",
        gross: "11574",
        discount: "526",
      },
      { taxRateBps: 0, net: "10" },
    ],
  };

  it("reads pricing, sections, optional lines and tax per rate", async () => {
    const t = transport({ create_quote: () => DOCUMENT });

    const quote = await createQuotes({ transport: t })
      .create({
        organizationId: "o",
        input: {
          title: "Fit-out",
          pricesIncludeTax: true,
          discountAmount: eur(1000n),
          depositBps: 3000,
        },
        lines: [
          {
            description: "Support",
            unitAmount: eur(10_000n),
            section: "Extras",
            optional: true,
          },
        ],
      })
      .orThrow();

    expect(t.calls[0]?.[1]).toMatchObject({
      attrs: {
        title: "Fit-out",
        pricesIncludeTax: true,
        discountAmount: "1000",
        depositBps: 3000,
      },
      lines: [{ section: "Extras", optional: true }],
    });
    expect(quote).toMatchObject({
      decidedUserId: "g1",
      decidedIp: "10.0.0.1",
      decidedUserAgent: "Browser/1",
      pricing: {
        pricesIncludeTax: true,
        discountBps: 0,
        discountAmount: eur(1000n),
        depositBps: 3000,
        depositDue: eur(6600n),
      },
      lines: [
        { position: 1, section: "Work", optional: false, selected: true },
        { position: 2, optional: true, selected: false },
        { position: 3, optional: true, selected: false },
      ],
      taxLines: [
        {
          taxRateBps: 2100,
          taxCode: "S",
          net: eur(9565n),
          tax: eur(2009n),
          gross: eur(11_574n),
          discount: eur(526n),
        },
        { taxRateBps: 0, net: eur(10n), tax: eur(0n), discount: eur(0n) },
      ],
    });
    expect(quote.fields).toEqual({ region: "eu" });
    expect(quote.taxLines[1]?.taxCode).toBeUndefined();
  });

  it("passes the optional lines a customer takes and reads versions", async () => {
    const t = transport({
      decide_quote: () => DOCUMENT,
      respond_to_quote: () => ({
        status: "accepted",
        identifier: "Q-1",
        revision: 2,
      }),
      quote_versions: () => [
        {
          revision: 1,
          total: "22000",
          currency: "EUR",
          publishedAt: "2026-10-15T09:00:00Z",
          publishedBy: "u1",
        },
        {
          revision: 2,
          total: "1",
          currency: "EUR",
          publishedAt: "2026-10-16T09:00:00Z",
        },
      ],
      quote_version: () => ({
        ...DOCUMENT,
        revision: 1,
        publishedAt: "2026-10-15T09:00:00Z",
      }),
    });

    const quotes = createQuotes({ transport: t });
    await quotes
      .decide({
        quoteId: "q1",
        decision: "accepted",
        options: { selected: [2] },
      })
      .orThrow();
    expect(t.calls[0]?.[1]).toMatchObject({ selected: [2] });
    expect(
      await quotes
        .respond({
          token: "tok",
          decision: "accepted",
          answer: { name: "Els", selected: [2, 3] },
        })
        .orThrow(),
    ).toEqual({ status: "accepted", identifier: "Q-1", revision: 2 });
    expect(t.calls[1]?.[1]).toMatchObject({ selected: [2, 3] });

    const versions = await quotes.versions("q1").orThrow();
    expect(versions).toMatchObject([
      { revision: 1, total: eur(22_000n), publishedBy: "u1" },
      { revision: 2, total: eur(1n) },
    ]);
    expect(versions[1]?.publishedBy).toBeUndefined();
    expect(versions[0]?.publishedAt.toString()).toBe("2026-10-15T09:00:00Z");

    const version = await quotes
      .version({ quoteId: "q1", revision: 1 })
      .orThrow();

    expect(t.calls[3]?.[1]).toEqual({ quote: "q1", revision: 1 });
    expect(version).toMatchObject({
      revision: 1,
      quote: { id: "q1", revision: 1 },
    });
    expect(version.quote.fields).toEqual({ region: "eu" });
  });

  it("serves a signed-in guest without a token", async () => {
    const t = transport({
      portal_quote: () => ({
        identifier: "Q-1",
        revision: 2,
        title: "Fit-out",
        status: "viewed",
        currency: "EUR",
        pricesIncludeTax: true,
        discountBps: 500,
        discountAmount: "0",
        depositBps: null,
        depositDue: "0",
        listTotal: "100",
        subtotal: "90",
        discountTotal: "10",
        taxTotal: "0",
        total: "90",
        lines: [{ ...LINE, position: 1, optional: false, selected: true }],
        taxLines: [
          { taxRateBps: 0, net: "90", tax: "0", gross: "90", discount: "10" },
        ],
      }),
      respond_to_portal_quote: () => ({
        status: "rejected",
        identifier: "Q-1",
        revision: 2,
      }),
    });

    const quotes = createQuotes({ transport: t });
    const page = await quotes.portalView({ quoteId: "q1" }).orThrow();
    expect(page).toMatchObject({
      pricing: { pricesIncludeTax: true, discountBps: 500 },
      totals: {
        listTotal: eur(100n),
        discountTotal: eur(10n),
        total: eur(90n),
      },
      taxLines: [{ discount: eur(10n) }],
    });
    expect(page.pricing.depositBps).toBeUndefined();
    expect(t.calls[0]?.[1]).toEqual({ quote: "q1" });

    await quotes
      .portalRespond({ quoteId: "q1", decision: "rejected" })
      .orThrow();
    await quotes
      .portalRespond({
        quoteId: "q1",
        decision: "accepted",
        answer: { name: "Els", note: "Yes", selected: [1] },
      })
      .orThrow();
    expect(t.calls[1]?.[1]).toEqual({
      quote: "q1",
      decision: "rejected",
      name: null,
      note: null,
      selected: null,
    });
    expect(t.calls[2]?.[1]).toEqual({
      quote: "q1",
      decision: "accepted",
      name: "Els",
      note: "Yes",
      selected: [1],
    });
  });
});
