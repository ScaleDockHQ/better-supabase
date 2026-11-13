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
  options: { documents: documentsSqlOptions },
  events: documentsEvents,
  create: createDocuments,
  category: "content",
  entities: {
    document: { mutability: "state-machine", emits: { create: true } },
    document_suggestion: { mutability: "read-only" },
  },
  concerns: ["lifecycle", "search"],
  description:
    "Yjs documents attached to any subject: an update log, a compacted snapshot, a private realtime topic per document for updates and presence, suggestions that editors accept into the log, and named versions through the versions module.",
  recipes: ["document-editor"],
});
