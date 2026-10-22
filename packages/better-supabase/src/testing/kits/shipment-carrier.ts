import type {
  CarrierTrackingEvent,
  ShipmentAddress,
  ShipmentCarrier,
  ShipmentLabel,
  ShipmentRateRequest,
} from "../../blocks/shipments/carrier.ts";
import type { Result } from "../../core/result.ts";
import type { WebhookInput } from "../../core/signatures.ts";
import type { ConformanceReport } from "../conformance.ts";

import {
  LABEL_FORMATS,
  TRACKING_STATUSES,
} from "../../blocks/shipments/statuses.ts";
import { isMoney } from "../../commerce/money.ts";
import { conform, expect } from "../conformance.ts";

export interface TestShipmentCarrierOptions {
  /** Addresses the carrier ships between. */
  readonly from: ShipmentAddress;
  readonly to: ShipmentAddress;
  /** A service code the carrier sells for that route. */
  readonly service: string;
  /** The currency to quote in; unset takes the carrier's default. */
  readonly currency?: string;
  /**
   * For a carrier with `parseWebhook`: a correctly signed tracking webhook, and
   * one whose signature fails.
   */
  readonly webhook?: {
    readonly valid: () => WebhookInput | Promise<WebhookInput>;
    readonly forged: () => WebhookInput | Promise<WebhookInput>;
  };
}

const kindOf = (result: Result<unknown>): string =>
  result.ok ? "ok" : result.error.kind;

const formats: readonly string[] = LABEL_FORMATS;
const statuses: readonly string[] = TRACKING_STATUSES;

function eventsValid(
  events: readonly CarrierTrackingEvent[],
  where: string,
  ordered: boolean,
): void {
  for (const [index, event] of events.entries()) {
    expect(event.id.length > 0, `${where}: event ${index} has no id`);
    expect(
      statuses.includes(event.status),
      `${where}: event ${event.id} has status "${event.status}"`,
    );

    const previous = events[index - 1];

    expect(
      !ordered ||
        previous === undefined ||
        previous.occurredAt.epochNanoseconds <=
          event.occurredAt.epochNanoseconds,
      `${where}: events are not oldest first`,
    );
  }
}

/**
 * Runs the `ShipmentCarrier` contract against `carrier`: the API version,
 * refused requests, rates, a label with idempotent retries, tracking, voiding
 * the label and, with `webhook`, signed and forged tracking webhooks. Run it
 * against a carrier's test account: it buys one label and voids it.
 */
