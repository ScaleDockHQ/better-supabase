import { describe, expect, it } from "vitest";

import { createDocumentTemplates } from "../../../src/blocks/document-templates/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-30T10:00:00Z";

const row = (extra: Record<string, unknown> = {}) => ({
  id: "t1",
  organizationId: "org-1",
  legalEntityId: "le1",
  documentType: "quote",
  language: null,
  name: "letter",
  body: "x",
  version: 1,
  active: false,
  createdAt: AT,
  updatedAt: AT,
  ...extra,
});

const block = {
  id: "b1",
  organizationId: "org-1",
  key: "footer",
  legalEntityId: "le1",
  language: "de",
  body: "Danke",
  version: 3,
  createdAt: AT,
  updatedAt: AT,
};

const VARIABLES = {
  document: {},
  entity: {},
  buyer: {},
  lines: [],
  tax_lines: [],
  totals: {},
  payment_terms: {},
};

const rendered = (extra: Record<string, unknown> = {}) => ({
  contractVersion: 1,
  documentType: "statement",
  documentId: "d1",
  legalEntityId: null,
  language: null,
  variables: VARIABLES,
  template: null,
  blocks: null,
  frozen: true,
  frozenAt: AT,
  snapshotId: "s1",
  ...extra,
});

describe("createDocumentTemplates with every option set", () => {
  const make = (
    fns: Record<string, (args: Record<string, unknown>) => unknown>,
  ) => {
    const t = fieldsTransport(fns);

    return {
      t,
      templates: createDocumentTemplates({ transport: t, tenant: "org-1" }),
    };
  };

  it("passes filters, names and entities through", async () => {
    const { t, templates } = make({
      list_document_templates: () => [row()],
      get_document_template: () => row(),
      set_document_template_active: () => row({ active: true }),
      list_document_text_blocks: () => [block],
      save_document_text_block: () => block,
      save_document_template: () => row(),
    });

    const listed = await templates
      .listTemplates({
        documentType: "quote",
        legalEntityId: "le1",
        activeOnly: true,
      })
      .orThrow();

    expect(listed[0]?.documentType).toBe("quote");
    expect(await templates.listTemplates().orThrow()).toHaveLength(1);
    expect((await templates.getTemplate("t1").orThrow()).name).toBe("letter");
    expect(
      (await templates.setTemplateActive("t1", true).orThrow()).active,
    ).toBe(true);

    const blocks = await templates
      .listTextBlocks({ key: "footer", legalEntityId: "le1" })
      .orThrow();

    expect(blocks[0]?.language).toBe("de");
    expect(await templates.listTextBlocks().orThrow()).toHaveLength(1);

    await templates
      .saveTextBlock({
        key: "footer",
        body: "Danke",
        language: "de",
        legalEntityId: "le1",
      })
      .orThrow();
    await templates
      .saveTemplate({
        documentType: "quote",
        body: "x",
        name: "letter",
        legalEntityId: "le1",
        active: false,
      })
      .orThrow();

    expect(
      t.calls.find(([fn]) => fn === "list_document_templates")?.[1],
    ).toEqual({
      tenant: "org-1",
      document_type: "quote",
      legal_entity_id: "le1",
      active_only: true,
    });
  });

  it("resolves with names and reads every source and type", async () => {
    const sources = [
      "entity_language",
      "entity",
      "organization_language",
      "organization",
      "entity_other_language",
      "anything else",
    ];

    const types = [
      "invoice",
      "credit_note",
      "quote",
      "order",
      "dunning_letter",
      "delivery_note",
      "statement",
    ];

    const queue = types.map((documentType, index) => ({
      ...row({ documentType }),
      source: sources[index % sources.length],
    }));

    const { templates } = make({
      resolve_document_template: () => queue.shift(),
    });

    for (const type of types) {
      const resolved = await templates
        .resolveTemplate({
          documentType: "quote",
          legalEntityId: "le1",
          language: "nl",
          name: "letter",
        })
        .orThrow();

      expect(resolved?.documentType).toBe(type);
    }
  });

  it("rejects an unknown document type from the database", async () => {
    const { templates } = make({
      get_document_template: () => row({ documentType: "memo" }),
    });

    await expect(
      templates.getTemplate("t1").then((result) => result.ok),
    ).resolves.toBe(false);
  });

  it("renders frozen statements and freezes with options", async () => {
    const { t, templates } = make({
      render_document: () => rendered(),
      freeze_document: () => rendered({ blocks: { a: 1 } }),
    });

    const doc = await templates
      .render({
        documentType: "statement",
        documentId: "d1",
        language: "de",
        fresh: true,
        templateName: "letter",
      })
      .orThrow();

    expect(doc.frozen).toBe(true);
    expect(doc.blocks).toEqual({});
    expect(doc.frozenAt?.toString()).toBe(AT);
    expect(doc.snapshotId).toBe("s1");

    const frozen = await templates
      .freeze({
        documentType: "statement",
        documentId: "d1",
        language: "de",
        templateName: "letter",
      })
      .orThrow();

    expect(frozen.blocks["a"]).toBe("1");
    expect(t.calls.at(-1)?.[1]).toMatchObject({
      language: "de",
      template_name: "letter",
    });
  });

  it("reads a text-block validation and the issue codes", async () => {
    const { templates } = make({
      validate_document_template: () => [
        { code: "DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE", message: "m", tag: "t" },
        { code: "DOCUMENT_TEMPLATE_UNKNOWN_FILTER", message: "m", tag: "t" },
        { code: "something", message: "m", tag: "t" },
      ],
    });

    const issues = await templates
      .validate({ documentType: "invoice", body: "x", textBlock: true })
      .orThrow();

    expect(issues.map((issue) => issue.code)).toEqual([
      "DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE",
      "DOCUMENT_TEMPLATE_UNKNOWN_FILTER",
      "DOCUMENT_TEMPLATE_SYNTAX",
    ]);
  });

  it("accepts a logger", async () => {
    const noop = (): void => {};

    const templates = createDocumentTemplates({
      transport: fieldsTransport({ get_document_template: () => row() }),
      tenant: "org-1",
      logger: { debug: noop, info: noop, warn: noop, error: noop },
    });

    expect((await templates.getTemplate("t1")).ok).toBe(true);
  });

  it("needs an organization for the organization-scoped calls", async () => {
    const templates = createDocumentTemplates({
      transport: fieldsTransport({}),
    });

    const result = await templates.listTemplates();

    expect(result.ok).toBe(false);
  });
});
