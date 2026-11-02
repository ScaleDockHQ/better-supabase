import { describe, expect, it } from "vitest";

import {
  createTax,
  prepareTaxReturnInputSchema,
  taxBlock,
  taxCodeInputSchema,
} from "../../../src/blocks/tax/index.ts";
import { money } from "../../../src/commerce/money.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-30T10:00:00Z";

const RATE = {
  id: "r1",
  organizationId: "org-1",
  taxCodeId: "c1",
  rateBps: 2100,
  validFrom: "1970-01-01",
  validTo: null,
  createdAt: AT,
};

const CODE = {
  id: "c1",
  organizationId: "org-1",
  legalEntityId: null,
  code: "VAT21",
  name: "VAT 21%",
  type: "sales",
  salesAccountId: "acc-1",
  purchaseAccountId: null,
  returnBoxes: ["1a"],
  archivedAt: null,
  createdAt: AT,
  updatedAt: AT,
  rates: [RATE],
};

const validate = (
  schema: { "~standard": { validate: (value: unknown) => unknown } },
  value: unknown,
) => schema["~standard"].validate(value) as { issues?: unknown[] };

describe("createTax", () => {
  it("accepts a logger for its hooks", async () => {
    const tax = createTax({
      transport: fieldsTransport({ list_tax_codes: () => [CODE] }),
      tenant: "org-1",
      logger: { debug() {}, info() {}, warn() {}, error() {} },
    });

    expect(await tax.codes().orThrow()).toHaveLength(1);
  });

  it("saves and lists tax codes with their rates", async () => {
    const t = fieldsTransport({
      save_tax_code: () => CODE,
      list_tax_codes: () => [{ ...CODE, archivedAt: AT }],
    });

    const tax = createTax({ transport: t, tenant: "org-1" });

    const saved = await tax
      .saveCode({
        input: {
          code: "VAT21",
          name: "VAT 21%",
          type: "sales",
          rateBps: 2100,
          returnBoxes: ["1a"],
        },
      })
      .orThrow();

    expect(saved).toMatchObject({ id: "c1", type: "sales" });
    expect(saved.rates[0]?.validFrom.toString()).toBe("1970-01-01");
    expect(saved.rates[0]).not.toHaveProperty("validTo");

    const [archived] = await tax.codes({ includeArchived: true }).orThrow();

    expect(archived?.archivedAt?.toString()).toBe(AT);
    expect(t.calls[1]).toEqual([
      "list_tax_codes",
      { tenant: "org-1", include_archived: true, legal_entity: null },
    ]);
  });

  it("reads the rate valid on a date", async () => {
    const t = fieldsTransport({
      tax_rate_on: (args) => (args["on_date"] === "2027-01-01" ? 2300 : null),
    });

    const tax = createTax({ transport: t, tenant: "org-1" });

    expect(
      await tax.rateOn({ codeId: "c1", onDate: "2027-01-01" }).orThrow(),
    ).toBe(2300);
    expect(
      await tax.rateOn({ codeId: "c1", onDate: "1960-01-01" }).orThrow(),
    ).toBeUndefined();
  });

  it("decodes the totals of a margin scheme document", async () => {
    // Price 121000 with a cost of 80000 at 21%: the margin is 41000, so the tax
    // is round(41000 * 2100 / 12100) = 7116 and the net 121000 - 7116 = 113884.
    const t = fieldsTransport({
      compute_document_tax: () => ({
        groups: [
          {
            taxCodeId: "c2",
            code: "MARGIN",
            type: "margin",
            rateBps: 2100,
            net: "113884",
            tax: "7116",
            gross: "121000",
            discount: "0",
            showTax: false,
          },
        ],
        subtotal: "113884",
        taxTotal: "7116",
        total: "121000",
        showTaxAmount: false,
      }),
    });

    const tax = createTax({ transport: t, tenant: "org-1" });

    const result = await tax
      .computeDocumentTax({
        currency: "EUR",
        onDate: "2026-06-30",
        pricesIncludeTax: true,
        lines: [
          {
            quantity: 1,
            unitAmount: money(121_000n, "EUR"),
            unitCost: money(80_000n, "EUR"),
            taxCodeId: "c2",
          },
        ],
      })
      .orThrow();

    expect(result.showTaxAmount).toBe(false);
    expect(result.taxTotal).toEqual(money(7116n, "EUR"));
    expect(result.groups[0]?.net).toEqual(money(113_884n, "EUR"));
    expect(t.calls[0]?.[1]).toEqual({
      lines: [
        {
          quantity: 1,
          unitAmount: "121000",
          taxCodeId: "c2",
          unitCost: "80000",
        },
      ],
      on_date: "2026-06-30",
      prices_include_tax: true,
      credit_restriction_bps: 0,
    });
  });

  it("passes a credit restriction and refuses mixed currencies", async () => {
    // 100000 at 21% with 2500 bps restricted is taxed on 75000: tax 15750.
    const t = fieldsTransport({
      compute_document_tax: () => ({
        groups: [],
        subtotal: "100000",
        taxTotal: "15750",
        total: "115750",
        showTaxAmount: true,
      }),
    });

    const tax = createTax({ transport: t, tenant: "org-1" });

    const result = await tax
      .computeDocumentTax({
        currency: "EUR",
        onDate: "2026-06-30",
        creditRestrictionBps: 2500,
        lines: [
          { quantity: 1, unitAmount: money(100_000n, "EUR"), taxCodeId: "c1" },
        ],
      })
      .orThrow();

    expect(result.total).toEqual(money(115_750n, "EUR"));
    expect(t.calls[0]?.[1]).toMatchObject({ credit_restriction_bps: 2500 });

    const mixed = await tax.computeDocumentTax({
      currency: "EUR",
      onDate: "2026-06-30",
      lines: [{ quantity: 1, unitAmount: money(1n, "USD") }],
    });

    expect(mixed.ok).toBe(false);
    expect(t.calls).toHaveLength(1);
  });

  it("prepares and files a return with its sales list", async () => {
    const RETURN = {
      id: "t1",
      organizationId: "org-1",
      legalEntityId: null,
      period: "2026-Q2",
      periodStart: "2026-04-01",
      periodEnd: "2026-06-30",
      status: "prepared",
      currency: "EUR",
      boxes: {
        boxes: [
          { box: "1a", base: "100000", tax: "21000" },
          { box: "3b", base: "50000", tax: "0" },
        ],
        salesTax: "21000",
        purchaseTax: "0",
        netTax: "21000",
        issues: [
          {
            code: "EU_SALES_VAT_INVALID",
            invoiceId: "i9",
            message: "an intra-EU sale needs the customer's VAT number",
          },
        ],
      },
      euSalesList: [
        {
          customerVatNumber: "DE123456789",
          country: "DE",
          kind: "goods",
          amount: "50000",
          currency: "EUR",
          invoiceCount: 1,
        },
      ],
      preparedBy: "u1",
      preparedAt: AT,
      filedAt: null,
      createdAt: AT,
      updatedAt: AT,
    };

    const t = fieldsTransport({
      prepare_tax_return: () => RETURN,
      file_tax_return: () => ({ ...RETURN, status: "filed", filedAt: AT }),
      list_tax_returns: () => [RETURN],
    });

    const tax = createTax({ transport: t, tenant: "org-1" });

    const prepared = await tax
      .prepareReturn({
        since: "2026-04-01",
        until: "2026-06-30",
        period: "2026-Q2",
      })
      .orThrow();

    expect(prepared.boxes).toEqual([
      { box: "1a", base: 100_000n, tax: 21_000n },
      { box: "3b", base: 50_000n, tax: 0n },
    ]);
    expect(prepared.netTax).toBe(21_000n);
    expect(prepared.issues[0]?.code).toBe("EU_SALES_VAT_INVALID");
    expect(prepared.euSalesList[0]).toMatchObject({
      customerVatNumber: "DE123456789",
      kind: "goods",
      amount: money(50_000n, "EUR"),
    });
    expect((await tax.fileReturn("t1").orThrow()).status).toBe("filed");
    expect(await tax.returns().orThrow()).toHaveLength(1);
    expect(t.calls[0]).toEqual([
      "prepare_tax_return",
      {
        tenant: "org-1",
        since: "2026-04-01",
        until: "2026-06-30",
        legal_entity_id: null,
        period: "2026-Q2",
        currency: null,
      },
    ]);
  });

  it("decodes every optional field and falls back when they are missing", async () => {
    const FULL_CODE = {
      ...CODE,
      legalEntityId: "le-1",
      salesAccountId: "acc-1",
      purchaseAccountId: "acc-2",
      rates: [{ ...RATE, validTo: "2026-12-31" }],
    };

    const SPARSE_RETURN = {
      id: "t2",
      organizationId: "org-1",
      legalEntityId: "le-1",
      period: "2026-Q3",
      periodStart: "2026-07-01",
      periodEnd: "2026-09-30",
      status: "filed",
      boxes: null,
      euSalesList: [
        {
          customerVatNumber: "FR123",
          country: "FR",
          kind: "services",
          amount: "10",
          invoiceCount: 2,
        },
      ],
      filedAt: AT,
      createdAt: AT,
      updatedAt: AT,
    };

    const t = fieldsTransport({
      save_tax_code: () => FULL_CODE,
      save_tax_rate: () => ({ ...RATE, validTo: "2026-12-31" }),
      compute_document_tax: () => ({
        groups: [{ rateBps: 0, net: "5", tax: "0", gross: "5" }],
        subtotal: "5",
        taxTotal: "0",
        total: "5",
      }),
      list_tax_returns: () => [SPARSE_RETURN],
    });

    const tax = createTax({ transport: t, tenant: "org-1" });

    const code = await tax
      .saveCode({
        input: {
          code: "VAT21",
          validFrom: "2026-01-01",
          legalEntityId: "le-1",
        },
        codeId: "c1",
      })
      .orThrow();

    expect(code).toMatchObject({
      legalEntityId: "le-1",
      salesAccountId: "acc-1",
      purchaseAccountId: "acc-2",
    });
    expect(code.rates[0]?.validTo?.toString()).toBe("2026-12-31");
    expect(t.calls[0]?.[1]).toMatchObject({
      code_id: "c1",
      input: { validFrom: "2026-01-01" },
    });

    const rate = await tax
      .saveRate({
        codeId: "c1",
        rate: { rateBps: 2100, validFrom: "2026-01-01", validTo: "2026-12-31" },
      })
      .orThrow();

    expect(rate.validTo?.toString()).toBe("2026-12-31");
    expect(t.calls[1]?.[1]).toMatchObject({
      valid_from: "2026-01-01",
      valid_to: "2026-12-31",
    });

    const computed = await tax
      .computeDocumentTax({
        currency: "EUR",
        onDate: "2026-06-30",
        lines: [
          {
            quantity: 1,
            unitAmount: money(5n, "EUR"),
            discountBps: 0,
            taxRateBps: 0,
          },
        ],
      })
      .orThrow();

    expect(computed.showTaxAmount).toBe(true);
    expect(computed.groups[0]).toMatchObject({ showTax: true, rateBps: 0 });
    expect(computed.groups[0]).not.toHaveProperty("code");

    const [filed] = await tax.returns().orThrow();

    expect(filed).toMatchObject({
      status: "filed",
      legalEntityId: "le-1",
      salesTax: 0n,
      netTax: 0n,
    });
    expect(filed?.boxes).toEqual([]);
    expect(filed?.euSalesList[0]).toMatchObject({
      kind: "services",
      amount: money(10n, "EUR"),
    });
    expect(filed?.filedAt?.toString()).toBe(AT);
  });

  it("sends null for omitted dates and decodes sparse rows", async () => {
    const t = fieldsTransport({
      list_tax_codes: () => [
        { ...CODE, salesAccountId: null, purchaseAccountId: "acc-2" },
      ],
      save_tax_rate: () => RATE,
      prepare_tax_return: () => ({
        id: "t3",
        organizationId: "org-1",
        period: "2026-Q4",
        periodStart: "2026-10-01",
        periodEnd: "2026-12-31",
        status: "prepared",
        boxes: { issues: [{ code: "NO_RATE", message: "a line has no rate" }] },
        createdAt: AT,
        updatedAt: AT,
      }),
    });

    const tax = createTax({ transport: t, tenant: "org-1" });

    const [code] = await tax.codes({ legalEntityId: "le-1" }).orThrow();

    expect(code).not.toHaveProperty("salesAccountId");
    expect(code?.purchaseAccountId).toBe("acc-2");
    expect(t.calls[0]?.[1]).toMatchObject({
      include_archived: false,
      legal_entity: "le-1",
    });

    await tax.saveRate({ codeId: "c1", rate: { rateBps: 2100 } }).orThrow();

    expect(t.calls[1]?.[1]).toMatchObject({ valid_from: null, valid_to: null });

    const prepared = await tax
      .prepareReturn({ since: "2026-10-01", until: "2026-12-31" })
      .orThrow();

    expect(prepared.issues).toEqual([
      { code: "NO_RATE", message: "a line has no rate" },
    ]);
    expect(prepared.euSalesList).toEqual([]);
    expect(t.calls[2]?.[1]).toMatchObject({ period: null, currency: null });
  });

  it("needs a tenant for the organization calls", async () => {
    const tax = createTax({ transport: fieldsTransport({}) });

    expect((await tax.codes()).ok).toBe(false);
  });
});

describe("tax schemas", () => {
  it("validates a code and a return request", () => {
    expect(
      validate(taxCodeInputSchema, {
        code: "VAT21",
        name: "VAT 21%",
        type: "sales",
        returnBoxes: ["1a"],
      }).issues,
    ).toBeUndefined();
    expect(
      validate(taxCodeInputSchema, { code: "X", type: "nonsense" }).issues,
    ).toBeDefined();
    expect(
      validate(prepareTaxReturnInputSchema, {
        since: "2026-04-01",
        until: "2026-06-30",
      }).issues,
    ).toBeUndefined();
  });

  it("registers the block with its events", () => {
    expect(taxBlock.name).toBe("tax");
    expect(taxBlock.sql).toEqual(["tax"]);
  });
});
