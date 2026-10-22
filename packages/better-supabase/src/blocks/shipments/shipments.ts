import type { Money } from "../../commerce/money.ts";
import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { WebhookInput } from "../../core/signatures.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { SubjectRef } from "../../schema/types.ts";
import type { BlockOptions } from "../shared.ts";
import type {
  CarrierTrackingEvent,
  ShipmentAddress,
  ShipmentCarrier,
  ShipmentParcel,
  ShipmentRate,
} from "./carrier.ts";
import type {
  LabelFormat,
  ShipmentStatus,
  TrackingStatus,
} from "./statuses.ts";

import { compareMoney } from "../../commerce/money.ts";
import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { optionalSubjectRefOf } from "../../core/block-subjects.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, ok } from "../../core/result.ts";
import { amountText, optionalMoneyOf } from "../money-codec.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  instantArg,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";
import { shipmentCarrierOf } from "./carrier.ts";
import {
  LABEL_FORMATS,
  SHIPMENT_STATUSES,
  TRACKING_STATUSES,
} from "./statuses.ts";

export interface ShipmentsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockOptions {
  /**
   * A Standard Schema for the shipments' extra columns
   * (`blocks.shipments.options.extraColumns`), keyed by database name.
   */
  readonly fields?: S;
  /**
   * The carriers that quote, label and track, by `name`. Without one the block
   * still records shipments and tracking events by hand.
   */
  readonly carriers?: readonly ShipmentCarrier[];
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Shipments<FieldsOf<S>>>>;
  /**
   * Receives the errors `after` hooks throw and a label the block failed to
   * void. Default: `console`.
   */
  readonly logger?: Logger;
}

export interface ShipmentPackage {
  readonly id: string;
  /** From 1. */
  readonly position: number;
  readonly weightGrams: number;
  readonly lengthMm?: number;
  readonly widthMm?: number;
  readonly heightMm?: number;
  readonly reference?: string;
}

/** A shipment: its packages, its addresses and, once bought, its label. */
export interface Shipment<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly reference: string;
  /** `draft` until labeled, then the latest tracking event's status. */
  readonly status: ShipmentStatus;
  readonly from: ShipmentAddress;
  readonly to: ShipmentAddress;
  /** The assets location it ships from. */
  readonly fromLocationId?: string;
  readonly subject?: SubjectRef;
  readonly carrier?: string;
  readonly service?: string;
  readonly trackingNumber?: string;
  readonly trackingUrl?: string;
  readonly labelId?: string;
  readonly labelUrl?: string;
  readonly labelFormat?: LabelFormat;
  readonly labelCost?: Money;
  readonly labeledAt?: Temporal.Instant;
  readonly deliveredAt?: Temporal.Instant;
  readonly cancelledAt?: Temporal.Instant;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  readonly packages: readonly ShipmentPackage[];
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

export interface ShipmentInput<F extends object = Record<never, never>> {
  readonly from: ShipmentAddress;
  readonly to: ShipmentAddress;
  /** 1 to 50 packages. */
  readonly packages: readonly ShipmentParcel[];
  /** Defaults to a generated `SHP-…` code. */
  readonly reference?: string;
  /** Needs the assets block. */
  readonly fromLocationId?: string;
  /** The record it ships for, such as an order. */
  readonly subject?: SubjectRef;
  readonly fields?: Partial<F>;
}

export interface ShipmentListOptions {
  readonly status?: ShipmentStatus;
  readonly subject?: SubjectRef;
  readonly carrier?: string;
  /** Shipments created before this, for the next page. */
  readonly before?: Temporal.Instant;
  /** Default 50, at most 500. */
  readonly limit?: number;
}

export interface ShipmentLabelChoice {
  /** A carrier's `name` from `options.carriers`. */
  readonly carrier: string;
  /** A service code the carrier quoted. */
  readonly service: string;
}

