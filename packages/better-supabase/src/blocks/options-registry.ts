import type { AccessRequestsSqlOptions } from "./access-requests/options.ts";
import type { AccountingSqlOptions } from "./accounting/options.ts";
import type { ActivitiesSqlOptions } from "./activities/options.ts";
import type { AgentsSqlOptions } from "./agents/options.ts";
import type { AiCacheSqlOptions } from "./ai-cache/options.ts";
import type { AiChatSqlOptions } from "./ai-chat/options.ts";
import type { AiFilesSqlOptions } from "./ai-files/options.ts";
import type { AiKeysSqlOptions } from "./ai-keys/options.ts";
import type { AiSchedulesSqlOptions } from "./ai-schedules/options.ts";
import type { AnnouncementsSqlOptions } from "./announcements/options.ts";
import type { ApiKeysSqlOptions } from "./api-keys/options.ts";
import type { ApprovalsSqlOptions } from "./approvals/options.ts";
import type { AssetsSqlOptions } from "./assets/options.ts";
import type { AttachmentsSqlOptions } from "./attachments/options.ts";
import type { AuditSqlOptions } from "./audit/options.ts";
import type { AutomationsSqlOptions } from "./automations/options.ts";
import type { BankingSqlOptions } from "./banking/options.ts";
import type { BillingSqlOptions } from "./billing/options.ts";
import type { BookingsSqlOptions } from "./bookings/options.ts";
import type { BulkSqlOptions } from "./bulk/options.ts";
import type { CalendarSqlOptions } from "./calendar/options.ts";
import type { CarePlansSqlOptions } from "./care-plans/options.ts";
import type { CasesSqlOptions } from "./cases/options.ts";
import type { CatalogSqlOptions } from "./catalog/options.ts";
import type { CollectionsSqlOptions } from "./collections/options.ts";
import type { CommentsSqlOptions } from "./comments/options.ts";
import type { ComplianceSqlOptions } from "./compliance/options.ts";
import type { ConnectorsSqlOptions } from "./connectors/options.ts";
import type { ContactsSqlOptions } from "./contacts/options.ts";
import type { ContentSqlOptions } from "./content/options.ts";
import type { ContractsSqlOptions } from "./contracts/options.ts";
import type { CoursesSqlOptions } from "./courses/options.ts";
import type { CreatedBySqlOptions } from "./created-by/options.ts";
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
import type { EnrollmentsSqlOptions } from "./enrollments/options.ts";
import type { ExpensesSqlOptions } from "./expenses/options.ts";
import type { FlagsSqlOptions } from "./flags/options.ts";
import type { FormsSqlOptions } from "./forms/options.ts";
import type { FundingSqlOptions } from "./funding/options.ts";
import type { GoalsSqlOptions } from "./goals/options.ts";
import type { GrantsSqlOptions } from "./grants/options.ts";
import type { GuestsSqlOptions } from "./guests/options.ts";
import type { HiringSqlOptions } from "./hiring/options.ts";
import type { IdentitiesSqlOptions } from "./identities/options.ts";
import type { ImpersonationSqlOptions } from "./impersonation/options.ts";
import type { ImportsSqlOptions } from "./imports/options.ts";
import type { InboxSqlOptions } from "./inbox/options.ts";
import type { IncidentsSqlOptions } from "./incidents/options.ts";
import type { InspectionsSqlOptions } from "./inspections/options.ts";
import type { InventorySqlOptions } from "./inventory/options.ts";
import type { InvoicesSqlOptions } from "./invoices/options.ts";
import type { KnowledgeSqlOptions } from "./knowledge/options.ts";
import type { LeadScoringSqlOptions } from "./lead-scoring/options.ts";
import type { LeasesSqlOptions } from "./leases/options.ts";
import type { LeaveSqlOptions } from "./leave/options.ts";
import type { LegalEntitiesSqlOptions } from "./legal-entities/options.ts";
import type { LimsSqlOptions } from "./lims/options.ts";
import type { MailSyncSqlOptions } from "./mail-sync/options.ts";
import type { ManufacturingSqlOptions } from "./manufacturing/options.ts";
import type { MedicationsSqlOptions } from "./medications/options.ts";
import type { MeetingsSqlOptions } from "./meetings/options.ts";
import type { MembershipsSqlOptions } from "./memberships/options.ts";
import type { MemorySqlOptions } from "./memory/options.ts";
import type { MessagingSqlOptions } from "./messaging/options.ts";
import type { MetricsSqlOptions } from "./metrics/options.ts";
import type { ModerationSqlOptions } from "./moderation/options.ts";
import type { NotificationsSqlOptions } from "./notifications/options.ts";
import type { NumberingSqlOptions } from "./numbering/options.ts";
import type { OauthServerSqlOptions } from "./oauth-server/options.ts";
import type { ObservationsSqlOptions } from "./observations/options.ts";
import type { OnboardingSqlOptions } from "./onboarding/options.ts";
import type { BlockOptionsSchema } from "./options.ts";
import type { OrdersSqlOptions } from "./orders/options.ts";
import type {
  OrganizationsSqlOptions,
  InvitationsSqlOptions,
} from "./organizations/options.ts";
import type { OutboxSqlOptions } from "./outbox/options.ts";
import type { PassesSqlOptions } from "./passes/options.ts";
import type { PayrollExportSqlOptions } from "./payroll-export/options.ts";
import type { PermissionsSqlOptions } from "./permissions/options.ts";
import type { PipelinesSqlOptions } from "./pipelines/options.ts";
import type { PostsSqlOptions } from "./posts/options.ts";
import type { ProfilesSqlOptions } from "./profiles/options.ts";
import type { PromotionsSqlOptions } from "./promotions/options.ts";
import type { PushSqlOptions } from "./push/options.ts";
import type { QualificationsSqlOptions } from "./qualifications/options.ts";
import type {
  QueueSqlOptions,
  RateLimitSqlOptions,
  WebhookInboxSqlOptions,
} from "./queue/options.ts";
import type { QuotesSqlOptions } from "./quotes/options.ts";
import type { ReactionsSqlOptions } from "./reactions/options.ts";
import type { RelationsSqlOptions } from "./relations/options.ts";
import type { RemindersSqlOptions } from "./reminders/options.ts";
import type { ReservedSlugsSqlOptions } from "./reserved-slugs/options.ts";
import type { ReviewsSqlOptions } from "./reviews/options.ts";
import type { RisksSqlOptions } from "./risks/options.ts";
import type { SavedViewsSqlOptions } from "./saved-views/options.ts";
import type { ScoresSqlOptions } from "./scores/options.ts";
import type { SearchSqlOptions } from "./search/options.ts";
import type { SecurityEventsSqlOptions } from "./security-events/options.ts";
import type { SegmentsSqlOptions } from "./segments/options.ts";
import type { SequencesSqlOptions } from "./sequences/options.ts";
import type { ServiceAccountsSqlOptions } from "./service-accounts/options.ts";
import type { SessionsSqlOptions } from "./sessions/options.ts";
import type { SettingsSqlOptions } from "./settings/options.ts";
import type { ShareLinksSqlOptions } from "./share-links/options.ts";
import type { ShiftsSqlOptions } from "./shifts/options.ts";
import type { ShipmentsSqlOptions } from "./shipments/options.ts";
import type { SignaturesSqlOptions } from "./signatures/options.ts";
import type { SigningKeysSqlOptions } from "./signing-keys/options.ts";
import type { SlaSqlOptions } from "./sla/options.ts";
import type { SsoSqlOptions } from "./sso/options.ts";
import type { StateMachineSqlOptions } from "./state-machine/options.ts";
import type { StreamsSqlOptions } from "./streams/options.ts";
import type { SubjectsSqlOptions } from "./subjects/options.ts";
import type { TagsSqlOptions } from "./tags/options.ts";
import type { TasksSqlOptions } from "./tasks/options.ts";
import type { TeamsSqlOptions } from "./teams/options.ts";
import type { TemplatesSqlOptions } from "./templates/options.ts";
import type { TimeTrackingSqlOptions } from "./time-tracking/options.ts";
import type { TrashSqlOptions } from "./trash/options.ts";
import type { UpdatedAtSqlOptions } from "./updated-at/options.ts";
import type { UsageSqlOptions } from "./usage/options.ts";
import type { VectorSearchSqlOptions } from "./vector-search/options.ts";
import type { VercelMarketplaceSqlOptions } from "./vercel-marketplace/options.ts";
import type { VersionsSqlOptions } from "./versions/options.ts";
import type { WaitlistSqlOptions } from "./waitlist/options.ts";
import type {
  WebhooksOutSqlOptions,
  WebhooksInSqlOptions,
} from "./webhooks/options.ts";
import type { WorkflowEditorSqlOptions } from "./workflow-editor/options.ts";
import type { WorkflowSdkSqlOptions } from "./workflow-sdk/options.ts";

