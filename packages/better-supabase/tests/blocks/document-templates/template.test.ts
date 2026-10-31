import { describe, expect, it } from "vitest";

import type { DocumentVariables } from "../../../src/blocks/document-templates/index.ts";

import {
  escapeHtml,
  formatDocumentDate,
  formatDocumentMoney,
  renderDocumentHtml,
  validateDocumentTemplate,
  validateDocumentTextBlock,
} from "../../../src/blocks/document-templates/index.ts";

const VARIABLES: DocumentVariables = {
  document: {
    id: "inv-1",
    type: "invoice",
    number: "2026-0001",
    title: "Consulting",
    status: "issued",
    date: "2026-10-31",
    currency: "EUR",
    language: "nl",
    note: null,
    reference: null,
    dueOn: "2026-11-30",
  },
  entity: {
    id: "le-1",
    code: "NL01",
    name: "Acme B.V.",
    address: {},
    vatNumber: null,
    cocNumber: null,
    iban: null,
    bic: null,
    logoAttachmentId: null,
  },
  buyer: {
    type: "company",
    id: "co-1",
    name: "<script>alert(1)</script> & Co",
    language: "nl",
    address: {},
    vatNumber: null,
  },
  lines: [
    {
      position: 1,
      description: "Hours",
      quantity: "2",
      unitAmount: "5000",
      amount: "10000",
      taxCode: null,
      taxRateBps: 2100,
    },
    {
      position: 2,
      description: 'Travel "far"',
      quantity: "1",
      unitAmount: "123456",
      amount: "123456",
      taxCode: null,
      taxRateBps: 2100,
    },
  ],
  tax_lines: [],
  totals: {
    currency: "EUR",
    listTotal: "133456",
    discountTotal: "0",
    subtotal: "133456",
    taxTotal: "28026",
    total: "161482",
  },
  payment_terms: {},
} as unknown as DocumentVariables;

const render = (template: string, blocks: Record<string, string> = {}) =>
  renderDocumentHtml({
    documentType: "invoice",
    template,
    variables: VARIABLES,
    blocks,
  });

const htmlOf = (template: string, blocks: Record<string, string> = {}) => {
  const result = render(template, blocks);

  if (!result.ok) {
    throw new Error(result.error.message);
  }

  return result.data;
};

describe("escapeHtml", () => {
  it("escapes the five characters that matter in HTML", () => {
    expect(escapeHtml(`<a href="x">Tom & 'Jerry'</a>`)).toBe(
      "&lt;a href=&quot;x&quot;&gt;Tom &amp; &#39;Jerry&#39;&lt;/a&gt;",
    );
  });
});

describe("formatDocumentMoney", () => {
  it("formats minor units for a locale without a float", () => {
    expect(formatDocumentMoney("161482", "EUR", "en")).toBe("€1,614.82");
    expect(formatDocumentMoney("-5", "EUR", "en")).toBe("-€0.05");
    expect(formatDocumentMoney("9007199254740993123", "EUR", "en")).toContain(
      "90,071,992,547,409,931.23",
    );
  });

  it("uses the currency's digits", () => {
    expect(formatDocumentMoney("1500", "JPY", "en")).toBe("¥1,500");
  });

  it("returns text that is not an integer unchanged", () => {
    expect(formatDocumentMoney("12.5", "EUR", "en")).toBe("12.5");
  });
});

describe("formatDocumentDate", () => {
  it("formats an ISO date in UTC", () => {
    expect(formatDocumentDate("2026-10-31", "en")).toBe("Oct 31, 2026");
    expect(formatDocumentDate("not a date", "en")).toBe("not a date");
  });
});

describe("validateDocumentTemplate", () => {
  it("accepts the contract's variables, each, if and text blocks", () => {
    expect(
      validateDocumentTemplate(
        "invoice",
        "{{texts.footer}}{{#each lines as line}}{{line.description}} {{line.amount | money}}{{/each}}{{#if document.note}}{{document.note}}{{else}}none{{/if}}",
      ),
    ).toEqual([]);
  });

  it("names an unknown variable with its hint code", () => {
    expect(validateDocumentTemplate("invoice", "{{document.nope}}")).toEqual([
      expect.objectContaining({
        code: "DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE",
        tag: "document.nope",
      }),
    ]);
  });

  it("refuses a variable of another document type", () => {
    expect(validateDocumentTemplate("invoice", "{{shipping.carrier}}")).toEqual(
      [expect.objectContaining({ code: "DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE" })],
    );
  });

  it("refuses an unknown filter", () => {
    expect(
      validateDocumentTemplate("invoice", "{{totals.total | shout}}"),
    ).toEqual([
      expect.objectContaining({ code: "DOCUMENT_TEMPLATE_UNKNOWN_FILTER" }),
    ]);
  });

  it("refuses an unclosed block and a stray close", () => {
    expect(
      validateDocumentTemplate("invoice", "{{#each lines as line}}x"),
    ).toEqual([expect.objectContaining({ code: "DOCUMENT_TEMPLATE_SYNTAX" })]);
    expect(validateDocumentTemplate("invoice", "x{{/each}}")).toEqual([
      expect.objectContaining({ code: "DOCUMENT_TEMPLATE_SYNTAX" }),
    ]);
  });

  it("lets a text block read any document type but no texts", () => {
    expect(
      validateDocumentTextBlock("{{buyer.name}} {{document.dueOn}}"),
    ).toEqual([]);
    expect(validateDocumentTextBlock("{{texts.other}}")).toEqual([
      expect.objectContaining({ code: "DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE" }),
    ]);
  });
});

describe("renderDocumentHtml", () => {
  it("escapes every value and keeps the template's own markup", () => {
    const html = htmlOf("<h1>{{document.number}}</h1><p>{{buyer.name}}</p>");

    expect(html).toBe(
      "<h1>2026-0001</h1><p>&lt;script&gt;alert(1)&lt;/script&gt; &amp; Co</p>",
    );
  });

  it("escapes quotes so a value cannot leave an attribute", () => {
    expect(
      render(`<td title="{{lines.0.description}}">{{document.title}}</td>`).ok,
    ).toBe(false);

    const html = htmlOf(
      `{{#each lines as line}}<td title="{{line.description}}"></td>{{/each}}`,
    );

    expect(html).toContain("Travel &quot;far&quot;");
    expect(html).not.toContain('"far"');
  });

  it("formats money and dates in the document's language", () => {
    const html = htmlOf("{{totals.total | money}} {{document.dueOn | date}}");

    expect(html).toContain("1.614,82");
    expect(html).toContain("30 nov 2026");
  });

  it("repeats lines and branches on a value", () => {
    const html = htmlOf(
      "{{#each lines as line}}[{{line.position}}:{{line.description}}]{{/each}}{{#if document.note}}note{{else}}no note{{/if}}",
    );

    expect(html).toContain("[1:Hours]");
    expect(html).toContain("no note");
  });

  it("renders a text block as template text, with its values escaped", () => {
    const html = htmlOf("{{texts.footer}}", {
      footer: "<b>Pay now</b>, {{buyer.name}}",
    });

    expect(html).toBe(
      "<b>Pay now</b>, &lt;script&gt;alert(1)&lt;/script&gt; &amp; Co",
    );
  });

  it("returns the hint of the first problem before it renders anything", () => {
    const result = render("<p>{{document.nope}}</p>");

    expect(result.ok).toBe(false);
    expect(result.ok ? undefined : result.error).toMatchObject({
      kind: "invalid_request",
      hint: "DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE",
    });
  });
});
