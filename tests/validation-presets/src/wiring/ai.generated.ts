import {
  type RpcClient,
  defineBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { agentsBlock } from "better-supabase/blocks/agents";
import { aiChatBlock } from "better-supabase/blocks/ai-chat";
import { aiFilesBlock } from "better-supabase/blocks/ai-files";
import { aiTasksBlock } from "better-supabase/blocks/ai-tasks";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { auditBlock } from "better-supabase/blocks/audit";
import { billingBlock } from "better-supabase/blocks/billing";
import { knowledgeBlock } from "better-supabase/blocks/knowledge";
import { memoryBlock } from "better-supabase/blocks/memory";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { teamsBlock } from "better-supabase/blocks/teams";

import { blockConfig } from "./ai.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  agents: agentsBlock,
  aiChat: aiChatBlock,
  aiFiles: aiFilesBlock,
  aiTasks: aiTasksBlock,
  apiKeys: apiKeysBlock,
  audit: auditBlock,
  billing: billingBlock,
  knowledge: knowledgeBlock,
  memory: memoryBlock,
  notifications: notificationsBlock,
  organizations: organizationsBlock,
  profiles: profilesBlock,
  teams: teamsBlock,
});

/**
 * The blocks as typed clients, acting as the caller of `supabase`: its
 * token, so RLS and each function's checks apply.
 */
export function blocks(supabase: RpcClient) {
  return blockSet.create({ transport: rpcTransport(supabase) });
}
