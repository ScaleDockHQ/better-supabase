import * as fastXmlParser from "fast-xml-parser";
import { describe, expect, it } from "vitest";

import type { UblSource } from "../../src/e-invoicing/index.ts";

import { money } from "../../src/commerce/money.ts";
import {
  eInvoiceChannelOf,
  fromUbl,
  toUbl,
} from "../../src/e-invoicing/index.ts";

const eur = (amount: number) => money(BigInt(amount), "EUR");

const seller = {
  name: "Acme B.V.",
  endpoint: { scheme: "0106", id: "12345678" },
  address: {
    street: "Main 1",
    city: "Utrecht",
    postalCode: "3511 AA",
    country: "NL",
  },
  vatId: "NL123456789B01",
  legalId: { id: "12345678", scheme: "0106" },
  contact: { email: "billing@acme.test" },
};

const buyer = {
  name: "Buyer & Co",
  endpoint: { scheme: "0208", id: "0123456789" },
  address: { city: "Brussels", country: "BE" },
  vatId: "BE0123456789",
};

const line = (
  description: string,
  quantity: number,
  unit: number,
  taxRateBps: number,
  discountBps = 0,
  taxCode?: string,
) => ({
  description,
  quantity,
  unitAmount: eur(unit),
  discountBps,
  taxRateBps,
  ...(taxCode === undefined ? {} : { taxCode }),
});

const draft = (): UblSource => {
  const { identifier: _identifier, ...rest } = invoice();

  return rest;
};

const invoice = (overrides: Partial<UblSource> = {}): UblSource => ({
  kind: "invoice",
  identifier: "INV-0001",
  issuedOn: Temporal.PlainDate.from("2026-10-01"),
  dueOn: Temporal.PlainDate.from("2026-10-31"),
  currency: "EUR",
  termsDays: 30,
  pricesIncludeTax: false,
  note: "Thanks <3",
  lines: [
    line("Consulting", 2, 10_000, 2100, 1000),
    line("Book", 1.5, 1999, 900),
  ],
  // 2 x 100.00 less 10% is 180.00 at 21%; 1.5 x 19.99 is 29.99 (rounded) at 9%.
  totals: {
    listTotal: eur(22_999),
    discountTotal: eur(2000),
    subtotal: eur(20_999),
    taxTotal: eur(3780 + 270),
    total: eur(20_999 + 3780 + 270),
  },
  ...overrides,
});

const tags = (xml: string, name: string): string[] =>
  [...xml.matchAll(new RegExp(`<${name}[^>]*>([^<]*)</${name}>`, "g"))].map(
    (match) => match[1] ?? "",
  );

