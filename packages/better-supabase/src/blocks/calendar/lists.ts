import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What the calendar event `page`, `facets` and `count` accept (ADR 0749, 1077).
 * The manifest declares the same names, and the SQL list function
 * `page_calendar_events` implements them. `from` and `to` take one instant.
 */
export const eventListSurface: EntityListSurface = {
  sorts: ["startsAt", "title", "updatedAt"],
  facets: ["status", "calendarId"],
  filters: ["calendarId", "status", "subjectType", "subjectId", "from", "to"],
  search: ["title", "location"],
};

/** The same for a calendar, over `page_calendars`. */
export const calendarListSurface: EntityListSurface = {
  sorts: ["name"],
  facets: ["ownerType"],
  filters: ["ownerType"],
  search: ["name"],
};
