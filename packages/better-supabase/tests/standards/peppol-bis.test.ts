import { describe, expect, it } from "vitest";

import { money } from "../../src/commerce/money.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import {
  PEPPOL_BIS_CUSTOMIZATION,
  PEPPOL_BIS_PROFILE,
  toUbl,
} from "../../src/e-invoicing/index.ts";

const party = (name: string, country: string) => ({
  name,
  endpoint: { scheme: "0088", id: `${country}-1` },
  address: { country },
});

const eur = (amount: number) => money(BigInt(amount), "EUR");

const { xml } = toUbl(
  {
    kind: "invoice",
    identifier: "INV-1",
    issuedOn: Temporal.PlainDate.from("2026-10-01"),
    dueOn: Temporal.PlainDate.from("2026-10-15"),
    currency: "EUR",
    termsDays: 14,
    pricesIncludeTax: false,
    lines: [
      {
        description: "Work",
        quantity: 1,
        unitAmount: eur(10_000),
        discountBps: 0,
        taxRateBps: 2100,
      },
    ],
    totals: {
      listTotal: eur(10_000),
      discountTotal: eur(0),
      subtotal: eur(10_000),
      taxTotal: eur(2100),
      total: eur(12_100),
    },
  },
  { seller: party("Seller", "NL"), buyer: party("Buyer", "DE") },
);

describe(`Peppol BIS Billing ${SPEC_PINS.peppolBisBilling} on UBL ${SPEC_PINS.ubl}`, () => {
  it("names the pinned EN 16931 and Peppol releases (BT-24, BT-23)", () => {
    expect(SPEC_PINS.en16931).toBe("EN 16931-1:2017");
    expect(PEPPOL_BIS_CUSTOMIZATION).toBe(
      `urn:cen.eu:en16931:2017#compliant#urn:fdc:peppol.eu:2017:poacc:billing:${SPEC_PINS.peppolBisBilling}`,
    );
    expect(PEPPOL_BIS_PROFILE).toBe(
      "urn:fdc:peppol.eu:2017:poacc:billing:01:1.0",
    );
    expect(xml).toContain(
      `<cbc:CustomizationID>${PEPPOL_BIS_CUSTOMIZATION}</cbc:CustomizationID><cbc:ProfileID>${PEPPOL_BIS_PROFILE}</cbc:ProfileID>`,
    );
  });

  it("uses the UBL 2.1 namespaces", () => {
    expect(SPEC_PINS.ubl).toBe("2.1");
    expect(xml).toContain(
      'xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2" xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2" xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2"',
    );
  });

  it("orders the top-level elements as the UBL Invoice schema sequence", () => {
    const order = [
      "cbc:CustomizationID",
      "cbc:ProfileID",
      "cbc:ID",
      "cbc:IssueDate",
      "cbc:DueDate",
      "cbc:InvoiceTypeCode",
      "cbc:DocumentCurrencyCode",
      "cbc:BuyerReference",
      "cac:AccountingSupplierParty",
      "cac:AccountingCustomerParty",
      "cac:PaymentTerms",
      "cac:TaxTotal",
      "cac:LegalMonetaryTotal",
      "cac:InvoiceLine",
    ];

    const positions = order.map((name) => xml.indexOf(`<${name}`));

    expect(positions.every((position) => position > 0)).toBe(true);
    expect(positions).toEqual(positions.toSorted((a, b) => a - b));
  });

  it("carries the mandatory Peppol endpoints and the VAT breakdown (BG-23)", () => {
    expect(xml).toContain(
      '<cbc:EndpointID schemeID="0088">NL-1</cbc:EndpointID>',
    );
    expect(xml).toContain(
      '<cbc:EndpointID schemeID="0088">DE-1</cbc:EndpointID>',
    );
    expect(xml).toContain(
      '<cac:TaxSubtotal><cbc:TaxableAmount currencyID="EUR">100.00</cbc:TaxableAmount><cbc:TaxAmount currencyID="EUR">21.00</cbc:TaxAmount><cac:TaxCategory><cbc:ID>S</cbc:ID><cbc:Percent>21</cbc:Percent><cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme></cac:TaxCategory></cac:TaxSubtotal>',
    );
  });
});
