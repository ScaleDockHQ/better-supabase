import type { BlockOf } from "../define-block.ts";
import type { DocumentTemplatesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createDocumentTemplates } from "./document-templates.ts";
import { documentTemplatesEvents } from "./events.ts";

/** The `document-templates` block's manifest (ADR 0029, ADR 0145). */
export const documentTemplatesBlock: BlockOf<
  "document-templates",
  typeof createDocumentTemplates,
  DocumentTemplatesEvents
> = defineBlock({
  name: "document-templates",
  sql: ["document-templates"],
  events: documentTemplatesEvents,
  create: createDocumentTemplates,
  category: "tenancy",
});
