import type { AccessRequestsSqlOptions } from "./access-requests/options.ts";
import type { AccessSqlOptions } from "./access/options.ts";
import type { AgentsSqlOptions } from "./agents/options.ts";
import type { AiCacheSqlOptions } from "./ai-cache/options.ts";
import type { AiChatSqlOptions } from "./ai-chat/options.ts";
import type { AiFilesSqlOptions } from "./ai-files/options.ts";
import type { AiProvidersSqlOptions } from "./ai-providers/options.ts";
import type { AiTasksSqlOptions } from "./ai-tasks/options.ts";
import type { AnnouncementsSqlOptions } from "./announcements/options.ts";
import type { ApiKeysSqlOptions } from "./api-keys/options.ts";
import type { ApprovalsSqlOptions } from "./approvals/options.ts";
import type { AssetsSqlOptions } from "./assets/options.ts";
import type { AttachmentsSqlOptions } from "./attachments/options.ts";
import type { AuditSqlOptions } from "./audit/options.ts";
import type { BillingSqlOptions } from "./billing/options.ts";
import type { BookingsSqlOptions } from "./bookings/options.ts";
import type { BulkSqlOptions } from "./bulk/options.ts";
import type { CalendarSqlOptions } from "./calendar/options.ts";
import type { CatalogSqlOptions } from "./catalog/options.ts";
import type { CollectionsSqlOptions } from "./collections/options.ts";
import type { CommentsSqlOptions } from "./comments/options.ts";
import type { ConnectorsSqlOptions } from "./connectors/options.ts";
import type { ContractsSqlOptions } from "./contracts/options.ts";
import type { ControlsSqlOptions } from "./controls/options.ts";
import type { CoursesSqlOptions } from "./courses/options.ts";
import type { CredentialsSqlOptions } from "./credentials/options.ts";
import type { CustomFieldsSqlOptions } from "./custom-fields/options.ts";
import type { DataLifecycleSqlOptions } from "./data-lifecycle/options.ts";
import type { DealsSqlOptions } from "./deals/options.ts";
import type { DispatchSqlOptions } from "./dispatch/options.ts";
import type { DocumentsSqlOptions } from "./documents/options.ts";
import type { DomainsSqlOptions } from "./domains/options.ts";
import type { DonationsSqlOptions } from "./donations/options.ts";
import type { DriveSqlOptions } from "./drive/options.ts";
import type { EmployeesSqlOptions } from "./employees/options.ts";
import type { EngagementsSqlOptions } from "./engagements/options.ts";
import type { EnrollmentsSqlOptions } from "./enrollments/options.ts";
import type { ExpensesSqlOptions } from "./expenses/options.ts";
import type { FlagsSqlOptions } from "./flags/options.ts";
import type { FormsSqlOptions } from "./forms/options.ts";
import type { GrantsSqlOptions } from "./grants/options.ts";
import type { HiringSqlOptions } from "./hiring/options.ts";
import type { IdentitiesSqlOptions } from "./identities/options.ts";
import type { InboxSqlOptions } from "./inbox/options.ts";
import type { IncidentsSqlOptions } from "./incidents/options.ts";
import type { InventorySqlOptions } from "./inventory/options.ts";
import type { InvoicesSqlOptions } from "./invoices/options.ts";
import type {
  JobsSqlOptions,
  RateLimitSqlOptions,
  WebhookInboxSqlOptions,
} from "./jobs/options.ts";
import type { KnowledgeSqlOptions } from "./knowledge/options.ts";
import type { LeasesSqlOptions } from "./leases/options.ts";
import type { LeaveSqlOptions } from "./leave/options.ts";
import type { MemorySqlOptions } from "./memory/options.ts";
import type { MessagingSqlOptions } from "./messaging/options.ts";
import type { MetricsSqlOptions } from "./metrics/options.ts";
import type { ModerationSqlOptions } from "./moderation/options.ts";
import type { NotificationsSqlOptions } from "./notifications/options.ts";
import type { NumberSequencesSqlOptions } from "./number-sequences/options.ts";
import type { OAuthServerSqlOptions } from "./oauth-server/options.ts";
import type { OnboardingSqlOptions } from "./onboarding/options.ts";
import type { BlockOptionsSchema } from "./options.ts";
import type { OrdersSqlOptions } from "./orders/options.ts";
import type {
  OrganizationsSqlOptions,
  InvitationsSqlOptions,
} from "./organizations/options.ts";
import type { OutboxSqlOptions } from "./outbox/options.ts";
import type { PartiesSqlOptions } from "./parties/options.ts";
import type { PassesSqlOptions } from "./passes/options.ts";
import type { PipelinesSqlOptions } from "./pipelines/options.ts";
import type { ProfilesSqlOptions } from "./profiles/options.ts";
import type { PromotionsSqlOptions } from "./promotions/options.ts";
import type { PushSqlOptions } from "./push/options.ts";
import type { QuotesSqlOptions } from "./quotes/options.ts";
import type { ReactionsSqlOptions } from "./reactions/options.ts";
import type { RelationsSqlOptions } from "./relations/options.ts";
import type { RemindersSqlOptions } from "./reminders/options.ts";
import type { ReservedSlugsSqlOptions } from "./reserved-slugs/options.ts";
import type { ReviewsSqlOptions } from "./reviews/options.ts";
import type { RulesSqlOptions } from "./rules/options.ts";
import type { SavedViewsSqlOptions } from "./saved-views/options.ts";
import type { ScoresSqlOptions } from "./scores/options.ts";
import type { SearchSqlOptions } from "./search/options.ts";
import type { ServicePrincipalsSqlOptions } from "./service-principals/options.ts";
import type { SessionsSqlOptions } from "./sessions/options.ts";
import type { SettingsSqlOptions } from "./settings/options.ts";
import type { ShareLinksSqlOptions } from "./share-links/options.ts";
import type { SharedSignalsSqlOptions } from "./shared-signals/options.ts";
import type { ShipmentsSqlOptions } from "./shipments/options.ts";
import type { SignaturesSqlOptions } from "./signatures/options.ts";
import type { SigningKeysSqlOptions } from "./signing-keys/options.ts";
import type { SlaSqlOptions } from "./sla/options.ts";
import type { SsoSqlOptions } from "./sso/options.ts";
import type { StateMachineSqlOptions } from "./state-machine/options.ts";
import type { StreamsSqlOptions } from "./streams/options.ts";
import type { SupportSessionsSqlOptions } from "./support-sessions/options.ts";
import type { TagsSqlOptions } from "./tags/options.ts";
import type { TargetsSqlOptions } from "./targets/options.ts";
import type { TeamsSqlOptions } from "./teams/options.ts";
import type { TemplatesSqlOptions } from "./templates/options.ts";
import type { TenantSqlOptions } from "./tenant/options.ts";
import type { TimeTrackingSqlOptions } from "./time-tracking/options.ts";
import type { TrashSqlOptions } from "./trash/options.ts";
import type { UsageSqlOptions } from "./usage/options.ts";
import type { VectorSearchSqlOptions } from "./vector-search/options.ts";
import type { VercelMarketplaceSqlOptions } from "./vercel-marketplace/options.ts";
import type { VersionsSqlOptions } from "./versions/options.ts";
import type { WaitlistSqlOptions } from "./waitlist/options.ts";
import type {
  WebhooksOutSqlOptions,
  WebhooksInSqlOptions,
} from "./webhooks/options.ts";
import type { WorkItemsSqlOptions } from "./work-items/options.ts";
import type { WorkflowBuilderSqlOptions } from "./workflow-builder/options.ts";
import type { WorkflowSdkWorldSqlOptions } from "./workflow-sdk-world/options.ts";

