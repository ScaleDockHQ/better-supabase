import {
  type RpcClient,
  defineBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { aiChatBlock } from "better-supabase/blocks/ai-chat";
import { aiFilesBlock } from "better-supabase/blocks/ai-files";
import { aiProvidersBlock } from "better-supabase/blocks/ai-providers";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { auditBlock } from "better-supabase/blocks/audit";
import { billingBlock } from "better-supabase/blocks/billing";
import { entitlementsBlock } from "better-supabase/blocks/entitlements";
import { knowledgeBlock } from "better-supabase/blocks/knowledge";
import { memoryBlock } from "better-supabase/blocks/memory";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { settingsBlock } from "better-supabase/blocks/settings";
import { teamsBlock } from "better-supabase/blocks/teams";
import { usageBlock } from "better-supabase/blocks/usage";

import { blockConfig } from "./ai-chat.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  aiChat: aiChatBlock,
  aiFiles: aiFilesBlock,
  aiProviders: aiProvidersBlock,
  apiKeys: apiKeysBlock,
  audit: auditBlock,
  billing: billingBlock,
  entitlements: entitlementsBlock,
  knowledge: knowledgeBlock,
  memory: memoryBlock,
  notifications: notificationsBlock,
  onboarding: onboardingBlock,
  organizations: organizationsBlock,
  outbox: outboxBlock,
  profiles: profilesBlock,
  settings: settingsBlock,
  teams: teamsBlock,
  usage: usageBlock,
});

/**
 * The blocks as typed clients, acting as the caller of `supabase`: its
 * token, so RLS and each function's checks apply.
 */
export function blocks(supabase: RpcClient) {
  return blockSet.create({ transport: rpcTransport(supabase) });
}
