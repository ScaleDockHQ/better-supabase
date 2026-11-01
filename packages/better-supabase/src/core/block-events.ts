import type { EventMap } from "./event-map.ts";
import type { EventHub } from "./events.ts";
import type { RequestContext } from "./plugin.ts";

import { cloneValue } from "./clone.ts";
import { nowInstant } from "./temporal.ts";

/**
 * `support_session.*`: support sessions, where a platform admin views the app
 * as a user.
 */
export interface SupportEventData {
  /** Absent on `support_session.denied`. */
  readonly sessionId?: string;
  readonly adminId: string;
  readonly targetUserId: string;
  readonly reason?: string;
  readonly readOnly?: boolean;
  readonly expiresAt?: Temporal.Instant;
  /** `support_session.denied`: which check refused it. */
  readonly denial?: "authorize" | "permission" | "policy" | "store";
  /** `support_session.ended`: who or what ended it. */
  readonly endedBy?: "admin" | "expired" | "revoked";
  /** The organization the session is scoped to, when it has one. */
  readonly organizationId?: string | null;
}

/** `organization.*`: organizations and their members. */
export interface OrganizationEventData {
  readonly organizationId: string;
  /** The member the event is about. */
  readonly userId?: string;
  readonly role?: string;
  readonly previousRole?: string;
}

/** `invitation.*`. The token is never part of the event. */
export interface InvitationEventData {
  readonly invitationId: string;
  /** Absent for a platform-scope invitation. */
  readonly organizationId?: string;
  readonly email?: string;
  readonly role?: string;
}

/** `notification.*`. */
export interface NotificationEventData {
  readonly notificationId: string;
  readonly organizationId?: string | null;
  readonly type: string;
  readonly recipientIds?: readonly string[];
  readonly channel?: string;
  readonly error?: string;
}

/**
 * `notification.delivered`, `notification.failed` and the provider events
 * (`opened`, `clicked`, `bounced`, `complained`, `delayed`): the record the
 * notification is about is the subject, or the notification itself when it has
 * none.
 */
export interface NotificationDeliveryEventData
  extends NotificationEventData, SubjectEventData {
  readonly organizationId: string | null;
  readonly deliveryId?: string;
  readonly provider?: string | null;
  readonly providerEventId?: string | null;
}

/** `webhook_endpoint.*`: outgoing webhooks. */
export interface WebhookEventData {
  readonly endpointId: string;
  readonly organizationId?: string;
  /** `webhook_endpoint.disabled`: when the endpoint started failing. */
  readonly failingSince?: string;
  readonly deliveryId?: string;
  readonly eventType?: string;
  /** The HTTP status of the attempt, when there was a response. */
  readonly status?: number;
  readonly attempt?: number;
  readonly error?: string;
}

/** `billing.*`: Stripe customers, checkouts, subscriptions and seats. */
export interface BillingEventData {
  readonly organizationId: string;
  readonly customerId?: string;
  /**
   * The tenant's Stripe Accounts v2 account (`acct_`), when it is billed as
   * one.
   */
  readonly accountId?: string;
  readonly subscriptionId?: string;
  /** The Stripe subscription status. */
  readonly status?: string;
  /** `billing.seats_synced`: the new and the previous quantity. */
  readonly quantity?: number;
  readonly previousQuantity?: number;
  /** The Stripe event that caused it. */
  readonly stripeEventId?: string;
}

/** `attachment.*`, written to the outbox by the attachments module. */
export interface AttachmentEventData {
  readonly attachmentId: string;
  readonly organizationId: string;
  readonly uploadedBy?: string;
  readonly subjectType?: string;
  readonly subjectId?: string;
  readonly mimeType?: string;
  readonly size?: number;
  /** `attachment.scanned`: `clean`, `infected` or `failed`. */
  readonly status?: string;
  /**
   * The file's current version: on `attachment.uploaded`, `.replaced` and
   * `.restored`.
   */
  readonly version?: number;
}

