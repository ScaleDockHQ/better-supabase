import type { BlockOf } from "../define-block.ts";
import type { DocumentsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createDocuments } from "./documents.ts";
import { documentsEvents } from "./events.ts";
import { documentsSqlOptions } from "./options.ts";

/** The `documents` block's manifest (ADR 0029). */
export const documentsBlock: BlockOf<
  "documents",
  typeof createDocuments,
  DocumentsEvents
> = defineBlock({
  name: "documents",
  sql: ["documents"],
  options: {
    documents: documentsSqlOptions,
  },
  events: documentsEvents,
  create: createDocuments,
  category: "content",
  recipes: ["document-editor"],
});
