import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `levelPage`, `levelFacets` and `levelCount` accept (ADR 1077). The
 * manifest declares the same names, and the SQL list function
 * `page_inventory_levels` implements them. `status` takes `in_stock`, `low` or
 * `out`; `q` matches a variant or location id.
 */
export const stockLevelListSurface: EntityListSurface = {
  sorts: ["available", "onHand", "variantId"],
  facets: ["status", "locationId"],
  filters: ["status", "variantId", "locationId"],
  search: ["variantId", "locationId"],
};

/**
 * What `movementPage`, `movementFacets` and `movementCount` accept; the SQL
 * function is `page_inventory_movements`. `q` matches the kind and the document
 * id.
 */
export const stockMovementListSurface: EntityListSurface = {
  sorts: ["effectiveAt", "quantity"],
  facets: ["kind", "locationId"],
  filters: [
    "kind",
    "variantId",
    "locationId",
    "binId",
    "lotId",
    "documentType",
    "documentId",
  ],
  search: ["kind", "documentId"],
};

/**
 * What `lotPage`, `lotFacets` and `lotCount` accept; the SQL function is
 * `page_inventory_lots`. `expiry` takes `expired`, `soon`, `later` or `none`,
 * and `q` matches the lot code.
 */
export const stockLotListSurface: EntityListSurface = {
  sorts: ["expiresOn", "onHand", "code"],
  facets: ["expiry", "locationId"],
  filters: ["expiry", "variantId", "locationId"],
  search: ["code"],
};
