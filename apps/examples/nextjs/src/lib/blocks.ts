import type { RpcClient } from "better-supabase/blocks";

import { defineBlocks, rpcTransport } from "better-supabase/blocks";
import { accessRequestsBlock } from "better-supabase/blocks/access-requests";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { approvalsBlock } from "better-supabase/blocks/approvals";
import { attachmentsBlock } from "better-supabase/blocks/attachments";
import { auditBlock } from "better-supabase/blocks/audit";
import { bookingsBlock } from "better-supabase/blocks/bookings";
import { bulkBlock } from "better-supabase/blocks/bulk";
import { calendarBlock } from "better-supabase/blocks/calendar";
import { catalogBlock } from "better-supabase/blocks/catalog";
import { commentsBlock } from "better-supabase/blocks/comments";
import { customFieldsBlock } from "better-supabase/blocks/custom-fields";
import { dataLifecycleBlock } from "better-supabase/blocks/data-lifecycle";
import { dealsBlock } from "better-supabase/blocks/deals";
import { documentsBlock } from "better-supabase/blocks/documents";
import { driveBlock } from "better-supabase/blocks/drive";
import { employeesBlock } from "better-supabase/blocks/employees";
import { engagementsBlock } from "better-supabase/blocks/engagements";
import { formsBlock } from "better-supabase/blocks/forms";
import { hiringBlock } from "better-supabase/blocks/hiring";
import { importsBlock } from "better-supabase/blocks/imports";
import { inboxBlock } from "better-supabase/blocks/inbox";
import { inventoryBlock } from "better-supabase/blocks/inventory";
import { invoicesBlock } from "better-supabase/blocks/invoices";
import { ledgerBlock } from "better-supabase/blocks/ledger";
import { createMetrics, metricsBlock } from "better-supabase/blocks/metrics";
import {
  createNotifications,
  notificationsBlock,
} from "better-supabase/blocks/notifications";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { ordersBlock } from "better-supabase/blocks/orders";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { partiesBlock } from "better-supabase/blocks/parties";
import { pipelinesBlock } from "better-supabase/blocks/pipelines";
import { promotionsBlock } from "better-supabase/blocks/promotions";
import { quotesBlock } from "better-supabase/blocks/quotes";
import { rankBlock } from "better-supabase/blocks/rank";
import { reactionsBlock } from "better-supabase/blocks/reactions";
import { relationsBlock } from "better-supabase/blocks/relations";
import { remindersBlock } from "better-supabase/blocks/reminders";
import { rulesBlock } from "better-supabase/blocks/rules";
import { savedViewsBlock } from "better-supabase/blocks/saved-views";
import { searchBlock } from "better-supabase/blocks/search";
import { servicePrincipalsBlock } from "better-supabase/blocks/service-principals";
import { createSettings, settingsBlock } from "better-supabase/blocks/settings";
import { shareLinksBlock } from "better-supabase/blocks/share-links";
import { signingKeysBlock } from "better-supabase/blocks/signing-keys";
import { slaBlock } from "better-supabase/blocks/sla";
import { ssoBlock } from "better-supabase/blocks/sso";
import { stateMachineBlock } from "better-supabase/blocks/state-machine";
import { subjectsBlock } from "better-supabase/blocks/subjects";
import { targetsBlock } from "better-supabase/blocks/targets";
import { teamsBlock } from "better-supabase/blocks/teams";
import { templatesBlock } from "better-supabase/blocks/templates";
import { timeTrackingBlock } from "better-supabase/blocks/time-tracking";
import { trashBlock } from "better-supabase/blocks/trash";
import { usageBlock } from "better-supabase/blocks/usage";
import { versionsBlock } from "better-supabase/blocks/versions";
import { waitlistBlock } from "better-supabase/blocks/waitlist";
import { webhooksBlock } from "better-supabase/blocks/webhooks";
import { workItemsBlock } from "better-supabase/blocks/work-items";
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
  search: searchBlock,
  metrics: metricsBlock.using((options) =>
    createMetrics({ ...options, metrics }),
  ),
  usage: usageBlock,
  workflows: workflowsBlock,
  onboarding: onboardingBlock,
  settings: settingsBlock.using((options) =>
    createSettings({ ...options, settings }),
  ),
  sso: ssoBlock,
  accessRequests: accessRequestsBlock,
  reactions: reactionsBlock,
  shareLinks: shareLinksBlock,
  attachments: attachmentsBlock,
  waitlist: waitlistBlock,
  parties: partiesBlock,
  deals: dealsBlock,
  pipelines: pipelinesBlock,
  engagements: engagementsBlock,
  quotes: quotesBlock,
  targets: targetsBlock,
  workItems: workItemsBlock,
  stateMachine: stateMachineBlock,
  rank: rankBlock,
  savedViews: savedViewsBlock,
  approvals: approvalsBlock,
  rules: rulesBlock,
  sla: slaBlock,
  customFields: customFieldsBlock,
  bulk: bulkBlock,
  trash: trashBlock,
  relations: relationsBlock,
  employees: employeesBlock,
  hiring: hiringBlock,
  timeTracking: timeTrackingBlock,
  invoices: invoicesBlock,
  catalog: catalogBlock,
  inventory: inventoryBlock,
  ledger: ledgerBlock,
  orders: ordersBlock,
  promotions: promotionsBlock,
  calendar: calendarBlock,
  bookings: bookingsBlock,
  reminders: remindersBlock,
  drive: driveBlock,
  versions: versionsBlock,
  forms: formsBlock,
  imports: importsBlock,
  templates: templatesBlock,
  documents: documentsBlock,
  webhooks: webhooksBlock,
  servicePrincipals: servicePrincipalsBlock,
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
