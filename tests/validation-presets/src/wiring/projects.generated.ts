import {
  type RpcClient,
  defineBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { accessBlock } from "better-supabase/blocks/access";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { approvalsBlock } from "better-supabase/blocks/approvals";
import { attachmentsBlock } from "better-supabase/blocks/attachments";
import { auditBlock } from "better-supabase/blocks/audit";
import { billingBlock } from "better-supabase/blocks/billing";
import { commentsBlock } from "better-supabase/blocks/comments";
import { enrollmentsBlock } from "better-supabase/blocks/enrollments";
import { entitlementsBlock } from "better-supabase/blocks/entitlements";
import { jobsBlock } from "better-supabase/blocks/jobs";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { rankBlock } from "better-supabase/blocks/rank";
import { remindersBlock } from "better-supabase/blocks/reminders";
import { settingsBlock } from "better-supabase/blocks/settings";
import { stateMachineBlock } from "better-supabase/blocks/state-machine";
import { subjectsBlock } from "better-supabase/blocks/subjects";
import { tagsBlock } from "better-supabase/blocks/tags";
import { teamsBlock } from "better-supabase/blocks/teams";
import { timeTrackingBlock } from "better-supabase/blocks/time-tracking";

import { blockConfig } from "./projects.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  access: accessBlock,
  apiKeys: apiKeysBlock,
  approvals: approvalsBlock,
  attachments: attachmentsBlock,
  audit: auditBlock,
  billing: billingBlock,
  comments: commentsBlock,
  enrollments: enrollmentsBlock,
  entitlements: entitlementsBlock,
  jobs: jobsBlock,
  notifications: notificationsBlock,
  onboarding: onboardingBlock,
  organizations: organizationsBlock,
  outbox: outboxBlock,
  profiles: profilesBlock,
  rank: rankBlock,
  reminders: remindersBlock,
  settings: settingsBlock,
  stateMachine: stateMachineBlock,
  subjects: subjectsBlock,
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
