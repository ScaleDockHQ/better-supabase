import type { Money } from "../../commerce/money.ts";
import type { DbError } from "../../core/errors.ts";
import type { Result } from "../../core/result.ts";
import type { VerifyOptions, WebhookInput } from "../../core/signatures.ts";
import type { LabelFormat, TrackingStatus } from "./statuses.ts";

import { isMoney, money } from "../../commerce/money.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { verifyWebhook } from "../../core/signatures.ts";
import { temporal } from "../../core/temporal-required.ts";
import { TRACKING_STATUSES } from "./statuses.ts";

/** A sender or recipient address. */
export interface ShipmentAddress {
  readonly name?: string;
  readonly company?: string;
  readonly line1: string;
  readonly line2?: string;
  readonly city: string;
  readonly postalCode?: string;
  /** The state or province code, such as `CA`. */
  readonly state?: string;
  /** ISO 3166-1 alpha-2, such as `NL`. */
  readonly country: string;
  readonly phone?: string;
  readonly email?: string;
}

/** One package of a shipment. */
export interface ShipmentParcel {
  readonly weightGrams: number;
  readonly lengthMm?: number;
  readonly widthMm?: number;
  readonly heightMm?: number;
  readonly reference?: string;
}

export interface ShipmentRateRequest {
  readonly from: ShipmentAddress;
  readonly to: ShipmentAddress;
  readonly parcels: readonly ShipmentParcel[];
  /** The currency to quote in, when the carrier offers a choice. */
  readonly currency?: string;
}

export interface ShipmentRate {
  /** The carrier's `name`. */
  readonly carrier: string;
  /** The carrier's service code, such as `standard` or `express`. */
  readonly service: string;
  readonly amount: Money;
  readonly estimatedDays?: number;
}

export interface ShipmentLabelRequest extends ShipmentRateRequest {
  /** A service code one of `rates` returned. */
  readonly service: string;
  /** The shipment's reference, printed on the label. */
  readonly reference: string;
}

export interface ShipmentLabel {
  /** The carrier's id for the label; `cancel` takes it. */
  readonly labelId: string;
  readonly trackingNumber: string;
  readonly service: string;
  readonly cost: Money;
  readonly format: LabelFormat;
  /** Where to download the label, when the carrier hosts it. */
  readonly labelUrl?: string;
  /** The carrier's public tracking page. */
  readonly trackingUrl?: string;
}

export interface CarrierTrackingEvent {
  /**
   * The carrier's id for the event. A redelivered or re-polled event repeats
   * it, so the block records each id once per shipment.
   */
  readonly id: string;
  readonly status: TrackingStatus;
  readonly occurredAt: Temporal.Instant;
  readonly description?: string;
  readonly location?: string;
}

/** The events of one tracking number, as a webhook delivers them. */
export interface CarrierTrackingUpdate {
  readonly trackingNumber: string;
  readonly events: readonly CarrierTrackingEvent[];
}

export interface CarrierCancelInput {
  readonly labelId: string;
  readonly trackingNumber: string;
}

export interface CarrierCallOptions {
  /** The same key returns the first call's result instead of buying twice. */
  readonly idempotencyKey?: string;
  readonly signal?: AbortSignal;
}

/**
 * Quotes, buys, tracks and voids shipping labels. Versioned: a breaking change
 * ships a new `apiVersion`. Every method returns a `Result`: `invalid_input`
 * for a request the carrier can't ship (no parcels, an unknown service),
 * `not_found` for an unknown tracking number or label, `conflict` for a label
 * the carrier can no longer void, and `unauthorized` for a webhook whose
 * signature fails.
 */
export interface ShippingProvider {
  readonly apiVersion: 1;
  /** The carrier's name, stored on each shipment it labels. */
  readonly name: string;
  rates(
    request: ShipmentRateRequest,
    options?: CarrierCallOptions,
  ): AsyncResult<readonly ShipmentRate[]>;
  createLabel(
    request: ShipmentLabelRequest,
    options?: CarrierCallOptions,
  ): AsyncResult<ShipmentLabel>;
  /** The tracking number's events so far, oldest first. */
  track(
    trackingNumber: string,
    options?: CarrierCallOptions,
  ): AsyncResult<readonly CarrierTrackingEvent[]>;
  /** Voids a label that hasn't shipped. */
  cancel(
    input: CarrierCancelInput,
    options?: CarrierCallOptions,
  ): AsyncResult<{ readonly cancelled: true }>;
  /**
   * Verifies a tracking webhook with the carrier's secret and returns its
   * updates. Unset for a carrier that only answers `track`.
   */
  parseWebhook?(
    input: WebhookInput,
  ): AsyncResult<readonly CarrierTrackingUpdate[]>;
}

