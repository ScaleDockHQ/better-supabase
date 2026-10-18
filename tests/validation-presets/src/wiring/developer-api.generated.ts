import {
  type RpcClient,
  defineBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { auditBlock } from "better-supabase/blocks/audit";
import { billingBlock } from "better-supabase/blocks/billing";
import { entitlementsBlock } from "better-supabase/blocks/entitlements";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { servicePrincipalsBlock } from "better-supabase/blocks/service-principals";
import { settingsBlock } from "better-supabase/blocks/settings";
import { signingKeysBlock } from "better-supabase/blocks/signing-keys";
import { teamsBlock } from "better-supabase/blocks/teams";
import { usageBlock } from "better-supabase/blocks/usage";
import { webhooksBlock } from "better-supabase/blocks/webhooks";

import { blockConfig } from "./developer-api.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  apiKeys: apiKeysBlock,
  audit: auditBlock,
  billing: billingBlock,
  entitlements: entitlementsBlock,
  notifications: notificationsBlock,
  onboarding: onboardingBlock,
  organizations: organizationsBlock,
  outbox: outboxBlock,
  profiles: profilesBlock,
  servicePrincipals: servicePrincipalsBlock,
  settings: settingsBlock,
  signingKeys: signingKeysBlock,
  teams: teamsBlock,
  usage: usageBlock,
  webhooks: webhooksBlock,
});

/**
 * The blocks as typed clients, acting as the caller of `supabase`: its
 * token, so RLS and each function's checks apply.
 */
export function blocks(supabase: RpcClient) {
  return blockSet.create({ transport: rpcTransport(supabase) });
}
