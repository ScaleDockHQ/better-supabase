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

/** `org.*`: organizations and their members. */
export interface OrgEventData {
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

/** Every kit event type and its data. */
export interface KitEventMap {
  "support.started": SupportEventData;
  "support.ended": SupportEventData;
  "support.denied": SupportEventData;
  "org.created": OrgEventData;
  "org.updated": OrgEventData;
  "org.deleted": OrgEventData;
  "org.member_added": OrgEventData;
  "org.member_removed": OrgEventData;
  "org.member_left": OrgEventData;
  "org.role_changed": OrgEventData;
  "org.ownership_transferred": OrgEventData;
  "org.switched": OrgEventData;
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
}

export type KitEventType = keyof KitEventMap;

/** Where an event came from, beyond its data. */
export interface KitEventMeta {
  /** e.g. `organizations/<id>`; becomes the CloudEvents `subject`. */
  readonly subject?: string;
  readonly tenant?: string;
  /** The user who caused it. */
  readonly actorId?: string;
  readonly context?: RequestContext;
}

/** A kit event as `betterSupabase.on('kit', handler)` receives it. */
export type KitEvent<K extends KitEventType = KitEventType> = {
  readonly [T in K]: KitEventMeta & {
    readonly type: T;
    /** A copy: changing it never changes what the kit does (invariant 5). */
    readonly data: KitEventMap[T];
    readonly time: Temporal.Instant;
  };
}[K];

/** A type, or a `prefix.*` pattern such as `support.*`. */
export type KitEventPattern =
  | KitEventType
  | `${KitEventType extends `${infer P}.${string}` ? P : never}.*`;

/** The event types a pattern matches. */
export type KitEventsMatching<P extends KitEventPattern> =
  P extends `${infer Prefix}.*`
    ? Extract<KitEventType, `${Prefix}.${string}`>
    : Extract<P, KitEventType>;

/**
 * Fixed OpenTelemetry attribute names for kit work, so dashboards and
 * queries can rely on them.
 */
export const KIT_ATTRIBUTES = {
  event: "better_supabase.kit.event",
  tenant: "better_supabase.tenant",
  actor: "better_supabase.actor.id",
  supportSessionId: "better_supabase.support.session_id",
  orgId: "better_supabase.org.id",
  invitationId: "better_supabase.invitation.id",
  notificationType: "better_supabase.notification.type",
  webhookEndpointId: "better_supabase.webhook.endpoint_id",
} as const;

/** The `KIT_ATTRIBUTES` an event carries. */
export function kitEventAttributes(event: KitEvent): Record<string, string> {
  const attributes: Record<string, string> = {
    [KIT_ATTRIBUTES.event]: event.type,
  };
  if (event.tenant) attributes[KIT_ATTRIBUTES.tenant] = event.tenant;
  if (event.actorId) attributes[KIT_ATTRIBUTES.actor] = event.actorId;
  const data: Readonly<Record<string, unknown>> = Object.fromEntries(
    Object.entries(event.data),
  );
  const add = (key: string, value: unknown): void => {
    if (typeof value === "string" && value.length > 0) attributes[key] = value;
  };
  add(KIT_ATTRIBUTES.supportSessionId, data["sessionId"]);
  add(KIT_ATTRIBUTES.orgId, data["organizationId"]);
  add(KIT_ATTRIBUTES.invitationId, data["invitationId"]);
  add(KIT_ATTRIBUTES.notificationType, data["type"]);
  add(KIT_ATTRIBUTES.webhookEndpointId, data["endpointId"]);
  return attributes;
}

/**
 * Emits a kit event on `events` with a copy of `data`. Does nothing without
 * a `kit` handler, so kits call it unconditionally.
 */
export function emitKitEvent<K extends KitEventType>(
  events: EventHub,
  type: K,
  data: KitEventMap[K],
  meta: KitEventMeta = {},
): void {
  if (!events.has("kit")) return;
  // SAFETY: cloneValue keeps the shape of plain objects, and the object is
  // the KitEvent<K> member for this type.
  const event = {
    ...meta,
    type,
    data: cloneValue(data),
    time: nowInstant(),
  } as KitEvent;
  events.emit("kit", event);
}

const matches = (pattern: string, type: string): boolean =>
  pattern.endsWith(".*")
    ? type.startsWith(pattern.slice(0, -1))
    : pattern === type;

/**
 * Listens to the kit events that match `pattern` (`'support.started'` or
 * `'support.*'`). Returns a function that stops listening.
 */
export function onKitEvent<P extends KitEventPattern>(
  betterSupabase: { readonly events: EventHub },
  pattern: P,
  handler: (event: KitEvent<KitEventsMatching<P>>) => void,
): () => void {
  return betterSupabase.events.on("kit", (event) => {
    if (!matches(pattern, event.type)) return;
    // SAFETY: matches() checked the type against the pattern.
    handler(event as KitEvent<KitEventsMatching<P>>);
  });
}
