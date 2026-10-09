import type { DeliveryStatus } from "../blocks/inbox/types.ts";

import { isRecord, optionalText } from "../core/block-helpers.ts";

/** One status callback for a message the bot sent on a channel. */
export interface DeliveryUpdate {
  readonly externalId: string;
  readonly status: DeliveryStatus;
  readonly error?: string;
}

/**
 * What a stored webhook body says about deliveries. `only` is true when the
 * body carries nothing but statuses, so it needs no replay into Chat SDK.
 */
export interface ParsedDeliveries {
  readonly updates: readonly DeliveryUpdate[];
  readonly only: boolean;
}

/** Reads delivery statuses from a stored webhook event; `null` when the body is not one it knows. */
export type DeliveryParser = (event: {
  readonly body: string;
  readonly headers: Readonly<Record<string, string>>;
}) => ParsedDeliveries | null;

const STATUSES: Readonly<Record<string, DeliveryStatus>> = {
  accepted: "queued",
  queued: "queued",
  sending: "queued",
  scheduled: "queued",
  sent: "sent",
  delivered: "delivered",
  read: "read",
  failed: "failed",
  undelivered: "failed",
  canceled: "failed",
};

const statusOf = (value: unknown): DeliveryStatus | undefined =>
  typeof value === "string" ? STATUSES[value.toLowerCase()] : undefined;

function json(body: string): unknown {
  try {
    return JSON.parse(body);
  } catch {
    return undefined;
  }
}

const list = (value: unknown): readonly unknown[] =>
  Array.isArray(value) ? value : [];

/** WhatsApp Cloud API: `entry[].changes[].value.statuses[]`. */
export const whatsappDeliveries: DeliveryParser = ({ body }) => {
  const payload = json(body);
  if (!isRecord(payload) || payload["object"] !== "whatsapp_business_account")
    return null;
  const updates: DeliveryUpdate[] = [];
  let other = false;
  for (const entry of list(payload["entry"]))
    for (const change of list(isRecord(entry) ? entry["changes"] : undefined)) {
      const value = isRecord(change) ? change["value"] : undefined;
      if (!isRecord(value)) continue;
      if (list(value["messages"]).length > 0) other = true;
      for (const item of list(value["statuses"])) {
        if (!isRecord(item)) continue;
        const status = statusOf(item["status"]);
        const id = optionalText(item["id"]);
        if (!status || id === undefined) continue;
        const first = list(item["errors"])[0];
        const error = isRecord(first)
          ? (optionalText(first["title"]) ?? optionalText(first["message"]))
          : undefined;
        updates.push({
          externalId: id,
          status,
          ...(error === undefined ? {} : { error }),
        });
      }
    }
  return { updates, only: updates.length > 0 && !other };
};

/** Messenger and Instagram: `entry[].messaging[].delivery.mids`. Read receipts carry no ids and are skipped. */
export const messengerDeliveries: DeliveryParser = ({ body }) => {
  const payload = json(body);
  if (
    !isRecord(payload) ||
    (payload["object"] !== "page" && payload["object"] !== "instagram")
  )
    return null;
  const events = list(payload["entry"]).flatMap((entry) =>
    list(isRecord(entry) ? entry["messaging"] : undefined).filter(isRecord),
  );
  const receipts = events.filter(
    (event) => isRecord(event["delivery"]) || isRecord(event["read"]),
  );
  const updates: DeliveryUpdate[] = receipts.flatMap((event) => {
    const delivery = event["delivery"];
    return isRecord(delivery)
      ? list(delivery["mids"]).flatMap((mid) =>
          typeof mid === "string"
            ? [{ externalId: mid, status: "delivered" as const }]
            : [],
        )
      : [];
  });
  return {
    updates,
    only: receipts.length > 0 && receipts.length === events.length,
  };
};

/** Twilio status callbacks: a form body with `MessageSid` and `MessageStatus` and no `Body`. */
export const twilioDeliveries: DeliveryParser = ({ body, headers }) => {
  const type = headers["content-type"] ?? "";
  if (!type.includes("application/x-www-form-urlencoded")) return null;
  const form = new URLSearchParams(body);
  const id = form.get("MessageSid") ?? form.get("SmsSid");
  const status = statusOf(form.get("MessageStatus") ?? form.get("SmsStatus"));
  if (id === null || !status || form.has("Body")) return null;
  const error = form.get("ErrorMessage") ?? form.get("ErrorCode");
  return {
    updates: [{ externalId: id, status, ...(error === null ? {} : { error }) }],
    only: true,
  };
};

/** The parsers `inboundHandler` uses by default, keyed by adapter name. */
export const DELIVERY_PARSERS: Readonly<Record<string, DeliveryParser>> = {
  whatsapp: whatsappDeliveries,
  messenger: messengerDeliveries,
  instagram: messengerDeliveries,
  twilio: twilioDeliveries,
  sms: twilioDeliveries,
};
