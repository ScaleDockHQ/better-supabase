import {
  type RpcClient,
  defineBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { permissionsBlock } from "better-supabase/blocks/permissions";
import { announcementsBlock } from "better-supabase/blocks/announcements";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { attachmentsBlock } from "better-supabase/blocks/attachments";
import { auditBlock } from "better-supabase/blocks/audit";
import { billingBlock } from "better-supabase/blocks/billing";
import { calendarBlock } from "better-supabase/blocks/calendar";
import { commentsBlock } from "better-supabase/blocks/comments";
import { enrollmentsBlock } from "better-supabase/blocks/enrollments";
import { acknowledgementsBlock } from "better-supabase/blocks/acknowledgements";
import { driveBlock } from "better-supabase/blocks/drive";
import { employeesBlock } from "better-supabase/blocks/employees";
import { entitlementsBlock } from "better-supabase/blocks/entitlements";
import { knowledgeBlock } from "better-supabase/blocks/knowledge";
import { messagingBlock } from "better-supabase/blocks/messaging";
import { channelsBlock } from "better-supabase/blocks/channels";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { reactionsBlock } from "better-supabase/blocks/reactions";
import { savedViewsBlock } from "better-supabase/blocks/saved-views";
import { searchBlock } from "better-supabase/blocks/search";
import { settingsBlock } from "better-supabase/blocks/settings";
import { subjectsBlock } from "better-supabase/blocks/subjects";
import { tagsBlock } from "better-supabase/blocks/tags";
import { teamsBlock } from "better-supabase/blocks/teams";
import { versionsBlock } from "better-supabase/blocks/versions";

import { blockConfig } from "./intranet.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  permissions: permissionsBlock,
  announcements: announcementsBlock,
  apiKeys: apiKeysBlock,
  attachments: attachmentsBlock,
  audit: auditBlock,
  billing: billingBlock,
  calendar: calendarBlock,
  comments: commentsBlock,
  enrollments: enrollmentsBlock,
  acknowledgements: acknowledgementsBlock,
  drive: driveBlock,
  employees: employeesBlock,
  entitlements: entitlementsBlock,
  knowledge: knowledgeBlock,
  messaging: messagingBlock,
  channels: channelsBlock,
  notifications: notificationsBlock,
  onboarding: onboardingBlock,
  organizations: organizationsBlock,
  outbox: outboxBlock,
  profiles: profilesBlock,
  reactions: reactionsBlock,
  savedViews: savedViewsBlock,
  search: searchBlock,
  settings: settingsBlock,
  subjects: subjectsBlock,
  tags: tagsBlock,
  teams: teamsBlock,
  versions: versionsBlock,
});

/**
 * The blocks as typed clients, acting as the caller of `supabase`: its
 * token, so RLS and each function's checks apply.
 */
export function blocks(supabase: RpcClient) {
  return blockSet.create({ transport: rpcTransport(supabase) });
}
