import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { employeesBlock } from "../employees/manifest.ts";
import { enrollmentsBlock } from "../enrollments/manifest.ts";
import { leaveBlock } from "../leave/manifest.ts";
import { payrollExportBlock } from "../payroll-export/manifest.ts";
import { qualificationsBlock } from "../qualifications/manifest.ts";
import { shiftsBlock } from "../shifts/manifest.ts";
import { createPeople } from "./people.ts";

/** The blocks `people` is made of, by block name. */
export const peopleParts: {
  readonly employees: typeof employeesBlock;
  readonly leave: typeof leaveBlock;
  readonly shifts: typeof shiftsBlock;
  readonly "payroll-export": typeof payrollExportBlock;
  readonly qualifications: typeof qualificationsBlock;
  readonly enrollments: typeof enrollmentsBlock;
} = {
  employees: employeesBlock,
  leave: leaveBlock,
  shifts: shiftsBlock,
  "payroll-export": payrollExportBlock,
  qualifications: qualificationsBlock,
  enrollments: enrollmentsBlock,
};

export type PeopleParts = typeof peopleParts;

/**
 * The `people` composite (ADR 0177): employees, leave, shifts, payroll export,
 * qualifications and enrollments. It installs its parts and sets their
 * defaults; the parts stay ordinary blocks in the config.
 */
export const peopleBlock: BlockOf<"people", typeof createPeople> = defineBlock({
  name: "people",
  composes: peopleParts,
  create: createPeople,
  category: "people",
});