import { accessRequestsSqlOptions } from "./access-requests/options.ts";
import { accountingSqlOptions } from "./accounting/options.ts";
import { activitiesSqlOptions } from "./activities/options.ts";
import { agentsSqlOptions } from "./agents/options.ts";
import { aiCacheSqlOptions } from "./ai-cache/options.ts";
import { aiChatSqlOptions } from "./ai-chat/options.ts";
import { aiFilesSqlOptions } from "./ai-files/options.ts";
import { aiKeysSqlOptions } from "./ai-keys/options.ts";
import { aiSchedulesSqlOptions } from "./ai-schedules/options.ts";
import { announcementsSqlOptions } from "./announcements/options.ts";
import { apiKeysSqlOptions } from "./api-keys/options.ts";
import { approvalsSqlOptions } from "./approvals/options.ts";
import { assetsSqlOptions } from "./assets/options.ts";
import { attachmentsSqlOptions } from "./attachments/options.ts";
import { auditSqlOptions } from "./audit/options.ts";
import { automationsSqlOptions } from "./automations/options.ts";
import { bankingSqlOptions } from "./banking/options.ts";
import { billingSqlOptions } from "./billing/options.ts";
import { bookingsSqlOptions } from "./bookings/options.ts";
import { bulkSqlOptions } from "./bulk/options.ts";
import { calendarSqlOptions } from "./calendar/options.ts";
import { carePlansSqlOptions } from "./care-plans/options.ts";
import { casesSqlOptions } from "./cases/options.ts";
import { catalogSqlOptions } from "./catalog/options.ts";
import { collectionsSqlOptions } from "./collections/options.ts";
import { commentsSqlOptions } from "./comments/options.ts";
import { complianceSqlOptions } from "./compliance/options.ts";
import { connectorsSqlOptions } from "./connectors/options.ts";
import { contactsSqlOptions } from "./contacts/options.ts";
import { contentSqlOptions } from "./content/options.ts";
import { contractsSqlOptions } from "./contracts/options.ts";
import { coursesSqlOptions } from "./courses/options.ts";
import { createdBySqlOptions } from "./created-by/options.ts";
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
import { enrollmentsSqlOptions } from "./enrollments/options.ts";
import { expensesSqlOptions } from "./expenses/options.ts";
import { flagsSqlOptions } from "./flags/options.ts";
import { formsSqlOptions } from "./forms/options.ts";
import { fundingSqlOptions } from "./funding/options.ts";
import { goalsSqlOptions } from "./goals/options.ts";
import { grantsSqlOptions } from "./grants/options.ts";
import { guestsSqlOptions } from "./guests/options.ts";
import { hiringSqlOptions } from "./hiring/options.ts";
import { identitiesSqlOptions } from "./identities/options.ts";
import { impersonationSqlOptions } from "./impersonation/options.ts";
import { importsSqlOptions } from "./imports/options.ts";
import { inboxSqlOptions } from "./inbox/options.ts";
import { incidentsSqlOptions } from "./incidents/options.ts";
import { inspectionsSqlOptions } from "./inspections/options.ts";
import { inventorySqlOptions } from "./inventory/options.ts";
import { invoicesSqlOptions } from "./invoices/options.ts";
import { knowledgeSqlOptions } from "./knowledge/options.ts";
import { leadScoringSqlOptions } from "./lead-scoring/options.ts";
import { leasesSqlOptions } from "./leases/options.ts";
import { leaveSqlOptions } from "./leave/options.ts";
import { legalEntitiesSqlOptions } from "./legal-entities/options.ts";
import { limsSqlOptions } from "./lims/options.ts";
import { mailSyncSqlOptions } from "./mail-sync/options.ts";
import { manufacturingSqlOptions } from "./manufacturing/options.ts";
import { medicationsSqlOptions } from "./medications/options.ts";
import { meetingsSqlOptions } from "./meetings/options.ts";
import { membershipsSqlOptions } from "./memberships/options.ts";
import { memorySqlOptions } from "./memory/options.ts";
import { messagingSqlOptions } from "./messaging/options.ts";
import { metricsSqlOptions } from "./metrics/options.ts";
import { moderationSqlOptions } from "./moderation/options.ts";
import { notificationsSqlOptions } from "./notifications/options.ts";
import { numberingSqlOptions } from "./numbering/options.ts";
import { oauthServerSqlOptions } from "./oauth-server/options.ts";
import { observationsSqlOptions } from "./observations/options.ts";
import { onboardingSqlOptions } from "./onboarding/options.ts";
import { NO_OPTIONS } from "./options.ts";
import { ordersSqlOptions } from "./orders/options.ts";
import {
  organizationsSqlOptions,
  invitationsSqlOptions,
} from "./organizations/options.ts";
import { outboxSqlOptions } from "./outbox/options.ts";
import { passesSqlOptions } from "./passes/options.ts";
import { payrollExportSqlOptions } from "./payroll-export/options.ts";
import { permissionsSqlOptions } from "./permissions/options.ts";
import { pipelinesSqlOptions } from "./pipelines/options.ts";
import { postsSqlOptions } from "./posts/options.ts";
import { profilesSqlOptions } from "./profiles/options.ts";
import { promotionsSqlOptions } from "./promotions/options.ts";
import { pushSqlOptions } from "./push/options.ts";
import { qualificationsSqlOptions } from "./qualifications/options.ts";
import {
  queueSqlOptions,
  rateLimitSqlOptions,
  webhookInboxSqlOptions,
} from "./queue/options.ts";
import { quotesSqlOptions } from "./quotes/options.ts";
import { reactionsSqlOptions } from "./reactions/options.ts";
import { relationsSqlOptions } from "./relations/options.ts";
import { remindersSqlOptions } from "./reminders/options.ts";
import { reservedSlugsSqlOptions } from "./reserved-slugs/options.ts";
import { reviewsSqlOptions } from "./reviews/options.ts";
import { risksSqlOptions } from "./risks/options.ts";
import { savedViewsSqlOptions } from "./saved-views/options.ts";
import { scoresSqlOptions } from "./scores/options.ts";
import { searchSqlOptions } from "./search/options.ts";
import { securityEventsSqlOptions } from "./security-events/options.ts";
import { segmentsSqlOptions } from "./segments/options.ts";
import { sequencesSqlOptions } from "./sequences/options.ts";
import { serviceAccountsSqlOptions } from "./service-accounts/options.ts";
import { sessionsSqlOptions } from "./sessions/options.ts";
import { settingsSqlOptions } from "./settings/options.ts";
import { shareLinksSqlOptions } from "./share-links/options.ts";
import { shiftsSqlOptions } from "./shifts/options.ts";
import { shipmentsSqlOptions } from "./shipments/options.ts";
import { signaturesSqlOptions } from "./signatures/options.ts";
import { signingKeysSqlOptions } from "./signing-keys/options.ts";
import { slaSqlOptions } from "./sla/options.ts";
import { ssoSqlOptions } from "./sso/options.ts";
import { stateMachineSqlOptions } from "./state-machine/options.ts";
import { streamsSqlOptions } from "./streams/options.ts";
import { subjectsSqlOptions } from "./subjects/options.ts";
import { tagsSqlOptions } from "./tags/options.ts";
import { tasksSqlOptions } from "./tasks/options.ts";
import { teamsSqlOptions } from "./teams/options.ts";
import { templatesSqlOptions } from "./templates/options.ts";
import { timeTrackingSqlOptions } from "./time-tracking/options.ts";
import { trashSqlOptions } from "./trash/options.ts";
import { updatedAtSqlOptions } from "./updated-at/options.ts";
import { usageSqlOptions } from "./usage/options.ts";
import { vectorSearchSqlOptions } from "./vector-search/options.ts";
import { vercelMarketplaceSqlOptions } from "./vercel-marketplace/options.ts";
import { versionsSqlOptions } from "./versions/options.ts";
import { waitlistSqlOptions } from "./waitlist/options.ts";
import {
  webhooksOutSqlOptions,
  webhooksInSqlOptions,
} from "./webhooks/options.ts";
import { workflowEditorSqlOptions } from "./workflow-editor/options.ts";
import { workflowSdkSqlOptions } from "./workflow-sdk/options.ts";

