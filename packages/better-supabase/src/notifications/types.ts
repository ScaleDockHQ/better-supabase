/** A subject a notification is about, e.g. `{ type: 'task', id: '42' }`. */
export interface NotificationSubject {
  readonly type: string;
  readonly id: string;
  /** Shown in the list, e.g. the task title, kept as it was at send time. */
  readonly label?: string;
}

/** One notification as its recipient sees it. */
export interface NotificationItem<K extends string = string, D = unknown> {
  /** The recipient row id: pass it to `markRead` and `dismiss`. */
  readonly id: string;
  /** The shared event id, the same for every recipient. */
  readonly eventId: string;
  readonly kind: K;
  readonly data: D;
  readonly tenant: string | null;
  readonly actorId: string | null;
  readonly subject: NotificationSubject | null;
  readonly summary: string | null;
  readonly actionPath: string | null;
  readonly priority: string | null;
  readonly createdAt: Temporal.Instant;
  readonly readAt: Temporal.Instant | null;
  readonly resolvedAt: Temporal.Instant | null;
}

/** What `render` returns: the text for one notification, in one locale. */
export interface RenderedText {
  readonly title: string;
  readonly body?: string;
}
