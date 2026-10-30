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
  recipes: ["subject-link", "subject-chip", "my-work"],
});