type None = Record<never, never>;

/**
 * The options of every SQL module, keyed by module name. `BlocksConfig` types
 * `blocks.<module>.options` from it, and `schemas/config-v1.json` is generated
 * from `BLOCK_OPTION_SCHEMAS`.
 */
export interface BlockOptionsRegistry {
  readonly "access-requests": AccessRequestsSqlOptions;
  readonly accounting: AccountingSqlOptions;
  readonly acknowledgements: None;
  readonly activities: ActivitiesSqlOptions;
  readonly agents: AgentsSqlOptions;
  readonly "ai-cache": AiCacheSqlOptions;
  readonly "ai-chat": AiChatSqlOptions;
  readonly "ai-files": AiFilesSqlOptions;
  readonly "ai-keys": AiKeysSqlOptions;
  readonly "ai-schedules": AiSchedulesSqlOptions;
  readonly announcements: AnnouncementsSqlOptions;
  readonly "api-keys": ApiKeysSqlOptions;
  readonly approvals: ApprovalsSqlOptions;
  readonly assets: AssetsSqlOptions;
  readonly assignment: None;
  readonly attachments: AttachmentsSqlOptions;
  readonly audit: AuditSqlOptions;
  readonly automations: AutomationsSqlOptions;
  readonly banking: BankingSqlOptions;
  readonly tax: Record<never, never>;
  readonly "document-templates": None;
  readonly "payroll-export": PayrollExportSqlOptions;
  readonly "billable-time": None;
  readonly billing: BillingSqlOptions;
  readonly bookings: BookingsSqlOptions;
  readonly bulk: BulkSqlOptions;
  readonly calendar: CalendarSqlOptions;
  readonly "care-plans": CarePlansSqlOptions;
  readonly catalog: CatalogSqlOptions;
  readonly channels: None;
  readonly "chat-sdk-state": None;
  readonly collections: CollectionsSqlOptions;
  readonly comments: CommentsSqlOptions;
  readonly compliance: ComplianceSqlOptions;
  readonly connectors: ConnectorsSqlOptions;
  readonly consents: None;
  readonly contacts: ContactsSqlOptions;
  readonly contracts: ContractsSqlOptions;
  readonly courses: CoursesSqlOptions;
  readonly "created-by": CreatedBySqlOptions;
  readonly credentials: CredentialsSqlOptions;
  readonly "custom-fields": CustomFieldsSqlOptions;
  readonly flags: FlagsSqlOptions;
  readonly "data-lifecycle": DataLifecycleSqlOptions;
  readonly deals: DealsSqlOptions;
  readonly dispatch: DispatchSqlOptions;
  readonly documents: DocumentsSqlOptions;
  readonly domains: DomainsSqlOptions;
  readonly donations: DonationsSqlOptions;
  readonly drive: DriveSqlOptions;
  readonly "drive-files": None;
  readonly employees: EmployeesSqlOptions;
  readonly enrichment: None;
  readonly enrollments: EnrollmentsSqlOptions;
  readonly entitlements: None;
  readonly expenses: ExpensesSqlOptions;
  readonly "field-encryption": None;
  readonly "field-history": None;
  readonly forecasts: None;
  readonly forms: FormsSqlOptions;
  readonly goals: GoalsSqlOptions;
  readonly grants: GrantsSqlOptions;
  readonly guests: GuestsSqlOptions;
  readonly hiring: HiringSqlOptions;
  readonly idempotency: None;
  readonly identities: IdentitiesSqlOptions;
  readonly impersonation: ImpersonationSqlOptions;
  readonly imports: ImportsSqlOptions;
  readonly inbox: InboxSqlOptions;
  readonly incidents: IncidentsSqlOptions;
  readonly inspections: InspectionsSqlOptions;
  readonly meetings: MeetingsSqlOptions;
  readonly maintenance: Record<never, never>;
  readonly dam: Record<never, never>;
  readonly lims: LimsSqlOptions;
  readonly inventory: InventorySqlOptions;
  readonly invitations: InvitationsSqlOptions;
  readonly invoices: InvoicesSqlOptions;
  readonly "jsonb-schemas": None;
  readonly knowledge: KnowledgeSqlOptions;
  readonly "lead-scoring": LeadScoringSqlOptions;
  readonly leases: LeasesSqlOptions;
  readonly leave: LeaveSqlOptions;
  readonly ledger: None;
  readonly "legal-entities": LegalEntitiesSqlOptions;
  readonly "mail-sync": MailSyncSqlOptions;
  readonly manufacturing: ManufacturingSqlOptions;
  readonly funding: FundingSqlOptions;
  readonly memberships: MembershipsSqlOptions;
  readonly memory: MemorySqlOptions;
  readonly messaging: MessagingSqlOptions;
  readonly metrics: MetricsSqlOptions;
  readonly mfa: None;
  readonly moderation: ModerationSqlOptions;
  readonly notifications: NotificationsSqlOptions;
  readonly numbering: NumberingSqlOptions;
  readonly "oauth-server": OauthServerSqlOptions;
  readonly onboarding: OnboardingSqlOptions;
  readonly orders: OrdersSqlOptions;
  readonly organizations: OrganizationsSqlOptions;
  readonly outbox: OutboxSqlOptions;
  readonly passes: PassesSqlOptions;
  readonly permissions: PermissionsSqlOptions;
  readonly pgtap: None;
  readonly pipelines: PipelinesSqlOptions;
  readonly posts: PostsSqlOptions;
  readonly content: ContentSqlOptions;
  readonly qualifications: QualificationsSqlOptions;
  readonly shifts: ShiftsSqlOptions;
  readonly medications: MedicationsSqlOptions;
  readonly profiles: ProfilesSqlOptions;
  readonly promotions: PromotionsSqlOptions;
  readonly push: PushSqlOptions;
  readonly queue: QueueSqlOptions;
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
  readonly risks: RisksSqlOptions;
  readonly cases: CasesSqlOptions;
  readonly observations: ObservationsSqlOptions;
  readonly "rls-guard": None;
  readonly "saved-views": SavedViewsSqlOptions;
  readonly scores: ScoresSqlOptions;
  readonly search: SearchSqlOptions;
  readonly "security-events": SecurityEventsSqlOptions;
  readonly segments: SegmentsSqlOptions;
  readonly sequences: SequencesSqlOptions;
  readonly "service-accounts": ServiceAccountsSqlOptions;
  readonly sessions: SessionsSqlOptions;
  readonly settings: SettingsSqlOptions;
  readonly "share-links": ShareLinksSqlOptions;
  readonly shipments: ShipmentsSqlOptions;
  readonly signatures: SignaturesSqlOptions;
  readonly "signing-keys": SigningKeysSqlOptions;
  readonly sla: SlaSqlOptions;
  readonly sso: SsoSqlOptions;
  readonly "state-machine": StateMachineSqlOptions;
  readonly streams: StreamsSqlOptions;
  readonly subjects: SubjectsSqlOptions;
  readonly tags: TagsSqlOptions;
  readonly tasks: TasksSqlOptions;
  readonly teams: TeamsSqlOptions;
  readonly templates: TemplatesSqlOptions;
  readonly "time-tracking": TimeTrackingSqlOptions;
  readonly timeline: None;
  readonly trash: TrashSqlOptions;
  readonly "updated-at": UpdatedAtSqlOptions;
  readonly usage: UsageSqlOptions;
  readonly "vector-search": VectorSearchSqlOptions;
  readonly "vercel-marketplace": VercelMarketplaceSqlOptions;
  readonly versions: VersionsSqlOptions;
  readonly waitlist: WaitlistSqlOptions;
  readonly "webhook-inbox": WebhookInboxSqlOptions;
  readonly "webhooks-in": WebhooksInSqlOptions;
  readonly "webhooks-out": WebhooksOutSqlOptions;
  readonly "workflow-editor": WorkflowEditorSqlOptions;
  readonly "workflow-sdk": WorkflowSdkSqlOptions;
  readonly workflows: None;
}

