import type { ShippingProvider } from "better-supabase/blocks/shipments";

import { AsyncResult, dbError, err, ok } from "better-supabase";
import { money } from "better-supabase/commerce";

import type { HttpOptions } from "./http.ts";

import { list, numberOf, record, requestJson, text } from "./http.ts";

const NAME = "example-carrier";

/**
 * A `ShippingProvider` over a carrier's REST API (ADR 0082). Every method
 * returns a `Result`: a request the carrier can't ship is `invalid_input`, an
 * unknown tracking number `not_found`. `createLabel` passes the idempotency key
 * on, so a retry returns the first label instead of buying a second one. Add
 * `parseWebhook` with `verifyWebhook` when the carrier signs tracking
 * webhooks.
 */
export function createShippingProvider(options: HttpOptions): ShippingProvider {
  return {
    apiVersion: 1,
    name: NAME,
    rates: (request, call) =>
      AsyncResult.from(async () => {
        if (request.parcels.length === 0 || request.to.country.length !== 2) {
          return err(
            dbError(
              "invalid_input",
              "A shipment needs a package and a country",
            ),
          );
        }

        const body = await requestJson(options, "/rates", {
          method: "POST",
          body: request,
          ...(call?.signal === undefined ? {} : { signal: call.signal }),
        });

        if (!body.ok) {
          return body;
        }

        return ok(
          list(record(body.data, "rates").rates, "rates").map((item) => {
            const rate = record(item, "rate");

            return {
              carrier: NAME,
              service: text(rate.service, "rate.service"),
              amount: money(
                BigInt(text(rate.amountMinor, "rate.amountMinor")),
                text(rate.currency, "rate.currency"),
              ),
            };
          }),
        );
      }),
    createLabel: (request, call) =>
      AsyncResult.from(async () => {
        const body = await requestJson(options, "/labels", {
          method: "POST",
          body: request,
          ...(call?.idempotencyKey === undefined
            ? {}
            : { headers: { "idempotency-key": call.idempotencyKey } }),
          ...(call?.signal === undefined ? {} : { signal: call.signal }),
        });

        if (!body.ok) {
          return body;
        }

        const label = record(body.data, "label");

        return ok({
          labelId: text(label.id, "label.id"),
          trackingNumber: text(label.trackingNumber, "label.trackingNumber"),
          service: request.service,
          cost: money(
            BigInt(text(label.costMinor, "label.costMinor")),
            text(label.currency, "label.currency"),
          ),
          format: "pdf" as const,
        });
      }),
    track: (trackingNumber, call) =>
      AsyncResult.from(async () => {
        const body = await requestJson(
          options,
          `/tracking/${encodeURIComponent(trackingNumber)}`,
          call?.signal === undefined ? {} : { signal: call.signal },
        );

        if (!body.ok) {
          return body;
        }

        return ok(
          list(record(body.data, "tracking").events, "events").map((item) => {
            const event = record(item, "event");
            const status = text(event.status, "event.status");

            return {
              id: text(event.id, "event.id"),
              // Map the carrier's own codes to `TRACKING_STATUSES` here.
              status:
                status === "delivered"
                  ? ("delivered" as const)
                  : ("in_transit" as const),
              occurredAt: Temporal.Instant.fromEpochMilliseconds(
                numberOf(event.at, "event.at"),
              ),
            };
          }),
        );
      }),
    cancel: (input, call) =>
      AsyncResult.from(async () => {
        const body = await requestJson(
          options,
          `/labels/${encodeURIComponent(input.labelId)}/void`,
          {
            method: "POST",
            ...(call?.signal === undefined ? {} : { signal: call.signal }),
          },
        );

        return body.ok ? ok({ cancelled: true as const }) : body;
      }),
  };
}
