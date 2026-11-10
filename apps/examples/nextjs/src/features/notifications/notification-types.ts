import type {
  NotificationItem,
  Rendered,
  RenderedText,
} from "better-supabase/blocks/notifications";

import * as v from "valibot";

const TestSent = v.object({
  title: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
});

/** Sent by the sample workflows (`/workflows`). */
const WorkflowMessage = TestSent;

/** Sent when an audit export job finishes; `job` names the file. */
const AuditExportReady = v.object({
  title: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
  job: v.pipe(v.string(), v.uuid()),
});

/** Each notification type and the schema `send` checks its `data` against. */
export const notificationTypes = {
  "test.sent": TestSent,
  "workflow.message": WorkflowMessage,
  "audit.export.ready": AuditExportReady,
};

export function renderNotification(item: NotificationItem): RenderedText {
  if (item.type === "test.sent" && v.is(TestSent, item.data)) {
    return { title: item.data.title };
  }

  if (item.type === "workflow.message" && v.is(WorkflowMessage, item.data)) {
    return { title: item.data.title };
  }

  if (item.type === "audit.export.ready" && v.is(AuditExportReady, item.data)) {
    return { title: item.data.title };
  }

  return { title: item.summary ?? item.type };
}

/** A notification as plain data, so it crosses the server boundary. */
export interface NotificationRow {
  readonly id: string;
  readonly title: string;
  readonly readAt: string | null;
  readonly createdAt: string;
  /** Where the notification leads, such as an export's download. */
  readonly href: string | null;
}

export function toNotificationRow(item: Rendered): NotificationRow {
  return {
    id: item.id,
    title: item.text?.title ?? item.type,
    readAt: item.readAt?.toString() ?? null,
    createdAt: item.createdAt.toString(),
    href: item.actionPath,
  };
}
