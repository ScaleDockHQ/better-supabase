import {
  type AccessRequestsSqlOptions,
  accessRequestsSqlOptions,
} from "./access-requests/options.ts";
import { type AccessSqlOptions, accessSqlOptions } from "./access/options.ts";
import { type AgentsSqlOptions, agentsSqlOptions } from "./agents/options.ts";
import {
  type AiCacheSqlOptions,
  aiCacheSqlOptions,
} from "./ai-cache/options.ts";
import { type AiChatSqlOptions, aiChatSqlOptions } from "./ai-chat/options.ts";
import {
  type AiFilesSqlOptions,
  aiFilesSqlOptions,
} from "./ai-files/options.ts";
import {
  type AiProvidersSqlOptions,
  aiProvidersSqlOptions,
} from "./ai-providers/options.ts";
import {
  type AiTasksSqlOptions,
  aiTasksSqlOptions,
} from "./ai-tasks/options.ts";
import {
  type AnnouncementsSqlOptions,
  announcementsSqlOptions,
} from "./announcements/options.ts";
import {
  type ApiKeysSqlOptions,
  apiKeysSqlOptions,
} from "./api-keys/options.ts";
import {
  type ApprovalsSqlOptions,
  approvalsSqlOptions,
} from "./approvals/options.ts";
import {
  type AttachmentsSqlOptions,
  attachmentsSqlOptions,
} from "./attachments/options.ts";
import { type AuditSqlOptions, auditSqlOptions } from "./audit/options.ts";
import {
  type BillingSqlOptions,
  billingSqlOptions,
} from "./billing/options.ts";
import { type BulkSqlOptions, bulkSqlOptions } from "./bulk/options.ts";
import {
  type CatalogSqlOptions,
  catalogSqlOptions,
} from "./catalog/options.ts";
import {
  type CommentsSqlOptions,
  commentsSqlOptions,
} from "./comments/options.ts";
import {
  type ConnectorsSqlOptions,
  connectorsSqlOptions,
} from "./connectors/options.ts";
import {
  type CredentialsSqlOptions,
  credentialsSqlOptions,
} from "./credentials/options.ts";
import {
  type CustomFieldsSqlOptions,
  customFieldsSqlOptions,
} from "./custom-fields/options.ts";
import {
  type DataLifecycleSqlOptions,
  dataLifecycleSqlOptions,
} from "./data-lifecycle/options.ts";
import { type DealsSqlOptions, dealsSqlOptions } from "./deals/options.ts";
import {
  type DocumentsSqlOptions,
  documentsSqlOptions,
} from "./documents/options.ts";
import { type DriveSqlOptions, driveSqlOptions } from "./drive/options.ts";
import {
  type EmployeesSqlOptions,
  employeesSqlOptions,
} from "./employees/options.ts";
import {
  type EngagementsSqlOptions,
  engagementsSqlOptions,
} from "./engagements/options.ts";
import { type FlagsSqlOptions, flagsSqlOptions } from "./flags/options.ts";
import {
  type FormsSqlOptions,
  formsSqlOptions,
  type SignaturesSqlOptions,
  signaturesSqlOptions,
} from "./forms/options.ts";
import { type GrantsSqlOptions, grantsSqlOptions } from "./grants/options.ts";
import { type HiringSqlOptions, hiringSqlOptions } from "./hiring/options.ts";
import {
  type IdentitiesSqlOptions,
  identitiesSqlOptions,
} from "./identities/options.ts";
import { type InboxSqlOptions, inboxSqlOptions } from "./inbox/options.ts";
import {
  type InventorySqlOptions,
  inventorySqlOptions,
} from "./inventory/options.ts";
import {
  type InvoicesSqlOptions,
  invoicesSqlOptions,
} from "./invoices/options.ts";
import {
  type JobsSqlOptions,
  jobsSqlOptions,
  type RateLimitSqlOptions,
  rateLimitSqlOptions,
} from "./jobs/options.ts";
import {
  type KnowledgeSqlOptions,
  knowledgeSqlOptions,
} from "./knowledge/options.ts";
import { type MemorySqlOptions, memorySqlOptions } from "./memory/options.ts";
import {
  type MetricsSqlOptions,
  metricsSqlOptions,
} from "./metrics/options.ts";
import {
  type NotificationsSqlOptions,
  notificationsSqlOptions,
} from "./notifications/options.ts";
import {
  type NumberSequencesSqlOptions,
  numberSequencesSqlOptions,
} from "./number-sequences/options.ts";
import {
  type OnboardingSqlOptions,
  onboardingSqlOptions,
} from "./onboarding/options.ts";
import { type BlockOptionsSchema, NO_OPTIONS } from "./options.ts";
import { type OrdersSqlOptions, ordersSqlOptions } from "./orders/options.ts";
import {
  type OrganizationsSqlOptions,
  organizationsSqlOptions,
  type InvitationsSqlOptions,
  invitationsSqlOptions,
} from "./organizations/options.ts";
import { type OutboxSqlOptions, outboxSqlOptions } from "./outbox/options.ts";
import {
  type PartiesSqlOptions,
  partiesSqlOptions,
} from "./parties/options.ts";
import {
  type PipelinesSqlOptions,
  pipelinesSqlOptions,
} from "./pipelines/options.ts";
import {
  type ProfilesSqlOptions,
  profilesSqlOptions,
} from "./profiles/options.ts";
import {
  type PromotionsSqlOptions,
  promotionsSqlOptions,
} from "./promotions/options.ts";
import { type PushSqlOptions, pushSqlOptions } from "./push/options.ts";
import { type QuotesSqlOptions, quotesSqlOptions } from "./quotes/options.ts";
import {
  type ReactionsSqlOptions,
  reactionsSqlOptions,
} from "./reactions/options.ts";
import {
  type RelationsSqlOptions,
  relationsSqlOptions,
} from "./relations/options.ts";
import {
  type RemindersSqlOptions,
  remindersSqlOptions,
} from "./reminders/options.ts";
import {
  type ReservedSlugsSqlOptions,
  reservedSlugsSqlOptions,
} from "./reserved-slugs/options.ts";
import {
  type SavedViewsSqlOptions,
  savedViewsSqlOptions,
} from "./saved-views/options.ts";
import { type SearchSqlOptions, searchSqlOptions } from "./search/options.ts";
import {
  type ServicePrincipalsSqlOptions,
  servicePrincipalsSqlOptions,
} from "./service-principals/options.ts";
import {
  type SessionsSqlOptions,
  sessionsSqlOptions,
} from "./sessions/options.ts";
import {
  type SettingsSqlOptions,
  settingsSqlOptions,
} from "./settings/options.ts";
import {
  type ShareLinksSqlOptions,
  shareLinksSqlOptions,
} from "./share-links/options.ts";
import { type SlaSqlOptions, slaSqlOptions } from "./sla/options.ts";
import { type SsoSqlOptions, ssoSqlOptions } from "./sso/options.ts";
import {
  type StateMachineSqlOptions,
  stateMachineSqlOptions,
} from "./state-machine/options.ts";
import {
  type StreamsSqlOptions,
  streamsSqlOptions,
} from "./streams/options.ts";
import {
  type SupportSessionsSqlOptions,
  supportSessionsSqlOptions,
} from "./support-sessions/options.ts";
import { type TagsSqlOptions, tagsSqlOptions } from "./tags/options.ts";
import { type TeamsSqlOptions, teamsSqlOptions } from "./teams/options.ts";
import { type TenantSqlOptions, tenantSqlOptions } from "./tenant/options.ts";
import {
  type TimeTrackingSqlOptions,
  timeTrackingSqlOptions,
} from "./time-tracking/options.ts";
import { type TrashSqlOptions, trashSqlOptions } from "./trash/options.ts";
import { type UsageSqlOptions, usageSqlOptions } from "./usage/options.ts";
import {
  type VectorSearchSqlOptions,
  vectorSearchSqlOptions,
} from "./vector-search/options.ts";
import {
  type VersionsSqlOptions,
  versionsSqlOptions,
} from "./versions/options.ts";
import {
  type WaitlistSqlOptions,
  waitlistSqlOptions,
} from "./waitlist/options.ts";
import {
  type WebhooksOutSqlOptions,
  webhooksOutSqlOptions,
  type WebhooksInSqlOptions,
  webhooksInSqlOptions,
} from "./webhooks/options.ts";
import {
  type WorkItemsSqlOptions,
  workItemsSqlOptions,
} from "./work-items/options.ts";
import {
  type WorkflowSdkWorldSqlOptions,
  workflowSdkWorldSqlOptions,
} from "./workflow-sdk-world/options.ts";

