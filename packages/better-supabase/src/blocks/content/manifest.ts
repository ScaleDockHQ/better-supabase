import type { BlockOf } from "../define-block.ts";
import type { ContentEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createContent } from "./content.ts";
import { contentEvents } from "./events.ts";
import { contentEntryListSurface } from "./lists.ts";
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
  entities: {
    content_entry: {
      ...contentEntryListSurface,
      mutability: "editable",
      emits: { create: true, update: true },
    },
  },
  concerns: ["lifecycle", "search"],
  description:
    "Typed, localized content entries per organization, such as pages and posts, with a slug unique per type and locale. Entries are drafted, scheduled and published, optionally through approvals, and anyone can read published entries.",
  schedules: [
    {
      name: "publish",
      cron: "*/5 * * * *",
      runs: "publishDue()",
      description: "Publishes the scheduled entries whose time has come.",
    },
  ],
});
