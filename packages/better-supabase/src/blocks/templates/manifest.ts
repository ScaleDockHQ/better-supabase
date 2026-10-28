import type { BlockOf } from "../define-block.ts";
import type { TemplatesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { templatesEvents } from "./events.ts";
import { templatesSqlOptions } from "./options.ts";
import { createTemplates } from "./templates.ts";

/** The `templates` block's manifest (ADR 0029). */
export const templatesBlock: BlockOf<
  "templates",
  typeof createTemplates,
  TemplatesEvents
> = defineBlock({
  name: "templates",
  sql: ["templates"],
  options: { templates: templatesSqlOptions },
  events: templatesEvents,
  create: createTemplates,
  category: "content",
  recipes: ["templates-gallery"],
  schedules: [
    {
      name: "recurring",
      cron: "*/5 * * * *",
      runs: "recurring.schedule()",
      description:
        "Enqueues a templates.recur job for each recurring template occurrence due in the next day.",
    },
  ],
});
