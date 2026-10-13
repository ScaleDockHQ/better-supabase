import { sqlTransport } from "better-supabase/blocks";
import {
  createNotifications,
  watcherSink,
} from "better-supabase/blocks/notifications";
import { outboxCloudEvent } from "better-supabase/blocks/outbox";

import type { Session, User } from "./stack.ts";

import { NOTIFICATION_TYPES } from "./notification-types.ts";

/** The notification types the outbox events become, as each recipe's docs page maps them. */
export const WATCHED = {
  "comment.created": "subject.commented",
  "subject.tagged": "subject.tagged",
  "status.changed": "subject.moved",
  "share_link.created": "subject.shared",
  "field_value.set": "subject.field_changed",
} as const;

/** Notifications as the app builds them: the caller's transport and the recipe's types. */
export function notificationsFor(s: Session) {
  return createNotifications({
    transport: sqlTransport(s.sql),
    types: NOTIFICATION_TYPES,
  });
}

/**
 * The outbox relay only claims committed events, and each test rolls back.
 * `watching` builds the CloudEvents the relay would send, with
 * `outboxCloudEvent`, from the events written after it was called.
 */
export async function watching(s: Session) {
  await s.client.query("reset role");
  const [latest] = await s.rows<{ after: string }>(
    "select coalesce(max(position), 0)::text as after from better_supabase.outbox_events",
  );
  const after = latest!.after;
  return {
    /** Sends the new events through the watcher sink, as the relay route does. */
    async relay(): Promise<number> {
      await s.client.query("reset role");
      const rows = await s.rows<OutboxRow>(
        `select position::text, id::text, type, payload, source, subject,
                organization_id::text as tenant, created_at::text
         from better_supabase.outbox_events
         where position > $1::bigint order by position`,
        [after],
      );
      const events = rows.map((row) =>
        outboxCloudEvent(
          {
            position: Number(row.position),
            id: row.id,
            type: row.type,
            payload: row.payload,
            source: row.source,
            subject: row.subject,
            tenant: row.tenant,
            key: null,
            actorId: null,
            createdAt: Temporal.Instant.from(row.created_at),
          },
          { source: "/recipes" },
        ),
      );
      await s.service();
      await watcherSink(notificationsFor(s), { types: WATCHED }).send(events);
      return events.length;
    },
  };
}

interface OutboxRow {
  readonly position: string;
  readonly id: string;
  readonly type: string;
  readonly payload: unknown;
  readonly source: string | null;
  readonly subject: string | null;
  readonly tenant: string | null;
  readonly created_at: string;
}

/** An organization with an owner and a member, one subject row, and the member watching it. */
export async function workspace(
  s: Session,
  subjectType: string,
  insert: string,
): Promise<{
  readonly owner: User;
  readonly member: User;
  readonly organizationId: string;
  readonly subjectId: string;
}> {
  const owner = await s.user("owner");
  const member = await s.user("member");
  const organizationId = await s.organization(owner, [member]);
  await s.client.query("reset role");
  const [row] = await s.rows<{ id: string }>(insert, [organizationId]);
  const subjectId = row!.id;
  await s.watch(member, organizationId, subjectType, subjectId);
  return { owner, member, organizationId, subjectId };
}

/** The notification types `user` received about one subject, sorted by type. */
export async function received(
  s: Session,
  user: User,
  subjectId: string,
): Promise<string[]> {
  await s.client.query("reset role");
  const rows = await s.rows<{ type: string }>(
    `select e.type from better_supabase.notification_events e
     join better_supabase.notification_recipients r on r.event_id = e.id
     where r.user_id = $1 and e.subject_id = $2
     order by e.type`,
    [user.id, subjectId],
  );
  return rows.map((row) => row.type);
}
