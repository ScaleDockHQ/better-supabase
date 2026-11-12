import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { promptsSqlOptions } from "./options.ts";
import { createPrompts } from "./prompts.ts";

/** The `prompts` block's manifest (ADR 0029). */
export const promptsBlock: BlockOf<"prompts", typeof createPrompts> =
  defineBlock({
    name: "prompts",
    sql: ["prompts"],
    options: { prompts: promptsSqlOptions },
    create: createPrompts,
    category: "ai",
    entities: { prompt: { mutability: "read-only" } },
    description:
      "Versioned prompt templates by name, per tenant or for the whole system, with labels such as production that point at one version; only the service role reads and writes them.",
  });
