import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `dispatch.page`, `dispatch.facets` and `dispatch.count` accept for a
 * work order (ADR 0749). The manifest declares the same names, and the SQL list
 * function `page_work_orders` implements them. `from` and `until` are
 * timestamps, each a list of one.
 */
export const workOrderListSurface: EntityListSurface = {
  sorts: ["createdAt", "startsAt", "title"],
  facets: ["status", "priority"],
  filters: [
    "status",
    "priority",
    "technicianId",
    "assetId",
    "subjectType",
    "subjectId",
    "from",
    "until",
  ],
  search: true,
};
