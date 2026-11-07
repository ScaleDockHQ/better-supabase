import type { BlockOptionsSchema } from "../options.ts";
import type { AiChatMessageStorage } from "./records.ts";

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
  /** `false` makes the tenant optional: chats and projects outside a tenant. */
  readonly tenant?: boolean;
  readonly messages?: AiChatMessageStorage;
  /**
   * The function that tells whether a user belongs to a team, such as
   * `public.is_team_member`.
   */
  readonly teamMembership?: string;
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
    tenant: option.boolean({ default: true }),
    messages: option.unknown<AiChatMessageStorage>({ client: true }),
    teamMembership: option.string(),
  });
