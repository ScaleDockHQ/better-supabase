import { describe, expect, it } from "vitest";

import {
  createDocumentTemplates,
  documentTemplatesBlock,
} from "../../../src/blocks/document-templates/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-30T10:00:00Z";

const TEMPLATE = {
  id: "t1",
  organizationId: "org-1",
  legalEntityId: null,
  documentType: "invoice",
  language: "nl",
  name: "default",
  body: "<p>{{document.number}}</p>",
  version: 2,
  active: true,
  createdAt: AT,
  updatedAt: AT,
};

const VARIABLES = {
  document: { id: "d1", type: "invoice", number: "2026-1", language: "nl" },
  entity: { code: "NL01" },
  buyer: { name: "<i>Buyer</i>" },
  lines: [],
  tax_lines: [],
  totals: { total: "1000", currency: "EUR" },
  payment_terms: {},
};

const RENDERED = {
  contractVersion: 1,
  documentType: "invoice",
  documentId: "d1",
  legalEntityId: "le1",
  language: "nl",
  variables: VARIABLES,
  template: {
    id: "t1",
    name: "default",
    documentType: "invoice",
    legalEntityId: null,
    language: "nl",
    version: 2,
    body: "<p>{{document.number}} {{buyer.name}}</p>",
    source: "organization_language",
  },
  blocks: { footer: "Thanks" },
  frozen: false,
  frozenAt: null,
  snapshotId: null,
};

describe("createDocumentTemplates", () => {
  it("saves a template into the request's organization", async () => {
    const t = fieldsTransport({ save_document_template: () => TEMPLATE });

    const templates = createDocumentTemplates({
      transport: t,
      tenant: "org-1",
    });

    const saved = await templates
      .saveTemplate({
        documentType: "invoice",
        body: TEMPLATE.body,
        language: "nl",
      })
      .orThrow();

    expect(saved.version).toBe(2);
    expect(saved.legalEntityId).toBeNull();
    expect(saved.createdAt.toString()).toBe("2026-10-30T10:00:00Z");
    expect(t.calls[0]).toEqual([
      "save_document_template",
      {
        tenant: "org-1",
        document_type: "invoice",
        body: TEMPLATE.body,
        language: "nl",
        name: "default",
        legal_entity_id: null,
        active: true,
      },
    ]);
  });

  it("returns the database's hint when a template is refused", async () => {
    const templates = createDocumentTemplates({
      tenant: "org-1",
      transport: {
        call: () =>
          Promise.reject(
            Object.assign(new Error("unknown variable"), {
              code: "22023",
              hint: "DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE",
            }),
          ),
      },
    });

    const result = await templates.saveTemplate({
      documentType: "invoice",
      body: "{{nope}}",
    });

    expect(result.ok).toBe(false);
  });

  it("resolves to undefined when no template fits", async () => {
    const t = fieldsTransport({ resolve_document_template: () => null });

    const templates = createDocumentTemplates({
      transport: t,
      tenant: "org-1",
    });

    await expect(
      templates.resolveTemplate({ documentType: "quote" }).orThrow(),
    ).resolves.toBeUndefined();
  });

  it("renders a document with its template and blocks", async () => {
    const t = fieldsTransport({ render_document: () => RENDERED });

    const templates = createDocumentTemplates({
      transport: t,
      tenant: "org-1",
    });

    const rendered = await templates
      .render({ documentType: "invoice", documentId: "d1", fresh: true })
      .orThrow();

    expect(rendered.template?.source).toBe("organization_language");
    expect(rendered.blocks).toEqual({ footer: "Thanks" });
    expect(rendered.variables.buyer.name).toBe("<i>Buyer</i>");
    expect(rendered.frozenAt).toBeNull();
    expect(t.calls[0]).toEqual([
      "render_document",
      {
        tenant: "org-1",
        document_type: "invoice",
        document_id: "d1",
        language: null,
        fresh: true,
        template_name: null,
      },
    ]);
  });

  it("renders HTML with the values escaped", async () => {
    const templates = createDocumentTemplates({
      transport: fieldsTransport({ render_document: () => RENDERED }),
      tenant: "org-1",
    });

    await expect(
      templates
        .renderHtml({ documentType: "invoice", documentId: "d1" })
        .orThrow(),
    ).resolves.toBe("<p>2026-1 &lt;i&gt;Buyer&lt;/i&gt;</p>");
  });

  it("fails with a hint when no template fits", async () => {
    const templates = createDocumentTemplates({
      transport: fieldsTransport({
        render_document: () => ({ ...RENDERED, template: null }),
      }),
      tenant: "org-1",
    });

    const result = await templates.renderHtml({
      documentType: "invoice",
      documentId: "d1",
    });

    expect(result.ok ? undefined : result.error).toMatchObject({
      kind: "not_found",
      hint: "DOCUMENT_TEMPLATE_MISSING",
    });
  });

  it("rejects variables without the contract keys", async () => {
    const templates = createDocumentTemplates({
      transport: fieldsTransport({
        render_document: () => ({ ...RENDERED, variables: { document: {} } }),
      }),
      tenant: "org-1",
    });

    await expect(
      templates.render({ documentType: "invoice", documentId: "d1" }).orThrow(),
    ).rejects.toThrow(/contract keys/);
  });

  it("reads the contract and validates a body through the database", async () => {
    const t = fieldsTransport({
      document_template_contract: () => ({
        version: 1,
        documentType: "invoice",
        variables: [{ path: "totals.total", type: "money" }],
      }),
      validate_document_template: () => [
        { code: "DOCUMENT_TEMPLATE_SYNTAX", message: "unclosed", tag: "#if x" },
      ],
    });

    const templates = createDocumentTemplates({
      transport: t,
      tenant: "org-1",
    });

    await expect(templates.contract("invoice").orThrow()).resolves.toEqual({
      version: 1,
      documentType: "invoice",
      variables: [{ path: "totals.total", type: "money" }],
    });
    await expect(
      templates
        .validate({ documentType: "invoice", body: "{{#if x}}" })
        .orThrow(),
    ).resolves.toEqual([
      { code: "DOCUMENT_TEMPLATE_SYNTAX", message: "unclosed", tag: "#if x" },
    ]);
  });
});

describe("documentTemplatesBlock", () => {
  it("is the document-templates block over its SQL module", () => {
    expect(documentTemplatesBlock.name).toBe("document-templates");
    expect(documentTemplatesBlock.sql).toEqual(["document-templates"]);
  });
});