import { accessRequestsSqlOptions } from "./access-requests/options.ts";
import { accessSqlOptions } from "./access/options.ts";
import { agentsSqlOptions } from "./agents/options.ts";
import { aiCacheSqlOptions } from "./ai-cache/options.ts";
import { aiChatSqlOptions } from "./ai-chat/options.ts";
import { aiFilesSqlOptions } from "./ai-files/options.ts";
import { aiProvidersSqlOptions } from "./ai-providers/options.ts";
import { aiTasksSqlOptions } from "./ai-tasks/options.ts";
import { announcementsSqlOptions } from "./announcements/options.ts";
import { apiKeysSqlOptions } from "./api-keys/options.ts";
import { approvalsSqlOptions } from "./approvals/options.ts";
import { assetsSqlOptions } from "./assets/options.ts";
import { attachmentsSqlOptions } from "./attachments/options.ts";
import { auditSqlOptions } from "./audit/options.ts";
import { billingSqlOptions } from "./billing/options.ts";
import { bookingsSqlOptions } from "./bookings/options.ts";
import { bulkSqlOptions } from "./bulk/options.ts";
import { calendarSqlOptions } from "./calendar/options.ts";
import { catalogSqlOptions } from "./catalog/options.ts";
import { collectionsSqlOptions } from "./collections/options.ts";
import { commentsSqlOptions } from "./comments/options.ts";
import { connectorsSqlOptions } from "./connectors/options.ts";
import { contractsSqlOptions } from "./contracts/options.ts";
import { controlsSqlOptions } from "./controls/options.ts";
import { coursesSqlOptions } from "./courses/options.ts";
import { credentialsSqlOptions } from "./credentials/options.ts";
import { customFieldsSqlOptions } from "./custom-fields/options.ts";
import { dataLifecycleSqlOptions } from "./data-lifecycle/options.ts";
import { dealsSqlOptions } from "./deals/options.ts";
import { dispatchSqlOptions } from "./dispatch/options.ts";
import { documentsSqlOptions } from "./documents/options.ts";
import { domainsSqlOptions } from "./domains/options.ts";
import { donationsSqlOptions } from "./donations/options.ts";
import { driveSqlOptions } from "./drive/options.ts";
import { employeesSqlOptions } from "./employees/options.ts";
import { engagementsSqlOptions } from "./engagements/options.ts";
import { enrollmentsSqlOptions } from "./enrollments/options.ts";
import { expensesSqlOptions } from "./expenses/options.ts";
import { flagsSqlOptions } from "./flags/options.ts";
import { formsSqlOptions } from "./forms/options.ts";
import { grantsSqlOptions } from "./grants/options.ts";
import { hiringSqlOptions } from "./hiring/options.ts";
import { identitiesSqlOptions } from "./identities/options.ts";
import { inboxSqlOptions } from "./inbox/options.ts";
import { incidentsSqlOptions } from "./incidents/options.ts";
import { inventorySqlOptions } from "./inventory/options.ts";
import { invoicesSqlOptions } from "./invoices/options.ts";
import {
  jobsSqlOptions,
  rateLimitSqlOptions,
  webhookInboxSqlOptions,
} from "./jobs/options.ts";
import { knowledgeSqlOptions } from "./knowledge/options.ts";
import { leasesSqlOptions } from "./leases/options.ts";
import { leaveSqlOptions } from "./leave/options.ts";
import { memorySqlOptions } from "./memory/options.ts";
import { messagingSqlOptions } from "./messaging/options.ts";
import { metricsSqlOptions } from "./metrics/options.ts";
import { moderationSqlOptions } from "./moderation/options.ts";
import { notificationsSqlOptions } from "./notifications/options.ts";
import { numberSequencesSqlOptions } from "./number-sequences/options.ts";
import { oauthServerSqlOptions } from "./oauth-server/options.ts";
import { onboardingSqlOptions } from "./onboarding/options.ts";
import { NO_OPTIONS } from "./options.ts";
import { ordersSqlOptions } from "./orders/options.ts";
import {
  organizationsSqlOptions,
  invitationsSqlOptions,
} from "./organizations/options.ts";
import { outboxSqlOptions } from "./outbox/options.ts";
import { partiesSqlOptions } from "./parties/options.ts";
import { passesSqlOptions } from "./passes/options.ts";
import { pipelinesSqlOptions } from "./pipelines/options.ts";
import { profilesSqlOptions } from "./profiles/options.ts";
import { promotionsSqlOptions } from "./promotions/options.ts";
import { pushSqlOptions } from "./push/options.ts";
import { quotesSqlOptions } from "./quotes/options.ts";
import { reactionsSqlOptions } from "./reactions/options.ts";
import { relationsSqlOptions } from "./relations/options.ts";
import { remindersSqlOptions } from "./reminders/options.ts";
import { reservedSlugsSqlOptions } from "./reserved-slugs/options.ts";
import { reviewsSqlOptions } from "./reviews/options.ts";
import { rulesSqlOptions } from "./rules/options.ts";
import { savedViewsSqlOptions } from "./saved-views/options.ts";
import { scoresSqlOptions } from "./scores/options.ts";
import { searchSqlOptions } from "./search/options.ts";
import { servicePrincipalsSqlOptions } from "./service-principals/options.ts";
import { sessionsSqlOptions } from "./sessions/options.ts";
import { settingsSqlOptions } from "./settings/options.ts";
import { shareLinksSqlOptions } from "./share-links/options.ts";
import { sharedSignalsSqlOptions } from "./shared-signals/options.ts";
import { shipmentsSqlOptions } from "./shipments/options.ts";
import { signaturesSqlOptions } from "./signatures/options.ts";
import { signingKeysSqlOptions } from "./signing-keys/options.ts";
import { slaSqlOptions } from "./sla/options.ts";
import { ssoSqlOptions } from "./sso/options.ts";
import { stateMachineSqlOptions } from "./state-machine/options.ts";
import { streamsSqlOptions } from "./streams/options.ts";
import { supportSessionsSqlOptions } from "./support-sessions/options.ts";
import { tagsSqlOptions } from "./tags/options.ts";
import { targetsSqlOptions } from "./targets/options.ts";
import { teamsSqlOptions } from "./teams/options.ts";
import { templatesSqlOptions } from "./templates/options.ts";
import { tenantSqlOptions } from "./tenant/options.ts";
import { timeTrackingSqlOptions } from "./time-tracking/options.ts";
import { trashSqlOptions } from "./trash/options.ts";
import { usageSqlOptions } from "./usage/options.ts";
import { vectorSearchSqlOptions } from "./vector-search/options.ts";
import { vercelMarketplaceSqlOptions } from "./vercel-marketplace/options.ts";
import { versionsSqlOptions } from "./versions/options.ts";
import { waitlistSqlOptions } from "./waitlist/options.ts";
import {
  webhooksOutSqlOptions,
  webhooksInSqlOptions,
} from "./webhooks/options.ts";
import { workItemsSqlOptions } from "./work-items/options.ts";
import { workflowBuilderSqlOptions } from "./workflow-builder/options.ts";
import { workflowSdkWorldSqlOptions } from "./workflow-sdk-world/options.ts";

