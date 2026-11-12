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
    entities: { ai_eval: { mutability: "read-only" } },
    description:
      "Evaluation datasets of inputs and expected outputs (imported or taken from rated ai-chat replies), runs against a prompt version and model, a score per scorer and item, and a regression compare between two runs; only the service role reads and writes them.",
  });