/** `data_export.*`, written to the outbox by the data-lifecycle module. */
export interface DataExportEventData {
  readonly exportId: string;
  readonly subject: "user" | "organization" | "record";
  readonly organizationId?: string;
  readonly userId?: string;
  readonly requestedBy?: string;
  /** Subject `record`: the `config.subjects` type and id that was exported. */
  readonly subjectType?: string;
  readonly subjectId?: string;
  /** `data_export.completed`: the object paths and when they stop being served. */
  readonly files?: readonly string[];
  readonly expiresAt?: string;
  /** `data_export.failed`. */
  readonly error?: string;
}

/**
 * `organization.deletion_*` and `organization.purged`, from the data-lifecycle
 * module.
 */
export interface OrganizationDeletionEventData {
  readonly organizationId: string;
  /** Who requested or cancelled; absent for the purge. */
  readonly userId?: string;
  readonly purgeAfter?: string;
}

/** `legal_hold.*`, from the data-lifecycle module. */
export interface LegalHoldEventData {
  readonly holdId: string;
  /** Absent for a hold on every tenant. */
  readonly organizationId?: string;
  /** Absent for a hold on every kind. */
  readonly kind?: string;
  readonly reason: string;
}

/** `organization.domain_*`, from the sso module. */
export interface OrganizationDomainEventData {
  readonly organizationId: string;
  readonly domainId?: string;
  readonly domain: string;
  /** The member who verified it, when the app passed one. */
  readonly userId?: string | null;
}

/** `waitlist_entry.*`, from the waitlist module. */
export interface WaitlistEventData {
  readonly entryId: string;
  readonly email: string;
}

/**
 * `invite_code.*`, from the waitlist module. The code itself is never part of
 * the event.
 */
export interface InviteCodeEventData {
  readonly codeId: string;
  readonly organizationId?: string | null;
  readonly prefix: string;
  readonly role?: string | null;
}

/** `sso_provider.*`, from the sso module. */
export interface SsoProviderEventData {
  readonly organizationId: string;
  readonly providerId: string;
  readonly domains: readonly string[];
  readonly userId?: string | null;
}

/** `scim_user.*` and `scim_group.*`, from the sso module. */
export interface ScimEventData {
  readonly organizationId: string;
  readonly scimUserId?: string;
  readonly scimGroupId?: string;
}

/** `api_key.*`, from the api-keys module. The secret is never part of the event. */
export interface ApiKeyEventData {
  readonly keyId: string;
  readonly organizationId?: string | null;
  readonly userId?: string | null;
  readonly name: string;
  readonly publicId: string;
  /** `api_key.rotated`: the key it replaced. */
  readonly previousKeyId?: string;
}

/** `organization_setting.*` and `platform_setting.*`, from the settings module. */
export interface SettingEventData {
  readonly organizationId?: string;
  readonly key: string;
}

/** `flag.*`, from the flags module. */
export interface FlagEventData {
  readonly key: string;
  /**
   * `flag.override_changed`: the variant, or `null` when the override was
   * removed.
   */
  readonly variant?: string | null;
  readonly organizationId?: string | null;
  readonly userId?: string | null;
  /** `flag.override_changed` on a custom context, such as `brand`. */
  readonly context?: string | null;
  readonly contextKey?: string | null;
}

/** `announcement.*`, from the announcements module. */
export interface AnnouncementEventData {
  readonly announcementId: string;
}

/**
 * `credential.*`, from the credentials module. The secret is never part of the
 * event.
 */
export interface CredentialEventData {
  readonly provider: string;
  readonly name: string;
}

/** `connector.*` and `connector_grant.*`, from the connectors module. */
export interface ConnectorEventData {
  readonly organizationId: string;
  readonly serverId: string;
  readonly name?: string;
  /** `connector.fingerprint_decided`. */
  readonly fingerprint?: string;
  readonly approved?: boolean;
  /** `connector_grant.*`. */
  readonly grantId?: string;
  readonly userId?: string;
}

/** `agent.*`, from the agents module. */
export interface AgentEventData {
  readonly organizationId: string;
  readonly agentId: string;
  readonly slug?: string;
  readonly visibility?: string;
  /** `agent.installed` and `agent.uninstalled`: the member. */
  readonly userId?: string;
}

/**
 * `ai_provider_key.*`, from the ai-keys module. Only the credential reference
 * is stored.
 */
export interface AiProviderKeyEventData {
  readonly organizationId: string;
  readonly keyId: string;
  readonly provider: string;
  readonly name: string;
}

