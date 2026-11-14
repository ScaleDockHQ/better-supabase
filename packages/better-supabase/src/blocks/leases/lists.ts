import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `leasePage`, `leaseFacets` and `leaseCount` accept for a lease (ADR
 * 0749). The manifest declares the same names, and the SQL list function
 * `list_leases` implements them.
 */
export const leaseListSurface: EntityListSurface = {
  sorts: ["startsOn", "endsOn", "createdAt"],
  facets: ["status", "unitId"],
  filters: ["status", "unitId", "partyType", "partyId"],
};
