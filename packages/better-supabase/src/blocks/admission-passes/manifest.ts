import type { BlockOf } from "../define-block.ts";
import type { AdmissionPassesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createAdmissionPasses } from "./admission-passes.ts";
import { admissionPassesEvents } from "./events.ts";
import { admissionPassesSqlOptions } from "./options.ts";
import { admissionPassesBinding } from "./record-binding.ts";
import { passInputSchema } from "./schemas.ts";

/** The `passes` block's manifest (ADR 0029). */
export const admissionPassesBlock: BlockOf<
  "admission-passes",
  typeof createAdmissionPasses,
  AdmissionPassesEvents,
  Record<never, never>,
  never,
  typeof admissionPassesBinding
> = defineBlock({
  name: "admission-passes",
  sql: ["admission-passes"],
  options: { "admission-passes": admissionPassesSqlOptions },
  events: admissionPassesEvents,
  schemas: { pass: { input: passInputSchema } },
  create: createAdmissionPasses,
  record: admissionPassesBinding,
  category: "scheduling",
});
