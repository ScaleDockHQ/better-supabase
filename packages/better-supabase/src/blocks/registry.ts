import type { AnyBlock } from "./define-block.ts";

import { accessRequestsBlock } from "./access-requests/manifest.ts";
import { accountingBlock } from "./accounting/manifest.ts";
import { acknowledgementsBlock } from "./acknowledgements/manifest.ts";
import { activitiesBlock } from "./activities/manifest.ts";
import { agentsBlock } from "./agents/manifest.ts";
import { aiCacheBlock } from "./ai-cache/manifest.ts";
import { aiChatBlock } from "./ai-chat/manifest.ts";
import { aiFilesBlock } from "./ai-files/manifest.ts";
import { aiKeysBlock } from "./ai-keys/manifest.ts";
import { aiSchedulesBlock } from "./ai-schedules/manifest.ts";
import { announcementsBlock } from "./announcements/manifest.ts";
import { apiKeysBlock } from "./api-keys/manifest.ts";
import { approvalsBlock } from "./approvals/manifest.ts";
import { assetsBlock } from "./assets/manifest.ts";
import { assignmentBlock } from "./assignment/manifest.ts";
import { attachmentsBlock } from "./attachments/manifest.ts";
import { auditBlock } from "./audit/manifest.ts";
import { automationsBlock } from "./automations/manifest.ts";
import { bankingBlock } from "./banking/manifest.ts";
import { billableTimeBlock } from "./billable-time/manifest.ts";
import { billingBlock } from "./billing/manifest.ts";
import { bookingsBlock } from "./bookings/manifest.ts";
import { bulkBlock } from "./bulk/manifest.ts";
import { calendarBlock } from "./calendar/manifest.ts";
import { carePlansBlock } from "./care-plans/manifest.ts";
import { casesBlock } from "./cases/manifest.ts";
import { catalogBlock } from "./catalog/manifest.ts";
import { channelsBlock } from "./channels/manifest.ts";
import { collectionsBlock } from "./collections/manifest.ts";
import { commentsBlock } from "./comments/manifest.ts";
import { complianceBlock } from "./compliance/manifest.ts";
import { connectorsBlock } from "./connectors/manifest.ts";
import { consentsBlock } from "./consents/manifest.ts";
import { contactsBlock } from "./contacts/manifest.ts";
import { contentBlock } from "./content/manifest.ts";
import { contractsBlock } from "./contracts/manifest.ts";
import { coursesBlock } from "./courses/manifest.ts";
import { createdByBlock } from "./created-by/manifest.ts";
import { credentialsBlock } from "./credentials/manifest.ts";
import { customFieldsBlock } from "./custom-fields/manifest.ts";
import { damBlock } from "./dam/manifest.ts";
import { dataLifecycleBlock } from "./data-lifecycle/manifest.ts";
import { dealsBlock } from "./deals/manifest.ts";
import { dispatchBlock } from "./dispatch/manifest.ts";
import { documentsBlock } from "./documents/manifest.ts";
import { domainsBlock } from "./domains/manifest.ts";
import { donationsBlock } from "./donations/manifest.ts";
import { driveBlock } from "./drive/manifest.ts";
import { employeesBlock } from "./employees/manifest.ts";
import { enrichmentBlock } from "./enrichment/manifest.ts";
import { enrollmentsBlock } from "./enrollments/manifest.ts";
import { entitlementsBlock } from "./entitlements/manifest.ts";
import { expensesBlock } from "./expenses/manifest.ts";
import { fieldEncryptionBlock } from "./field-encryption/manifest.ts";
import { fieldHistoryBlock } from "./field-history/manifest.ts";
import { flagsBlock } from "./flags/manifest.ts";
import { forecastsBlock } from "./forecasts/manifest.ts";
import { formsBlock } from "./forms/manifest.ts";
import { fundingBlock } from "./funding/manifest.ts";
import { goalsBlock } from "./goals/manifest.ts";
import { grantsBlock } from "./grants/manifest.ts";
import { guestsBlock } from "./guests/manifest.ts";
import { hiringBlock } from "./hiring/manifest.ts";
import { identitiesBlock } from "./identities/manifest.ts";
import { impersonationBlock } from "./impersonation/manifest.ts";
import { importsBlock } from "./imports/manifest.ts";
import { inboxBlock } from "./inbox/manifest.ts";
import { incidentsBlock } from "./incidents/manifest.ts";
import { inspectionsBlock } from "./inspections/manifest.ts";
import { inventoryBlock } from "./inventory/manifest.ts";
import { invoicesBlock } from "./invoices/manifest.ts";
import { jsonbSchemasBlock } from "./jsonb-schemas/manifest.ts";
import { knowledgeBlock } from "./knowledge/manifest.ts";
import { leadScoringBlock } from "./lead-scoring/manifest.ts";
import { leasesBlock } from "./leases/manifest.ts";
import { leaveBlock } from "./leave/manifest.ts";
import { ledgerBlock } from "./ledger/manifest.ts";
import { legalEntitiesBlock } from "./legal-entities/manifest.ts";
import { mailSyncBlock } from "./mail-sync/manifest.ts";
import { maintenanceBlock } from "./maintenance/manifest.ts";
import { manufacturingBlock } from "./manufacturing/manifest.ts";
import { medicationsBlock } from "./medications/manifest.ts";
import { meetingsBlock } from "./meetings/manifest.ts";
import { membershipsBlock } from "./memberships/manifest.ts";
import { memoryBlock } from "./memory/manifest.ts";
import { messagingBlock } from "./messaging/manifest.ts";
import { metricsBlock } from "./metrics/manifest.ts";
import { mfaBlock } from "./mfa/manifest.ts";
import { moderationBlock } from "./moderation/manifest.ts";
import { notificationsBlock } from "./notifications/manifest.ts";
import { numberingBlock } from "./numbering/manifest.ts";
import { oauthServerBlock } from "./oauth-server/manifest.ts";
import { observationsBlock } from "./observations/manifest.ts";
import { onboardingBlock } from "./onboarding/manifest.ts";
import { ordersBlock } from "./orders/manifest.ts";
import { organizationsBlock } from "./organizations/manifest.ts";
import { outboxBlock } from "./outbox/manifest.ts";
import { passesBlock } from "./passes/manifest.ts";
import { payrollExportBlock } from "./payroll-export/manifest.ts";
import { permissionsBlock } from "./permissions/manifest.ts";
import { pgtapBlock } from "./pgtap/manifest.ts";
import { pipelinesBlock } from "./pipelines/manifest.ts";
import { postsBlock } from "./posts/manifest.ts";
import { profilesBlock } from "./profiles/manifest.ts";
import { promotionsBlock } from "./promotions/manifest.ts";
import { pushBlock } from "./push/manifest.ts";
import { qualificationsBlock } from "./qualifications/manifest.ts";
import {
  idempotencyBlock,
  queueBlock,
  rateLimitBlock,
  webhookInboxBlock,
} from "./queue/manifest.ts";
import { quotesBlock } from "./quotes/manifest.ts";
import { rankBlock } from "./rank/manifest.ts";
import { reactionsBlock } from "./reactions/manifest.ts";
import { readSetsBlock } from "./read-sets/manifest.ts";
import { realtimeTablesBlock } from "./realtime-tables/manifest.ts";
import { relationsBlock } from "./relations/manifest.ts";
import { remindersBlock } from "./reminders/manifest.ts";
import { reservedSlugsBlock } from "./reserved-slugs/manifest.ts";
import { reviewsBlock } from "./reviews/manifest.ts";
import { risksBlock } from "./risks/manifest.ts";
import { rlsGuardBlock } from "./rls-guard/manifest.ts";
import { savedViewsBlock } from "./saved-views/manifest.ts";
import { scoresBlock } from "./scores/manifest.ts";
import { searchBlock } from "./search/manifest.ts";
import { securityEventsBlock } from "./security-events/manifest.ts";
import { segmentsBlock } from "./segments/manifest.ts";
import { sequencesBlock } from "./sequences/manifest.ts";
import { serviceAccountsBlock } from "./service-accounts/manifest.ts";
import { sessionsBlock } from "./sessions/manifest.ts";
import { settingsBlock } from "./settings/manifest.ts";
import { shareLinksBlock } from "./share-links/manifest.ts";
import { shiftsBlock } from "./shifts/manifest.ts";
import { shipmentsBlock } from "./shipments/manifest.ts";
import { signaturesBlock } from "./signatures/manifest.ts";
import { signingKeysBlock } from "./signing-keys/manifest.ts";
import { slaBlock } from "./sla/manifest.ts";
import { ssoBlock } from "./sso/manifest.ts";
import { stateMachineBlock } from "./state-machine/manifest.ts";
import { streamsBlock } from "./streams/manifest.ts";
import { subjectsBlock } from "./subjects/manifest.ts";
import { tagsBlock } from "./tags/manifest.ts";
import { tasksBlock } from "./tasks/manifest.ts";
import { taxBlock } from "./tax/manifest.ts";
import { teamsBlock } from "./teams/manifest.ts";
import { templatesBlock } from "./templates/manifest.ts";
import { timeTrackingBlock } from "./time-tracking/manifest.ts";
import { timelineBlock } from "./timeline/manifest.ts";
import { trashBlock } from "./trash/manifest.ts";
import { undoBlock } from "./undo/manifest.ts";
import { updatedAtBlock } from "./updated-at/manifest.ts";
import { usageBlock } from "./usage/manifest.ts";
import { vectorSearchBlock } from "./vector-search/manifest.ts";
import { vercelMarketplaceBlock } from "./vercel-marketplace/manifest.ts";
import { versionsBlock } from "./versions/manifest.ts";
import { waitlistBlock } from "./waitlist/manifest.ts";
import { incomingWebhooksBlock, webhooksBlock } from "./webhooks/manifest.ts";
import { workflowEditorBlock } from "./workflow-editor/manifest.ts";
import { workflowSdkBlock } from "./workflow-sdk/manifest.ts";
import { workflowsBlock } from "./workflows/manifest.ts";

