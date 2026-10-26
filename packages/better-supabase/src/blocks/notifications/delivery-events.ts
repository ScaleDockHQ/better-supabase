import type { BlockEmit } from "../../core/block-events.ts";
import type { DeliveryEventKind, RecordedDeliveryEvent } from "./api-types.ts";
import type { NotificationsEvents } from "./events.ts";

import { isRecord, nullableText } from "../shared.ts";

const DELIVERY_EVENT_KINDS: readonly DeliveryEventKind[] = [
  "delivered",
  "opened",
  "clicked",
  "bounced",
  "complained",
  "delayed",
];

export const deliveryEventKindOf = (value: unknown): DeliveryEventKind | null =>
  DELIVERY_EVENT_KINDS.find((kind) => kind === value) ?? null;

/** One `record_delivery_event` result, or `null` for an unknown shape. */
export function recordedDeliveryEventOf(
  value: unknown,
): RecordedDeliveryEvent | null {
  if (!isRecord(value)) {
    return null;
  }

  const kind = deliveryEventKindOf(value["kind"]);

  if (kind === null) {
    return null;
  }

  return {
    deliveryId: String(value["delivery_id"]),
    notificationId: String(value["notification_id"]),
    tenant: nullableText(value["tenant"]),
    type: String(value["type"]),
    channel: String(value["channel"]),
    userId: nullableText(value["user_id"]),
    subject: {
      type: String(value["subject_type"]),
      id: String(value["subject_id"]),
    },
    kind,
    providerStatus: deliveryEventKindOf(value["provider_status"]),
    recorded: value["recorded"] === true,
  };
}

/**
 * Emits `notification.<kind>` for a provider event `record_delivery_event`
 * stored, and nothing for one it had already stored.
 */
export function emitDeliveryEvent(
  emit: BlockEmit<NotificationsEvents>,
  recorded: RecordedDeliveryEvent,
  provider: string,
  providerEventId: string | null,
): void {
  if (!recorded.recorded) {
    return;
  }

  emit(
    `notification.${recorded.kind}`,
    {
      notificationId: recorded.notificationId,
      organizationId: recorded.tenant,
      type: recorded.type,
      channel: recorded.channel,
      deliveryId: recorded.deliveryId,
      provider,
      providerEventId,
      subjectType: recorded.subject.type,
      subjectId: recorded.subject.id,
    },
    `notifications/${recorded.notificationId}`,
    recorded.tenant,
  );
}
