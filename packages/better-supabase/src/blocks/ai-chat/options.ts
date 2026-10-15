import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.ai-chat.options`. */
export type AiChatSqlOptions = {
  readonly topic?: string;
  readonly listTopic?: string;
  readonly temporaryTtl?: unknown;
  readonly staleAfter?: unknown;
  readonly sandboxIdleAfter?: number;
};

export const aiChatSqlOptions: BlockOptionsSchema<AiChatSqlOptions> =
  blockOptions<AiChatSqlOptions>({
    topic: option.string({ default: "ai-chat", client: true }),
    listTopic: option.string({ default: "ai-chats", client: true }),
    temporaryTtl: option.unknown(),
    staleAfter: option.unknown(),
    sandboxIdleAfter: option.number({ default: 600 }),
  });
