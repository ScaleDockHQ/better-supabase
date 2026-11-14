import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `shipmentPage`, `shipmentFacets` and `shipmentCount` accept for a
 * shipment (ADR 0749). The manifest declares the same names, and the SQL list
 * function `list_shipments` implements them.
 */
export const shipmentListSurface: EntityListSurface = {
  sorts: ["createdAt", "deliveredAt"],
  facets: ["status", "carrier"],
  filters: ["status", "carrier", "subjectType", "subjectId"],
};
