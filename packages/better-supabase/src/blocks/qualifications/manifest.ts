import type { BlockOf } from "../define-block.ts";
import type { QualificationsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { qualificationsEvents } from "./events.ts";
import { qualificationsSqlOptions } from "./options.ts";
import { createQualifications } from "./qualifications.ts";
import {
  qualificationGrantInputSchema,
  qualificationTypeInputSchema,
} from "./schemas.ts";

/** The `qualifications` block's manifest (ADR 0029). */
export const qualificationsBlock: BlockOf<
  "qualifications",
  typeof createQualifications,
  QualificationsEvents
> = defineBlock({
  name: "qualifications",
  sql: ["qualifications"],
  options: { qualifications: qualificationsSqlOptions },
  events: qualificationsEvents,
  schemas: {
    qualification_type: { input: qualificationTypeInputSchema },
    qualification: { input: qualificationGrantInputSchema },
  },
  create: createQualifications,
  recipes: ["qualification-matrix", "my-qualifications"],
  category: "people",
  entities: {
    qualification: { mutability: "state-machine" },
    qualification_type: {
      mutability: "editable",
      emits: { create: true, update: true },
    },
    qualification_requirement: {
      mutability: "append-only",
      emits: { create: false, delete: false },
    },
  },
  concerns: ["lifecycle", "search"],
  description:
    "Qualification types (certifications, licences, skills) with a validity in months and optional evidence, requirements naming who must hold them (a role, a team, a job title, an asset kind, a segment or one holder), holdings of members, companies and assets that expire, a gap report, the holders qualified on a date, expiry notifications, and holdings granted from course certificates.",
});