/**
 * `ai_tool_policy.updated` and `ai_tool_approval.decided`, from the ai-chat
 * module.
 */
export interface AiToolEventData {
  readonly organizationId: string;
  readonly tool: string;
  readonly policy?: string | null;
  readonly chatId?: string;
  readonly approvalId?: string;
  readonly decision?: string;
}

/**
 * `incoming_webhook.*`, from the webhooks-in module. Secrets are never part of
 * the event.
 */
export interface IncomingWebhookEventData {
  readonly organizationId: string;
  readonly endpointId: string;
  readonly name?: string;
  readonly verify?: string;
  readonly enabled?: boolean;
  /** `incoming_webhook.token_rotated`: whether the secret changed too. */
  readonly secretRotated?: boolean;
}

/** `inbox_conversation.*` and `inbox_message.received`, from the inbox module. */
export interface InboxEventData {
  readonly conversationId: string;
  readonly organizationId: string;
  readonly inboxId: string;
  readonly contactId?: string | null;
  readonly assigneeId?: string | null;
  readonly previousAssigneeId?: string | null;
  readonly status?: string;
  /** `inbox_message.received`. */
  readonly messageId?: string;
}

/** `push.*`, from the push module. */
export interface PushDeviceEventData {
  readonly deviceId: string;
  readonly userId: string;
  readonly platform?: string;
  readonly provider?: string;
}

/** `workflow_run.*`, from the workflows module. */
export interface WorkflowRunEventData {
  readonly runId: string;
  readonly organizationId?: string | null;
  readonly engine: string;
  readonly externalId?: string | null;
  readonly definition?: string | null;
  readonly status: string;
  readonly error?: string | null;
  /** The record the run belongs to, when it was started on one. */
  readonly subjectType?: string | null;
  readonly subjectId?: string | null;
}

/**
 * `workflow_definition.published` and `workflow_alert.triggered`, from the
 * workflow-editor module.
 */
export interface WorkflowEventData {
  readonly organizationId?: string | null;
  readonly definitionId?: string;
  readonly versionId?: string;
  readonly version?: number;
  /** `workflow_alert.triggered`. */
  readonly alertId?: string;
  readonly definition?: string;
  readonly onEvent?: string;
  readonly channel?: string;
  readonly runId?: string;
  readonly status?: string;
  readonly error?: string | null;
}

/**
 * `object.uploaded`, from the attachments module: a Storage object in a scanned
 * bucket.
 */
export interface StorageObjectEventData {
  readonly bucket: string;
  readonly path: string;
}

/** `audit.revealed`, from the audit module: who looked at restricted details. */
export interface AuditRevealEventData {
  readonly organizationId?: string | null;
  readonly entries: readonly string[];
}

/**
 * `ai_chat.*` and `ai_chat_message.completed`, written to the outbox by the
 * ai-chat module.
 */
export interface AiChatEventData {
  readonly chatId: string;
  readonly organizationId: string;
  readonly ownerId: string;
  /** `ai_chat_message.completed`: the saved answer. */
  readonly messageId?: string;
  readonly model?: string;
  /** `complete`, `aborted` or `error`. */
  readonly status?: string;
  /** `ai_chat.shared`: the share link and the message it ends at. */
  readonly shareId?: string;
  readonly leafId?: string;
}

/**
 * The keys every subject-bound event carries in its data: the tenant and the
 * record the event is about. Outbox consumers such as `activitySink` and
 * `watcherSink` read these, so they work for every block without per-block
 * code. The CloudEvent `subject` names the block's own row (a comment, a tag),
 * and `partitionkey` repeats the tenant.
 */
export interface SubjectEventData {
  readonly organizationId: string | null;
  readonly subjectType: string;
  readonly subjectId: string;
}

/** The event types in `M` whose data is a `SubjectEventData`. */
export type SubjectEventType<M extends EventMap = EventMap> = {
  readonly [K in keyof M]: M[K] extends SubjectEventData ? K : never;
}[keyof M] &
  string;

/** `SaasEventData` for an event about one subject. */
export type SaasSubjectEventData = SaasEventData & SubjectEventData;

/**
 * Events from the generic SaaS blocks (numbers, teams, tags, status, fields,
 * shares, reminders, imports, saved views, relations, bulk runs).
 */
