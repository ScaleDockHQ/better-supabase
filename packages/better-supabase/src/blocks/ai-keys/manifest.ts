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
  recipes: ["ai-provider-settings"],
});
