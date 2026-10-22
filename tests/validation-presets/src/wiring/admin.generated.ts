import {
  type RpcClient,
  defineBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { permissionsBlock } from "better-supabase/blocks/permissions";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { approvalsBlock } from "better-supabase/blocks/approvals";
import { auditBlock } from "better-supabase/blocks/audit";
import { billingBlock } from "better-supabase/blocks/billing";
import { bulkActionsBlock } from "better-supabase/blocks/bulk-actions";
import { enrollmentsBlock } from "better-supabase/blocks/enrollments";
import { entitlementsBlock } from "better-supabase/blocks/entitlements";
import { featureFlagsBlock } from "better-supabase/blocks/feature-flags";
import { metricsBlock } from "better-supabase/blocks/metrics";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { savedViewsBlock } from "better-supabase/blocks/saved-views";
import { settingsBlock } from "better-supabase/blocks/settings";
import { teamsBlock } from "better-supabase/blocks/teams";

import { blockConfig } from "./admin.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  permissions: permissionsBlock,
  apiKeys: apiKeysBlock,
  approvals: approvalsBlock,
  audit: auditBlock,
  billing: billingBlock,
  bulkActions: bulkActionsBlock,
  enrollments: enrollmentsBlock,
  entitlements: entitlementsBlock,
  featureFlags: featureFlagsBlock,
  metrics: metricsBlock,
  notifications: notificationsBlock,
  onboarding: onboardingBlock,
  organizations: organizationsBlock,
  outbox: outboxBlock,
  profiles: profilesBlock,
  savedViews: savedViewsBlock,
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
