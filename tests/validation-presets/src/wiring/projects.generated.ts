import {
  type RpcClient,
  defineBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { approvalsBlock } from "better-supabase/blocks/approvals";
import { attachmentsBlock } from "better-supabase/blocks/attachments";
import { auditBlock } from "better-supabase/blocks/audit";
import { billingBlock } from "better-supabase/blocks/billing";
import { commentsBlock } from "better-supabase/blocks/comments";
import { entitlementsBlock } from "better-supabase/blocks/entitlements";
import { jobsBlock } from "better-supabase/blocks/jobs";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { rankBlock } from "better-supabase/blocks/rank";
import { remindersBlock } from "better-supabase/blocks/reminders";
import { stateMachineBlock } from "better-supabase/blocks/state-machine";
import { tagsBlock } from "better-supabase/blocks/tags";
import { teamsBlock } from "better-supabase/blocks/teams";
import { timeTrackingBlock } from "better-supabase/blocks/time-tracking";

import { blockConfig } from "./projects.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  apiKeys: apiKeysBlock,
  approvals: approvalsBlock,
  attachments: attachmentsBlock,
  audit: auditBlock,
  billing: billingBlock,
  comments: commentsBlock,
  entitlements: entitlementsBlock,
  jobs: jobsBlock,
  notifications: notificationsBlock,
  organizations: organizationsBlock,
  profiles: profilesBlock,
  rank: rankBlock,
  reminders: remindersBlock,
  stateMachine: stateMachineBlock,
  tags: tagsBlock,
  teams: teamsBlock,
  timeTracking: timeTrackingBlock,
});

/**
 * The blocks as typed clients, acting as the caller of `supabase`: its
 * token, so RLS and each function's checks apply.
 */
export function blocks(supabase: RpcClient) {
  return blockSet.create({ transport: rpcTransport(supabase) });
}
