import type { AnyBlock } from "./define-block.ts";

import { accessRequestsBlock } from "./access-requests/manifest.ts";
import { accessBlock } from "./access/manifest.ts";
import { actorBlock } from "./actor/manifest.ts";
import { agentsBlock } from "./agents/manifest.ts";
import { aiCacheBlock } from "./ai-cache/manifest.ts";
import { aiChatBlock } from "./ai-chat/manifest.ts";
import { aiFilesBlock } from "./ai-files/manifest.ts";
import { aiProvidersBlock } from "./ai-providers/manifest.ts";
import { aiTasksBlock } from "./ai-tasks/manifest.ts";
import { announcementsBlock } from "./announcements/manifest.ts";
import { apiKeysBlock } from "./api-keys/manifest.ts";
import { approvalsBlock } from "./approvals/manifest.ts";
import { assetsBlock } from "./assets/manifest.ts";
import { attachmentsBlock } from "./attachments/manifest.ts";
import { auditBlock } from "./audit/manifest.ts";
import { billableTimeBlock } from "./billable-time/manifest.ts";
import { billingBlock } from "./billing/manifest.ts";
import { bookingsBlock } from "./bookings/manifest.ts";
import { bulkBlock } from "./bulk/manifest.ts";
import { calendarBlock } from "./calendar/manifest.ts";
import { catalogBlock } from "./catalog/manifest.ts";
import { collectionsBlock } from "./collections/manifest.ts";
import { commentsBlock } from "./comments/manifest.ts";
import { connectorsBlock } from "./connectors/manifest.ts";
import { contractsBlock } from "./contracts/manifest.ts";
import { controlsBlock } from "./controls/manifest.ts";
import { coursesBlock } from "./courses/manifest.ts";
import { credentialsBlock } from "./credentials/manifest.ts";
import { customFieldsBlock } from "./custom-fields/manifest.ts";
import { dataLifecycleBlock } from "./data-lifecycle/manifest.ts";
import { dealsBlock } from "./deals/manifest.ts";
import { dispatchBlock } from "./dispatch/manifest.ts";
import { documentsBlock } from "./documents/manifest.ts";
import { domainsBlock } from "./domains/manifest.ts";
import { donationsBlock } from "./donations/manifest.ts";
import { driveBlock } from "./drive/manifest.ts";
import { employeesBlock } from "./employees/manifest.ts";
import { engagementsBlock } from "./engagements/manifest.ts";
import { enrollmentsBlock } from "./enrollments/manifest.ts";
import { ensureRlsBlock } from "./ensure-rls/manifest.ts";
import { entitlementsBlock } from "./entitlements/manifest.ts";
import { expensesBlock } from "./expenses/manifest.ts";
import { fieldEncryptionBlock } from "./field-encryption/manifest.ts";
import { flagsBlock } from "./flags/manifest.ts";
import { formsBlock, signaturesBlock } from "./forms/manifest.ts";
import { grantsBlock } from "./grants/manifest.ts";
import { guestsBlock } from "./guests/manifest.ts";
import { hiringBlock } from "./hiring/manifest.ts";
import { identitiesBlock } from "./identities/manifest.ts";
import { importsBlock } from "./imports/manifest.ts";
import { inboxBlock } from "./inbox/manifest.ts";
import { incidentsBlock } from "./incidents/manifest.ts";
import { inventoryBlock } from "./inventory/manifest.ts";
import { invoicesBlock } from "./invoices/manifest.ts";
import {
  idempotencyBlock,
  jobsBlock,
  rateLimitBlock,
  webhookInboxBlock,
} from "./jobs/manifest.ts";
import { jsonbSchemasBlock } from "./jsonb-schemas/manifest.ts";
import { knowledgeBlock } from "./knowledge/manifest.ts";
import { leasesBlock } from "./leases/manifest.ts";
import { leaveBlock } from "./leave/manifest.ts";
import { ledgerBlock } from "./ledger/manifest.ts";
import { memoryBlock } from "./memory/manifest.ts";
import { metricsBlock } from "./metrics/manifest.ts";
import { mfaBlock } from "./mfa/manifest.ts";
import { moderationBlock } from "./moderation/manifest.ts";
import { notificationsBlock } from "./notifications/manifest.ts";
import { numberSequencesBlock } from "./number-sequences/manifest.ts";
import { oauthServerBlock } from "./oauth-server/manifest.ts";
import { onboardingBlock } from "./onboarding/manifest.ts";
import { ordersBlock } from "./orders/manifest.ts";
import { organizationsBlock } from "./organizations/manifest.ts";
import { outboxBlock } from "./outbox/manifest.ts";
import { partiesBlock } from "./parties/manifest.ts";
import { passesBlock } from "./passes/manifest.ts";
import { pgtapBlock } from "./pgtap/manifest.ts";
import { pipelinesBlock } from "./pipelines/manifest.ts";
import { profilesBlock } from "./profiles/manifest.ts";
import { promotionsBlock } from "./promotions/manifest.ts";
import { pushBlock } from "./push/manifest.ts";
import { quotesBlock } from "./quotes/manifest.ts";
import { rankBlock } from "./rank/manifest.ts";
import { reactionsBlock } from "./reactions/manifest.ts";
import { readSetsBlock } from "./read-sets/manifest.ts";
import { realtimeTablesBlock } from "./realtime-tables/manifest.ts";
import { relationsBlock } from "./relations/manifest.ts";
import { remindersBlock } from "./reminders/manifest.ts";
import { reservedSlugsBlock } from "./reserved-slugs/manifest.ts";
import { reviewsBlock } from "./reviews/manifest.ts";
import { rulesBlock } from "./rules/manifest.ts";
import { savedViewsBlock } from "./saved-views/manifest.ts";
import { scoresBlock } from "./scores/manifest.ts";
import { searchBlock } from "./search/manifest.ts";
import { servicePrincipalsBlock } from "./service-principals/manifest.ts";
import { sessionsBlock } from "./sessions/manifest.ts";
import { settingsBlock } from "./settings/manifest.ts";
import { shareLinksBlock } from "./share-links/manifest.ts";
import { sharedSignalsBlock } from "./shared-signals/manifest.ts";
import { shipmentsBlock } from "./shipments/manifest.ts";
import { signingKeysBlock } from "./signing-keys/manifest.ts";
import { slaBlock } from "./sla/manifest.ts";
import { ssoBlock } from "./sso/manifest.ts";
import { stateMachineBlock } from "./state-machine/manifest.ts";
import { streamsBlock } from "./streams/manifest.ts";
import { subjectsBlock } from "./subjects/manifest.ts";
import { supportSessionsBlock } from "./support-sessions/manifest.ts";
import { tagsBlock } from "./tags/manifest.ts";
import { targetsBlock } from "./targets/manifest.ts";
import { teamsBlock } from "./teams/manifest.ts";
import { templatesBlock } from "./templates/manifest.ts";
import { tenantBlock } from "./tenant/manifest.ts";
import { timeTrackingBlock } from "./time-tracking/manifest.ts";
import { trashBlock } from "./trash/manifest.ts";
import { undoBlock } from "./undo/manifest.ts";
import { updatedAtBlock } from "./updated-at/manifest.ts";
import { usageBlock } from "./usage/manifest.ts";
import { vectorSearchBlock } from "./vector-search/manifest.ts";
import { vercelMarketplaceBlock } from "./vercel-marketplace/manifest.ts";
import { versionsBlock } from "./versions/manifest.ts";
import { waitlistBlock } from "./waitlist/manifest.ts";
import { incomingWebhooksBlock, webhooksBlock } from "./webhooks/manifest.ts";
import { workItemsBlock } from "./work-items/manifest.ts";
import { workflowBuilderBlock } from "./workflow-builder/manifest.ts";
import { workflowSdkWorldBlock } from "./workflow-sdk-world/manifest.ts";
import { workflowsBlock } from "./workflows/manifest.ts";

