import {
  type RpcClient,
  defineBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { accessBlock } from "better-supabase/blocks/access";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { attachmentsBlock } from "better-supabase/blocks/attachments";
import { auditBlock } from "better-supabase/blocks/audit";
import { billingBlock } from "better-supabase/blocks/billing";
import { commentsBlock } from "better-supabase/blocks/comments";
import { enrollmentsBlock } from "better-supabase/blocks/enrollments";
import { entitlementsBlock } from "better-supabase/blocks/entitlements";
import { inboxBlock } from "better-supabase/blocks/inbox";
import { knowledgeBlock } from "better-supabase/blocks/knowledge";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { pipelinesBlock } from "better-supabase/blocks/pipelines";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { savedViewsBlock } from "better-supabase/blocks/saved-views";
import { searchBlock } from "better-supabase/blocks/search";
import { settingsBlock } from "better-supabase/blocks/settings";
import { slaBlock } from "better-supabase/blocks/sla";
import { subjectsBlock } from "better-supabase/blocks/subjects";
import { tagsBlock } from "better-supabase/blocks/tags";
import { teamsBlock } from "better-supabase/blocks/teams";
import { workItemsBlock } from "better-supabase/blocks/work-items";

import { blockConfig } from "./helpdesk.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  access: accessBlock,
  apiKeys: apiKeysBlock,
  attachments: attachmentsBlock,
  audit: auditBlock,
  billing: billingBlock,
  comments: commentsBlock,
  enrollments: enrollmentsBlock,
  entitlements: entitlementsBlock,
  inbox: inboxBlock,
  knowledge: knowledgeBlock,
  notifications: notificationsBlock,
  onboarding: onboardingBlock,
  organizations: organizationsBlock,
  outbox: outboxBlock,
  pipelines: pipelinesBlock,
  profiles: profilesBlock,
  savedViews: savedViewsBlock,
  search: searchBlock,
  settings: settingsBlock,
  sla: slaBlock,
  subjects: subjectsBlock,
  tags: tagsBlock,
  teams: teamsBlock,
  workItems: workItemsBlock,
});

/**
 * The blocks as typed clients, acting as the caller of `supabase`: its
 * token, so RLS and each function's checks apply.
 */
export function blocks(supabase: RpcClient) {
  return blockSet.create({ transport: rpcTransport(supabase) });
}
