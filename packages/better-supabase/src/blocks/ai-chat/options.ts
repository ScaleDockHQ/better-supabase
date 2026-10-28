import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";
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
  readonly extraColumns?: ExtraColumns;
  readonly projectExtraColumns?: ExtraColumns;
  readonly participantExtraColumns?: ExtraColumns;
  readonly messageExtraColumns?: ExtraColumns;
  readonly runExtraColumns?: ExtraColumns;
  readonly approvalExtraColumns?: ExtraColumns;
  readonly policyExtraColumns?: ExtraColumns;
  readonly inputExtraColumns?: ExtraColumns;
  readonly sourceExtraColumns?: ExtraColumns;
  readonly feedbackExtraColumns?: ExtraColumns;
  readonly shareExtraColumns?: ExtraColumns;
  readonly modelExtraColumns?: ExtraColumns;
  readonly moderationExtraColumns?: ExtraColumns;
  readonly stepExtraColumns?: ExtraColumns;
  readonly sandboxExtraColumns?: ExtraColumns;
  readonly harnessExtraColumns?: ExtraColumns;
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
    extraColumns: option.extraColumns(),
    projectExtraColumns: option.extraColumns(),
    participantExtraColumns: option.extraColumns(),
    messageExtraColumns: option.extraColumns(),
    runExtraColumns: option.extraColumns(),
    approvalExtraColumns: option.extraColumns(),
    policyExtraColumns: option.extraColumns(),
    inputExtraColumns: option.extraColumns(),
    sourceExtraColumns: option.extraColumns(),
    feedbackExtraColumns: option.extraColumns(),
    shareExtraColumns: option.extraColumns(),
    modelExtraColumns: option.extraColumns(),
    moderationExtraColumns: option.extraColumns(),
    stepExtraColumns: option.extraColumns(),
    sandboxExtraColumns: option.extraColumns(),
    harnessExtraColumns: option.extraColumns(),
  });