export interface SaasEventData {
  readonly organizationId?: string | null;
  readonly id?: string;
  readonly entity?: string;
  readonly period?: string;
  readonly number?: number;
  readonly subjectType?: string;
  readonly subjectId?: string;
  readonly from?: string;
  readonly to?: string;
  readonly reason?: string;
  readonly userId?: string;
  readonly kind?: string;
  readonly name?: string;
  readonly status?: string;
  readonly count?: number;
  /** Counts per outcome of one import entity (`import.entity_completed`). */
  readonly counts?: Readonly<Record<string, number>>;
  readonly role?: string;
  readonly error?: string | null;
  /** The other end of a relation, for `subject.linked` and `subject.unlinked`. */
  readonly targetType?: string;
  readonly targetId?: string;
  /** Rows that failed in a bulk run. */
  readonly failed?: number;
  /** When a `status.paused` pause ends, or `null` until it is resumed. */
  readonly until?: string | null;
  /** The lifecycle flag of a `status.flagged` event, and whether it is now on. */
  readonly flag?: string;
  readonly enabled?: boolean;
}

/** Events from the calendar and bookings blocks. */
export interface SchedulingEventData {
  readonly organizationId?: string | null;
  readonly id?: string;
  readonly name?: string;
  readonly calendarId?: string;
  readonly resourceId?: string;
  readonly serviceId?: string | null;
}

/**
 * Events from the collaboration blocks (versions, trash, reactions, approvals,
 * access requests, documents).
 */
export interface CollaborationEventData extends SubjectEventData {
  readonly id?: string;
  readonly number?: number;
  readonly label?: string | null;
  readonly source?: string;
  readonly restoredFrom?: number;
  /** The trash batch: a subject and the children trashed with it. */
  readonly batchId?: string;
  /** The emoji, or a custom emoji's `:shortcode:`. */
  readonly emoji?: string;
  /** Who reacted: a user id, or the name the service passed. */
  readonly actor?: string;
  /** A reaction's kind: `emoji`, or `vote` (whose `emoji` is `vote`). */
  readonly kind?: "emoji" | "vote";
  /** A vote's direction, `1` or `-1`; `1` for an emoji. */
  readonly value?: number;
  /** The action an approval request is for, such as `publish`. */
  readonly action?: string;
  /** An approval request's status after the event. */
  readonly status?: string;
  /** The approval step the request is on, from 0. */
  readonly step?: number;
}

/** Events from the access-requests module. */
export interface AccessRequestEventData {
  readonly organizationId: string;
  readonly userId: string;
  /** The requested role; null for a record request. */
  readonly role: string | null;
  /** The access request. */
  readonly id: string;
  readonly approvalId?: string | null;
  /** When the granted access ends; null for a grant without a duration. */
  readonly expiresAt?: string | null;
  /** `role` for a role request, `record` for access to one record. */
  readonly target?: "role" | "record";
  /** A record request's subject type, such as `client`; null for a role. */
  readonly subjectType?: string | null;
  readonly subjectId?: string | null;
  /** The action a record request asks for, such as `read`. */
  readonly action?: string | null;
  /**
   * For `access_request.ended`: `expired` or `revoked`. For
   * `access_request.emergency_opened`: the reason the user gave.
   */
  readonly reason?: string | null;
  /** For `access_request.emergency_reviewed`: `justified` or `unjustified`. */
  readonly verdict?: "justified" | "unjustified";
}

/**
 * `access_request.emergency_opened` and `access_request.emergency_reviewed`:
 * emergency access is always to one record.
 */
export interface EmergencyAccessEventData extends AccessRequestEventData {
  readonly target: "record";
  readonly subjectType: string;
  readonly subjectId: string;
  readonly action: string;
}

/** `subject_member.added` and `subject_member.ended`, from the subjects block. */
export interface SubjectMemberEventData extends SubjectEventData {
  readonly organizationId: string;
  /** The `subject_members` row. */
  readonly id: string;
  /** Set for a user on the team, null for a team. */
  readonly userId: string | null;
  /** Set for a team on the team, null for a user. */
  readonly teamId: string | null;
  readonly role: string;
  /** The last day the membership counts, `YYYY-MM-DD`, or null. */
  readonly endsOn: string | null;
}

