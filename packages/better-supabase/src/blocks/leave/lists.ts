import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `requestPage`, `requestFacets` and `requestCount` accept for a leave
 * request (ADR 0749, 1077). The manifest declares the same names, and the SQL
 * list function `page_leave_requests` implements them. `everyone`, `userId`,
 * `employeeId`, `from` and `to` are scalar filters (a list of one): `everyone`
 * takes `"true"` and needs `leave.read`, `from` and `to` are dates and select
 * the requests that overlap them.
 */
export const leaveRequestListSurface: EntityListSurface = {
  sorts: ["startsOn", "endsOn", "createdAt"],
  facets: ["status", "typeId"],
  filters: [
    "status",
    "typeId",
    "everyone",
    "userId",
    "employeeId",
    "from",
    "to",
  ],
  search: ["note", "type"],
};
