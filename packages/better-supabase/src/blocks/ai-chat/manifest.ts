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
  entities: {
    ai_chat: {
      mutability: "editable",
      emits: { create: false, update: false, delete: false },
    },
    ai_project: {
      mutability: "editable",
      emits: { update: false, delete: false },
    },
  },
  concerns: ["lifecycle"],
  description:
    "Chats, projects, participants and a message tree (or one linear list) in the canonical AI message format or the SDK's own parts, with runs (and the id of a durable engine's run), run steps for progress, a compare-and-set stream claim, harness sessions, tool approvals and policies, pending inputs, cited sources, feedback, hashed share links, a model catalog per plan, moderation events and private Realtime topics per chat and per user.",
  recipes: ["chat-with-history", "chat-message-markdown"],
  env: [
    {
      key: "AI_GATEWAY_API_KEY",
      description:
        "Server-only: the Vercel AI Gateway key the chat route calls models with (on Vercel the OIDC token works instead).",
      required: false,
    },
  ],
  routes: ["ai-chat"],
});
