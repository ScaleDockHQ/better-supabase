import type { BlockOptions } from "../../core/block-helpers.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { JobHandler } from "../jobs/types.ts";

import { applyTemporal } from "../../core/block-helpers.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  blockCall,
  oneOf,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export interface BookingsOptions extends BlockOptions {
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Bookings>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

/** The queue each hold enqueues a job on, to expire it when its time is up. */
export const BOOKING_EXPIRE_QUEUE = "bookings.expire-holds";

/** A duration as a `Temporal.Duration` or an ISO 8601 / Postgres interval string. */
export type BookingDuration = Temporal.Duration | string;

export interface BookingRange {
  readonly from: Temporal.Instant;
  readonly until: Temporal.Instant;
}

export interface BookingResourceInput {
  readonly id?: string;
  readonly name?: string;
  /** What the resource is, matched against a service's `resourceKinds`. Default `staff`. */
  readonly kind?: string;
  /** How many bookings can overlap: seats in a class, desks in a room. Default 1. */
  readonly capacity?: number;
  /** The IANA zone its weekly hours are in. Default `UTC`. */
  readonly tz?: string;
  /** The calendar confirmed bookings are copied into, when the calendar block is installed. */
  readonly calendarId?: string | null;
  readonly active?: boolean;
}

/** Weekly opening hours: `weekday` 1 is Monday, times are `HH:MM` in the resource's zone. */
export interface WeeklyHours {
  readonly weekday: 1 | 2 | 3 | 4 | 5 | 6 | 7;
  readonly start: string;
  readonly end: string;
}

export interface BookingExceptionInput {
  readonly startsAt: Temporal.Instant;
  readonly endsAt: Temporal.Instant;
  /** `true` opens the resource outside its hours. Default `false`, which closes it. */
  readonly available?: boolean;
  readonly reason?: string;
}

export interface BookingServiceInput {
  readonly id?: string;
  readonly name?: string;
  readonly duration?: BookingDuration;
  readonly bufferBefore?: BookingDuration;
  readonly bufferAfter?: BookingDuration;
  /** The resource kinds that can serve it; empty means every resource. */
  readonly resourceKinds?: readonly string[];
  /** The distance between slot starts. Default the duration. */
  readonly step?: BookingDuration | null;
  /** How far ahead a slot must start. */
  readonly minNotice?: BookingDuration;
  /** How long a hold keeps the slot. Default 10 minutes. */
  readonly holdFor?: BookingDuration;
  /** Minutes before the start that reminders go out. Default one day. */
  readonly reminderOffsets?: readonly number[];
  readonly active?: boolean;
}

export interface BookingSlot {
  readonly resourceId: string;
  readonly startsAt: Temporal.Instant;
  readonly endsAt: Temporal.Instant;
  /** The start as wall-clock time in the zone asked for, else the resource's. */
  readonly localStart: Temporal.PlainDateTime;
  /** Free seats at this time. */
  readonly seats: number;
}

export interface BookingCustomer {
  readonly name?: string;
  readonly email?: string;
  /** Only managers can book for another user. */
  readonly userId?: string;
  readonly notes?: string;
}

export type BookingStatus = "hold" | "confirmed" | "cancelled";

export interface Booking {
  readonly id: string;
  readonly resourceId: string;
  readonly serviceId: string;
  readonly seat: number;
  readonly startsAt: Temporal.Instant;
  readonly endsAt: Temporal.Instant;
  readonly status: BookingStatus;
  readonly holdExpiresAt?: Temporal.Instant;
  readonly customerName?: string;
  readonly customerEmail?: string;
  readonly customerUserId?: string;
  readonly notes?: string;
  readonly createdAt?: Temporal.Instant;
  readonly cancelledAt?: Temporal.Instant;
  readonly cancelReason?: string;
}

/** A new booking with the token that confirms or cancels it without signing in. Shown once. */
export interface PlacedBooking extends Booking {
  readonly accessToken: string;
}

export interface PublicBookingService {
  readonly id: string;
  readonly name: string;
  /** The duration as Postgres prints an interval, such as `00:30:00`. */
  readonly duration: string;
  readonly resources: readonly {
    readonly id: string;
    readonly name: string;
    readonly kind: string;
    readonly tz: string;
  }[];
}

/** The payload a hold enqueues on `bookings.expire-holds`. */
export interface BookingExpirePayload {
  readonly bookingId?: string;
}

export interface Bookings {
  saveResource(
    organizationId: string,
    input: BookingResourceInput,
  ): AsyncResult<{ readonly id: string }>;
  /** Replaces a resource's weekly hours. Resolves to the number of rows. */
  setAvailability(
    resourceId: string,
    hours: readonly WeeklyHours[],
  ): AsyncResult<number>;
  addException(
    resourceId: string,
    exception: BookingExceptionInput,
  ): AsyncResult<{ readonly id: string }>;
  deleteException(id: string): AsyncResult<boolean>;
  saveService(
    organizationId: string,
    input: BookingServiceInput,
  ): AsyncResult<{ readonly id: string }>;
  /** The open slots of a service, at most 62 days at a time. */
  availableSlots(
    serviceId: string,
    range: BookingRange,
    options?: { readonly tz?: string; readonly resourceId?: string },
  ): AsyncResult<BookingSlot[]>;
  /** Holds a slot for the service's `holdFor`, or books it with `confirm`. */
  hold(
    serviceId: string,
    resourceId: string,
    startsAt: Temporal.Instant,
    customer?: BookingCustomer,
    options?: { readonly confirm?: boolean },
  ): AsyncResult<PlacedBooking>;
  confirm(bookingId: string): AsyncResult<Booking>;
  cancel(bookingId: string, reason?: string): AsyncResult<Booking>;
  /** The bookings that overlap the range, as the caller's policies allow. */
  list(
    organizationId: string,
    range: BookingRange,
    options?: { readonly resourceId?: string },
  ): AsyncResult<Booking[]>;
  /** Cancels every hold whose time is up. Service only. */
  expireHolds(): AsyncResult<number>;
  /** The handler for the `bookings.expire-holds` queue. */
  readonly job: JobHandler<unknown>;
  /** The public side, through a share link to a service (`subjectType: "booking_service"`). */
  readonly public: {
    service(token: string): AsyncResult<PublicBookingService>;
    slots(
      token: string,
      range: BookingRange,
      options?: { readonly tz?: string },
    ): AsyncResult<BookingSlot[]>;
    /** Holds a slot for a guest, who must give a name and an email. */
    hold(
      token: string,
      resourceId: string,
      startsAt: Temporal.Instant,
      customer: BookingCustomer & {
        readonly name: string;
        readonly email: string;
      },
    ): AsyncResult<PlacedBooking>;
    confirm(bookingId: string, accessToken: string): AsyncResult<Booking>;
    cancel(bookingId: string, accessToken: string): AsyncResult<Booking>;
  };
}

const STATUSES: readonly BookingStatus[] = ["hold", "confirmed", "cancelled"];

/** A booking row as `hold_booking`, `list_bookings` and the others return it. */
export function bookingOf(value: unknown): Booking {
  const row = recordOf(value, "booking");
  const text = (key: string) => {
    const found = optionalText(row[key]);
    return found === undefined ? {} : { [key]: found };
  };
  const instant = (key: string) => {
    const found = optionalInstant(row[key]);
    return found === undefined ? {} : { [key]: found };
  };
  return {
    id: textOf(row["id"]),
    resourceId: textOf(row["resourceId"]),
    serviceId: textOf(row["serviceId"]),
    seat: Number(row["seat"] ?? 1),
    startsAt: requiredInstant(row["startsAt"], "startsAt"),
    endsAt: requiredInstant(row["endsAt"], "endsAt"),
    status: oneOf(row["status"], STATUSES, "hold"),
    ...instant("holdExpiresAt"),
    ...text("customerName"),
    ...text("customerEmail"),
    ...text("customerUserId"),
    ...text("notes"),
    ...instant("createdAt"),
    ...instant("cancelledAt"),
    ...text("cancelReason"),
  };
}

function placedOf(value: unknown): PlacedBooking {
  const row = recordOf(value, "booking");
  return { ...bookingOf(row), accessToken: textOf(row["accessToken"]) };
}

function slotOf(value: Record<string, unknown>): BookingSlot {
  return {
    resourceId: textOf(value["resourceId"]),
    startsAt: requiredInstant(value["startsAt"], "startsAt"),
    endsAt: requiredInstant(value["endsAt"], "endsAt"),
    localStart: temporal().PlainDateTime.from(textOf(value["localStart"])),
    seats: Number(value["seats"] ?? 0),
  };
}

const slotsOf = (value: unknown): BookingSlot[] =>
  recordsOf(value, "slots").map(slotOf);

const idOf = (value: unknown): { readonly id: string } => ({
  id: textOf(recordOf(value, "result")["id"]),
});

/** The jsonb item a save takes: durations as ISO 8601 strings, undefined keys left out. */
function itemOf(input: object): Record<string, unknown> {
  const item: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(input)) {
    if (value === undefined) continue;
    item[key] =
      value !== null && typeof value === "object" && !Array.isArray(value)
        ? String(value)
        : value;
  }
  return item;
}

