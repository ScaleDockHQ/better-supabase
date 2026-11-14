import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `prescriptionPage`, `prescriptionFacets` and `prescriptionCount` accept
 * for a prescription (ADR 0749, 0779). The manifest declares the same names,
 * and the SQL list function `list_prescriptions` implements them.
 */
export const prescriptionListSurface: EntityListSurface = {
  sorts: ["createdAt", "signedAt"],
  facets: ["status"],
  filters: ["status", "orderId", "subjectType", "subjectId", "prescriberId"],
};
