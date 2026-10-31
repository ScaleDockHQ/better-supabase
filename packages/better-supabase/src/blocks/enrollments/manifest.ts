import type { BlockOf } from "../define-block.ts";
import type { EnrollmentsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createEnrollments } from "./enrollments.ts";
import { enrollmentsEvents } from "./events.ts";
import { enrollmentsSqlOptions } from "./options.ts";
import { enrollmentsBinding } from "./record-binding.ts";

/** The `enrollments` block's manifest (ADR 0029). */
export const enrollmentsBlock: BlockOf<
  "enrollments",
  typeof createEnrollments,
  EnrollmentsEvents,
  Record<never, never>,
  never,
  typeof enrollmentsBinding
> = defineBlock({
  name: "enrollments",
  sql: ["enrollments"],
  options: { enrollments: enrollmentsSqlOptions },
  events: enrollmentsEvents,
  create: createEnrollments,
  record: enrollmentsBinding,
  category: "people",
});