/**
 * `subject.accessed`, from the subjects block: a read of a record whose type
 * has `subjects.<type>.auditReads`. Audit log only, under category `read`.
 */
export interface SubjectAccessedEventData extends SubjectEventData {
  readonly organizationId: string;
  /** Why the record was read, when the caller gave a purpose. */
  readonly purpose: string | null;
  /** The reader held emergency access to the record. */
  readonly emergency: boolean;
  /** The block whose read function returned the record, such as `comments`. */
  readonly block: string | null;
  /** That read function, such as `list_comments`. */
  readonly function: string | null;
}

/** Events from the documents module. */
export interface DocumentEventData extends SubjectEventData {
  readonly organizationId: string;
  /** The document. */
  readonly id: string;
  readonly name: string;
}

/** Events about a suggested change to a document. */
export interface DocumentSuggestionEventData extends DocumentEventData {
  readonly suggestionId: string;
  /** Who suggested the change. */
  readonly authorId: string | null;
  readonly status: "open" | "accepted" | "rejected" | "withdrawn";
}

/**
 * Events from the catalog and inventory blocks. Amounts and quantities are
 * text: JSON numbers lose `bigint` precision.
 */
export interface CommerceEventData {
  readonly organizationId: string | null;
  readonly id?: string;
  readonly slug?: string;
  readonly kind?: string | null;
  readonly from?: string;
  readonly to?: string;
  readonly productId?: string;
  readonly variantId?: string;
  readonly sku?: string;
  readonly priceListId?: string | null;
  readonly currency?: string;
  readonly amount?: string;
  readonly previousAmount?: string | null;
  readonly locationId?: string;
  readonly quantity?: string;
  readonly reason?: string;
  readonly status?: string;
  readonly available?: string;
  readonly reorderPoint?: string;
  /**
   * For allocation events: the document that holds the stock, such as `order`
   * and its id.
   */
  readonly documentType?: string;
  readonly documentId?: string;
  /** For allocation events: the quantity the event allocated. */
  readonly allocated?: string;
  readonly supplierType?: string | null;
  readonly supplierId?: string | null;
  /** For goods receipts: the purchase order the delivery belongs to. */
  readonly purchaseOrderId?: string;
  /** For goods receipts: the incoming inspection the receipt opened. */
  readonly inspectionId?: string | null;
  readonly orderId?: string;
  readonly number?: string;
  readonly customerId?: string | null;
  readonly subtotal?: string;
  readonly discountTotal?: string;
  readonly shippingTotal?: string;
  readonly taxTotal?: string;
  readonly total?: string;
  readonly refundedTotal?: string;
  /** Units across the order's lines. */
  readonly units?: string;
  readonly invoiceNumber?: string | null;
  readonly carrier?: string | null;
  readonly trackingNumber?: string | null;
  readonly promotionId?: string;
  readonly code?: string | null;
}

/** `CommerceEventData` for an event about one subject, such as a variant. */
export type CommerceSubjectEventData = CommerceEventData & SubjectEventData;

