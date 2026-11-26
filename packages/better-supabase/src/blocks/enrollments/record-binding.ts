import type { RecordBinding } from "../record-bindings.ts";
import type { Enrollment, Enrollments } from "./enrollments.ts";

import { defineRecordBinding } from "../record-bindings.ts";

/** A record's enrollments: the programs it is in, with their progress. */
export const enrollmentsBinding: RecordBinding<
  Enrollments,
  readonly Enrollment[]
> = defineRecordBinding({
  permissions: { read: "read", write: "enroll" },
  module: "enrollments",
  // oxlint-disable-next-line typescript/no-deprecated -- the deprecated alias is still implemented until 0.70 (ADR 1077)
  get: (client: Enrollments, subject) => client.list({ subject }),
  events: [
    "enrollment.created",
    "enrollment.step_completed",
    "enrollment.completed",
    "enrollment.cancelled",
  ],
});
