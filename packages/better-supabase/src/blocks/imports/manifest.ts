import type { BlockOf } from "../define-block.ts";
import type { ImportsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { importsEvents } from "./events.ts";
import { createImports } from "./imports.ts";
import { importsSqlOptions } from "./options.ts";

/** The `imports` block's manifest (ADR 0029). */
export const importsBlock: BlockOf<
  "imports",
  typeof createImports,
  ImportsEvents
> = defineBlock({
  name: "imports",
  sql: ["imports"],
  options: { imports: importsSqlOptions },
  events: importsEvents,
  create: createImports,
  category: "database",
  entities: {
    import: { mutability: "state-machine", emits: { create: false } },
  },
  description:
    "Import runs and the external record map. import_upsert_batch writes items through the targets blocks and the app register, skips equal content, reports rows a user changed since the last import and marks missing keys on full runs. The dry run, parsing and mapping live in TypeScript.",
  recipes: ["csv-import-wizard", "upsert-import"],
});
