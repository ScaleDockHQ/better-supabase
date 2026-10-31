import {
  type RpcClient,
  defineBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { permissionsBlock } from "better-supabase/blocks/permissions";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { approvalsBlock } from "better-supabase/blocks/approvals";
import { attachmentsBlock } from "better-supabase/blocks/attachments";
import { auditBlock } from "better-supabase/blocks/audit";
import { billingBlock } from "better-supabase/blocks/billing";
import { bookingsBlock } from "better-supabase/blocks/bookings";
import { calendarBlock } from "better-supabase/blocks/calendar";
import { commentsBlock } from "better-supabase/blocks/comments";
import { enrollmentsBlock } from "better-supabase/blocks/enrollments";
import { employeesBlock } from "better-supabase/blocks/employees";
import { entitlementsBlock } from "better-supabase/blocks/entitlements";
import { formsBlock } from "better-supabase/blocks/forms";
import { signaturesBlock } from "better-supabase/blocks/signatures";
import { hiringBlock } from "better-supabase/blocks/hiring";
import { queueBlock } from "better-supabase/blocks/queue";
import { messagingBlock } from "better-supabase/blocks/messaging";
import { timelineBlock } from "better-supabase/blocks/timeline";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { pipelinesBlock } from "better-supabase/blocks/pipelines";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { remindersBlock } from "better-supabase/blocks/reminders";
import { automationsBlock } from "better-supabase/blocks/automations";
import { savedViewsBlock } from "better-supabase/blocks/saved-views";
import { searchBlock } from "better-supabase/blocks/search";
import { settingsBlock } from "better-supabase/blocks/settings";
import { subjectsBlock } from "better-supabase/blocks/subjects";
import { tagsBlock } from "better-supabase/blocks/tags";
import { teamsBlock } from "better-supabase/blocks/teams";
import { templatesBlock } from "better-supabase/blocks/templates";
import { versionsBlock } from "better-supabase/blocks/versions";

import { blockConfig } from "./ats.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  permissions: permissionsBlock,
  apiKeys: apiKeysBlock,
  approvals: approvalsBlock,
  attachments: attachmentsBlock,
  audit: auditBlock,
  billing: billingBlock,
  bookings: bookingsBlock,
  calendar: calendarBlock,
  comments: commentsBlock,
  enrollments: enrollmentsBlock,
  employees: employeesBlock,
  entitlements: entitlementsBlock,
  forms: formsBlock,
  signatures: signaturesBlock,
  hiring: hiringBlock,
  queue: queueBlock,
  messaging: messagingBlock,
  timeline: timelineBlock,
  notifications: notificationsBlock,
  onboarding: onboardingBlock,
  organizations: organizationsBlock,
  outbox: outboxBlock,
  pipelines: pipelinesBlock,
  profiles: profilesBlock,
  reminders: remindersBlock,
  automations: automationsBlock,
  savedViews: savedViewsBlock,
  search: searchBlock,
  settings: settingsBlock,
  subjects: subjectsBlock,
  tags: tagsBlock,
  teams: teamsBlock,
  templates: templatesBlock,
  versions: versionsBlock,
});

/**
 * The blocks as typed clients, acting as the caller of `supabase`: its
 * token, so RLS and each function's checks apply.
 */
export function blocks(supabase: RpcClient) {
  return blockSet.create({ transport: rpcTransport(supabase) });
}
