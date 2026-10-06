import type { EventHub } from "./events.ts";
import type { RequestContext } from "./plugin.ts";

import { cloneValue } from "./clone.ts";
import { nowInstant } from "./temporal.ts";

/** `support.*`: support sessions, where a platform admin views the app as a user. */
export interface SupportEventData {
  /** Absent on `support.denied`. */
  readonly sessionId?: string;
  readonly adminId: string;
  readonly targetUserId: string;
  readonly reason?: string;
  readonly readOnly?: boolean;
  readonly expiresAt?: Temporal.Instant;
  /** `support.denied`: which check refused it. */
  readonly denial?: "authorize" | "permission" | "policy" | "store";
  /** `support.ended`: who or what ended it. */
  readonly endedBy?: "admin" | "expired" | "revoked";
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
  readonly type: string;
  readonly recipientIds?: readonly string[];
  readonly channel?: string;
  readonly error?: string;
}

/** `webhook.*`: outgoing webhooks. */
export interface WebhookEventData {
  readonly endpointId: string;
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
  readonly subscriptionId?: string;
  /** The Stripe subscription status. */
  readonly status?: string;
  /** `billing.seats_synced`: the new and the previous quantity. */
  readonly quantity?: number;
  readonly previousQuantity?: number;
  /** The Stripe event that caused it. */
  readonly stripeEventId?: string;
}

/** `comment.*`, written to the outbox by the comments module. */
export interface CommentEventData {
  readonly commentId: string;
  readonly organizationId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly authorId?: string;
  readonly parentId?: string;
  /** `comment.created`: every mention; `comment.mentioned`: the new ones. */
  readonly mentionIds?: readonly string[];
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
}

/** `data_export.*`, written to the outbox by the data-lifecycle module. */
export interface DataExportEventData {
  readonly exportId: string;
  readonly subject: "user" | "organization";
  readonly organizationId?: string;
  readonly userId?: string;
  readonly requestedBy?: string;
  /** `data_export.ready`: the object paths and when they stop being served. */
  readonly files?: readonly string[];
  readonly expiresAt?: string;
  /** `data_export.failed`. */
  readonly error?: string;
}

/** `organization.deletion_*` and `organization.purged`, from the data-lifecycle module. */
export interface OrganizationDeletionEventData {
  readonly organizationId: string;
  /** Who requested or cancelled; absent for the purge. */
  readonly userId?: string;
  readonly purgeAfter?: string;
}

/** `organization.domain_verified`, from the sso module. */
export interface OrganizationDomainEventData {
  readonly organizationId: string;
  readonly domain: string;
  /** The member who verified it, when the app passed one. */
  readonly userId?: string | null;
}

/** `waitlist.approved`, from the waitlist module. */
export interface WaitlistEventData {
  readonly entryId: string;
  readonly email: string;
}

/** Every block event type and its data. */
export interface BlockEventMap {
  "support.started": SupportEventData;
  "support.ended": SupportEventData;
  "support.denied": SupportEventData;
  "organization.created": OrganizationEventData;
  "organization.updated": OrganizationEventData;
  "organization.deleted": OrganizationEventData;
  "organization.member_added": OrganizationEventData;
  "organization.member_removed": OrganizationEventData;
  "organization.member_left": OrganizationEventData;
  "organization.role_changed": OrganizationEventData;
  "organization.ownership_transferred": OrganizationEventData;
  "organization.switched": OrganizationEventData;
  "organization.domain_verified": OrganizationDomainEventData;
  "waitlist.approved": WaitlistEventData;
  "invitation.created": InvitationEventData;
  "invitation.resent": InvitationEventData;
  "invitation.accepted": InvitationEventData;
  "invitation.declined": InvitationEventData;
  "invitation.revoked": InvitationEventData;
  "notification.created": NotificationEventData;
  "notification.delivered": NotificationEventData;
  "notification.failed": NotificationEventData;
  "webhook.delivered": WebhookEventData;
  "webhook.failed": WebhookEventData;
  "webhook.disabled": WebhookEventData;
  "billing.customer_linked": BillingEventData;
  "billing.checkout_completed": BillingEventData;
  "billing.subscription_created": BillingEventData;
  "billing.subscription_updated": BillingEventData;
  "billing.subscription_deleted": BillingEventData;
  "billing.seats_synced": BillingEventData;
  "comment.created": CommentEventData;
  "comment.mentioned": CommentEventData;
  "comment.deleted": CommentEventData;
  "attachment.uploaded": AttachmentEventData;
  "attachment.scanned": AttachmentEventData;
  "data_export.requested": DataExportEventData;
  "data_export.ready": DataExportEventData;
  "data_export.failed": DataExportEventData;
  "organization.deletion_requested": OrganizationDeletionEventData;
  "organization.deletion_cancelled": OrganizationDeletionEventData;
  "organization.purged": OrganizationDeletionEventData;
}

