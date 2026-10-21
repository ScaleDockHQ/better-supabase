import type { BlockOf } from "../define-block.ts";
import type { AiChatEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createAiChat } from "./ai-chat.ts";
import { aiChatEvents } from "./events.ts";
import { aiChatSqlOptions } from "./options.ts";

/** The `ai-chat` block's manifest (ADR 0029). */
export const aiChatBlock: BlockOf<
  "ai-chat",
  typeof createAiChat,
  AiChatEvents
> = defineBlock({
  name: "ai-chat",
  sql: ["ai-chat"],
  options: { "ai-chat": aiChatSqlOptions },
  events: aiChatEvents,
  create: createAiChat,
  client: "ai-chat",
  category: "ai",
  recipes: ["chat-with-history"],
});
