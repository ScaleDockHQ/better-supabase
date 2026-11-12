import type { BlockOf } from "../define-block.ts";
import type { SubjectsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { subjectsEvents } from "./events.ts";
import { subjectsSqlOptions } from "./options.ts";
import { createSubjects } from "./subjects.ts";

/** The `subjects` block's manifest (ADR 0029). */
export const subjectsBlock: BlockOf<
  "subjects",
  typeof createSubjects,
  SubjectsEvents
> = defineBlock({
  name: "subjects",
  sql: ["subjects"],
  options: { subjects: subjectsSqlOptions },
  events: subjectsEvents,
  create: createSubjects,
  category: "identity",
  entities: {
    subject_member: { mutability: "state-machine", emits: { create: true } },
    subject: { mutability: "state-machine" },
  },
  description:
    "The app-wide subject registry from config.recordTypes: subject_title, subject_url, subject_titles, can_subject, can_subject_for and record_summary for every registered type, my_work across the installed blocks, record teams (subject_members, add_subject_member, end_subject_member, list_subject_members, my_subjects) that grant subjects.<type>.team actions, read logging for types with subjects.<type>.auditReads (record_subject_read, subject_access_log), and Realtime presence on presence:<type>:<id> for readers of the subject.",
  recipes: ["subject-link", "subject-chip", "my-work"],
});