type None = Record<never, never>;

/**
 * The options of every SQL module, keyed by module name. `BlocksConfig` types
 * `blocks.<module>.options` from it, and `schemas/config-v1.json` is generated
 * from `BLOCK_OPTION_SCHEMAS`.
 */
export interface BlockOptionsRegistry {
  readonly access: AccessSqlOptions;
  readonly "access-requests": AccessRequestsSqlOptions;
  readonly actor: None;
  readonly agents: AgentsSqlOptions;
  readonly "ai-cache": AiCacheSqlOptions;
  readonly "ai-chat": AiChatSqlOptions;
  readonly "ai-files": AiFilesSqlOptions;
  readonly "ai-providers": AiProvidersSqlOptions;
  readonly "ai-tasks": AiTasksSqlOptions;
  readonly announcements: AnnouncementsSqlOptions;
  readonly "api-keys": ApiKeysSqlOptions;
  readonly approvals: ApprovalsSqlOptions;
  readonly attachments: AttachmentsSqlOptions;
  readonly audit: AuditSqlOptions;
  readonly billing: BillingSqlOptions;
  readonly bookings: BookingsSqlOptions;
  readonly bulk: BulkSqlOptions;
  readonly calendar: CalendarSqlOptions;
  readonly catalog: CatalogSqlOptions;
  readonly "chat-sdk-state": None;
  readonly collections: CollectionsSqlOptions;
  readonly comments: CommentsSqlOptions;
  readonly connectors: ConnectorsSqlOptions;
  readonly credentials: CredentialsSqlOptions;
  readonly "custom-fields": CustomFieldsSqlOptions;
  readonly "data-lifecycle": DataLifecycleSqlOptions;
  readonly deals: DealsSqlOptions;
  readonly documents: DocumentsSqlOptions;
  readonly domains: DomainsSqlOptions;
  readonly drive: DriveSqlOptions;
  readonly "drive-files": None;
  readonly employees: EmployeesSqlOptions;
  readonly engagements: EngagementsSqlOptions;
  readonly "ensure-rls": None;
  readonly entitlements: None;
  readonly flags: FlagsSqlOptions;
  readonly forms: FormsSqlOptions;
  readonly grants: GrantsSqlOptions;
  readonly hiring: HiringSqlOptions;
  readonly idempotency: None;
  readonly identities: IdentitiesSqlOptions;
  readonly imports: None;
  readonly "oauth-server": OAuthServerSqlOptions;
  readonly inbox: InboxSqlOptions;
  readonly inventory: InventorySqlOptions;
  readonly invitations: InvitationsSqlOptions;
  readonly invoices: InvoicesSqlOptions;
  readonly jobs: JobsSqlOptions;
  readonly "jsonb-schemas": None;
  readonly knowledge: KnowledgeSqlOptions;
  readonly leave: LeaveSqlOptions;
  readonly ledger: None;
  readonly assets: AssetsSqlOptions;
  readonly guests: None;
  readonly memory: MemorySqlOptions;
  readonly messaging: MessagingSqlOptions;
  readonly channels: None;
  readonly activity: None;
  readonly metrics: MetricsSqlOptions;
  readonly mfa: None;
  readonly notifications: NotificationsSqlOptions;
  readonly "number-sequences": NumberSequencesSqlOptions;
  readonly onboarding: OnboardingSqlOptions;
  readonly orders: OrdersSqlOptions;
  readonly organizations: OrganizationsSqlOptions;
  readonly outbox: OutboxSqlOptions;
  readonly parties: PartiesSqlOptions;
  readonly passes: PassesSqlOptions;
  readonly "billable-time": None;
  readonly leases: LeasesSqlOptions;
  readonly expenses: ExpensesSqlOptions;
  readonly donations: DonationsSqlOptions;
  readonly dispatch: DispatchSqlOptions;
  readonly shipments: ShipmentsSqlOptions;
  readonly contracts: ContractsSqlOptions;
  readonly controls: ControlsSqlOptions;
  readonly incidents: IncidentsSqlOptions;
  readonly courses: CoursesSqlOptions;
  readonly pgtap: None;
  readonly pipelines: PipelinesSqlOptions;
  readonly profiles: ProfilesSqlOptions;
  readonly promotions: PromotionsSqlOptions;
  readonly push: PushSqlOptions;
  readonly quotes: QuotesSqlOptions;
  readonly rank: None;
  readonly "rate-limit": RateLimitSqlOptions;
  readonly reactions: ReactionsSqlOptions;
  readonly "read-sets": None;
  readonly "realtime-tables": None;
  readonly relations: RelationsSqlOptions;
  readonly reminders: RemindersSqlOptions;
  readonly "reserved-slugs": ReservedSlugsSqlOptions;
  readonly reviews: ReviewsSqlOptions;
  readonly rules: RulesSqlOptions;
  readonly scores: ScoresSqlOptions;
  readonly moderation: ModerationSqlOptions;
  readonly enrollments: EnrollmentsSqlOptions;
  readonly "vercel-marketplace": VercelMarketplaceSqlOptions;
  readonly "saved-views": SavedViewsSqlOptions;
  readonly search: SearchSqlOptions;
  readonly "service-principals": ServicePrincipalsSqlOptions;
  readonly sessions: SessionsSqlOptions;
  readonly settings: SettingsSqlOptions;
  readonly "share-links": ShareLinksSqlOptions;
  readonly "shared-signals": SharedSignalsSqlOptions;
  readonly signatures: SignaturesSqlOptions;
  readonly "signing-keys": SigningKeysSqlOptions;
  readonly sla: SlaSqlOptions;
  readonly sso: SsoSqlOptions;
  readonly "state-machine": StateMachineSqlOptions;
  readonly streams: StreamsSqlOptions;
  readonly subjects: None;
  readonly "support-sessions": SupportSessionsSqlOptions;
  readonly tags: TagsSqlOptions;
  readonly targets: TargetsSqlOptions;
  readonly teams: TeamsSqlOptions;
  readonly templates: TemplatesSqlOptions;
  readonly tenant: TenantSqlOptions;
  readonly "time-tracking": TimeTrackingSqlOptions;
  readonly trash: TrashSqlOptions;
  readonly "updated-at": None;
  readonly usage: UsageSqlOptions;
  readonly "vector-search": VectorSearchSqlOptions;
  readonly versions: VersionsSqlOptions;
  readonly waitlist: WaitlistSqlOptions;
  readonly "webhook-inbox": WebhookInboxSqlOptions;
  readonly "webhooks-in": WebhooksInSqlOptions;
  readonly "webhooks-out": WebhooksOutSqlOptions;
  readonly "work-items": WorkItemsSqlOptions;
  readonly "workflow-builder": WorkflowBuilderSqlOptions;
  readonly "workflow-sdk-world": WorkflowSdkWorldSqlOptions;
  readonly workflows: None;
}

