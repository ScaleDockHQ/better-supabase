import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createSubjects } from "./subjects.ts";

/** The `subjects` block's manifest (ADR 0029). */
export const subjectsBlock: BlockOf<"subjects", typeof createSubjects> =
  defineBlock({
    name: "subjects",
    sql: ["subjects"],
    create: createSubjects,
    category: "identity",
    recipes: ["subject-link", "subject-chip", "my-work"],
  });
