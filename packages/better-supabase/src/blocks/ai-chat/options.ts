import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.ai-chat.options`. */
export type AiChatSqlOptions = {
  readonly topic?: string;
  readonly listTopic?: string;
  readonly temporaryTtl?: unknown;
  readonly staleAfter?: unknown;
  readonly sandboxIdleAfter?: number;
  readonly meterUsage?: boolean;
  readonly inputMeter?: string;
  readonly outputMeter?: string;
  readonly extraColumns?: ExtraColumns;
};

export const aiChatSqlOptions: BlockOptionsSchema<AiChatSqlOptions> =
  blockOptions<AiChatSqlOptions>({
    topic: option.string({ default: "ai-chat", client: true }),
    listTopic: option.string({ default: "ai-chats", client: true }),
    temporaryTtl: option.unknown(),
    staleAfter: option.unknown(),
    sandboxIdleAfter: option.number({ default: 600 }),
    meterUsage: option.boolean({ default: true }),
    inputMeter: option.string({ default: "ai.input_tokens" }),
    outputMeter: option.string({ default: "ai.output_tokens" }),
    extraColumns: option.extraColumns(),
  });
