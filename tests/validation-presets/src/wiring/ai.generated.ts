import {
  type RpcClient,
  defineBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { permissionsBlock } from "better-supabase/blocks/permissions";
import { agentsBlock } from "better-supabase/blocks/agents";
import { aiChatBlock } from "better-supabase/blocks/ai-chat";
import { aiFilesBlock } from "better-supabase/blocks/ai-files";
import { aiSchedulesBlock } from "better-supabase/blocks/ai-schedules";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { auditBlock } from "better-supabase/blocks/audit";
import { billingBlock } from "better-supabase/blocks/billing";
import { enrollmentsBlock } from "better-supabase/blocks/enrollments";
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

import { blockConfig } from "./ai.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  permissions: permissionsBlock,
  agents: agentsBlock,
  aiChat: aiChatBlock,
  aiFiles: aiFilesBlock,
  aiSchedules: aiSchedulesBlock,
  apiKeys: apiKeysBlock,
  audit: auditBlock,
  billing: billingBlock,
  enrollments: enrollmentsBlock,
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
});

/**
 * The blocks as typed clients, acting as the caller of `supabase`: its
 * token, so RLS and each function's checks apply.
 */
export function blocks(supabase: RpcClient) {
  return blockSet.create({ transport: rpcTransport(supabase) });
}
