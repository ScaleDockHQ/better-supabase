import {
  type RpcClient,
  defineBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { accessBlock } from "better-supabase/blocks/access";
import { accessRequestsBlock } from "better-supabase/blocks/access-requests";
import { agentsBlock } from "better-supabase/blocks/agents";
import { aiCacheBlock } from "better-supabase/blocks/ai-cache";
import { aiChatBlock } from "better-supabase/blocks/ai-chat";
import { aiFilesBlock } from "better-supabase/blocks/ai-files";
import { aiProvidersBlock } from "better-supabase/blocks/ai-providers";
import { aiTasksBlock } from "better-supabase/blocks/ai-tasks";
import { announcementsBlock } from "better-supabase/blocks/announcements";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { approvalsBlock } from "better-supabase/blocks/approvals";
import { attachmentsBlock } from "better-supabase/blocks/attachments";
import { auditBlock } from "better-supabase/blocks/audit";
import { billingBlock } from "better-supabase/blocks/billing";
import { bookingsBlock } from "better-supabase/blocks/bookings";
import { bulkBlock } from "better-supabase/blocks/bulk";
import { calendarBlock } from "better-supabase/blocks/calendar";
import { catalogBlock } from "better-supabase/blocks/catalog";
import { collectionsBlock } from "better-supabase/blocks/collections";
import { commentsBlock } from "better-supabase/blocks/comments";
import { connectorsBlock } from "better-supabase/blocks/connectors";
import { customFieldsBlock } from "better-supabase/blocks/custom-fields";
import { dataLifecycleBlock } from "better-supabase/blocks/data-lifecycle";
import { dealsBlock } from "better-supabase/blocks/deals";
import { documentsBlock } from "better-supabase/blocks/documents";
import { domainsBlock } from "better-supabase/blocks/domains";
import { reviewsBlock } from "better-supabase/blocks/reviews";
import { leaveBlock } from "better-supabase/blocks/leave";
import { ledgerBlock } from "better-supabase/blocks/ledger";
import { assetsBlock } from "better-supabase/blocks/assets";
import { scoresBlock } from "better-supabase/blocks/scores";
import { moderationBlock } from "better-supabase/blocks/moderation";
import { enrollmentsBlock } from "better-supabase/blocks/enrollments";
import { guestsBlock } from "better-supabase/blocks/guests";
import { passesBlock } from "better-supabase/blocks/passes";
import { billableTimeBlock } from "better-supabase/blocks/billable-time";
import { leasesBlock } from "better-supabase/blocks/leases";
import { expensesBlock } from "better-supabase/blocks/expenses";
import { donationsBlock } from "better-supabase/blocks/donations";
import { dispatchBlock } from "better-supabase/blocks/dispatch";
import { shipmentsBlock } from "better-supabase/blocks/shipments";
import { contractsBlock } from "better-supabase/blocks/contracts";
import { controlsBlock } from "better-supabase/blocks/controls";
import { incidentsBlock } from "better-supabase/blocks/incidents";
import { driveBlock } from "better-supabase/blocks/drive";
import { employeesBlock } from "better-supabase/blocks/employees";
import { engagementsBlock } from "better-supabase/blocks/engagements";
import { entitlementsBlock } from "better-supabase/blocks/entitlements";
import { flagsBlock } from "better-supabase/blocks/flags";
import { formsBlock } from "better-supabase/blocks/forms";
import { signaturesBlock } from "better-supabase/blocks/forms";
import { hiringBlock } from "better-supabase/blocks/hiring";
import { identitiesBlock } from "better-supabase/blocks/identities";
import { importsBlock } from "better-supabase/blocks/imports";
import { inboxBlock } from "better-supabase/blocks/inbox";
import { inventoryBlock } from "better-supabase/blocks/inventory";
import { invoicesBlock } from "better-supabase/blocks/invoices";
import { idempotencyBlock } from "better-supabase/blocks/jobs";
import { jobsBlock } from "better-supabase/blocks/jobs";
import { rateLimitBlock } from "better-supabase/blocks/jobs";
import { webhookInboxBlock } from "better-supabase/blocks/jobs";
import { knowledgeBlock } from "better-supabase/blocks/knowledge";
import { memoryBlock } from "better-supabase/blocks/memory";
import { metricsBlock } from "better-supabase/blocks/metrics";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { numberSequencesBlock } from "better-supabase/blocks/number-sequences";
import { oauthServerBlock } from "better-supabase/blocks/oauth-server";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { ordersBlock } from "better-supabase/blocks/orders";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { partiesBlock } from "better-supabase/blocks/parties";
import { pipelinesBlock } from "better-supabase/blocks/pipelines";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { promotionsBlock } from "better-supabase/blocks/promotions";
import { pushBlock } from "better-supabase/blocks/push";
import { quotesBlock } from "better-supabase/blocks/quotes";
import { rankBlock } from "better-supabase/blocks/rank";
import { reactionsBlock } from "better-supabase/blocks/reactions";
import { relationsBlock } from "better-supabase/blocks/relations";
import { remindersBlock } from "better-supabase/blocks/reminders";
import { rulesBlock } from "better-supabase/blocks/rules";
import { vercelMarketplaceBlock } from "better-supabase/blocks/vercel-marketplace";
import { savedViewsBlock } from "better-supabase/blocks/saved-views";
import { searchBlock } from "better-supabase/blocks/search";
import { servicePrincipalsBlock } from "better-supabase/blocks/service-principals";
import { settingsBlock } from "better-supabase/blocks/settings";
import { shareLinksBlock } from "better-supabase/blocks/share-links";
import { sharedSignalsBlock } from "better-supabase/blocks/shared-signals";
import { signingKeysBlock } from "better-supabase/blocks/signing-keys";
import { slaBlock } from "better-supabase/blocks/sla";
import { ssoBlock } from "better-supabase/blocks/sso";
import { stateMachineBlock } from "better-supabase/blocks/state-machine";
import { subjectsBlock } from "better-supabase/blocks/subjects";
import { tagsBlock } from "better-supabase/blocks/tags";
import { targetsBlock } from "better-supabase/blocks/targets";
import { teamsBlock } from "better-supabase/blocks/teams";
import { templatesBlock } from "better-supabase/blocks/templates";
import { timeTrackingBlock } from "better-supabase/blocks/time-tracking";
import { trashBlock } from "better-supabase/blocks/trash";
import { usageBlock } from "better-supabase/blocks/usage";
import { versionsBlock } from "better-supabase/blocks/versions";
import { waitlistBlock } from "better-supabase/blocks/waitlist";
import { incomingWebhooksBlock } from "better-supabase/blocks/webhooks";
import { webhooksBlock } from "better-supabase/blocks/webhooks";
import { workItemsBlock } from "better-supabase/blocks/work-items";
import { workflowBuilderBlock } from "better-supabase/blocks/workflow-builder";
import { workflowsBlock } from "better-supabase/blocks/workflows";

import { blockConfig } from "./everything.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  access: accessBlock,
  accessRequests: accessRequestsBlock,
  agents: agentsBlock,
  aiCache: aiCacheBlock,
  aiChat: aiChatBlock,
  aiFiles: aiFilesBlock,
  aiProviders: aiProvidersBlock,
  aiTasks: aiTasksBlock,
  announcements: announcementsBlock,
  apiKeys: apiKeysBlock,
  approvals: approvalsBlock,
  attachments: attachmentsBlock,
  audit: auditBlock,
  billing: billingBlock,
  bookings: bookingsBlock,
  bulk: bulkBlock,
  calendar: calendarBlock,
  catalog: catalogBlock,
  collections: collectionsBlock,
  comments: commentsBlock,
  connectors: connectorsBlock,
  customFields: customFieldsBlock,
  dataLifecycle: dataLifecycleBlock,
  deals: dealsBlock,
  documents: documentsBlock,
  domains: domainsBlock,
  reviews: reviewsBlock,
  leave: leaveBlock,
  ledger: ledgerBlock,
  assets: assetsBlock,
  scores: scoresBlock,
  moderation: moderationBlock,
  enrollments: enrollmentsBlock,
  guests: guestsBlock,
  passes: passesBlock,
  billableTime: billableTimeBlock,
  leases: leasesBlock,
  expenses: expensesBlock,
  donations: donationsBlock,
  dispatch: dispatchBlock,
  shipments: shipmentsBlock,
  contracts: contractsBlock,
  controls: controlsBlock,
  incidents: incidentsBlock,
  drive: driveBlock,
  employees: employeesBlock,
  engagements: engagementsBlock,
  entitlements: entitlementsBlock,
  flags: flagsBlock,
  forms: formsBlock,
  signatures: signaturesBlock,
  hiring: hiringBlock,
  identities: identitiesBlock,
  imports: importsBlock,
  inbox: inboxBlock,
  inventory: inventoryBlock,
  invoices: invoicesBlock,
  idempotency: idempotencyBlock,
  jobs: jobsBlock,
  rateLimit: rateLimitBlock,
  webhookInbox: webhookInboxBlock,
  knowledge: knowledgeBlock,
  memory: memoryBlock,
  metrics: metricsBlock,
  notifications: notificationsBlock,
  numberSequences: numberSequencesBlock,
  oauthServer: oauthServerBlock,
  onboarding: onboardingBlock,
  orders: ordersBlock,
  organizations: organizationsBlock,
  outbox: outboxBlock,
  parties: partiesBlock,
  pipelines: pipelinesBlock,
  profiles: profilesBlock,
  promotions: promotionsBlock,
  push: pushBlock,
  quotes: quotesBlock,
  rank: rankBlock,
  reactions: reactionsBlock,
  relations: relationsBlock,
  reminders: remindersBlock,
  rules: rulesBlock,
  vercelMarketplace: vercelMarketplaceBlock,
  savedViews: savedViewsBlock,
  search: searchBlock,
  servicePrincipals: servicePrincipalsBlock,
  settings: settingsBlock,
  shareLinks: shareLinksBlock,
  sharedSignals: sharedSignalsBlock,
  signingKeys: signingKeysBlock,
  sla: slaBlock,
  sso: ssoBlock,
  stateMachine: stateMachineBlock,
  subjects: subjectsBlock,
  tags: tagsBlock,
  targets: targetsBlock,
  teams: teamsBlock,
  templates: templatesBlock,
  timeTracking: timeTrackingBlock,
  trash: trashBlock,
  usage: usageBlock,
  versions: versionsBlock,
  waitlist: waitlistBlock,
  incomingWebhooks: incomingWebhooksBlock,
  webhooks: webhooksBlock,
  workItems: workItemsBlock,
  workflowBuilder: workflowBuilderBlock,
  workflows: workflowsBlock,
});

/**
 * The blocks as typed clients, acting as the caller of `supabase`: its
 * token, so RLS and each function's checks apply.
 */
export function blocks(supabase: RpcClient) {
  return blockSet.create({ transport: rpcTransport(supabase) });
}