/** The options schema of every SQL module, keyed by module name. */
export const BLOCK_OPTION_SCHEMAS: {
  readonly [M in keyof BlockOptionsRegistry]: BlockOptionsSchema<
    BlockOptionsRegistry[M]
  >;
} = {
  "access-requests": accessRequestsSqlOptions,
  accounting: accountingSqlOptions,
  activities: activitiesSqlOptions,
  agents: agentsSqlOptions,
  "ai-cache": aiCacheSqlOptions,
  "ai-chat": aiChatSqlOptions,
  "ai-files": aiFilesSqlOptions,
  "ai-keys": aiKeysSqlOptions,
  "ai-schedules": aiSchedulesSqlOptions,
  announcements: announcementsSqlOptions,
  acknowledgements: NO_OPTIONS,
  "api-keys": apiKeysSqlOptions,
  approvals: approvalsSqlOptions,
  assets: assetsSqlOptions,
  manufacturing: manufacturingSqlOptions,
  funding: fundingSqlOptions,
  passes: passesSqlOptions,
  assignment: NO_OPTIONS,
  attachments: attachmentsSqlOptions,
  audit: auditSqlOptions,
  automations: automationsSqlOptions,
  banking: bankingSqlOptions,
  tax: NO_OPTIONS,
  "document-templates": NO_OPTIONS,
  "payroll-export": payrollExportSqlOptions,
  "billable-time": NO_OPTIONS,
  billing: billingSqlOptions,
  bookings: bookingsSqlOptions,
  bulk: bulkSqlOptions,
  calendar: calendarSqlOptions,
  "care-plans": carePlansSqlOptions,
  catalog: catalogSqlOptions,
  channels: NO_OPTIONS,
  "chat-sdk-state": NO_OPTIONS,
  collections: collectionsSqlOptions,
  comments: commentsSqlOptions,
  compliance: complianceSqlOptions,
  connectors: connectorsSqlOptions,
  consents: NO_OPTIONS,
  contacts: contactsSqlOptions,
  contracts: contractsSqlOptions,
  courses: coursesSqlOptions,
  "created-by": createdBySqlOptions,
  credentials: credentialsSqlOptions,
  "custom-fields": customFieldsSqlOptions,
  "data-lifecycle": dataLifecycleSqlOptions,
  deals: dealsSqlOptions,
  dispatch: dispatchSqlOptions,
  documents: documentsSqlOptions,
  domains: domainsSqlOptions,
  donations: donationsSqlOptions,
  drive: driveSqlOptions,
  grants: grantsSqlOptions,
  "drive-files": NO_OPTIONS,
  employees: employeesSqlOptions,
  enrichment: NO_OPTIONS,
  enrollments: enrollmentsSqlOptions,
  entitlements: NO_OPTIONS,
  expenses: expensesSqlOptions,
  flags: flagsSqlOptions,
  "field-encryption": NO_OPTIONS,
  "field-history": NO_OPTIONS,
  forecasts: NO_OPTIONS,
  forms: formsSqlOptions,
  goals: goalsSqlOptions,
  guests: guestsSqlOptions,
  hiring: hiringSqlOptions,
  idempotency: NO_OPTIONS,
  impersonation: impersonationSqlOptions,
  imports: importsSqlOptions,
  inbox: inboxSqlOptions,
  incidents: incidentsSqlOptions,
  inspections: inspectionsSqlOptions,
  meetings: meetingsSqlOptions,
  inventory: inventorySqlOptions,
  invitations: invitationsSqlOptions,
  invoices: invoicesSqlOptions,
  "jsonb-schemas": NO_OPTIONS,
  knowledge: knowledgeSqlOptions,
  "lead-scoring": leadScoringSqlOptions,
  leases: leasesSqlOptions,
  leave: leaveSqlOptions,
  ledger: NO_OPTIONS,
  identities: identitiesSqlOptions,
  "legal-entities": legalEntitiesSqlOptions,
  "mail-sync": mailSyncSqlOptions,
  maintenance: NO_OPTIONS,
  dam: NO_OPTIONS,
  lims: limsSqlOptions,
  memberships: membershipsSqlOptions,
  memory: memorySqlOptions,
  messaging: messagingSqlOptions,
  metrics: metricsSqlOptions,
  mfa: NO_OPTIONS,
  moderation: moderationSqlOptions,
  notifications: notificationsSqlOptions,
  numbering: numberingSqlOptions,
  "oauth-server": oauthServerSqlOptions,
  onboarding: onboardingSqlOptions,
  orders: ordersSqlOptions,
  organizations: organizationsSqlOptions,
  outbox: outboxSqlOptions,
  permissions: permissionsSqlOptions,
  pgtap: NO_OPTIONS,
  pipelines: pipelinesSqlOptions,
  posts: postsSqlOptions,
  content: contentSqlOptions,
  qualifications: qualificationsSqlOptions,
  shifts: shiftsSqlOptions,
  medications: medicationsSqlOptions,
  profiles: profilesSqlOptions,
  promotions: promotionsSqlOptions,
  push: pushSqlOptions,
  queue: queueSqlOptions,
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
  risks: risksSqlOptions,
  cases: casesSqlOptions,
  observations: observationsSqlOptions,
  "rls-guard": NO_OPTIONS,
  "saved-views": savedViewsSqlOptions,
  scores: scoresSqlOptions,
  search: searchSqlOptions,
  "security-events": securityEventsSqlOptions,
  segments: segmentsSqlOptions,
  sequences: sequencesSqlOptions,
  "service-accounts": serviceAccountsSqlOptions,
  sessions: sessionsSqlOptions,
  settings: settingsSqlOptions,
  "share-links": shareLinksSqlOptions,
  shipments: shipmentsSqlOptions,
  signatures: signaturesSqlOptions,
  "signing-keys": signingKeysSqlOptions,
  sla: slaSqlOptions,
  sso: ssoSqlOptions,
  "state-machine": stateMachineSqlOptions,
  streams: streamsSqlOptions,
  subjects: subjectsSqlOptions,
  tags: tagsSqlOptions,
  tasks: tasksSqlOptions,
  teams: teamsSqlOptions,
  templates: templatesSqlOptions,
  "time-tracking": timeTrackingSqlOptions,
  timeline: NO_OPTIONS,
  trash: trashSqlOptions,
  "updated-at": updatedAtSqlOptions,
  usage: usageSqlOptions,
  "vector-search": vectorSearchSqlOptions,
  "vercel-marketplace": vercelMarketplaceSqlOptions,
  versions: versionsSqlOptions,
  waitlist: waitlistSqlOptions,
  "webhook-inbox": webhookInboxSqlOptions,
  "webhooks-in": webhooksInSqlOptions,
  "webhooks-out": webhooksOutSqlOptions,
  "workflow-editor": workflowEditorSqlOptions,
  "workflow-sdk": workflowSdkSqlOptions,
  workflows: NO_OPTIONS,
};

/** The manifest's options schema of `module`, when it is a built-in module. */
export function optionSchemaOf(module: string): BlockOptionsSchema | undefined {
  return Object.entries(BLOCK_OPTION_SCHEMAS).find(
    ([name]) => name === module,
  )?.[1];
}
