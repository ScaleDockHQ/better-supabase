/** A subject a notification is about, e.g. `{ type: 'task', id: '42' }`. */
export interface NotificationSubject {
  readonly type: string;
  readonly id: string;
  /** Shown in the list, e.g. the task title, kept as it was at send time. */
  readonly label?: string;
}

/**
 * A button on a notification, e.g. Approve. The app runs `operation` with
 * `payload` when the recipient picks it, then calls `resolve` with the
 * outcome.
 */
export interface NotificationAction {
  /** Unique within the notification: `[A-Za-z0-9_.:-]`, at most 64 characters. */
  readonly key: string;
  /** At most 100 characters. */
  readonly label: string;
  /** The app's name for what the action does, e.g. `approvals.approve`. */
  readonly operation?: string;
  readonly payload?: Readonly<Record<string, unknown>>;
}

/** One notification as its recipient sees it. */
export interface NotificationItem<K extends string = string, D = unknown> {
  /** The recipient row id: pass it to `markRead` and `dismiss`. */
  readonly id: string;
  /** The shared event id, the same for every recipient. */
  readonly eventId: string;
  readonly type: K;
  readonly data: D;
  readonly tenant: string | null;
  readonly actorId: string | null;
  readonly subject: NotificationSubject | null;
  readonly summary: string | null;
  readonly actionPath: string | null;
  /**
   * Empty without the events table's `actions` column (notifications version
   * 9).
   */
  readonly actions: readonly NotificationAction[];
  readonly priority: string | null;
  readonly createdAt: Temporal.Instant;
  readonly readAt: Temporal.Instant | null;
  readonly resolvedAt: Temporal.Instant | null;
  /** What `resolve` stored for this recipient, e.g. `{ action: "approve" }`. */
  readonly resolution: Readonly<Record<string, unknown>> | null;
  /** The events table's extra columns (`options.extraColumns`), by column name. */
  readonly fields: Readonly<Record<string, unknown>>;
}

/** What `render` returns: the text for one notification, in one locale. */
export interface RenderedText {
  readonly title: string;
  readonly body?: string;
}