/** Checks the carrier's `apiVersion` before a block uses it. */
export function shipmentCarrierOf(carrier: ShippingProvider): ShippingProvider {
  const version: unknown = carrier.apiVersion;

  if (version !== 1) {
    throw new TypeError(
      `carrier "${carrier.name}" targets shipment carrier API ${String(version)}; this better-supabase supports 1. Upgrade better-supabase or use a release of the carrier for API 1.`,
    );
  }

  return carrier;
}

const invalid = (message: string, hint: string): DbError =>
  dbError("invalid_input", message, { hint });

const isPositiveInteger = (value: unknown): value is number =>
  typeof value === "number" && Number.isSafeInteger(value) && value > 0;

/**
 * The first problem with a rate or label request: an address without a line,
 * city or two-letter country, no parcels, or a parcel whose weight or size
 * isn't a positive whole number.
 */
export function invalidShipmentRequest(
  request: ShipmentRateRequest,
): DbError | undefined {
  for (const [side, address] of [
    ["from", request.from],
    ["to", request.to],
  ] as const) {
    if (!/^[A-Z]{2}$/.test(address.country)) {
      return invalid(
        `The ${side} address needs a two-letter country code`,
        "SHIPMENT_ADDRESS_INVALID",
      );
    }

    if (address.line1.trim() === "" || address.city.trim() === "") {
      return invalid(
        `The ${side} address needs a street line and a city`,
        "SHIPMENT_ADDRESS_INVALID",
      );
    }
  }

  if (request.parcels.length === 0) {
    return invalid("A shipment needs at least one package", "SHIPMENT_EMPTY");
  }

  for (const parcel of request.parcels) {
    const sizes = [parcel.lengthMm, parcel.widthMm, parcel.heightMm].filter(
      (size) => size !== undefined,
    );

    if (
      !isPositiveInteger(parcel.weightGrams) ||
      !sizes.every(isPositiveInteger)
    ) {
      return invalid(
        "Package weights and sizes are positive whole numbers of grams and millimeters",
        "SHIPMENT_PACKAGE_INVALID",
      );
    }
  }

  return undefined;
}

export interface FlatRateService {
  /** The price of the first package. */
  readonly amount: Money;
  /** The price of each further package. Defaults to `amount`. */
  readonly additional?: Money;
  readonly estimatedDays?: number;
}

export interface FlatRateCarrierOptions {
  /** Defaults to `flat-rate`. */
  readonly name?: string;
  /** Services by code, such as `{ standard: { amount: money(695n, "EUR") } }`. */
  readonly services: Readonly<Record<string, FlatRateService>>;
  /** Prefixes generated tracking numbers. Defaults to `FR`. */
  readonly trackingPrefix?: string;
  /**
   * Standard Webhooks secrets (`whsec_…`) for `parseWebhook`. Unset: the
   * carrier has no `parseWebhook`.
   */
  readonly webhookSecret?: string | readonly string[];
  /** Passed to `verifyWebhook`, such as a `seen` store against replays. */
  readonly verify?: VerifyOptions;
}

const randomCode = (): string =>
  crypto.randomUUID().replaceAll("-", "").slice(0, 16).toUpperCase();

function parcelsTotal(
  service: FlatRateService,
  parcels: readonly ShipmentParcel[],
): Money {
  const additional = service.additional ?? service.amount;

  return money(
    service.amount.amount + additional.amount * BigInt(parcels.length - 1),
    service.amount.currency,
  );
}

function instantOf(value: unknown): Temporal.Instant | undefined {
  if (typeof value !== "string") {
    return undefined;
  }

  try {
    return temporal().Instant.from(value);
  } catch {
    return undefined;
  }
}

const optionalString = (
  key: "description" | "location",
  value: unknown,
): { readonly description?: string; readonly location?: string } =>
  typeof value === "string" && value !== "" ? { [key]: value } : {};

/**
 * Reads a tracking webhook body in the flat-rate format: `{ "trackingNumber":
 * "…", "events": [{ "id", "status", "occurredAt", "description"?, "location"?
 * }] }`, or an array of those.
 */
