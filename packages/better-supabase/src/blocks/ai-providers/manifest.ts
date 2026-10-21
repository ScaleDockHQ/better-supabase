import type { BlockOf } from "../define-block.ts";
import type { AiProvidersEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createAiProviders } from "./ai-providers.ts";
import { aiProvidersEvents } from "./events.ts";
import { aiProvidersSqlOptions } from "./options.ts";

/** The `ai-providers` block's manifest (ADR 0029). */
export const aiProvidersBlock: BlockOf<
  "ai-providers",
  typeof createAiProviders,
  AiProvidersEvents
> = defineBlock({
  name: "ai-providers",
  sql: ["ai-providers"],
  options: { "ai-providers": aiProvidersSqlOptions },
  events: aiProvidersEvents,
  create: createAiProviders,
  category: "ai",
  recipes: ["ai-provider-settings"],
});
