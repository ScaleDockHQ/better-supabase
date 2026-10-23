import type { BlockOf } from "../define-block.ts";
import type { PassesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { passesEvents } from "./events.ts";
import { passesSqlOptions } from "./options.ts";
import { createPasses } from "./passes.ts";
import { passesBinding } from "./record-binding.ts";
import { passInputSchema } from "./schemas.ts";

/** The `passes` block's manifest (ADR 0029). */
export const passesBlock: BlockOf<
  "passes",
  typeof createPasses,
  PassesEvents,
  Record<never, never>,
  never,
  typeof passesBinding
> = defineBlock({
  name: "passes",
  sql: ["passes"],
  options: { passes: passesSqlOptions },
  events: passesEvents,
  schemas: { pass: { input: passInputSchema } },
  create: createPasses,
  record: passesBinding,
  category: "scheduling",
});