/** One entry of a shipment's tracking timeline. */
export interface TrackingEvent {
  readonly id: string;
  /** The carrier's event id; `label:<labelId>` for the label itself. */
  readonly externalId: string;
  readonly status: TrackingStatus;
  readonly occurredAt: Temporal.Instant;
  readonly description?: string;
  readonly location?: string;
  readonly source: "carrier" | "webhook" | "manual";
  readonly createdAt: Temporal.Instant;
}

export interface TrackingRecorded<F extends object = Record<never, never>> {
  /** The events that were new; repeats are skipped. */
  readonly recorded: number;
  readonly shipment: Shipment<F>;
}

/** What `ingest` did with one tracking number of a webhook. */
export interface TrackingIngested {
  readonly trackingNumber: string;
  /** Unset when no shipment has the tracking number. */
  readonly shipmentId?: string;
  readonly status?: ShipmentStatus;
  readonly recorded: number;
}

/**
 * Shipments with packages, carrier labels and a tracking timeline. `F` is the
 * extra fields `options.fields` describes.
 */
export interface Shipments<F extends object = Record<never, never>> {
  /** Creates a draft shipment in the block's tenant. */
  create(input: ShipmentInput<F>): AsyncResult<Shipment<F>>;
  /** `null` when it doesn't exist or the caller can't read it. */
  get(id: string): AsyncResult<Shipment<F> | null>;
  list(options?: ShipmentListOptions): AsyncResult<readonly Shipment<F>[]>;
  /** Every configured carrier's quotes, by currency and then cheapest first. */
  rates(
    id: string,
    options?: { readonly currency?: string },
  ): AsyncResult<readonly ShipmentRate[]>;
  /**
   * Buys the label from the carrier and stores it on the draft shipment. The
   * shipment id is the idempotency key, so a retry doesn't buy twice.
   */
  buyLabel(id: string, choice: ShipmentLabelChoice): AsyncResult<Shipment<F>>;
  /** Pulls the carrier's tracking events and records the new ones. */
  refresh(id: string): AsyncResult<TrackingRecorded<F>>;
  /** Records tracking events by hand, such as a courier without an API. */
  recordTracking(
    id: string,
    events: readonly CarrierTrackingEvent[],
  ): AsyncResult<TrackingRecorded<F>>;
  /**
   * Verifies a carrier's tracking webhook and records its events on the
   * shipments with those tracking numbers. Runs on `options.service`, since a
   * webhook has no user; a redelivery records nothing twice.
   */
  ingest(
    carrier: string,
    request: WebhookInput,
  ): AsyncResult<readonly TrackingIngested[]>;
  /**
   * Cancels a shipment that hasn't shipped, voiding its label with the carrier
   * first.
   */
  cancel(id: string): AsyncResult<Shipment<F>>;
  /** The tracking timeline, oldest first. */
  trackingEvents(id: string): AsyncResult<readonly TrackingEvent[]>;
}

type Defined<T> = { [K in keyof T]?: Exclude<T[K], undefined> };

/** Copies the defined values only, so absent fields stay absent. */
function defined<T extends object>(values: T): Defined<T> {
  // SAFETY: the entries come from `values`, minus the undefined ones.
  return Object.fromEntries(
    Object.entries(values).filter(([, value]) => value !== undefined),
  ) as Defined<T>;
}

const optionalNumber = (value: unknown): number | undefined =>
  value === null || value === undefined ? undefined : Number(value);

function addressOf(value: unknown, fn: string): ShipmentAddress {
  const row = recordOf(value, fn);

  return {
    line1: textOf(row["line1"]),
    city: textOf(row["city"]),
    country: textOf(row["country"]),
    ...defined({
      name: optionalText(row["name"]),
      company: optionalText(row["company"]),
      line2: optionalText(row["line2"]),
      postalCode: optionalText(row["postalCode"]),
      state: optionalText(row["state"]),
      phone: optionalText(row["phone"]),
      email: optionalText(row["email"]),
    }),
  };
}

function packageOf(row: Record<string, unknown>): ShipmentPackage {
  return {
    id: textOf(row["id"]),
    position: Number(row["position"]),
    weightGrams: Number(row["weightGrams"]),
    ...defined({
      lengthMm: optionalNumber(row["lengthMm"]),
      widthMm: optionalNumber(row["widthMm"]),
      heightMm: optionalNumber(row["heightMm"]),
      reference: optionalText(row["reference"]),
    }),
  };
}

