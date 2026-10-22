import type { RpcClient } from "better-supabase/blocks";

import { defineBlocks, rpcTransport } from "better-supabase/blocks";
import { accessRequestsBlock } from "better-supabase/blocks/access-requests";
import { activitiesBlock } from "better-supabase/blocks/activities";
import { admissionPassesBlock } from "better-supabase/blocks/admission-passes";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { approvalsBlock } from "better-supabase/blocks/approvals";
import { assetsBlock } from "better-supabase/blocks/assets";
import { assignmentBlock } from "better-supabase/blocks/assignment";
import { attachmentsBlock } from "better-supabase/blocks/attachments";
import { auditBlock } from "better-supabase/blocks/audit";
import { automationsBlock } from "better-supabase/blocks/automations";
import { billableTimeBlock } from "better-supabase/blocks/billable-time";
import { bookingsBlock } from "better-supabase/blocks/bookings";
import { bulkActionsBlock } from "better-supabase/blocks/bulk-actions";
import { calendarBlock } from "better-supabase/blocks/calendar";
import { catalogBlock } from "better-supabase/blocks/catalog";
import { channelsBlock } from "better-supabase/blocks/channels";
import { commentsBlock } from "better-supabase/blocks/comments";
import { complianceBlock } from "better-supabase/blocks/compliance";
import { contactsBlock } from "better-supabase/blocks/contacts";
import { contractsBlock } from "better-supabase/blocks/contracts";
import { coursesBlock } from "better-supabase/blocks/courses";
import { customFieldsBlock } from "better-supabase/blocks/custom-fields";
import { dataLifecycleBlock } from "better-supabase/blocks/data-lifecycle";
import { dealsBlock } from "better-supabase/blocks/deals";
import { dispatchBlock } from "better-supabase/blocks/dispatch";
import { documentsBlock } from "better-supabase/blocks/documents";
import { donationsBlock } from "better-supabase/blocks/donations";
import { driveBlock } from "better-supabase/blocks/drive";
import { employeesBlock } from "better-supabase/blocks/employees";
import { enrichmentBlock } from "better-supabase/blocks/enrichment";
import { enrollmentsBlock } from "better-supabase/blocks/enrollments";
import { expensesBlock } from "better-supabase/blocks/expenses";
import { fieldHistoryBlock } from "better-supabase/blocks/field-history";
import { forecastsBlock } from "better-supabase/blocks/forecasts";
import { formsBlock } from "better-supabase/blocks/forms";
import { goalsBlock } from "better-supabase/blocks/goals";
import { guestsBlock } from "better-supabase/blocks/guests";
import { hiringBlock } from "better-supabase/blocks/hiring";
import { importsBlock } from "better-supabase/blocks/imports";
import { inboxBlock } from "better-supabase/blocks/inbox";
import { incidentsBlock } from "better-supabase/blocks/incidents";
import { inventoryBlock } from "better-supabase/blocks/inventory";
import { invoicesBlock } from "better-supabase/blocks/invoices";
import { leadScoringBlock } from "better-supabase/blocks/lead-scoring";
import { leasesBlock } from "better-supabase/blocks/leases";
import { ledgerBlock } from "better-supabase/blocks/ledger";
import { mailSyncBlock } from "better-supabase/blocks/mail-sync";
import { messagingBlock } from "better-supabase/blocks/messaging";
import { createMetrics, metricsBlock } from "better-supabase/blocks/metrics";
import { moderationBlock } from "better-supabase/blocks/moderation";
import {
  createNotifications,
  notificationsBlock,
} from "better-supabase/blocks/notifications";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { ordersBlock } from "better-supabase/blocks/orders";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { pipelinesBlock } from "better-supabase/blocks/pipelines";
import { postsBlock } from "better-supabase/blocks/posts";
import { promotionsBlock } from "better-supabase/blocks/promotions";
import { quotesBlock } from "better-supabase/blocks/quotes";
import { rankBlock } from "better-supabase/blocks/rank";
import { reactionsBlock } from "better-supabase/blocks/reactions";
import { relationsBlock } from "better-supabase/blocks/relations";
import { remindersBlock } from "better-supabase/blocks/reminders";
import { savedViewsBlock } from "better-supabase/blocks/saved-views";
import { scoresBlock } from "better-supabase/blocks/scores";
import { searchBlock } from "better-supabase/blocks/search";
import { segmentsBlock } from "better-supabase/blocks/segments";
import { sequencesBlock } from "better-supabase/blocks/sequences";
import { serviceAccountsBlock } from "better-supabase/blocks/service-accounts";
import { createSettings, settingsBlock } from "better-supabase/blocks/settings";
import { shareLinksBlock } from "better-supabase/blocks/share-links";
import { shipmentsBlock } from "better-supabase/blocks/shipments";
import { signingKeysBlock } from "better-supabase/blocks/signing-keys";
import { slaBlock } from "better-supabase/blocks/sla";
import { ssoBlock } from "better-supabase/blocks/sso";
import { stateMachineBlock } from "better-supabase/blocks/state-machine";
import { subjectsBlock } from "better-supabase/blocks/subjects";
import { tasksBlock } from "better-supabase/blocks/tasks";
import { teamsBlock } from "better-supabase/blocks/teams";
import { templatesBlock } from "better-supabase/blocks/templates";
import { timeTrackingBlock } from "better-supabase/blocks/time-tracking";
import { trashBlock } from "better-supabase/blocks/trash";
import { usageBlock } from "better-supabase/blocks/usage";
import { versionsBlock } from "better-supabase/blocks/versions";
import { waitlistBlock } from "better-supabase/blocks/waitlist";
import { webhooksBlock } from "better-supabase/blocks/webhooks";
import { workflowsBlock } from "better-supabase/blocks/workflows";

