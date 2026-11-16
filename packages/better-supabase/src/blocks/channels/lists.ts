import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `page`, `facets` and `count` accept for a channel (ADR 0749, 1077). The
 * manifest declares the same names, and the SQL list function `page_channels`
 * implements them. Without `browse` the page holds the caller's channels;
 * `["true"]` reads every channel the caller can see. `includeArchived` is a
 * flag filter. `q` searches the name, the topic and the purpose.
 */
export const channelListSurface: EntityListSurface = {
  sorts: ["name", "createdAt", "lastMessageAt"],
  facets: ["visibility"],
  filters: ["visibility", "browse", "includeArchived"],
  search: ["name", "topic", "purpose"],
};
