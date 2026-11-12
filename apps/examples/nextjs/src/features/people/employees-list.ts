import type { BlockListSpec } from "@/lib/block-list";

import { defineBlockList } from "@/lib/block-list";

import type { DirectoryEmployee } from "./people-queries";

export const employeeList = defineBlockList({
  facets: ["status"],
  sorts: ["name", "start", "reports"],
  defaultSort: "name",
  pageSize: 25,
});

/** The employee overview on the block list shim (EX-901). */
export const employeeSpec: BlockListSpec<DirectoryEmployee> = {
  text: (row) => [row.name, row.jobTitle, row.email],
  facets: { status: (row) => row.status },
  sorts: {
    name: (a, b) => a.name.localeCompare(b.name),
    // Latest start first; people without a date last.
    start: (a, b) => (b.startDate ?? "").localeCompare(a.startDate ?? ""),
    reports: (a, b) => b.directReports - a.directReports,
  },
};