import {
  notificationTypes,
  renderNotification,
} from "@/features/notifications/notification-types";
import { settings } from "@/features/settings/settings-definition";
import { blockConfig } from "@/lib/supabase/blocks.generated";
import { metrics } from "@/metrics";

import { betterSupabase } from "./supabase";

/** `sql.api` in better-supabase.config.ts, as `gen` wrote it. */
const API_SCHEMA = blockConfig.organizations.api;

/**
 * The blocks the app uses. Each one's schema (the `api` wrappers) and the
 * options its SQL half shares come from `blocks.generated.ts`.
 */
const blockSet = defineBlocks(blockConfig, {
  organizations: organizationsBlock,
  apiKeys: apiKeysBlock,
  audit: auditBlock,
  comments: commentsBlock,
  notifications: notificationsBlock.using((options) =>
    createNotifications({
      ...options,
      types: notificationTypes,
      render: renderNotification,
    }),
  ),
  inbox: inboxBlock,
  messaging: messagingBlock,
  channels: channelsBlock,
  search: searchBlock,
  metrics: metricsBlock.using((options) =>
    createMetrics({ ...options, metrics }),
  ),
  usage: usageBlock,
  workflows: workflowsBlock,
  enrollments: enrollmentsBlock,
  courses: coursesBlock,
  onboarding: onboardingBlock,
  settings: settingsBlock.using((options) =>
    createSettings({ ...options, settings }),
  ),
  sso: ssoBlock,
  accessRequests: accessRequestsBlock,
  reactions: reactionsBlock,
  posts: postsBlock,
  shareLinks: shareLinksBlock,
  attachments: attachmentsBlock,
  waitlist: waitlistBlock,
  parties: contactsBlock,
  deals: dealsBlock,
  pipelines: pipelinesBlock,
  engagements: activitiesBlock,
  mailSync: mailSyncBlock,
  segments: segmentsBlock,
  sequences: sequencesBlock,
  "lead-scoring": leadScoringBlock,
  assignment: assignmentBlock,
  enrichment: enrichmentBlock,
  forecasts: forecastsBlock,
  fieldHistory: fieldHistoryBlock,
  quotes: quotesBlock,
  targets: goalsBlock,
  workItems: tasksBlock,
  stateMachine: stateMachineBlock,
  rank: rankBlock,
  savedViews: savedViewsBlock,
  approvals: approvalsBlock,
  rules: automationsBlock,
  scores: scoresBlock,
  moderation: moderationBlock,
  sla: slaBlock,
  customFields: customFieldsBlock,
  bulk: bulkActionsBlock,
  trash: trashBlock,
  relations: relationsBlock,
  employees: employeesBlock,
  hiring: hiringBlock,
  timeTracking: timeTrackingBlock,
  invoices: invoicesBlock,
  catalog: catalogBlock,
  inventory: inventoryBlock,
  ledger: ledgerBlock,
  guests: guestsBlock,
  passes: admissionPassesBlock,
  "billable-time": billableTimeBlock,
  leases: leasesBlock,
  expenses: expensesBlock,
  donations: donationsBlock,
  dispatch: dispatchBlock,
  shipments: shipmentsBlock,
  contracts: contractsBlock,
  controls: complianceBlock,
  incidents: incidentsBlock,
  orders: ordersBlock,
  promotions: promotionsBlock,
  calendar: calendarBlock,
  bookings: bookingsBlock,
  assets: assetsBlock,
  reminders: remindersBlock,
  drive: driveBlock,
  versions: versionsBlock,
  forms: formsBlock,
  imports: importsBlock,
  templates: templatesBlock,
  documents: documentsBlock,
  webhooks: webhooksBlock,
  servicePrincipals: serviceAccountsBlock,
  signingKeys: signingKeysBlock,
  dataLifecycle: dataLifecycleBlock,
  teams: teamsBlock,
  subjects: subjectsBlock,
  outbox: outboxBlock.with({ source: "https://example.bettersupabase.com" }),
});

/**
 * The blocks as typed clients over the Data API, acting as the caller of
 * `supabase` (its token, so RLS and each function's checks apply). The blocks
 * that work in one organization act in `tenant`.
 */
export function blocks(supabase: RpcClient, tenant?: string | null) {
  const transport = rpcTransport(supabase);

  const built = blockSet.create({
    transport,
    events: betterSupabase.events,
    tenant: () => tenant,
  });

  return {
    ...built,
    /** A module function without a typed client, such as `flag_enabled`. */
    call: (fn: string, args: Parameters<typeof transport.call>[2]) =>
      transport.call(API_SCHEMA, fn, args),
  };
}
