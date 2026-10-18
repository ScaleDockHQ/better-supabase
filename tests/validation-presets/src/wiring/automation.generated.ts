import {
  type RpcClient,
  defineBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { auditBlock } from "better-supabase/blocks/audit";
import { billingBlock } from "better-supabase/blocks/billing";
import { connectorsBlock } from "better-supabase/blocks/connectors";
import { entitlementsBlock } from "better-supabase/blocks/entitlements";
import { jobsBlock } from "better-supabase/blocks/jobs";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { settingsBlock } from "better-supabase/blocks/settings";
import { teamsBlock } from "better-supabase/blocks/teams";
import { webhooksBlock } from "better-supabase/blocks/webhooks";
import { workflowBuilderBlock } from "better-supabase/blocks/workflow-builder";
import { workflowsBlock } from "better-supabase/blocks/workflows";

import { blockConfig } from "./automation.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  apiKeys: apiKeysBlock,
  audit: auditBlock,
  billing: billingBlock,
  connectors: connectorsBlock,
  entitlements: entitlementsBlock,
  jobs: jobsBlock,
  notifications: notificationsBlock,
  onboarding: onboardingBlock,
  organizations: organizationsBlock,
  outbox: outboxBlock,
  profiles: profilesBlock,
  settings: settingsBlock,
  teams: teamsBlock,
  webhooks: webhooksBlock,
  workflowBuilder: workflowBuilderBlock,
  workflows: workflowsBlock,
});

/**
 * The blocks as typed clients, acting as the caller of `supabase`: its
 * token, so RLS and each function's checks apply.
 */
export function blocks(supabase: RpcClient) {
  return blockSet.create({ transport: rpcTransport(supabase) });
}