/** The options schema of every SQL module, keyed by module name. */
export const BLOCK_OPTION_SCHEMAS: {
  readonly [M in keyof BlockOptionsRegistry]: BlockOptionsSchema<
    BlockOptionsRegistry[M]
  >;
} = {
  access: accessSqlOptions,
  "access-requests": accessRequestsSqlOptions,
  actor: NO_OPTIONS,
  agents: agentsSqlOptions,
  "ai-cache": aiCacheSqlOptions,
  "ai-chat": aiChatSqlOptions,
  "ai-files": aiFilesSqlOptions,
  "ai-providers": aiProvidersSqlOptions,
  "ai-tasks": aiTasksSqlOptions,
  announcements: announcementsSqlOptions,
  "api-keys": apiKeysSqlOptions,
  approvals: approvalsSqlOptions,
  attachments: attachmentsSqlOptions,
  audit: auditSqlOptions,
  billing: billingSqlOptions,
  bookings: bookingsSqlOptions,
  bulk: bulkSqlOptions,
  calendar: calendarSqlOptions,
  catalog: catalogSqlOptions,
  "chat-sdk-state": NO_OPTIONS,
  collections: collectionsSqlOptions,
  comments: commentsSqlOptions,
  connectors: connectorsSqlOptions,
  credentials: credentialsSqlOptions,
  "custom-fields": customFieldsSqlOptions,
  "data-lifecycle": dataLifecycleSqlOptions,
  deals: dealsSqlOptions,
  documents: documentsSqlOptions,
  domains: domainsSqlOptions,
  drive: driveSqlOptions,
  "drive-files": NO_OPTIONS,
  employees: employeesSqlOptions,
  engagements: engagementsSqlOptions,
  "ensure-rls": NO_OPTIONS,
  entitlements: NO_OPTIONS,
  flags: flagsSqlOptions,
  forms: formsSqlOptions,
  grants: grantsSqlOptions,
  hiring: hiringSqlOptions,
  idempotency: NO_OPTIONS,
  identities: identitiesSqlOptions,
  imports: NO_OPTIONS,
  "oauth-server": oauthServerSqlOptions,
  inbox: inboxSqlOptions,
  inventory: inventorySqlOptions,
  invitations: invitationsSqlOptions,
  invoices: invoicesSqlOptions,
  jobs: jobsSqlOptions,
  "jsonb-schemas": NO_OPTIONS,
  knowledge: knowledgeSqlOptions,
  leave: leaveSqlOptions,
  ledger: NO_OPTIONS,
  assets: assetsSqlOptions,
  guests: NO_OPTIONS,
  memory: memorySqlOptions,
  channels: NO_OPTIONS,
  activity: NO_OPTIONS,
  messaging: messagingSqlOptions,
  metrics: metricsSqlOptions,
  mfa: NO_OPTIONS,
  notifications: notificationsSqlOptions,
  "number-sequences": numberSequencesSqlOptions,
  onboarding: onboardingSqlOptions,
  orders: ordersSqlOptions,
  organizations: organizationsSqlOptions,
  outbox: outboxSqlOptions,
  parties: partiesSqlOptions,
  passes: passesSqlOptions,
  "billable-time": NO_OPTIONS,
  leases: leasesSqlOptions,
  expenses: expensesSqlOptions,
  donations: donationsSqlOptions,
  dispatch: dispatchSqlOptions,
  shipments: shipmentsSqlOptions,
  contracts: contractsSqlOptions,
  controls: controlsSqlOptions,
  incidents: incidentsSqlOptions,
  courses: coursesSqlOptions,
  pgtap: NO_OPTIONS,
  pipelines: pipelinesSqlOptions,
  profiles: profilesSqlOptions,
  promotions: promotionsSqlOptions,
  push: pushSqlOptions,
  quotes: quotesSqlOptions,
  rank: NO_OPTIONS,
  "rate-limit": rateLimitSqlOptions,
  reactions: reactionsSqlOptions,
  "read-sets": NO_OPTIONS,
  "realtime-tables": NO_OPTIONS,
  relations: relationsSqlOptions,
  reminders: remindersSqlOptions,
  "reserved-slugs": reservedSlugsSqlOptions,
  reviews: reviewsSqlOptions,
  rules: rulesSqlOptions,
  scores: scoresSqlOptions,
  moderation: moderationSqlOptions,
  enrollments: enrollmentsSqlOptions,
  "vercel-marketplace": vercelMarketplaceSqlOptions,
  "saved-views": savedViewsSqlOptions,
  search: searchSqlOptions,
  "service-principals": servicePrincipalsSqlOptions,
  sessions: sessionsSqlOptions,
  settings: settingsSqlOptions,
  "share-links": shareLinksSqlOptions,
  "shared-signals": sharedSignalsSqlOptions,
  signatures: signaturesSqlOptions,
  "signing-keys": signingKeysSqlOptions,
  sla: slaSqlOptions,
  sso: ssoSqlOptions,
  "state-machine": stateMachineSqlOptions,
  streams: streamsSqlOptions,
  subjects: NO_OPTIONS,
  "support-sessions": supportSessionsSqlOptions,
  tags: tagsSqlOptions,
  targets: targetsSqlOptions,
  teams: teamsSqlOptions,
  templates: templatesSqlOptions,
  tenant: tenantSqlOptions,
  "time-tracking": timeTrackingSqlOptions,
  trash: trashSqlOptions,
  "updated-at": NO_OPTIONS,
  usage: usageSqlOptions,
  "vector-search": vectorSearchSqlOptions,
  versions: versionsSqlOptions,
  waitlist: waitlistSqlOptions,
  "webhook-inbox": webhookInboxSqlOptions,
  "webhooks-in": webhooksInSqlOptions,
  "webhooks-out": webhooksOutSqlOptions,
  "work-items": workItemsSqlOptions,
  "workflow-builder": workflowBuilderSqlOptions,
  "workflow-sdk-world": workflowSdkWorldSqlOptions,
  workflows: NO_OPTIONS,
};
