import type { AsyncResult } from "../../../core/result.ts";
import type { SuppressInput } from "../api-types.ts";

import { readBodyCapped } from "../../../core/block-helpers.ts";
import { dbError } from "../../../core/errors.ts";
import {
  type BlockProblemOptions,
  methodNotAllowed,
  problemResponse,
} from "../../../core/problem.ts";
import { verifyWebhook, type VerifyOptions } from "../../../core/signatures.ts";
import { isRecord } from "../../shared.ts";

/** What the handler writes suppressions through: `createNotifications` over the service transport. */
export interface SuppressionWriter {
  suppress(input: SuppressInput): AsyncResult<boolean>;
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
 * Webhooks) signature, writes a suppression for each bounced or complaining
 * address, and answers 204. A failed write answers 500 so Resend retries;
 * other events are acknowledged and ignored.
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
