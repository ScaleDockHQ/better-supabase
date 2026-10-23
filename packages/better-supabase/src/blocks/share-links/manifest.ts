import type { BlockOf } from "../define-block.ts";
import type { ShareLinksEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { shareLinksEvents } from "./events.ts";
import { shareLinksSqlOptions } from "./options.ts";
import { shareLinksBinding } from "./record-binding.ts";
import { createShareLinks } from "./share-links.ts";

/** The `share-links` block's manifest (ADR 0029). */
export const shareLinksBlock: BlockOf<
  "share-links",
  typeof createShareLinks,
  ShareLinksEvents,
  Record<never, never>,
  never,
  typeof shareLinksBinding
> = defineBlock({
  name: "share-links",
  sql: ["share-links"],
  options: { "share-links": shareLinksSqlOptions },
  events: shareLinksEvents,
  create: createShareLinks,
  record: shareLinksBinding,
  category: "collaboration",
  recipes: ["share-link-dialog"],
});