export type BlockEventType = keyof BlockEventMap;

/** Where an event came from, beyond its data. */
export interface BlockEventMeta {
  /** e.g. `organizations/<id>`; becomes the CloudEvents `subject`. */
  readonly subject?: string;
  readonly tenant?: string;
  /** The user who caused it. */
  readonly actorId?: string;
  readonly context?: RequestContext;
}

/** A block event as `betterSupabase.on('block', handler)` receives it. */
export type BlockEvent<K extends BlockEventType = BlockEventType> = {
  readonly [T in K]: BlockEventMeta & {
    readonly type: T;
    /** A copy: changing it never changes what the block does (invariant 5). */
    readonly data: BlockEventMap[T];
    readonly time: Temporal.Instant;
  };
}[K];

/** A type, or a `prefix.*` pattern such as `support.*`. */
export type BlockEventPattern =
  | BlockEventType
  | `${BlockEventType extends `${infer P}.${string}` ? P : never}.*`;

/** The event types a pattern matches. */
export type BlockEventsMatching<P extends BlockEventPattern> =
  P extends `${infer Prefix}.*`
    ? Extract<BlockEventType, `${Prefix}.${string}`>
    : Extract<P, BlockEventType>;

/**
 * Fixed OpenTelemetry attribute names for block work, so dashboards and
 * queries can rely on them.
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
  if (event.tenant) attributes[BLOCK_ATTRIBUTES.tenant] = event.tenant;
  if (event.actorId) attributes[BLOCK_ATTRIBUTES.actor] = event.actorId;
  const data: Readonly<Record<string, unknown>> = Object.fromEntries(
    Object.entries(event.data),
  );
  const add = (key: string, value: unknown): void => {
    if (typeof value === "string" && value.length > 0) attributes[key] = value;
  };
  add(BLOCK_ATTRIBUTES.supportSessionId, data["sessionId"]);
  add(BLOCK_ATTRIBUTES.organizationId, data["organizationId"]);
  add(BLOCK_ATTRIBUTES.invitationId, data["invitationId"]);
  add(BLOCK_ATTRIBUTES.notificationType, data["type"]);
  add(BLOCK_ATTRIBUTES.webhookEndpointId, data["endpointId"]);
  return attributes;
}

/**
 * Emits a block event on `events` with a copy of `data`. Does nothing without
 * a `block` handler, so blocks call it unconditionally.
 */
export function emitBlockEvent<K extends BlockEventType>(
  events: EventHub,
  type: K,
  data: BlockEventMap[K],
  meta: BlockEventMeta = {},
): void {
  if (!events.has("block")) return;
  // SAFETY: cloneValue keeps the shape of plain objects, and the object is
  // the BlockEvent<K> member for this type.
  const event = {
    ...meta,
    type,
    data: cloneValue(data),
    time: nowInstant(),
  } as BlockEvent;
  events.emit("block", event);
}

const matches = (pattern: string, type: string): boolean =>
  pattern.endsWith(".*")
    ? type.startsWith(pattern.slice(0, -1))
    : pattern === type;

/**
 * Listens to the block events that match `pattern` (`'support.started'` or
 * `'support.*'`). Returns a function that stops listening.
 */
export function onBlockEvent<P extends BlockEventPattern>(
  betterSupabase: { readonly events: EventHub },
  pattern: P,
  handler: (event: BlockEvent<BlockEventsMatching<P>>) => void,
): () => void {
  return betterSupabase.events.on("block", (event) => {
    if (!matches(pattern, event.type)) return;
    // SAFETY: matches() checked the type against the pattern.
    handler(event as BlockEvent<BlockEventsMatching<P>>);
  });
}
