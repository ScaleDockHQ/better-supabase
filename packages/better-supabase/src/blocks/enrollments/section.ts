import type { Section } from "../sections.ts";
import type { Enrollment, Enrollments } from "./enrollments.ts";

import { defineSection } from "../sections.ts";

/** A record's enrollments: the programs it is in, with their progress. */
export const enrollmentsSection: Section<Enrollments, readonly Enrollment[]> =
  defineSection({
    permissions: { read: "read", write: "enroll" },
    module: "enrollments",
    load: (client: Enrollments, subject) => client.list({ subject }),
    events: [
      "enrollment.created",
      "enrollment.step_completed",
      "enrollment.completed",
      "enrollment.cancelled",
    ],
  });
