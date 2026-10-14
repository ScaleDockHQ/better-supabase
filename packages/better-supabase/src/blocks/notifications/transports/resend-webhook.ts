import type { AsyncResult } from "../../../core/result.ts";
import type {
  DeliveryEventInput,
  DeliveryEventKind,
  RecordedDeliveryEvent,
  SuppressInput,
} from "../api-types.ts";

import { readBodyCapped } from "../../../core/block-helpers.ts";
import { dbError } from "../../../core/errors.ts";
import {
  type BlockProblemOptions,
  methodNotAllowed,
  problemResponse,
} from "../../../core/problem.ts";
import { verifyWebhook, type VerifyOptions } from "../../../core/signatures.ts";
import { temporal } from "../../../core/temporal-required.ts";
import { isRecord } from "../../shared.ts";

/**
 * What the handler writes through: `createNotifications` over the service
 * transport. Without `recordDeliveryEvent` (a custom writer), it only
 * writes suppressions.
 */
export interface SuppressionWriter {
  suppress(input: SuppressInput): AsyncResult<boolean>;
  recordDeliveryEvent?(
    input: DeliveryEventInput,
  ): AsyncResult<RecordedDeliveryEvent | null>;
}

const RESEND_KINDS: Readonly<Record<string, DeliveryEventKind>> = {
  "email.delivered": "delivered",
  "email.opened": "opened",
  "email.clicked": "clicked",
  "email.bounced": "bounced",
  "email.complained": "complained",
  "email.delivery_delayed": "delayed",
};

const instantOf = (value: unknown): Temporal.Instant | undefined => {
  if (typeof value !== "string") return undefined;
  const { Instant } = temporal();
  try {
    return Instant.from(value);
  } catch {
    return undefined;
  }
};

/**
 * The delivery event a Resend event reports, matched to the delivery by
 * `data.email_id`: `email.delivered`, `opened`, `clicked`, `bounced`,
 * `complained` and `delivery_delayed`. A `Transient` bounce doesn't
 * suppress the address. `undefined` for any other event.
 */
export function resendDeliveryEvent(
  event: unknown,
  eventId?: string,
): DeliveryEventInput | undefined {
  if (!isRecord(event) || !isRecord(event["data"])) return undefined;
  const type = event["type"];
  const kind =
    typeof type === "string" && Object.hasOwn(RESEND_KINDS, type)
      ? RESEND_KINDS[type]
      : undefined;
  const data = event["data"];
  const emailId = data["email_id"];
  if (kind === undefined || typeof emailId !== "string" || emailId === "")
    return undefined;
  const bounce = isRecord(data["bounce"]) ? data["bounce"] : undefined;
  const click = isRecord(data["click"]) ? data["click"] : undefined;
  const detail: Record<string, unknown> = {};
  for (const key of ["type", "subType", "message"] as const) {
    if (typeof bounce?.[key] === "string")
      detail[key === "type" ? "bounceType" : key] = bounce[key];
  }
  if (typeof click?.["link"] === "string") detail["link"] = click["link"];
  const occurredAt = instantOf(event["created_at"]);
  return {
    provider: "resend",
    providerMessageId: emailId,
    kind,
    ...(eventId === undefined ? {} : { providerEventId: eventId }),
    ...(occurredAt === undefined ? {} : { occurredAt }),
    detail,
    ...(kind === "bounced" && bounce?.["type"] === "Transient"
      ? { suppress: false }
      : {}),
  };
}

export interface ResendWebhookOptions
  extends BlockProblemOptions, VerifyOptions {
  /** The endpoint's signing secret (`whsec_…`); several while rotating. */
  readonly secret: string | readonly string[];
  readonly notifications: SuppressionWriter;
  /** Defaults to 256 KiB. */
  readonly maxBodyBytes?: number;
}

/**
 * The suppressions a Resend event asks for: one per recipient of an
 * `email.bounced` (unless Resend reports the bounce as `Transient`) or an
 * `email.complained` event, and none for any other event. `eventId` is the
 * webhook message id, stored with each suppression.
 */
export function resendSuppressions(
  event: unknown,
  eventId?: string,
): SuppressInput[] {
  if (!isRecord(event) || !isRecord(event["data"])) return [];
  const data = event["data"];
  const bounce = isRecord(data["bounce"]) ? data["bounce"] : undefined;
  let reason: SuppressInput["reason"];
  switch (event["type"]) {
    case "email.bounced":
      if (bounce?.["type"] === "Transient") return [];
      reason = "bounce";
      break;
    case "email.complained":
      reason = "complaint";
      break;
    default:
      return [];
  }
  const to = Array.isArray(data["to"]) ? data["to"] : [data["to"]];
  const detail: Record<string, unknown> = {};
  if (typeof data["email_id"] === "string")
    detail["emailId"] = data["email_id"];
  for (const key of ["type", "subType", "message"] as const) {
    if (typeof bounce?.[key] === "string")
      detail[key === "type" ? "bounceType" : key] = bounce[key];
  }
  return to
    .filter(
      (address): address is string =>
        typeof address === "string" && address.includes("@"),
    )
    .map((address) => ({
      address,
      reason,
      channel: "email",
      provider: "resend",
      ...(eventId === undefined ? {} : { providerEventId: eventId }),
      detail,
    }));
}

/**
 * A `Request` handler for Resend's webhooks. It verifies the Svix (Standard
 * Webhooks) signature, records each delivery status on its delivery
 * (`recordDeliveryEvent`), writes a suppression for each bounced or
 * complaining address, and answers 204. A failed write answers 500 so
 * Resend retries; other events are acknowledged and ignored.
 */
export function resendWebhook(
  options: ResendWebhookOptions,
): (request: Request) => Promise<Response> {
  const limit = options.maxBodyBytes ?? 256 * 1024;
  const format = options.problem;
  return async (request) => {
    if (request.method !== "POST") return methodNotAllowed(["POST"]);
    const body = await readBodyCapped(request, limit);
    if (body === undefined) {
      return problemResponse(
        {
          ...dbError("invalid_input", "The body is too large", {
            code: "WEBHOOK_TOO_LARGE",
          }),
          status: 413,
        },
        { format },
      );
    }
    const verified = await verifyWebhook(
      { headers: request.headers, body },
      options.secret,
      options,
    );
    if (!verified.ok) return problemResponse(verified.error, { format });
    const delivery = resendDeliveryEvent(
      verified.data.payload,
      verified.data.id,
    );
    if (delivery !== undefined && options.notifications.recordDeliveryEvent) {
      const recorded =
        await options.notifications.recordDeliveryEvent(delivery);
      if (!recorded.ok) return problemResponse(recorded.error, { format });
    }
    for (const input of resendSuppressions(
      verified.data.payload,
      verified.data.id,
    )) {
      const written = await options.notifications.suppress(input);
      if (!written.ok) return problemResponse(written.error, { format });
    }
    return new Response(null, { status: 204 });
  };
}
