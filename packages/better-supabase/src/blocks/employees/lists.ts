import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `page`, `facets` and `count` accept for an employee (ADR 0749, 1077).
 * The manifest declares the same names, and the SQL list function
 * `page_employees` implements them. Listing needs `employees.read`.
 */
export const employeeListSurface: EntityListSurface = {
  sorts: ["name", "startDate"],
  facets: ["status", "employmentType", "teamId"],
  filters: ["status", "employmentType", "teamId", "managerId", "userId"],
  search: ["name", "email", "jobTitle"],
};
