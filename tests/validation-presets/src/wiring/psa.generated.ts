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
import { commentsBlock } from "better-supabase/blocks/comments";
import { ledgerBlock } from "better-supabase/blocks/ledger";
import { enrollmentsBlock } from "better-supabase/blocks/enrollments";
import { billableTimeBlock } from "better-supabase/blocks/billable-time";
import { expensesBlock } from "better-supabase/blocks/expenses";
import { contractsBlock } from "better-supabase/blocks/contracts";
import { shiftsBlock } from "better-supabase/blocks/shifts";
import { entitlementsBlock } from "better-supabase/blocks/entitlements";
import { signaturesBlock } from "better-supabase/blocks/signatures";
import { invoicesBlock } from "better-supabase/blocks/invoices";
import { queueBlock } from "better-supabase/blocks/queue";
import { messagingBlock } from "better-supabase/blocks/messaging";
import { timelineBlock } from "better-supabase/blocks/timeline";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { numberingBlock } from "better-supabase/blocks/numbering";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { contactsBlock } from "better-supabase/blocks/contacts";
import { pipelinesBlock } from "better-supabase/blocks/pipelines";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { quotesBlock } from "better-supabase/blocks/quotes";
import { remindersBlock } from "better-supabase/blocks/reminders";
import { automationsBlock } from "better-supabase/blocks/automations";
import { savedViewsBlock } from "better-supabase/blocks/saved-views";
import { searchBlock } from "better-supabase/blocks/search";
import { settingsBlock } from "better-supabase/blocks/settings";
import { subjectsBlock } from "better-supabase/blocks/subjects";
import { tagsBlock } from "better-supabase/blocks/tags";
import { teamsBlock } from "better-supabase/blocks/teams";
import { timeTrackingBlock } from "better-supabase/blocks/time-tracking";
import { versionsBlock } from "better-supabase/blocks/versions";
import { tasksBlock } from "better-supabase/blocks/tasks";

import { blockConfig } from "./psa.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  permissions: permissionsBlock,
  apiKeys: apiKeysBlock,
  approvals: approvalsBlock,
  attachments: attachmentsBlock,
  audit: auditBlock,
  billing: billingBlock,
  comments: commentsBlock,
  ledger: ledgerBlock,
  enrollments: enrollmentsBlock,
  billableTime: billableTimeBlock,
  expenses: expensesBlock,
  contracts: contractsBlock,
  shifts: shiftsBlock,
  entitlements: entitlementsBlock,
  signatures: signaturesBlock,
  invoices: invoicesBlock,
  queue: queueBlock,
  messaging: messagingBlock,
  timeline: timelineBlock,
  notifications: notificationsBlock,
  numbering: numberingBlock,
  onboarding: onboardingBlock,
  organizations: organizationsBlock,
  outbox: outboxBlock,
  contacts: contactsBlock,
  pipelines: pipelinesBlock,
  profiles: profilesBlock,
  quotes: quotesBlock,
  reminders: remindersBlock,
  automations: automationsBlock,
  savedViews: savedViewsBlock,
  search: searchBlock,
  settings: settingsBlock,
  subjects: subjectsBlock,
  tags: tagsBlock,
  teams: teamsBlock,
  timeTracking: timeTrackingBlock,
  versions: versionsBlock,
  tasks: tasksBlock,
});

/**
 * The blocks as typed clients, acting as the caller of `supabase`: its
 * token, so RLS and each function's checks apply.
 */
export function blocks(supabase: RpcClient) {
  return blockSet.create({ transport: rpcTransport(supabase) });
}
