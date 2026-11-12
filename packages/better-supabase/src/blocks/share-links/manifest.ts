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
  entities: {
    share_link: { mutability: "state-machine", emits: { create: true } },
  },
  description:
    "Hashed share links, view counts and per-user state. The token is returned once. Resolving a link hashes the token the caller presents, so a stored plaintext token keeps working after it is hashed. A link can take a password, checked with bcrypt and rate-limited per link, and turn off downloads.",
  recipes: ["share-link-dialog", "file-request-upload"],
});
