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
    "productId",
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

/**
 * What `locationPage`, `locationFacets` and `locationCount` accept; the SQL
 * function is `page_stock_locations`. `active` is `["true"]` or `["false"]`,
 * and `q` matches the code and the name.
 */
export const stockLocationListSurface: EntityListSurface = {
  sorts: ["code", "name"],
  facets: ["kind", "active"],
  filters: ["kind", "active"],
  search: ["code", "name"],
};

/**
 * What `binPage`, `binFacets` and `binCount` accept; the SQL function is
 * `page_stock_bins`. `active` and `hold` are `["true"]` or `["false"]`, and `q`
 * matches the code and the name.
 */
export const stockBinListSurface: EntityListSurface = {
  sorts: ["code"],
  facets: ["locationId", "active"],
  filters: ["locationId", "active", "hold"],
  search: ["code", "name"],
};

/**
 * What `variantPage`, `variantFacets` and `variantCount` accept; the SQL
 * function is `page_stock_variants`. A variant list names the catalog variants
 * a stock page selects from; `q` matches the SKU and the title.
 */
export const stockVariantListSurface: EntityListSurface = {
  sorts: ["sku", "title"],
  filters: ["productId"],
  search: ["sku", "title"],
};
