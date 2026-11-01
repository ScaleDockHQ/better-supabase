import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createAiEvals } from "./ai-evals.ts";
import { aiEvalsSqlOptions } from "./options.ts";

/** The `ai-evals` block's manifest (ADR 0029). */
export const aiEvalsBlock: BlockOf<"ai-evals", typeof createAiEvals> =
  defineBlock({
    name: "ai-evals",
    sql: ["ai-evals"],
    options: { "ai-evals": aiEvalsSqlOptions },
    create: createAiEvals,
    category: "ai",
  });