/** Events from the drive module. `subjectId` is the node. */
export interface DriveEventData extends SubjectEventData {
  /** For `drive_node.created`: `folder` or `file`. */
  readonly kind?: "folder" | "file";
  /** For `drive_node.created` and `drive_node.renamed`. */
  readonly name?: string;
  /** For `drive_node.renamed`. */
  readonly previousName?: string;
  /** For `drive_node.created` and `drive_node.moved`; `null` at the root. */
  readonly parentId?: string | null;
  /** For `drive_node.moved`. */
  readonly previousParentId?: string | null;
  /**
   * For `drive_node.created`: `internal`, or `request` for a file sent through
   * a file request link.
   */
  readonly source?: string;
  /**
   * For `drive_node.shared` and `drive_node.unshared`: `user`, `team` or
   * `role`.
   */
  readonly principalType?: string;
  readonly principalId?: string;
  /** For `drive_node.shared`. */
  readonly role?: string;
  /** For `drive_node.hold_placed`: when the legal hold ends. */
  readonly legalHoldUntil?: string;
  /**
   * For `drive_node.locked` and `drive_node.unlocked`: who holds, or held, the
   * lock.
   */
  readonly lockedBy?: string;
  /** For `drive_node.locked`: when the lock ends. */
  readonly lockedUntil?: string;
  /** For `drive_node.unlocked`: someone other than the holder broke it. */
  readonly forced?: boolean;
  /**
   * For `drive_node.ownership_transferred` and `drive.ownership_transferred`:
   * the user who held the node or drive, and the user who holds it now.
   */
  readonly fromUserId?: string;
  readonly toUserId?: string;
  /**
   * For `drive_node.download_blocked_changed` and
   * `drive.download_blocked_changed`.
   */
  readonly downloadBlocked?: boolean;
  /**
   * For `drive_node.purged`: the stored objects to delete, as `{ bucket, path
   * }`.
   */
  readonly objects?: readonly {
    readonly bucket: string;
    readonly path: string;
  }[];
  /** For the controlled document events: the document's number. */
  readonly documentNumber?: string;
  /** For `drive_node.document_saved`. */
  readonly documentType?: string;
  /** For `drive_node.document_saved` and `drive_node.review_requested`. */
  readonly ownerId?: string | null;
  /**
   * For `drive_node.submitted` and `drive_node.released`: the attachment sent
   * for release, or released.
   */
  readonly attachmentId?: string;
  /** For `drive_node.submitted`: the approval request. */
  readonly requestId?: string;
  /** For `drive_node.released`: the version that is now effective. */
  readonly versionId?: string;
  /** For `drive_node.obsoleted`. */
  readonly reason?: string | null;
  /** For `drive_node.reviewed`: `unchanged` or `revise`. */
  readonly outcome?: "unchanged" | "revise";
  /** For `drive_node.reviewed`. */
  readonly note?: string | null;
  /** For `drive_node.reviewed` and `drive_node.review_requested`. */
  readonly nextReviewOn?: string;
}

/** `form.created` and `form_version.published` from the forms module. */
export interface FormEventData {
  readonly organizationId: string;
  /** The form, or for `form_version.published` the version. */
  readonly id: string;
  readonly key?: string;
  readonly formId?: string;
  readonly number?: number;
}

/**
 * Submission events from the forms module. The subject is the record the
 * submission is linked to, or the form itself (`form`) when it has none.
 */
export interface FormSubmissionEventData extends SubjectEventData {
  readonly organizationId: string;
  /** The submission. */
  readonly id: string;
  readonly formId: string;
  readonly versionId?: string;
  /** `member`, `public` or `service`. */
  readonly source?: string;
  /** For `form_submission.reviewed`: `submitted`, `accepted` or `rejected`. */
  readonly status?: string;
  /**
   * For `form_submission.submitted` on a scored form: the points earned, out of
   * `maxScore`.
   */
  readonly score?: number;
  readonly maxScore?: number;
  /** Against the pass mark; absent without one. */
  readonly passed?: boolean;
}

/**
 * Signature events from the signatures module. The subject is the record the
 * request asks signers to sign.
 */
export interface SignatureEventData extends SubjectEventData {
  readonly organizationId: string;
  /** The signature request. */
  readonly id: string;
  readonly versionId?: string;
  /** For `signature_request.signed`: the signature. */
  readonly signatureId?: string;
  /** For `signature_request.signed` and `signature_request.declined`. */
  readonly signer?: string;
  /** For `signature_request.signed`: `drawn`, `typed` or `click`. */
  readonly method?: string;
  /** For `signature_request.completed`: what signing meant, such as `approved`. */
  readonly meaning?: string | null;
}

/** `template.published` from the templates module. */
export interface TemplateEventData {
  readonly organizationId: string | null;
  /** The template. */
  readonly id: string;
  readonly versionId: string;
  readonly version: number;
  /** The template type, such as `invoice`. */
  readonly type: string;
}

/**
 * `template.applied` from the templates module. The subject is the record the
 * application created.
 */
export interface TemplateApplicationEventData extends SubjectEventData {
  readonly organizationId: string;
  /** The application. */
  readonly id: string;
  readonly templateId: string;
  readonly versionId: string;
}

/**
 * Time entry events from the time-tracking module. `subjectType` and
 * `subjectId` are null for time not tracked on a record.
 */