export function trackingUpdatesOf(
  payload: unknown,
): Result<readonly CarrierTrackingUpdate[]> {
  const items: readonly unknown[] = Array.isArray(payload)
    ? payload
    : [payload];

  const updates: CarrierTrackingUpdate[] = [];
  const statuses: readonly string[] = TRACKING_STATUSES;

  for (const item of items) {
    if (
      typeof item !== "object" ||
      item === null ||
      !("trackingNumber" in item) ||
      typeof item.trackingNumber !== "string" ||
      item.trackingNumber === "" ||
      !("events" in item) ||
      !Array.isArray(item.events)
    ) {
      return err(
        invalid(
          "A tracking update needs a trackingNumber and an events array",
          "SHIPMENT_TRACKING_INVALID",
        ),
      );
    }

    const events: CarrierTrackingEvent[] = [];

    // SAFETY: Array.isArray types the elements as any; unknown keeps the checks below honest.
    for (const event of item.events as readonly unknown[]) {
      if (
        typeof event !== "object" ||
        event === null ||
        !("id" in event) ||
        typeof event.id !== "string" ||
        event.id === "" ||
        !("status" in event) ||
        typeof event.status !== "string" ||
        !statuses.includes(event.status)
      ) {
        return err(
          invalid(
            "Each tracking event needs an id and a known status",
            "SHIPMENT_TRACKING_INVALID",
          ),
        );
      }

      const occurredAt = instantOf(
        "occurredAt" in event ? event.occurredAt : undefined,
      );

      if (occurredAt === undefined) {
        return err(
          invalid(
            "Each tracking event needs an ISO 8601 occurredAt",
            "SHIPMENT_TRACKING_INVALID",
          ),
        );
      }

      events.push({
        id: event.id,
        // SAFETY: checked against TRACKING_STATUSES above.
        status: event.status as TrackingStatus,
        occurredAt,
        ...optionalString(
          "description",
          "description" in event ? event.description : undefined,
        ),
        ...optionalString(
          "location",
          "location" in event ? event.location : undefined,
        ),
      });
    }

    updates.push({ trackingNumber: item.trackingNumber, events });
  }

  return ok(updates);
}

/**
 * A `ShippingProvider` with fixed prices per service and package. It stores
 * nothing beyond the labels of recent idempotency keys: labels carry a
 * generated tracking number and no file, `track` returns no events, and
 * `cancel` always succeeds. With `webhookSecret` it reads Standard Webhooks
 * tracking updates in the format of `trackingUpdatesOf`, so drivers, a
 * forwarding service or tests can post tracking events.
 */
export function flatRateCarrier(
  options: FlatRateCarrierOptions,
): ShippingProvider {
  const name = options.name ?? "flat-rate";
  const prefix = options.trackingPrefix ?? "FR";

  for (const [code, service] of Object.entries(options.services)) {
    if (
      !isMoney(service.amount) ||
      (service.additional !== undefined &&
        (!isMoney(service.additional) ||
          service.additional.currency !== service.amount.currency))
    ) {
      throw new TypeError(
        `flatRateCarrier: the "${code}" service needs an amount, and an additional amount in the same currency`,
      );
    }
  }

  const labels = new Map<string, ShipmentLabel>();

  const ratesOf = (request: ShipmentRateRequest): Result<ShipmentRate[]> => {
    const problem = invalidShipmentRequest(request);

    if (problem) {
      return err(problem);
    }

    return ok(
      Object.entries(options.services)
        .filter(
          ([, service]) =>
            request.currency === undefined ||
            service.amount.currency === request.currency,
        )
        .map(([service, rate]) => ({
          carrier: name,
          service,
          amount: parcelsTotal(rate, request.parcels),
          ...(rate.estimatedDays === undefined
            ? {}
            : { estimatedDays: rate.estimatedDays }),
        })),
    );
  };

  const labelOf = (
    request: ShipmentLabelRequest,
    key: string | undefined,
  ): Result<ShipmentLabel> => {
    const problem = invalidShipmentRequest(request);

    if (problem) {
      return err(problem);
    }

    const service = options.services[request.service];

    if (service === undefined) {
      return err(
        invalid(
          `The carrier has no "${request.service}" service`,
          "SHIPMENT_SERVICE_UNKNOWN",
        ),
      );
    }

    const earlier = key === undefined ? undefined : labels.get(key);

    if (earlier) {
      return ok(earlier);
    }

    const code = randomCode();

    const label: ShipmentLabel = {
      labelId: `label_${code}`,
      trackingNumber: `${prefix}${code}`,
      service: request.service,
      cost: parcelsTotal(service, request.parcels),
      format: "pdf",
    };

    if (key !== undefined && labels.size < 1000) {
      labels.set(key, label);
    }

    return ok(label);
  };

  const secrets = options.webhookSecret;

  return {
    apiVersion: 1,
    name,
    rates: (request) => new AsyncResult(Promise.resolve(ratesOf(request))),
    createLabel: (request, call) =>
      new AsyncResult(Promise.resolve(labelOf(request, call?.idempotencyKey))),
    track: (trackingNumber) =>
      trackingNumber.startsWith(prefix)
        ? AsyncResult.ok([])
        : AsyncResult.err(
            dbError("not_found", "Unknown tracking number", {
              hint: "SHIPMENT_TRACKING_UNKNOWN",
            }),
          ),
    cancel: () => AsyncResult.ok({ cancelled: true }),
    ...(secrets === undefined
      ? {}
      : {
          parseWebhook: (input: WebhookInput) =>
            AsyncResult.from(async () => {
              const verified = await verifyWebhook(
                input,
                secrets,
                options.verify,
              );

              return verified.ok
                ? trackingUpdatesOf(verified.data.payload)
                : verified;
            }),
        }),
  };
}
