import { describe, expect, it } from "vitest";

import type { DocumentVariables } from "../../../src/blocks/document-templates/index.ts";

import {
  formatDocumentDate,
  formatDocumentMoney,
  renderDocumentHtml,
  validateDocumentTemplate,
  validateDocumentTextBlock,
} from "../../../src/blocks/document-templates/index.ts";

const VARIABLES = {
  document: { number: "7", dueOn: "2026-11-30", note: null },
  buyer: { name: "Ada", language: "de" },
  entity: { name: "Acme" },
  lines: [
    { description: "A", amount: "100", quantity: 2 },
    { description: "B", amount: "250", quantity: true },
  ],
  totals: { total: "350" },
} as unknown as DocumentVariables;

const codes = (body: string): readonly string[] =>
  validateDocumentTemplate("invoice", body).map((issue) => issue.code);

describe("template syntax edges", () => {
  it.each([
    ["{{#each lines as line}}{{line.description}}", "DOCUMENT_TEMPLATE_SYNTAX"],
    ["{{#if document.note}}x", "DOCUMENT_TEMPLATE_SYNTAX"],
    ["{{/if}}", "DOCUMENT_TEMPLATE_SYNTAX"],
    ["{{/each}}", "DOCUMENT_TEMPLATE_SYNTAX"],
    ["{{#each lines as line}}{{/if}}", "DOCUMENT_TEMPLATE_SYNTAX"],
    ["{{else}}", "DOCUMENT_TEMPLATE_SYNTAX"],
    [
      "{{#if document.note}}a{{else}}b{{else}}c{{/if}}",
      "DOCUMENT_TEMPLATE_SYNTAX",
    ],
    ["{{#unknown thing}}", "DOCUMENT_TEMPLATE_SYNTAX"],
    ["{{ }}", "DOCUMENT_TEMPLATE_SYNTAX"],
    ["{{document.number | | money}}", "DOCUMENT_TEMPLATE_SYNTAX"],
    ["{{ not a path }}", "DOCUMENT_TEMPLATE_SYNTAX"],
    ["stray }} brace", "DOCUMENT_TEMPLATE_SYNTAX"],
    ["stray {{ brace", "DOCUMENT_TEMPLATE_SYNTAX"],
    ["{{document.number | upper}}", "DOCUMENT_TEMPLATE_UNKNOWN_FILTER"],
    ["{{document.missing}}", "DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE"],
    ["{{#if nothing.here}}x{{/if}}", "DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE"],
    ["{{#each totals as t}}x{{/each}}", "DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE"],
    ["{{#each lines as lines}}x{{/each}}", "DOCUMENT_TEMPLATE_SYNTAX"],
    [
      "{{#each lines as line}}{{line}}{{/each}}",
      "DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE",
    ],
    [
      "{{#each lines as line}}{{line.nope}}{{/each}}",
      "DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE",
    ],
    ["{{lines}}", "DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE"],
    ["{{totals}}", "DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE"],
    ["{{texts}}", "DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE"],
  ])("reports %j", (body, code) => {
    expect(codes(body)).toContain(code);
  });

  it("accepts nested blocks, else branches and text keys", () => {
    expect(
      codes(
        "{{#each lines as line}}{{#if line.amount}}{{line.amount | money}}{{else}}-{{/if}}{{/each}}{{texts.footer}}",
      ),
    ).toEqual([]);
  });

  it("checks text blocks against every document type and no texts", () => {
    expect(
      validateDocumentTextBlock("{{document.level}} {{buyer.name}}"),
    ).toEqual([]);
    expect(
      validateDocumentTextBlock("{{texts.other}}").map((issue) => issue.code),
    ).toContain("DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE");
  });
});

describe("rendering edges", () => {
  const render = (
    template: string,
    extra: Partial<Parameters<typeof renderDocumentHtml>[0]> = {},
  ) =>
    renderDocumentHtml({
      documentType: "invoice",
      template,
      variables: VARIABLES,
      ...extra,
    });

  const html = (
    template: string,
    extra: Partial<Parameters<typeof renderDocumentHtml>[0]> = {},
  ): string => {
    const result = render(template, extra);

    if (!result.ok) {
      throw new Error(result.error.message);
    }

    return result.data;
  };

  it("prints numbers and booleans and skips missing values", () => {
    expect(
      html(
        "{{#each lines as line}}[{{line.quantity}}]{{/each}}|{{document.note}}|{{entity.name}}",
      ),
    ).toBe("[2][true]||Acme");
  });

  it("takes the locale from the option or English", () => {
    expect(html("{{totals.total | money}}", { locale: "nl" })).toContain(
      "3,50",
    );
    expect(html("{{document.dueOn | date}}", { locale: "en" })).toContain(
      "Nov",
    );
    expect(html("{{totals.total | money}}")).toBe("3.50");
  });

  it("falls back to English when the document has no language", () => {
    const result = renderDocumentHtml({
      documentType: "invoice",
      template: "{{totals.total | money}}",
      variables: { totals: { total: "350" } } as unknown as DocumentVariables,
    });

    expect(result.ok && result.data).toBe("3.50");
  });

  it("branches on empty, zero and empty lists (all false)", () => {
    const body =
      "{{#if document.note}}note{{else}}none{{/if}}{{#if lines}}L{{/if}}{{#if totals.total}}T{{/if}}";

    expect(html(body)).toBe("noneLT");
    expect(
      html(body, {
        variables: {
          document: { note: "x" },
          lines: [],
          totals: { total: "0" },
        } as unknown as DocumentVariables,
      }),
    ).toBe("note");
  });

  it("renders text blocks once and not inside blocks", () => {
    expect(
      html("{{texts.a}}", {
        blocks: { a: "x {{buyer.name}} {{texts.b}}", b: "y" },
      }),
    ).toBe("x Ada ");
    expect(html("{{texts.missing}}", { blocks: {} })).toBe("");
    expect(html("{{texts.bad}}", { blocks: { bad: "{{#if nothing}}" } })).toBe(
      "",
    );
  });

  it("branches on the presence of a text block", () => {
    const body = "{{#if texts.footer}}Y{{else}}N{{/if}}";

    expect(html(body, { blocks: { footer: "x" } })).toBe("Y");
    expect(html(body)).toBe("N");
  });

  it("renders nothing for a list the document does not have", () => {
    expect(
      html("a{{#each lines as line}}{{line.description}}{{/each}}b", {
        variables: {} as unknown as DocumentVariables,
      }),
    ).toBe("ab");
  });

  it("prints nothing for a path through a missing key", () => {
    expect(
      html("[{{document.note}}][{{#if buyer.name}}{{buyer.name}}{{/if}}]", {
        variables: {
          document: { note: { deep: 1 } },
          buyer: { name: "Zed" },
        } as unknown as DocumentVariables,
      }),
    ).toBe("[][Zed]");
  });

  it("refuses an invalid template before rendering", () => {
    const result = render("{{document.missing}}");

    expect(result.ok).toBe(false);
  });
});

describe("formatters", () => {
  it("formats dates and amounts it cannot parse as given", () => {
    expect(formatDocumentDate("not a date", "en")).toBe("not a date");
    expect(formatDocumentDate("2026-10-31", "nl")).toContain("2026");
    expect(formatDocumentMoney("abc", undefined, "en")).toBe("abc");
    expect(formatDocumentMoney("1050", undefined, "en")).toBe("10.50");
    expect(formatDocumentMoney("1050", "ZZZ", "en")).toContain("10.50");
  });
});