export interface TimeEntryEventData {
  readonly organizationId: string;
  /** The time entry. */
  readonly id: string;
  readonly userId: string;
  readonly employeeId?: string;
  readonly subjectType: string | null;
  readonly subjectId: string | null;
  /** When the entry starts, the time metrics bucket its seconds by. */
  readonly startedAt: string;
  /** For `time_entry.updated`: when the entry started before the update. */
  readonly previousStartedAt?: string;
  /** For `time_entry.recorded` and `time_entry.updated`; null while running. */
  readonly seconds?: number | null;
  readonly billable?: boolean;
  /** The hourly rate in minor units, as text (ADR 0037), when the entry has one. */
  readonly rate?: string | null;
  /** The rate's ISO 4217 currency code, set exactly when `rate` is. */
  readonly rateCurrency?: string | null;
}

/** Timesheet events from the time-tracking module. */
export interface TimesheetEventData {
  readonly organizationId: string;
  /** The timesheet. */
  readonly id: string;
  readonly userId: string;
  readonly employeeId?: string;
  /** The Monday the week starts on, as `YYYY-MM-DD`. */
  readonly week: string;
  readonly approvalId: string | null;
}

/** Every block event type and its data. */

export {
  defineEvents,
  event,
  mergeEvents,
  type EventMap,
  type EventMapOf,
  type Events,
  type EventSpec,
  type MergedEventMap,
} from "./event-map.ts";

export type BlockEventType<M extends EventMap = EventMap> = keyof M & string;

/**
 * Event types that changed name in 0.6, old to new, for sinks and consumers
 * that still receive the old ones (`BLOCK_EVENT_RENAMES[type] ?? type`).
 * `better-supabase codemod 0.6` rewrites the string literals.
 */
export const BLOCK_EVENT_RENAMES: Readonly<Record<string, string>> = {
  "org.created": "organization.created",
  "org.updated": "organization.updated",
  "org.deleted": "organization.deleted",
  "org.member_added": "organization.member_added",
  "org.member_removed": "organization.member_removed",
  "org.member_left": "organization.member_left",
  "org.role_changed": "organization.role_changed",
  "org.ownership_transferred": "organization.ownership_transferred",
  "org.switched": "organization.switched",
};

/** Where an event came from, beyond its data. */
export interface BlockEventMeta {
  /** E.g. `organizations/<id>`; becomes the CloudEvents `subject`. */
  readonly subject?: string;
  readonly tenant?: string;
  /** The user who caused it. */
  readonly actorId?: string;
  readonly context?: RequestContext;
}

/**
 * A block event as `betterSupabase.on('block', handler)` receives it. `M` types
 * its data: a block's own events, or the union from `defineBlocks`.
 */
export type BlockEvent<
  M extends EventMap = EventMap,
  K extends BlockEventType<M> = BlockEventType<M>,
> = {
  readonly [T in K]: BlockEventMeta & {
    readonly type: T;
    /** A copy: changing it never changes what the block does (invariant 5). */
    readonly data: M[T];
    readonly time: Temporal.Instant;
  };
}[K];

/** A type, or a `prefix.*` pattern such as `support_session.*`. */
export type BlockEventPattern<M extends EventMap = EventMap> =
  | BlockEventType<M>
  | `${BlockEventType<M> extends `${infer P}.${string}` ? P : never}.*`;

/** The event types a pattern matches. */
export type BlockEventsMatching<
  M extends EventMap,
  P extends BlockEventPattern<M>,
> = P extends `${infer Prefix}.*`
  ? Extract<BlockEventType<M>, `${Prefix}.${string}`>
  : Extract<P, BlockEventType<M>>;

/**
 * Fixed OpenTelemetry attribute names for block work, so dashboards and queries
 * can rely on them.
 */
export const BLOCK_ATTRIBUTES = {
  event: "better_supabase.block.event",
  tenant: "better_supabase.tenant",
  actor: "better_supabase.actor.id",
  supportSessionId: "better_supabase.support.session_id",
  organizationId: "better_supabase.organization.id",
  invitationId: "better_supabase.invitation.id",
  notificationType: "better_supabase.notification.type",
  webhookEndpointId: "better_supabase.webhook.endpoint_id",
} as const;