describe("toUbl", () => {
  it("writes a Peppol BIS invoice whose totals follow from the lines", () => {
    const document = toUbl(invoice(), {
      seller,
      buyer,
      payment: { iban: "NL91 ABNA 0417 1643 00", bic: "ABNANL2A" },
    });

    expect(document.type).toBe("Invoice");
    expect(document.id).toBe("INV-0001");
    expect(document.xml).toMatch(
      /^<\?xml version="1.0" encoding="UTF-8"\?>\n<Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"/,
    );
    expect(tags(document.xml, "cbc:InvoiceTypeCode")).toEqual(["380"]);
    expect(tags(document.xml, "cbc:DueDate")).toEqual(["2026-10-31"]);
    expect(tags(document.xml, "cbc:BuyerReference")).toEqual(["INV-0001"]);
    expect(tags(document.xml, "cbc:Note")).toEqual([
      "Thanks &lt;3",
      "Payment within 30 days",
    ]);
    expect(tags(document.xml, "cbc:PaymentMeansCode")).toEqual(["58"]);
    expect(document.xml).toContain("<cbc:ID>NL91ABNA0417164300</cbc:ID>");
    expect(tags(document.xml, "cbc:LineExtensionAmount")).toEqual([
      "209.99",
      "180.00",
      "29.99",
    ]);
    expect(tags(document.xml, "cbc:TaxAmount")).toEqual([
      "40.50",
      "37.80",
      "2.70",
    ]);
    expect(tags(document.xml, "cbc:TaxExclusiveAmount")).toEqual(["209.99"]);
    expect(tags(document.xml, "cbc:TaxInclusiveAmount")).toEqual(["250.49"]);
    expect(tags(document.xml, "cbc:PayableAmount")).toEqual(["250.49"]);
    expect(document.xml).not.toContain("PayableRoundingAmount");
    expect(tags(document.xml, "cbc:InvoicedQuantity")).toEqual(["2", "1.5"]);
    expect(tags(document.xml, "cbc:MultiplierFactorNumeric")).toEqual(["10"]);
    expect(tags(document.xml, "cbc:Percent")).toEqual(["21", "9", "21", "9"]);
    expect(tags(document.xml, "cbc:RegistrationName")).toEqual([
      "Acme B.V.",
      "Buyer &amp; Co",
    ]);
  });

  it("spreads a document discount over the VAT groups and rounds to the total", () => {
    const document = toUbl(
      invoice({
        lines: [line("A", 1, 10_000, 2100), line("B", 1, 5000, 900)],
        totals: {
          listTotal: eur(15_000),
          discountTotal: eur(1501),
          subtotal: eur(13_499),
          taxTotal: eur(1890 + 405),
          total: eur(13_499 + 1890 + 405 + 1),
        },
      }),
      { seller, buyer, buyerReference: "PO-7", orderReference: "PO-7" },
    );

    expect(tags(document.xml, "cbc:Amount")).toEqual(["10.01", "5.00"]);
    expect(tags(document.xml, "cbc:TaxableAmount")).toEqual(["89.99", "45.00"]);
    expect(tags(document.xml, "cbc:AllowanceTotalAmount")).toEqual(["15.01"]);
    expect(tags(document.xml, "cbc:PayableRoundingAmount")).toEqual(["0.01"]);
    expect(tags(document.xml, "cbc:PayableAmount")).toEqual(["157.95"]);
    expect(document.xml).toContain("<cac:OrderReference><cbc:ID>PO-7</cbc:ID>");
  });

  it("writes a credit note with its billing reference and exemption reasons", () => {
    const document = toUbl(
      invoice({
        kind: "credit_note",
        identifier: "CN-0001",
        lines: [line("Export", 1, 5000, 0, 0, "ae")],
        totals: {
          listTotal: eur(5000),
          discountTotal: eur(0),
          subtotal: eur(5000),
          taxTotal: eur(0),
          total: eur(5000),
        },
      }),
      { seller, buyer, billingReference: "INV-0001", paymentTerms: "Offset" },
    );

    expect(document.type).toBe("CreditNote");
    expect(document.xml).toContain("<CreditNote xmlns=");
    expect(tags(document.xml, "cbc:CreditNoteTypeCode")).toEqual(["381"]);
    expect(tags(document.xml, "cbc:CreditedQuantity")).toEqual(["1"]);
    expect(document.xml).not.toContain("cbc:DueDate");
    expect(tags(document.xml, "cbc:TaxExemptionReasonCode")).toEqual([
      "VATEX-EU-AE",
    ]);
    expect(tags(document.xml, "cbc:TaxExemptionReason")).toEqual([
      "Reverse charge",
    ]);
    expect(document.xml).toContain(
      "<cac:InvoiceDocumentReference><cbc:ID>INV-0001</cbc:ID>",
    );
  });

  it("refuses drafts, gross prices, rated exemptions and totals the lines don't give", () => {
    expect(() => toUbl(draft(), { seller, buyer })).toThrow(/draft/);
    expect(() =>
      toUbl(invoice({ pricesIncludeTax: true }), { seller, buyer }),
    ).toThrow(/net prices/);
    expect(() =>
      toUbl(invoice({ lines: [line("X", 1, 100, 2100, 0, "E")] }), {
        seller,
        buyer,
      }),
    ).toThrow(/needs a 0 rate/);
    expect(() =>
      toUbl(invoice({ totals: { ...invoice().totals, total: eur(1) } }), {
        seller,
        buyer,
      }),
    ).toThrow(/doesn't follow/);
  });

  it("takes the app's category mapping and leaves out the percent for O", () => {
    const document = toUbl(
      invoice({
        lines: [line("Fee", 1, 1000, 0)],
        totals: {
          listTotal: eur(1000),
          discountTotal: eur(0),
          subtotal: eur(1000),
          taxTotal: eur(0),
          total: eur(1000),
        },
        termsDays: 0,
      }),
      { seller, buyer, taxCategory: () => "O", unitCode: "HUR" },
    );

    expect(tags(document.xml, "cbc:Percent")).toEqual([]);
    expect(document.xml).toContain('unitCode="HUR"');
    expect(document.xml).not.toContain("cac:PaymentTerms");
  });
});

describe("fromUbl", () => {
  it("reads a written invoice back into a purchase bill", async () => {
    const document = toUbl(invoice(), {
      seller,
      buyer,
      orderReference: "PO-1",
    });

    const bill = await fromUbl(document.xml);

    expect(bill).toMatchObject({
      kind: "invoice",
      identifier: "INV-0001",
      currency: "EUR",
      orderReference: "PO-1",
      seller: {
        name: "Acme B.V.",
        endpoint: { scheme: "0106", id: "12345678" },
        vatId: "NL123456789B01",
        legalId: { id: "12345678", scheme: "0106" },
        contact: { email: "billing@acme.test" },
        address: { city: "Utrecht", postalCode: "3511 AA", country: "NL" },
      },
      buyer: { name: "Buyer & Co", address: { country: "BE" } },
      input: {
        title: "Acme B.V. INV-0001",
        direction: "purchase",
        supplierReference: "INV-0001",
        currency: "EUR",
        termsDays: 30,
        note: "Thanks <3",
      },
    });
    expect(bill.issuedOn.toString()).toBe("2026-10-01");
    expect(bill.dueOn?.toString()).toBe("2026-10-31");
    expect(bill.lines).toEqual([
      {
        description: "Consulting",
        quantity: 2,
        unitAmount: eur(10_000),
        discountBps: 1000,
        taxRateBps: 2100,
        taxCode: "S",
      },
      {
        description: "Book",
        quantity: 1.5,
        unitAmount: eur(1999),
        taxRateBps: 900,
        taxCode: "S",
      },
    ]);
    expect(bill.taxTotal).toEqual(eur(4050));
    expect(bill.payable).toEqual(eur(25_049));
  });

  it("keeps lines it can't price exactly as their net amount and documents' allowances as lines", async () => {
    const xml = `<?xml version="1.0"?>
<CreditNote xmlns="urn:oasis:names:specification:ubl:schema:xsd:CreditNote-2" xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2" xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
  <cbc:ID>CN-9</cbc:ID>
  <cbc:IssueDate>2026-10-02</cbc:IssueDate>
  <cbc:DocumentCurrencyCode>EUR</cbc:DocumentCurrencyCode>
  <cac:BillingReference><cac:InvoiceDocumentReference><cbc:ID>INV-8</cbc:ID></cac:InvoiceDocumentReference></cac:BillingReference>
  <cac:AccountingSupplierParty><cac:Party><cbc:EndpointID schemeID="0088">5790000435968</cbc:EndpointID><cac:PartyLegalEntity><cbc:RegistrationName>Supplier A/S</cbc:RegistrationName></cac:PartyLegalEntity></cac:Party></cac:AccountingSupplierParty>
  <cac:AccountingCustomerParty><cac:Party><cbc:EndpointID schemeID="0106">1</cbc:EndpointID><cac:PartyName><cbc:Name>Us</cbc:Name></cac:PartyName><cac:PostalAddress><cac:Country><cbc:IdentificationCode>NL</cbc:IdentificationCode></cac:Country></cac:PostalAddress></cac:Party></cac:AccountingCustomerParty>
  <cac:PaymentMeans><cbc:PaymentMeansCode>30</cbc:PaymentMeansCode><cbc:PaymentDueDate>2026-10-12</cbc:PaymentDueDate></cac:PaymentMeans>
  <cac:AllowanceCharge><cbc:ChargeIndicator>true</cbc:ChargeIndicator><cbc:AllowanceChargeReason>Freight</cbc:AllowanceChargeReason><cbc:Amount currencyID="EUR">5.00</cbc:Amount><cac:TaxCategory><cbc:ID>S</cbc:ID><cbc:Percent>25</cbc:Percent></cac:TaxCategory></cac:AllowanceCharge>
  <cac:AllowanceCharge><cbc:ChargeIndicator>false</cbc:ChargeIndicator><cbc:Amount currencyID="EUR">1.00</cbc:Amount><cac:TaxCategory><cbc:ID>S</cbc:ID><cbc:Percent>25</cbc:Percent></cac:TaxCategory></cac:AllowanceCharge>
  <cac:TaxTotal><cbc:TaxAmount currencyID="EUR">3.33</cbc:TaxAmount></cac:TaxTotal>
  <cac:LegalMonetaryTotal><cbc:PayableAmount currencyID="EUR">16.66</cbc:PayableAmount></cac:LegalMonetaryTotal>
  <cac:CreditNoteLine><cbc:ID>1</cbc:ID><cbc:CreditedQuantity unitCode="C62">3</cbc:CreditedQuantity><cbc:LineExtensionAmount currencyID="EUR">3.33</cbc:LineExtensionAmount><cac:Item><cbc:Name>Screws</cbc:Name><cac:ClassifiedTaxCategory><cbc:ID>S</cbc:ID><cbc:Percent>25</cbc:Percent></cac:ClassifiedTaxCategory></cac:Item><cac:Price><cbc:PriceAmount currencyID="EUR">1.111</cbc:PriceAmount></cac:Price></cac:CreditNoteLine>
  <cac:CreditNoteLine><cbc:ID>2</cbc:ID><cbc:CreditedQuantity unitCode="C62">1</cbc:CreditedQuantity><cbc:LineExtensionAmount currencyID="EUR">4.00</cbc:LineExtensionAmount><cac:AllowanceCharge><cbc:ChargeIndicator>true</cbc:ChargeIndicator><cbc:Amount currencyID="EUR">1.00</cbc:Amount></cac:AllowanceCharge><cac:Item><cbc:Description>Bolt</cbc:Description></cac:Item><cac:Price><cbc:PriceAmount currencyID="EUR">3.00</cbc:PriceAmount></cac:Price></cac:CreditNoteLine>
</CreditNote>`;

    const bill = await fromUbl(xml, { xmlParser: fastXmlParser });

    expect(bill.kind).toBe("credit_note");
    expect(bill.billingReference).toBe("INV-8");
    expect(bill.dueOn?.toString()).toBe("2026-10-12");
    expect(bill.seller).toEqual({
      name: "Supplier A/S",
      endpoint: { scheme: "0088", id: "5790000435968" },
      address: { country: "" },
    });
    expect(bill.lines).toEqual([
      {
        description: "Screws",
        quantity: 1,
        unitAmount: eur(333),
        taxRateBps: 2500,
        taxCode: "S",
      },
      { description: "Bolt", quantity: 1, unitAmount: eur(400), taxRateBps: 0 },
      {
        description: "Freight",
        quantity: 1,
        unitAmount: eur(500),
        taxRateBps: 2500,
        taxCode: "S",
      },
      {
        description: "Discount",
        quantity: 1,
        unitAmount: eur(-100),
        taxRateBps: 2500,
        taxCode: "S",
      },
    ]);
    expect(bill.input.termsDays).toBe(10);
  });

  it("reads a corrective invoice with party details and lines it can't price", async () => {
    const party = (role: string, inner: string) =>
      `<cac:${role}><cac:Party><cbc:EndpointID>9</cbc:EndpointID>${inner}</cac:Party></cac:${role}>`;

    const xml = `<Invoice xmlns:cac="a" xmlns:cbc="b">
  <cbc:ID>INV-3</cbc:ID>
  <cbc:IssueDate>2026-10-05</cbc:IssueDate>
  <cbc:DueDate>2026-10-01</cbc:DueDate>
  <cbc:InvoiceTypeCode>381</cbc:InvoiceTypeCode>
  <cbc:DocumentCurrencyCode>EUR</cbc:DocumentCurrencyCode>
  ${party("AccountingSupplierParty", "<cac:PartyName><cbc:Name>Shop</cbc:Name></cac:PartyName><cac:PartyTaxScheme><cbc:CompanyID>NL1</cbc:CompanyID><cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme></cac:PartyTaxScheme><cac:PartyLegalEntity><cbc:RegistrationName>Shop Holding</cbc:RegistrationName><cbc:CompanyID>77</cbc:CompanyID></cac:PartyLegalEntity><cac:Contact><cbc:Name>Ann</cbc:Name><cbc:Telephone>123</cbc:Telephone></cac:Contact>")}
  ${party("AccountingCustomerParty", "<cac:PartyName><cbc:Name>Us</cbc:Name></cac:PartyName>")}
  <cac:TaxTotal><cbc:TaxAmount>0</cbc:TaxAmount></cac:TaxTotal>
  <cac:LegalMonetaryTotal><cbc:PayableAmount>9</cbc:PayableAmount></cac:LegalMonetaryTotal>
  <cac:InvoiceLine><cbc:InvoicedQuantity>2</cbc:InvoicedQuantity><cbc:LineExtensionAmount>2.00</cbc:LineExtensionAmount><cac:Price><cbc:PriceAmount>10.00</cbc:PriceAmount><cbc:BaseQuantity>10</cbc:BaseQuantity></cac:Price></cac:InvoiceLine>
  <cac:InvoiceLine><cbc:InvoicedQuantity>-1</cbc:InvoicedQuantity><cbc:LineExtensionAmount>-3.00</cbc:LineExtensionAmount><cac:Item><cbc:Name>Return</cbc:Name></cac:Item><cac:Price><cbc:PriceAmount>3.00</cbc:PriceAmount></cac:Price></cac:InvoiceLine>
  <cac:InvoiceLine><cbc:InvoicedQuantity>1e2</cbc:InvoicedQuantity><cbc:LineExtensionAmount>4.00</cbc:LineExtensionAmount></cac:InvoiceLine>
  <cac:InvoiceLine><cbc:LineExtensionAmount>6.00</cbc:LineExtensionAmount><cac:Price><cbc:PriceAmount>6.00</cbc:PriceAmount></cac:Price></cac:InvoiceLine>
</Invoice>`;

    const bill = await fromUbl(xml, { xmlParser: fastXmlParser });

    expect(bill.kind).toBe("credit_note");
    expect(bill.input.termsDays).toBeUndefined();
    expect(bill.seller).toEqual({
      name: "Shop",
      endpoint: { scheme: "", id: "9" },
      address: { country: "" },
      vatId: "NL1",
      legalName: "Shop Holding",
      legalId: { id: "77" },
      contact: { name: "Ann", phone: "123" },
    });
    expect(
      bill.lines.map((found) => [found.quantity, found.unitAmount]),
    ).toEqual([
      [1, eur(200)],
      [1, eur(-300)],
      [1, eur(400)],
      [1, eur(600)],
    ]);
    expect(bill.lines[0]?.description).toBe("Line");
  });

  it("names what a document is missing", async () => {
    const head =
      '<Invoice xmlns:cbc="x" xmlns:cac="y"><cbc:ID>1</cbc:ID><cbc:IssueDate>2026-10-01</cbc:IssueDate><cbc:DocumentCurrencyCode>EUR</cbc:DocumentCurrencyCode>';

    await expect(
      fromUbl(`${head}</Invoice>`, { xmlParser: fastXmlParser }),
    ).rejects.toThrow(/no AccountingSupplierParty/);
    await expect(
      fromUbl(
        `${head}<cac:AccountingSupplierParty><cac:Party><cbc:EndpointID>1</cbc:EndpointID></cac:Party></cac:AccountingSupplierParty></Invoice>`,
        { xmlParser: fastXmlParser },
      ),
    ).rejects.toThrow(/has no name/);
    await expect(
      fromUbl(
        `${head}<cac:AccountingSupplierParty><cac:Party><cbc:EndpointID>1</cbc:EndpointID><cac:PartyName><cbc:Name>A</cbc:Name></cac:PartyName></cac:Party></cac:AccountingSupplierParty><cac:AccountingCustomerParty><cac:Party><cbc:EndpointID>2</cbc:EndpointID><cac:PartyName><cbc:Name>B</cbc:Name></cac:PartyName></cac:Party></cac:AccountingCustomerParty><cac:TaxTotal><cbc:TaxAmount>1.001</cbc:TaxAmount></cac:TaxTotal></Invoice>`,
        { xmlParser: fastXmlParser },
      ),
    ).rejects.toThrow(/is not an amount in EUR/);
    await expect(fromUbl("<Order/>")).rejects.toThrow(/not a UBL/);
    await expect(
      fromUbl(
        '<Invoice xmlns:cbc="x"><cbc:ID>1</cbc:ID><cbc:DocumentCurrencyCode>XXY</cbc:DocumentCurrencyCode></Invoice>',
      ),
    ).rejects.toThrow(/ISO 4217/);
    await expect(
      fromUbl(
        '<Invoice xmlns:cbc="x"><cbc:DocumentCurrencyCode>EUR</cbc:DocumentCurrencyCode></Invoice>',
      ),
    ).rejects.toThrow(/no number/);
  });
});

describe("eInvoiceChannelOf", () => {
  it("accepts apiVersion 1 and refuses others", () => {
    const channel = {
      apiVersion: 1 as const,
      key: "test",
      send: async () => ({ messageId: "m-1" }),
    };

    expect(eInvoiceChannelOf(channel)).toBe(channel);
    expect(() =>
      // @ts-expect-error a channel for a later contract.
      eInvoiceChannelOf({ ...channel, apiVersion: 2 }),
    ).toThrow(/API 2/);
  });
});
