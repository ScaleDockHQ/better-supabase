import type { BlockOf } from "../define-block.ts";
import type { AiGuardrailsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createAiGuardrails } from "./ai-guardrails.ts";
import { aiGuardrailsEvents } from "./events.ts";
import { aiGuardrailsSqlOptions } from "./options.ts";

/** The `ai-guardrails` block's manifest (ADR 0029). */
export const aiGuardrailsBlock: BlockOf<
  "ai-guardrails",
  typeof createAiGuardrails,
  AiGuardrailsEvents
> = defineBlock({
  name: "ai-guardrails",
  sql: ["ai-guardrails"],
  options: { "ai-guardrails": aiGuardrailsSqlOptions },
  events: aiGuardrailsEvents,
  create: createAiGuardrails,
  category: "ai",
  entities: { guardrail: { mutability: "state-machine" } },
  description:
    "Input and output policies per agent (prompt-injection heuristics, PII redaction, topic deny lists, a tool depth limit) and a decision log; a blocked check records guardrail.blocked. Only the service role reads and writes them.",
});