function customerOf(customer: BookingCustomer | undefined): object {
  return itemOf(customer ?? {});
}

export function createBookings(options: BookingsOptions): Bookings {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const service = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );
  const expireHolds: Bookings["expireHolds"] = () =>
    service("expire_booking_holds", {}, Number);
  const change = (bookingId: string, accessToken: string, to: BookingStatus) =>
    call(
      "public_change_booking",
      { booking: bookingId, access_token: accessToken, to_status: to },
      bookingOf,
    );
  const client: Bookings = {
    saveResource: (organizationId, input) =>
      call(
        "save_booking_resource",
        { tenant: organizationId, item: itemOf(input) },
        idOf,
      ),
    setAvailability: (resourceId, hours) =>
      call(
        "set_booking_availability",
        { resource: resourceId, source: { hours } },
        Number,
      ),
    addException: (resourceId, exception) =>
      call(
        "add_booking_exception",
        {
          resource: resourceId,
          starts_at: String(exception.startsAt),
          ends_at: String(exception.endsAt),
          available: exception.available ?? false,
          reason: exception.reason ?? null,
        },
        idOf,
      ),
    deleteException: (id) =>
      call(
        "delete_booking_exception",
        { exception_id: id },
        (value) => value === true,
      ),
    saveService: (organizationId, input) =>
      call(
        "save_booking_service",
        { tenant: organizationId, item: itemOf(input) },
        idOf,
      ),
    availableSlots: (serviceId, range, slotOptions) =>
      call(
        "available_slots",
        {
          service: serviceId,
          range_start: String(range.from),
          range_end: String(range.until),
          tz: slotOptions?.tz ?? null,
          resource: slotOptions?.resourceId ?? null,
        },
        slotsOf,
      ),
    hold: (serviceId, resourceId, startsAt, customer, holdOptions) =>
      call(
        "hold_booking",
        {
          service: serviceId,
          resource: resourceId,
          starts_at: String(startsAt),
          customer: customerOf(customer),
          confirm: holdOptions?.confirm ?? false,
        },
        placedOf,
      ),
    confirm: (bookingId) =>
      call("confirm_booking", { booking: bookingId }, bookingOf),
    cancel: (bookingId, reason) =>
      call(
        "cancel_booking",
        { booking: bookingId, reason: reason ?? null },
        bookingOf,
      ),
    list: (organizationId, range, listOptions) =>
      call(
        "list_bookings",
        {
          tenant: organizationId,
          range_start: String(range.from),
          range_end: String(range.until),
          resource: listOptions?.resourceId ?? null,
        },
        (value) => recordsOf(value, "bookings").map(bookingOf),
      ),
    expireHolds,
    job: async () => {
      await expireHolds().orThrow();
    },
    public: {
      service: (token) =>
        call("public_booking_service", { token }, (value) => {
          const row = recordOf(value, "booking service");
          return {
            id: textOf(row["id"]),
            name: textOf(row["name"]),
            duration: textOf(row["duration"]),
            resources: recordsOf(row["resources"], "resources").map(
              (resource) => ({
                id: textOf(resource["id"]),
                name: textOf(resource["name"]),
                kind: textOf(resource["kind"]),
                tz: textOf(resource["tz"]),
              }),
            ),
          };
        }),
      slots: (token, range, slotOptions) =>
        call(
          "public_available_slots",
          {
            token,
            range_start: String(range.from),
            range_end: String(range.until),
            tz: slotOptions?.tz ?? null,
          },
          slotsOf,
        ),
      hold: (token, resourceId, startsAt, customer) =>
        call(
          "public_hold_booking",
          {
            token,
            resource: resourceId,
            starts_at: String(startsAt),
            customer: customerOf(customer),
          },
          placedOf,
        ),
      confirm: (bookingId, accessToken) =>
        change(bookingId, accessToken, "confirmed"),
      cancel: (bookingId, accessToken) =>
        change(bookingId, accessToken, "cancelled"),
    },
  };
  return withBlockHooks(client, options.hooks, {
    block: "bookings",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
