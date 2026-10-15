import type { BlockOf } from "../define-block.ts";
import type { ImportsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { importsEvents } from "./events.ts";
import { createImports } from "./imports.ts";

/** The `imports` block's manifest (ADR 0029). */
export const importsBlock: BlockOf<
  "imports",
  typeof createImports,
  ImportsEvents
> = defineBlock({
  name: "imports",
  sql: ["imports"],
  events: importsEvents,
  create: createImports,
  category: "content",
});
