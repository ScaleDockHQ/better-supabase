import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `meetings.page`, `meetings.facets` and `meetings.count` accept for a
 * meeting (ADR 0749). The manifest declares the same names, and the SQL list
 * function `list_meetings` implements them. `from` and `to` are instants, each
 * a list of one.
 */
export const meetingListSurface: EntityListSurface = {
  sorts: ["startsAt", "title"],
  facets: ["kind", "status"],
  filters: ["kind", "status", "from", "to", "attendeeId"],
  search: true,
};
