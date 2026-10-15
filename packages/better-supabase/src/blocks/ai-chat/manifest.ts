import type { BlockOf } from "../define-block.ts";
import type { AiChatEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { createAiChat } from "./ai-chat.ts";
import { aiChatEvents } from "./events.ts";

/** The `ai-chat` block's manifest (ADR 0029). */
export const aiChatBlock: BlockOf<
  "ai-chat",
  typeof createAiChat,
  AiChatEvents
> = defineBlock({
  name: "ai-chat",
  sql: ["ai-chat"],
  options: {
    "ai-chat": optionKeys([
      "topic",
      "listTopic",
      "temporaryTtl",
      "staleAfter",
      "sandboxIdleAfter",
    ]),
  },
  events: aiChatEvents,
  create: createAiChat,
  client: "ai-chat",
  category: "ai",
});
