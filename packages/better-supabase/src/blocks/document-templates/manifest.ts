import type { BlockOf } from "../define-block.ts";
import type { DocumentTemplatesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createDocumentTemplates } from "./document-templates.ts";
import { documentTemplatesEvents } from "./events.ts";
import { documentTemplatesSqlOptions } from "./options.ts";

/** The `document-templates` block's manifest (ADR 0029, ADR 0145). */
export const documentTemplatesBlock: BlockOf<
  "document-templates",
  typeof createDocumentTemplates,
  DocumentTemplatesEvents
> = defineBlock({
  name: "document-templates",
  sql: ["document-templates"],
  options: { "document-templates": documentTemplatesSqlOptions },
  events: documentTemplatesEvents,
  create: createDocumentTemplates,
  category: "tenancy",
  entities: {
    document_template: {
      mutability: "editable",
      emits: { create: true, update: true },
    },
    document_text_block: {
      mutability: "editable",
      emits: { create: true, update: true },
    },
    document_snapshot: { mutability: "append-only", emits: { create: true } },
  },
  description:
    "Templates for invoices, credit notes, quotes, orders, dunning letters, delivery notes and statements per legal entity and language, reusable text blocks, one versioned variable contract per document type, and render_document, which returns the variables, the chosen template and its texts. An issued invoice or credit note is frozen with the template version it used, so rendering it again never changes it.",
});
