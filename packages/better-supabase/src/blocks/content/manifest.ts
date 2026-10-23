import type { BlockOf } from "../define-block.ts";
import type { ContentEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createContent } from "./content.ts";
import { contentEvents } from "./events.ts";
import { contentSqlOptions } from "./options.ts";
import { contentEntryInputSchema } from "./schemas.ts";

/** The `content` block's manifest (ADR 0029). */
export const contentBlock: BlockOf<
  "content",
  typeof createContent,
  ContentEvents
> = defineBlock({
  name: "content",
  sql: ["content"],
  options: { content: contentSqlOptions },
  events: contentEvents,
  schemas: { content_entry: { input: contentEntryInputSchema } },
  create: createContent,
  category: "content",
});