/**
 * Every block manifest, for the conformance test, the catalog and presets. Not
 * exported from a subpath: it imports every creator.
 */
export const BLOCK_MANIFESTS: readonly AnyBlock[] = [
  accessBlock,
  accessRequestsBlock,
  actorBlock,
  agentsBlock,
  aiCacheBlock,
  aiChatBlock,
  aiFilesBlock,
  aiProvidersBlock,
  aiTasksBlock,
  announcementsBlock,
  apiKeysBlock,
  approvalsBlock,
  attachmentsBlock,
  auditBlock,
  billingBlock,
  bookingsBlock,
  bulkBlock,
  calendarBlock,
  catalogBlock,
  collectionsBlock,
  commentsBlock,
  connectorsBlock,
  credentialsBlock,
  customFieldsBlock,
  dataLifecycleBlock,
  dealsBlock,
  documentsBlock,
  domainsBlock,
  reviewsBlock,
  leaveBlock,
  ledgerBlock,
  assetsBlock,
  scoresBlock,
  moderationBlock,
  enrollmentsBlock,
  guestsBlock,
  passesBlock,
  billableTimeBlock,
  leasesBlock,
  expensesBlock,
  donationsBlock,
  dispatchBlock,
  shipmentsBlock,
  contractsBlock,
  controlsBlock,
  incidentsBlock,
  coursesBlock,
  driveBlock,
  employeesBlock,
  engagementsBlock,
  ensureRlsBlock,
  entitlementsBlock,
  fieldEncryptionBlock,
  flagsBlock,
  formsBlock,
  signaturesBlock,
  grantsBlock,
  hiringBlock,
  identitiesBlock,
  importsBlock,
  inboxBlock,
  inventoryBlock,
  invoicesBlock,
  idempotencyBlock,
  jobsBlock,
  rateLimitBlock,
  webhookInboxBlock,
  jsonbSchemasBlock,
  knowledgeBlock,
  memoryBlock,
  metricsBlock,
  mfaBlock,
  notificationsBlock,
  numberSequencesBlock,
  oauthServerBlock,
  onboardingBlock,
  ordersBlock,
  organizationsBlock,
  outboxBlock,
  partiesBlock,
  pgtapBlock,
  pipelinesBlock,
  profilesBlock,
  promotionsBlock,
  pushBlock,
  quotesBlock,
  rankBlock,
  reactionsBlock,
  readSetsBlock,
  realtimeTablesBlock,
  relationsBlock,
  remindersBlock,
  reservedSlugsBlock,
  rulesBlock,
  vercelMarketplaceBlock,
  savedViewsBlock,
  searchBlock,
  servicePrincipalsBlock,
  sessionsBlock,
  settingsBlock,
  shareLinksBlock,
  sharedSignalsBlock,
  signingKeysBlock,
  slaBlock,
  ssoBlock,
  stateMachineBlock,
  streamsBlock,
  subjectsBlock,
  supportSessionsBlock,
  tagsBlock,
  targetsBlock,
  teamsBlock,
  templatesBlock,
  tenantBlock,
  timeTrackingBlock,
  trashBlock,
  undoBlock,
  updatedAtBlock,
  usageBlock,
  vectorSearchBlock,
  versionsBlock,
  waitlistBlock,
  incomingWebhooksBlock,
  webhooksBlock,
  workItemsBlock,
  workflowBuilderBlock,
  workflowSdkWorldBlock,
  workflowsBlock,
];
