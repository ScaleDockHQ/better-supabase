import type { BlockOf } from "../define-block.ts";
import type { AiKeysEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createAiKeys } from "./ai-keys.ts";
import { aiKeysEvents } from "./events.ts";
import { batchListSurface, keyListSurface } from "./lists.ts";
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
      ...keyListSurface,
      mutability: "editable",
      emits: { create: true, update: true, delete: true },
    },
    ai_batch: {
      ...batchListSurface,
      mutability: "editable",
      emits: { create: false, update: false, delete: false },
    },
  },
  description:
    "A tenant's own provider keys as credential_ref rows, and a registry of provider batch jobs with their results and a poll claim. Sandboxes live in ai-chat.",
  recipes: ["ai-provider-settings"],
});