function shipmentOf(value: unknown, fn: string): Shipment {
  const row = recordOf(value, fn);
  const format = optionalText(row["labelFormat"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    reference: textOf(row["reference"]),
    status: enumOrThrow(row["status"], SHIPMENT_STATUSES, "status"),
    from: addressOf(row["from"], fn),
    to: addressOf(row["to"], fn),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    packages: recordsOf(row["packages"], fn).map(packageOf),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
    ...defined({
      fromLocationId: optionalText(row["fromLocationId"]),
      subject: optionalSubjectRefOf(row["subjectType"], row["subjectId"]),
      carrier: optionalText(row["carrier"]),
      service: optionalText(row["service"]),
      trackingNumber: optionalText(row["trackingNumber"]),
      trackingUrl: optionalText(row["trackingUrl"]),
      labelId: optionalText(row["labelId"]),
      labelUrl: optionalText(row["labelUrl"]),
      labelFormat:
        format === undefined
          ? undefined
          : enumOrThrow(format, LABEL_FORMATS, "labelFormat"),
      labelCost: optionalMoneyOf(
        row["labelCost"],
        row["currency"],
        "labelCost",
      ),
      labeledAt: optionalInstant(row["labeledAt"]),
      deliveredAt: optionalInstant(row["deliveredAt"]),
      cancelledAt: optionalInstant(row["cancelledAt"]),
      createdBy: optionalText(row["createdBy"]),
    }),
  };
}

const SOURCES = ["carrier", "webhook", "manual"] as const;

function trackingEventOf(row: Record<string, unknown>): TrackingEvent {
  return {
    id: textOf(row["id"]),
    externalId: textOf(row["externalId"]),
    status: enumOrThrow(row["status"], TRACKING_STATUSES, "status"),
    occurredAt: requiredInstant(row["occurredAt"], "occurredAt"),
    source: enumOrThrow(row["source"], SOURCES, "source"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...defined({
      description: optionalText(row["description"]),
      location: optionalText(row["location"]),
    }),
  };
}

const eventsArg = (
  events: readonly CarrierTrackingEvent[],
): Record<string, unknown>[] =>
  events.map((event) => ({
    id: event.id,
    status: event.status,
    occurredAt: event.occurredAt.toString(),
    description: event.description ?? null,
    location: event.location ?? null,
  }));

const parcelsOf = (shipment: Shipment): ShipmentParcel[] =>
  shipment.packages.map((item) => ({
    weightGrams: item.weightGrams,
    ...defined({
      lengthMm: item.lengthMm,
      widthMm: item.widthMm,
      heightMm: item.heightMm,
      reference: item.reference,
    }),
  }));

const notFound = (): AsyncResult<never> =>
  AsyncResult.err(
    dbError("not_found", "Shipment not found", { hint: "SHIPMENT_NOT_FOUND" }),
  );

/** The `shipments` SQL module and the configured carriers as typed calls. */
export function createShipments<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: ShipmentsOptions<S>): Shipments<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const service = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );

  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);
  const logger = options.logger ?? console;
  const fields: BlockFields<F> = blockFields(options.fields, "shipment fields");

  const carriers = new Map(
    (options.carriers ?? []).map((carrier) => [
      carrier.name,
      shipmentCarrierOf(carrier),
    ]),
  );

  const carrierNamed = (
    name: string | undefined,
  ): AsyncResult<ShipmentCarrier> => {
    const found = name === undefined ? undefined : carriers.get(name);

    return found
      ? AsyncResult.ok(found)
      : AsyncResult.err(
          dbError(
            "invalid_input",
            `No carrier named "${String(name)}" is configured`,
            { hint: "SHIPMENT_CARRIER_UNKNOWN" },
          ),
        );
  };

  const one =
    (fn: string) =>
    (value: unknown): Shipment =>
      shipmentOf(value, fn);

  const find = (id: string): AsyncResult<Shipment> =>
    call("get_shipment", { shipment_id: id }, (value) =>
      value === null || value === undefined
        ? null
        : shipmentOf(value, "get_shipment"),
    ).andThen((found) => (found === null ? notFound() : AsyncResult.ok(found)));

  const recorded =
    (fn: string) =>
    (value: unknown): TrackingRecorded => {
      const row = recordOf(value, fn);

      return {
        recorded: Number(row["recorded"]),
        shipment: shipmentOf(row["shipment"], fn),
      };
    };

  const withFields = (
    result: AsyncResult<TrackingRecorded>,
  ): AsyncResult<TrackingRecorded<F>> =>
    result.andThen((found) =>
      fields
        .row(found.shipment)
        .map((shipment) => ({ recorded: found.recorded, shipment })),
    );

  const record = (
    id: string,
    events: readonly CarrierTrackingEvent[],
    source: "carrier" | "manual",
  ): AsyncResult<TrackingRecorded<F>> =>
    withFields(
      call(
        "record_tracking_events",
        { shipment_id: id, events: eventsArg(events), source },
        recorded("record_tracking_events"),
      ),
    );

  const client: Shipments<F> = {
    create: (input) =>
      tenant().andThen((organizationId) =>
        fields
          .args(input.fields)
          .andThen((checked) =>
            call(
              "create_shipment",
              {
                tenant: organizationId,
                from_address: input.from,
                to_address: input.to,
                packages: input.packages.map((item) => ({ ...item })),
                reference: input.reference ?? null,
                from_location_id: input.fromLocationId ?? null,
                subject_type: input.subject?.type ?? null,
                subject_id: input.subject?.id ?? null,
                fields: checked,
              },
              one("create_shipment"),
            ).andThen(fields.row),
          ),
      ),
    get: (id) =>
      call("get_shipment", { shipment_id: id }, (value) =>
        value === null || value === undefined
          ? null
          : shipmentOf(value, "get_shipment"),
      ).andThen((found) =>
        found === null ? AsyncResult.ok(null) : fields.row(found),
      ),
    list: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_shipments",
          {
            tenant: organizationId,
            status: list.status ?? null,
            subject_type: list.subject?.type ?? null,
            subject_id: list.subject?.id ?? null,
            carrier: list.carrier ?? null,
            before: instantArg(list.before) ?? null,
            page_size: list.limit ?? 50,
          },
          (value) =>
            recordsOf(value, "list_shipments").map((row) =>
              shipmentOf(row, "list_shipments"),
            ),
        ).andThen(fields.rows),
      ),
    rates: (id, quote = {}) =>
      find(id).andThen((shipment) =>
        AsyncResult.from(async () => {
          const found: ShipmentRate[] = [];

          for (const carrier of carriers.values()) {
            const rates = await carrier.rates({
              from: shipment.from,
              to: shipment.to,
              parcels: parcelsOf(shipment),
              ...(quote.currency === undefined
                ? {}
                : { currency: quote.currency }),
            });

            if (!rates.ok) {
              return rates;
            }

            found.push(...rates.data);
          }

          return ok(
            found.toSorted((a, b) =>
              a.amount.currency === b.amount.currency
                ? compareMoney(a.amount, b.amount)
                : a.amount.currency.localeCompare(b.amount.currency),
            ),
          );
        }),
      ),
    buyLabel: (id, choice) =>
      carrierNamed(choice.carrier).andThen((carrier) =>
        find(id).andThen((shipment) => {
          if (shipment.status !== "draft") {
            return AsyncResult.err(
              dbError("conflict", "The shipment already has a label", {
                hint: "SHIPMENT_NOT_DRAFT",
              }),
            );
          }

          return carrier
            .createLabel(
              {
                from: shipment.from,
                to: shipment.to,
                parcels: parcelsOf(shipment),
                service: choice.service,
                reference: shipment.reference,
              },
              { idempotencyKey: `label:${shipment.id}` },
            )
            .andThen((label) =>
              AsyncResult.from(async () => {
                const stored = await call(
                  "set_shipment_label",
                  {
                    shipment_id: shipment.id,
                    carrier: carrier.name,
                    service: label.service,
                    tracking_number: label.trackingNumber,
                    label_id: label.labelId,
                    label_cost: amountText(label.cost),
                    currency: label.cost.currency,
                    label_format: label.format,
                    label_url: label.labelUrl ?? null,
                    tracking_url: label.trackingUrl ?? null,
                  },
                  one("set_shipment_label"),
                ).andThen(fields.row);

                if (!stored.ok) {
                  // A label that is neither stored nor voided is still billed.
                  const voided = await carrier.cancel({
                    labelId: label.labelId,
                    trackingNumber: label.trackingNumber,
                  });

                  if (!voided.ok) {
                    logger.error(
                      `shipments: label ${label.labelId} from ${carrier.name} was bought but not stored or voided`,
                      { error: voided.error },
                    );
                  }
                }

                return stored;
              }),
            );
        }),
      ),
    refresh: (id) =>
      find(id).andThen((shipment) => {
        const trackingNumber = shipment.trackingNumber;

        if (trackingNumber === undefined) {
          return AsyncResult.err(
            dbError("conflict", "The shipment has no label yet", {
              hint: "SHIPMENT_NOT_LABELED",
            }),
          );
        }

        return carrierNamed(shipment.carrier).andThen((carrier) =>
          carrier
            .track(trackingNumber)
            .andThen((events) => record(id, events, "carrier")),
        );
      }),
    recordTracking: (id, events) => record(id, events, "manual"),
    ingest: (name, request) =>
      carrierNamed(name).andThen((carrier) => {
        if (!carrier.parseWebhook) {
          return AsyncResult.err(
            dbError(
              "invalid_input",
              `Carrier "${name}" doesn't send tracking webhooks`,
              { hint: "SHIPMENT_WEBHOOK_UNSUPPORTED" },
            ),
          );
        }

        return carrier.parseWebhook(request).andThen((updates) =>
          AsyncResult.from(async () => {
            const done: TrackingIngested[] = [];

            for (const update of updates) {
              const stored = await service(
                "ingest_tracking_events",
                {
                  carrier: carrier.name,
                  tracking_number: update.trackingNumber,
                  events: eventsArg(update.events),
                },
                (value): TrackingIngested => {
                  if (value === null || value === undefined) {
                    return {
                      trackingNumber: update.trackingNumber,
                      recorded: 0,
                    };
                  }

                  const row = recordOf(value, "ingest_tracking_events");

                  return {
                    trackingNumber: update.trackingNumber,
                    shipmentId: textOf(row["id"]),
                    status: enumOrThrow(
                      row["status"],
                      SHIPMENT_STATUSES,
                      "status",
                    ),
                    recorded: Number(row["recorded"]),
                  };
                },
              );

              if (!stored.ok) {
                return stored;
              }

              done.push(stored.data);
            }

            return ok(done);
          }),
        );
      }),
    cancel: (id) =>
      find(id).andThen((shipment) => {
        if (
          shipment.status !== "draft" &&
          shipment.status !== "label_created"
        ) {
          return AsyncResult.err(
            dbError("conflict", "The shipment has already shipped", {
              hint: "SHIPMENT_SHIPPED",
            }),
          );
        }

        const cancelled = (): AsyncResult<Shipment<F>> =>
          call(
            "cancel_shipment",
            { shipment_id: id },
            one("cancel_shipment"),
          ).andThen(fields.row);

        const { labelId, trackingNumber } = shipment;

        if (labelId === undefined || trackingNumber === undefined) {
          return cancelled();
        }

        return carrierNamed(shipment.carrier).andThen((carrier) =>
          carrier
            .cancel(
              { labelId, trackingNumber },
              { idempotencyKey: `void:${id}` },
            )
            .andThen(cancelled),
        );
      }),
    trackingEvents: (id) =>
      call("list_tracking_events", { shipment_id: id }, (value) =>
        recordsOf(value, "list_tracking_events").map(trackingEventOf),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "shipments",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
