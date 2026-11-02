import { createDocumentTemplates } from "better-supabase/blocks/document-templates";

type Transport = Parameters<typeof createDocumentTemplates>[0]["transport"];

/** Renders an invoice to escaped HTML, ready for a PDF tool. */
export function invoiceHtml(transport: Transport, invoiceId: string) {
  const templates = createDocumentTemplates({ transport, tenant: "org-1" });

  return templates.renderHtml({
    documentType: "invoice",
    documentId: invoiceId,
  });
}
