import type { EmployeeStatus } from "better-supabase/blocks/employees";

import type { EntityListMap } from "@/lib/block-entity-page";

import { defineBlockList } from "@/lib/block-list-url";

/** One employee of the directory, as the page and the list route send it. */
export interface EmployeeRow {
  readonly id: string;
  readonly name: string;
  readonly email: string | null;
  readonly jobTitle: string | null;
  readonly status: EmployeeStatus;
  readonly startDate: string | null;
}

export const employeeList = defineBlockList({
  facets: ["status"],
  sorts: ["name", "start"],
  defaultSort: "name",
  pageSize: 25,
});

/** The directory's URL names on the employees block's list. */
export const employeeMap: EntityListMap = {
  sorts: {
    name: { by: "name" },
    // Latest start first; people without a date last.
    start: { by: "startDate", direction: "desc" },
  },
  // The directory leaves offboarded people out, as the org chart does.
  defaultFilters: { status: ["preboarding", "active", "on_leave"] },
};
