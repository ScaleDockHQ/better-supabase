import type { BlockOf } from "../define-block.ts";
import type { AiKeysEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createAiKeys } from "./ai-keys.ts";
import { aiKeysEvents } from "./events.ts";
import { aiKeysSqlOptions } from "./options.ts";

/** The `ai-keys` block's manifest (ADR 0029). */
export const aiKeysBlock: BlockOf<
  "ai-keys",
  typeof createAiKeys,
  AiKeysEvents
> = defineBlock({
  name: "ai-keys",
  sql: ["ai-keys"],
  options: { "ai-keys": aiKeysSqlOptions },
  events: aiKeysEvents,
  create: createAiKeys,
  category: "ai",
  entities: {
    ai_provider_key: {
      mutability: "editable",
      emits: { create: true, update: true, delete: true },
    },
  },
  description:
    "A tenant's own provider keys as credential_ref rows, and a registry of provider batch jobs with their results and a poll claim. Sandboxes live in ai-chat.",
  recipes: ["ai-provider-settings"],
});
