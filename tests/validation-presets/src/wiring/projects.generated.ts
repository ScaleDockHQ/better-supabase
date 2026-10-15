import {
  type RpcClient,
  createBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { approvalsBlock } from "better-supabase/blocks/approvals";
import { attachmentsBlock } from "better-supabase/blocks/attachments";
import { auditBlock } from "better-supabase/blocks/audit";
import { billingBlock } from "better-supabase/blocks/billing";
import { commentsBlock } from "better-supabase/blocks/comments";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { rankBlock } from "better-supabase/blocks/rank";
import { remindersBlock } from "better-supabase/blocks/reminders";
import { stateMachineBlock } from "better-supabase/blocks/state-machine";
import { tagsBlock } from "better-supabase/blocks/tags";
import { teamsBlock } from "better-supabase/blocks/teams";
import { timeTrackingBlock } from "better-supabase/blocks/time-tracking";

/**
 * The blocks as typed clients, acting as the caller of `supabase`: its
 * token, so RLS and each function's checks apply.
 */
export function blocks(supabase: RpcClient) {
  return createBlocks(
    { transport: rpcTransport(supabase) },
    {
      apiKeys: apiKeysBlock,
      approvals: approvalsBlock,
      attachments: attachmentsBlock,
      audit: auditBlock,
      billing: billingBlock,
      comments: commentsBlock,
      notifications: notificationsBlock,
      organizations: organizationsBlock,
      profiles: profilesBlock,
      rank: rankBlock,
      reminders: remindersBlock,
      stateMachine: stateMachineBlock,
      tags: tagsBlock,
      teams: teamsBlock,
      timeTracking: timeTrackingBlock,
    },
  );
}