/** The `BLOCK_ATTRIBUTES` an event carries. */
export function blockEventAttributes(
  event: BlockEvent,
): Record<string, string> {
  const attributes: Record<string, string> = {
    [BLOCK_ATTRIBUTES.event]: event.type,
  };

  if (event.tenant) {
    attributes[BLOCK_ATTRIBUTES.tenant] = event.tenant;
  }

  if (event.actorId) {
    attributes[BLOCK_ATTRIBUTES.actor] = event.actorId;
  }

  const data: Readonly<Record<string, unknown>> = Object.fromEntries(
    Object.entries(event.data),
  );

  const add = (key: string, value: unknown): void => {
    if (typeof value === "string" && value.length > 0) {
      attributes[key] = value;
    }
  };

  add(BLOCK_ATTRIBUTES.supportSessionId, data["sessionId"]);
  add(BLOCK_ATTRIBUTES.organizationId, data["organizationId"]);
  add(BLOCK_ATTRIBUTES.invitationId, data["invitationId"]);
  add(BLOCK_ATTRIBUTES.notificationType, data["type"]);
  add(BLOCK_ATTRIBUTES.webhookEndpointId, data["endpointId"]);

  return attributes;
}

/**
 * Emits a block event on `events` with a copy of `data`. Does nothing without a
 * `block` handler, so blocks call it unconditionally. `M` is the emitting
 * block's event map.
 */
export function emitBlockEvent<
  M extends EventMap,
  K extends BlockEventType<M> = BlockEventType<M>,
>(events: EventHub, type: K, data: M[K], meta: BlockEventMeta = {}): void {
  if (!events.has("block")) {
    return;
  }

  // SAFETY: cloneValue keeps the shape of plain objects, so the copy is the
  // `M[K]` data it was made from.
  const copy = cloneValue(data) as M[K];

  const event: BlockEvent = {
    ...meta,
    type,
    data: copy,
    time: (events.now ?? nowInstant)(),
  };

  events.emit("block", event);
}

/** The options that decide who a block's events are attributed to. */
export interface BlockEmitterOptions {
  /** `betterSupabase.events`. Without it, nothing is emitted. */
  readonly events?: EventHub | undefined;
  readonly actorId?: string | undefined;
  readonly context?: RequestContext | undefined;
}

/** The `emit` of a block whose events are `M`. */
export type BlockEmit<M extends EventMap> = <K extends BlockEventType<M>>(
  type: K,
  data: M[K],
  subject: string,
  tenant?: string | null,
) => void;

/**
 * The `emit` a block creator calls with its own event map: skips the work
 * without an event hub and adds the actor and request context from the block's
 * options.
 */
export function blockEmitter<M extends EventMap>(
  options: BlockEmitterOptions,
): BlockEmit<M> {
  return (type, data, subject, tenant) => {
    if (!options.events) {
      return;
    }

    emitBlockEvent<M>(options.events, type, data, {
      subject,
      ...(tenant ? { tenant } : {}),
      ...(options.actorId ? { actorId: options.actorId } : {}),
      ...(options.context ? { context: options.context } : {}),
    });
  };
}

export { onBlockEvent } from "./block-event-listener.ts";

export type {
  ApplicationEventData,
  ChannelEventData,
  CollectionEntryEventData,
  CollectionEventData,
  SavedItemEventData,
  ConversationEventData,
  EmployeeEventData,
  DealEventData,
  EngagementAmendedEventData,
  EngagementErrorMarkedEventData,
  EngagementEventData,
  EngagementRecordingEventData,
  InvoiceEventData,
  JobEventData,
  MailAccountEventData,
  MailMessageEventData,
  MailTrackingEventData,
  SegmentEventData,
  SegmentMemberEventData,
  AssignmentEventData,
  EnrichmentEventData,
  ForecastSnapshotEventData,
  MessageEventData,
  PartyEventData,
  PipelineEventData,
  PipelineStageEventData,
  QuoteEventData,
  SlaEventData,
  WorkItemEventData,
} from "./block-events-records.ts";

/** `guardrail.blocked`, written to the outbox by the ai-guardrails module. */
export interface GuardrailEventData {
  readonly organizationId?: string | null;
  readonly decisionId: string;
  readonly agent: string;
  /** `input` or `output`. */
  readonly stage: string;
  /** The reasons the check blocked, such as `injection:ignore_instructions`. */
  readonly reasons: readonly unknown[];
}
