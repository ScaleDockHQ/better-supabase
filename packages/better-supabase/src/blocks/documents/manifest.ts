import type { BlockOf } from "../define-block.ts";
import type { DocumentsEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { createDocuments } from "./documents.ts";
import { documentsEvents } from "./events.ts";

/** The `documents` block's manifest (ADR 0029). */
export const documentsBlock: BlockOf<
  "documents",
  typeof createDocuments,
  DocumentsEvents
> = defineBlock({
  name: "documents",
  sql: ["documents"],
  options: {
    documents: optionKeys([
      "subjects",
      "topic",
      "maxUpdateBytes",
      "compactAfter",
    ]),
  },
  events: documentsEvents,
  create: createDocuments,
  category: "content",
});