type None = Record<never, never>;

/**
 * The options of every SQL module, keyed by module name. `BlocksConfig`
 * types `blocks.<module>.options` from it, and `schemas/config-v1.json` is
 * generated from `BLOCK_OPTION_SCHEMAS`.
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
  readonly bookings: None;
  readonly bulk: BulkSqlOptions;
  readonly calendar: None;
  readonly catalog: CatalogSqlOptions;
  readonly "chat-sdk-state": None;
  readonly collections: None;
  readonly comments: CommentsSqlOptions;
  readonly connectors: ConnectorsSqlOptions;
  readonly credentials: CredentialsSqlOptions;
  readonly "custom-fields": CustomFieldsSqlOptions;
  readonly "data-lifecycle": DataLifecycleSqlOptions;
  readonly deals: DealsSqlOptions;
  readonly documents: DocumentsSqlOptions;
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
  readonly inbox: InboxSqlOptions;
  readonly inventory: InventorySqlOptions;
  readonly invitations: InvitationsSqlOptions;
  readonly invoices: InvoicesSqlOptions;
  readonly jobs: JobsSqlOptions;
  readonly "jsonb-schemas": None;
  readonly knowledge: KnowledgeSqlOptions;
  readonly memory: MemorySqlOptions;
  readonly metrics: MetricsSqlOptions;
  readonly mfa: None;
  readonly notifications: NotificationsSqlOptions;
  readonly "number-sequences": NumberSequencesSqlOptions;
  readonly onboarding: OnboardingSqlOptions;
  readonly orders: OrdersSqlOptions;
  readonly organizations: OrganizationsSqlOptions;
  readonly outbox: OutboxSqlOptions;
  readonly parties: PartiesSqlOptions;
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
  readonly "saved-views": SavedViewsSqlOptions;
  readonly search: SearchSqlOptions;
  readonly "service-principals": ServicePrincipalsSqlOptions;
  readonly sessions: SessionsSqlOptions;
  readonly settings: SettingsSqlOptions;
  readonly "share-links": ShareLinksSqlOptions;
  readonly signatures: SignaturesSqlOptions;
  readonly sla: SlaSqlOptions;
  readonly sso: SsoSqlOptions;
  readonly "state-machine": StateMachineSqlOptions;
  readonly streams: StreamsSqlOptions;
  readonly subjects: None;
  readonly "support-sessions": SupportSessionsSqlOptions;
  readonly tags: TagsSqlOptions;
  readonly targets: None;
  readonly teams: TeamsSqlOptions;
  readonly templates: None;
  readonly tenant: TenantSqlOptions;
  readonly "time-tracking": TimeTrackingSqlOptions;
  readonly trash: TrashSqlOptions;
  readonly "updated-at": None;
  readonly usage: UsageSqlOptions;
  readonly "vector-search": VectorSearchSqlOptions;
  readonly versions: VersionsSqlOptions;
  readonly waitlist: WaitlistSqlOptions;
  readonly "webhook-inbox": None;
  readonly "webhooks-in": WebhooksInSqlOptions;
  readonly "webhooks-out": WebhooksOutSqlOptions;
  readonly "work-items": WorkItemsSqlOptions;
  readonly "workflow-builder": None;
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
  bookings: NO_OPTIONS,
  bulk: bulkSqlOptions,
  calendar: NO_OPTIONS,
  catalog: catalogSqlOptions,
  "chat-sdk-state": NO_OPTIONS,
  collections: NO_OPTIONS,
  comments: commentsSqlOptions,
  connectors: connectorsSqlOptions,
  credentials: credentialsSqlOptions,
  "custom-fields": customFieldsSqlOptions,
  "data-lifecycle": dataLifecycleSqlOptions,
  deals: dealsSqlOptions,
  documents: documentsSqlOptions,
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
  inbox: inboxSqlOptions,
  inventory: inventorySqlOptions,
  invitations: invitationsSqlOptions,
  invoices: invoicesSqlOptions,
  jobs: jobsSqlOptions,
  "jsonb-schemas": NO_OPTIONS,
  knowledge: knowledgeSqlOptions,
  memory: memorySqlOptions,
  metrics: metricsSqlOptions,
  mfa: NO_OPTIONS,
  notifications: notificationsSqlOptions,
  "number-sequences": numberSequencesSqlOptions,
  onboarding: onboardingSqlOptions,
  orders: ordersSqlOptions,
  organizations: organizationsSqlOptions,
  outbox: outboxSqlOptions,
  parties: partiesSqlOptions,
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
  "saved-views": savedViewsSqlOptions,
  search: searchSqlOptions,
  "service-principals": servicePrincipalsSqlOptions,
  sessions: sessionsSqlOptions,
  settings: settingsSqlOptions,
  "share-links": shareLinksSqlOptions,
  signatures: signaturesSqlOptions,
  sla: slaSqlOptions,
  sso: ssoSqlOptions,
  "state-machine": stateMachineSqlOptions,
  streams: streamsSqlOptions,
  subjects: NO_OPTIONS,
  "support-sessions": supportSessionsSqlOptions,
  tags: tagsSqlOptions,
  targets: NO_OPTIONS,
  teams: teamsSqlOptions,
  templates: NO_OPTIONS,
  tenant: tenantSqlOptions,
  "time-tracking": timeTrackingSqlOptions,
  trash: trashSqlOptions,
  "updated-at": NO_OPTIONS,
  usage: usageSqlOptions,
  "vector-search": vectorSearchSqlOptions,
  versions: versionsSqlOptions,
  waitlist: waitlistSqlOptions,
  "webhook-inbox": NO_OPTIONS,
  "webhooks-in": webhooksInSqlOptions,
  "webhooks-out": webhooksOutSqlOptions,
  "work-items": workItemsSqlOptions,
  "workflow-builder": NO_OPTIONS,
  "workflow-sdk-world": workflowSdkWorldSqlOptions,
  workflows: NO_OPTIONS,
};
