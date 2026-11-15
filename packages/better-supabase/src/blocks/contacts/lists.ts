import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `companyPage`, `companyFacets` and `companyCount` accept for a company
 * (ADR 0749, 1077). The manifest declares the same names, and the SQL list
 * function `page_companies` implements them. A page holds the active companies;
 * `role` keeps the ones that hold any of the roles.
 */
export const companyListSurface: EntityListSurface = {
  sorts: ["name", "createdAt", "updatedAt"],
  facets: ["lifecycle", "ownerId", "supplierStatus"],
  filters: ["lifecycle", "ownerId", "role", "supplierStatus"],
  search: ["name", "domain"],
};

/**
 * What `personPage`, `personFacets` and `personCount` accept for a person. The
 * SQL list function is `page_people`.
 */
export const personListSurface: EntityListSurface = {
  sorts: ["name", "createdAt", "updatedAt"],
  facets: ["lifecycle", "ownerId", "supplierStatus"],
  filters: ["lifecycle", "ownerId", "role", "supplierStatus"],
  search: ["name", "email"],
};