/**
 * Every block manifest, for the conformance test, the catalog and presets. Not
 * exported from a subpath: it imports every creator.
 */
export const BLOCK_MANIFESTS: readonly AnyBlock[] = [
  permissionsBlock,
  accessRequestsBlock,
  accountingBlock,
  createdByBlock,
  agentsBlock,
  aiCacheBlock,
  aiChatBlock,
  aiFilesBlock,
  aiKeysBlock,
  aiSchedulesBlock,
  announcementsBlock,
  apiKeysBlock,
  approvalsBlock,
  attachmentsBlock,
  auditBlock,
  billingBlock,
  bookingsBlock,
  bulkBlock,
  calendarBlock,
  carePlansBlock,
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
  complianceBlock,
  acknowledgementsBlock,
  incidentsBlock,
  coursesBlock,
  sequencesBlock,
  leadScoringBlock,
  postsBlock,
  contentBlock,
  qualificationsBlock,
  risksBlock,
  casesBlock,
  inspectionsBlock,
  meetingsBlock,
  maintenanceBlock,
  damBlock,
  manufacturingBlock,
  bankingBlock,
  legalEntitiesBlock,
  fundingBlock,
  payrollExportBlock,
  taxBlock,
  shiftsBlock,
  consentsBlock,
  observationsBlock,
  medicationsBlock,
  driveBlock,
  employeesBlock,
  activitiesBlock,
  rlsGuardBlock,
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
  queueBlock,
  rateLimitBlock,
  webhookInboxBlock,
  jsonbSchemasBlock,
  knowledgeBlock,
  memoryBlock,
  messagingBlock,
  channelsBlock,
  timelineBlock,
  mailSyncBlock,
  segmentsBlock,
  assignmentBlock,
  enrichmentBlock,
  fieldHistoryBlock,
  forecastsBlock,
  metricsBlock,
  mfaBlock,
  notificationsBlock,
  numberingBlock,
  oauthServerBlock,
  onboardingBlock,
  ordersBlock,
  organizationsBlock,
  outboxBlock,
  contactsBlock,
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
  automationsBlock,
  vercelMarketplaceBlock,
  savedViewsBlock,
  searchBlock,
  serviceAccountsBlock,
  sessionsBlock,
  settingsBlock,
  shareLinksBlock,
  securityEventsBlock,
  signingKeysBlock,
  slaBlock,
  ssoBlock,
  stateMachineBlock,
  streamsBlock,
  subjectsBlock,
  impersonationBlock,
  tagsBlock,
  goalsBlock,
  teamsBlock,
  templatesBlock,
  membershipsBlock,
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
  tasksBlock,
  workflowEditorBlock,
  workflowSdkBlock,
  workflowsBlock,
];
