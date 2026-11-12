import type { BlockOf } from "../define-block.ts";
import type { SavedViewsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { savedViewsEvents } from "./events.ts";
import { createSavedViews } from "./saved-views.ts";

/** The `saved-views` block's manifest (ADR 0029). */
export const savedViewsBlock: BlockOf<
  "saved-views",
  typeof createSavedViews,
  SavedViewsEvents
> = defineBlock({
  name: "saved-views",
  sql: ["saved-views"],
  events: savedViewsEvents,
  create: createSavedViews,
  client: "saved-views",
  category: "work",
  entities: {
    saved_view: {
      mutability: "editable",
      emits: { create: true, update: true, delete: true },
    },
  },
  description:
    "Named, ranked list states (filters, sort, columns, grouping, density) for one user, a team or the whole tenant.",
  recipes: ["record-form", "record-grid", "work-item-grid"],
});
