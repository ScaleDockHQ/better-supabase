import type { BlockOf } from "../define-block.ts";
import type { SavedViewsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { savedViewsEvents } from "./events.ts";
import { savedViewsSqlOptions } from "./options.ts";
import { createSavedViews } from "./saved-views.ts";

/** The `saved-views` block's manifest (ADR 0029). */
export const savedViewsBlock: BlockOf<
  "saved-views",
  typeof createSavedViews,
  SavedViewsEvents
> = defineBlock({
  name: "saved-views",
  sql: ["saved-views"],
  options: { "saved-views": savedViewsSqlOptions },
  events: savedViewsEvents,
  create: createSavedViews,
  client: "saved-views",
  category: "work",
});
