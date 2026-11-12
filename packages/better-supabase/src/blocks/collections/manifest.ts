import type { BlockOf } from "../define-block.ts";
import type { CollectionsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createCollections } from "./collections.ts";
import { collectionsEvents } from "./events.ts";

/** The `collections` block's manifest (ADR 0029). */
export const collectionsBlock: BlockOf<
  "collections",
  typeof createCollections,
  CollectionsEvents,
  { readonly notifier: "optional" }
> = defineBlock({
  name: "collections",
  sql: ["collections"],
  events: collectionsEvents,
  consumes: { notifier: "optional" },
  create: createCollections,
  category: "work",
  entities: { subject_collection: { mutability: "read-only" } },
  description:
    "Favorites (a member's ranked stars on any registered record), lists (named, static collections of one subject type owned by a user, a team or the organization) and saved items (a member's records to come back to, with a note and a reminder), with entries hidden unless the caller can read their record.",
});