export function testShipmentCarrier(
  carrier: ShipmentCarrier,
  options: TestShipmentCarrierOptions,
): Promise<ConformanceReport> {
  const request: ShipmentRateRequest = {
    from: options.from,
    to: options.to,
    parcels: [
      { weightGrams: 1200, lengthMm: 300, widthMm: 200, heightMm: 100 },
    ],
    ...(options.currency === undefined ? {} : { currency: options.currency }),
  };

  const reference = `conformance-${crypto.randomUUID()}`;
  const key = `conformance-${crypto.randomUUID()}`;
  let label: ShipmentLabel | undefined;

  const bought = async (): Promise<ShipmentLabel> => {
    label ??= await carrier
      .createLabel(
        { ...request, service: options.service, reference },
        { idempotencyKey: key },
      )
      .orThrow();

    return label;
  };

  return conform(`ShipmentCarrier "${carrier.name}"`, [
    [
      "has apiVersion 1 and a name",
      () => {
        const version: unknown = carrier.apiVersion;
        expect(version === 1, `apiVersion is ${String(version)}`);
        expect(carrier.name.length > 0, "name is empty");
      },
    ],
    [
      "refuses a request without packages or with a bad country",
      async () => {
        const empty = await carrier.rates({ ...request, parcels: [] });

        expect(
          kindOf(empty) === "invalid_input",
          `no packages gave ${kindOf(empty)}`,
        );

        const nowhere = await carrier.rates({
          ...request,
          to: { ...request.to, country: "" },
        });

        expect(
          kindOf(nowhere) === "invalid_input",
          `no country gave ${kindOf(nowhere)}`,
        );
      },
    ],
    [
      "quotes the service in the asked currency",
      async () => {
        const rates = await carrier.rates(request).orThrow();

        expect(
          rates.some((rate) => rate.service === options.service),
          `no rate for the "${options.service}" service`,
        );

        for (const rate of rates) {
          expect(
            rate.carrier === carrier.name,
            `rate carrier is "${rate.carrier}"`,
          );
          expect(
            isMoney(rate.amount) && rate.amount.amount >= 0n,
            `the ${rate.service} rate is not a Money of zero or more`,
          );
          expect(
            options.currency === undefined ||
              rate.amount.currency === options.currency,
            `the ${rate.service} rate is in ${rate.amount.currency}`,
          );
        }
      },
    ],
    [
      "refuses an unknown service",
      async () => {
        const unknown = await carrier.createLabel({
          ...request,
          service: `conformance-${crypto.randomUUID()}`,
          reference,
        });

        expect(
          kindOf(unknown) === "invalid_input",
          `an unknown service gave ${kindOf(unknown)}`,
        );
      },
    ],
    [
      "buys a label with a tracking number, a cost and a known format",
      async () => {
        const found = await bought();
        expect(found.labelId.length > 0, "labelId is empty");
        expect(found.trackingNumber.length > 0, "trackingNumber is empty");
        expect(isMoney(found.cost), "cost is not a Money");
        expect(formats.includes(found.format), `format is "${found.format}"`);

        for (const url of [found.labelUrl, found.trackingUrl]) {
          expect(
            url === undefined || url.startsWith("https://"),
            `${String(url)} is not an https URL`,
          );
        }
      },
    ],
    [
      "returns the same label for the same idempotency key",
      async () => {
        const first = await bought();

        const again = await carrier
          .createLabel(
            { ...request, service: options.service, reference },
            { idempotencyKey: key },
          )
          .orThrow();

        expect(
          again.labelId === first.labelId,
          "a retry with the same key bought another label",
        );
      },
    ],
    [
      "tracks the label, oldest event first",
      async () => {
        const found = await bought();
        const events = await carrier.track(found.trackingNumber).orThrow();
        eventsValid(events, "track", true);
      },
    ],
    [
      "answers not_found for an unknown tracking number",
      async () => {
        const unknown = await carrier.track(
          `conformance-${crypto.randomUUID()}`,
        );

        expect(
          kindOf(unknown) === "not_found",
          `an unknown tracking number gave ${kindOf(unknown)}`,
        );
      },
    ],
    [
      "voids the label",
      async () => {
        const found = await bought();

        const voided = await carrier
          .cancel({
            labelId: found.labelId,
            trackingNumber: found.trackingNumber,
          })
          .orThrow();

        expect(voided.cancelled, "cancel did not report cancelled");
      },
    ],
    [
      "reads signed tracking webhooks and refuses forged ones",
      async () => {
        const { webhook } = options;

        if (webhook === undefined || carrier.parseWebhook === undefined) {
          expect(
            webhook === undefined && carrier.parseWebhook === undefined,
            webhook === undefined
              ? "the carrier has parseWebhook; pass webhook to test it"
              : "webhook was passed but the carrier has no parseWebhook",
          );

          return;
        }

        const updates = await carrier
          .parseWebhook(await webhook.valid())
          .orThrow();

        expect(updates.length > 0, "a valid webhook gave no updates");

        for (const update of updates) {
          expect(
            update.trackingNumber.length > 0,
            "an update has no tracking number",
          );
          eventsValid(update.events, update.trackingNumber, false);
        }

        const forged = await carrier.parseWebhook(await webhook.forged());

        expect(
          kindOf(forged) === "unauthorized",
          `a forged webhook gave ${kindOf(forged)}`,
        );
      },
    ],
  ]);
}
