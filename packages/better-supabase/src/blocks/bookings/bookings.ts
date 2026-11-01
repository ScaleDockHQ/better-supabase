import type { BlockFields, FieldsOf } from "../../core/block-fields.ts";
import type { BlockOptions } from "../../core/block-helpers.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { WeeklyHours } from "../calendar/availability.ts";
import type { JobHandler } from "../queue/types.ts";
import type {
  BookedSeries,
  BookingRecurrence,
  BookingSeries,
  BookingSeriesScope,
} from "./series.ts";

import {
  allWithFields,
  blockFields,
  extraOf,
  withFields,
} from "../../core/block-fields.ts";
import { applyTemporal } from "../../core/block-helpers.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, err } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  blockCall,
  intervalOf,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";
import { bookingOf } from "./rows.ts";
import { bookingSeriesOf, recurrenceItem } from "./series.ts";

export interface BookingsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockOptions {
  /**
   * A Standard Schema for the booking columns the app adds
   * (`blocks.bookings.options.extraColumns`), keyed by column name. The
   * customer object of `hold` and `public.hold` carries them; the schema
   * validates them there, which returns a `validation` error for a bad value,
   * and types and parses them on every booking read.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Bookings<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

/** The queue each hold enqueues a job on, to expire it when its time is up. */
export const BOOKING_EXPIRE_QUEUE = "bookings.expire-holds";

/**
 * A duration as a `Temporal.Duration` or an ISO 8601 / Postgres interval
 * string.
 */
export type BookingDuration = Temporal.Duration | string;

export interface BookingRange {
  readonly from: Temporal.Instant;
  readonly until: Temporal.Instant;
}

export interface BookingResourceInput {
  readonly id?: string;
  readonly name?: string;
  /**
   * What the resource is, matched against a service's `resourceKinds`. Default
   * `staff`.
   */
  readonly kind?: string;
  /** How many bookings can overlap: seats in a class, desks in a room. Default 1. */
  readonly capacity?: number;
  /** The IANA zone its weekly hours are in. Default `UTC`. */
  readonly tz?: string;
  /**
   * The calendar confirmed bookings are copied into, when the calendar block is
   * installed.
   */
  readonly calendarId?: string | null;
  /**
   * The member who staffs it: with `checkBusy`, a slot also needs them free in
   * the calendar block (events, out of office, focus time and leave), which
   * turns a service into an appointment schedule.
   */
  readonly hostUserId?: string | null;
  /** Default `false`. */
  readonly checkBusy?: boolean;
  readonly active?: boolean;
}

export type { WeeklyHours };

export interface BookingExceptionInput {
  readonly startsAt: Temporal.Instant;
  readonly endsAt: Temporal.Instant;
  /**
   * `true` opens the resource outside its hours. Default `false`, which closes
   * it.
   */
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
  /** The series it belongs to (`options.recurring`). */
  readonly seriesId?: string;
}

/**
 * A new booking with the token that confirms or cancels it without signing in.
 * Shown once.
 */
export interface PlacedBooking extends Booking {
  readonly accessToken: string;
}

export interface PublicBookingService {
  readonly id: string;
  readonly name: string;
  readonly duration: Temporal.Duration;
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

/** `F` is the extra booking fields `options.fields` describes. */
export interface Bookings<F extends object = Record<never, never>> {
  saveResource(input: {
    organizationId: string;
    input: BookingResourceInput;
  }): AsyncResult<{ readonly id: string }>;
  /** Replaces a resource's weekly hours. Resolves to the number of rows. */
  setAvailability(input: {
    resourceId: string;
    hours: readonly WeeklyHours[];
  }): AsyncResult<number>;
  addException(input: {
    resourceId: string;
    exception: BookingExceptionInput;
  }): AsyncResult<{ readonly id: string }>;
  deleteException(id: string): AsyncResult<boolean>;
  saveService(input: {
    organizationId: string;
    input: BookingServiceInput;
  }): AsyncResult<{ readonly id: string }>;
  /** The open slots of a service, at most 62 days at a time. */
  availableSlots(
    input: { serviceId: string; range: BookingRange } & {
      readonly tz?: string;
      readonly resourceId?: string;
    },
  ): AsyncResult<BookingSlot[]>;
  /** Holds a slot for the service's `holdFor`, or books it with `confirm`. */
  hold(
    input: {
      serviceId: string;
      resourceId: string;
      startsAt: Temporal.Instant;
      customer?: (BookingCustomer & Partial<F>) | undefined;
    } & { readonly confirm?: boolean },
  ): AsyncResult<PlacedBooking & F>;
  confirm(bookingId: string): AsyncResult<Booking & F>;
  cancel(input: {
    bookingId: string;
    reason?: string | undefined;
  }): AsyncResult<Booking & F>;
  /** The bookings that overlap the range, as the caller's policies allow. */
  list(
    input: { organizationId: string; range: BookingRange } & {
      readonly resourceId?: string;
    },
  ): AsyncResult<(Booking & F)[]>;
  /** Cancels every hold whose time is up. Service only. */
  expireHolds(): AsyncResult<number>;
  /**
   * Books every occurrence of a rule from `startsAt`, confirmed, as one series
   * (`options.recurring`). A taken occurrence fails the whole series with
   * `BOOKING_SERIES_CONFLICT`, unless `skipConflicts` leaves it out.
   */
  bookSeries(
    input: {
      serviceId: string;
      resourceId: string;
      startsAt: Temporal.Instant;
      rule: BookingRecurrence;
      customer?: (BookingCustomer & Partial<F>) | undefined;
    } & { readonly skipConflicts?: boolean },
  ): AsyncResult<BookedSeries<Booking & F>>;
  /**
   * Moves a booking to `startsAt`, or with `scope: "following"` this one and
   * every later occurrence of its series by the same amount, all or nothing.
   * Resolves to the moved bookings.
   */
  reschedule(
    input: { bookingId: string; startsAt: Temporal.Instant } & {
      readonly scope?: BookingSeriesScope;
    },
  ): AsyncResult<(Booking & F)[]>;
  /**
   * Cancels this occurrence and, by default, every later one of its series.
   * Resolves to the number of bookings cancelled.
   */
  cancelSeries(
    input: { bookingId: string } & {
      readonly scope?: BookingSeriesScope;
      readonly reason?: string;
    },
  ): AsyncResult<number>;
  /** A series with its occurrences, as the caller's policies allow. */
  series(
    seriesId: string,
  ): AsyncResult<BookingSeries & { readonly bookings: (Booking & F)[] }>;
  /** The handler for the `bookings.expire-holds` queue. */
  readonly job: JobHandler<unknown>;
  /**
   * The public side, through a share link to a service (`subjectType:
   * "booking_service"`).
   */
  readonly public: {
    service(token: string): AsyncResult<PublicBookingService>;
    slots(
      input: { token: string; range: BookingRange } & { readonly tz?: string },
    ): AsyncResult<BookingSlot[]>;
    /** Holds a slot for a guest, who must give a name and an email. */
    hold(input: {
      token: string;
      resourceId: string;
      startsAt: Temporal.Instant;
      customer: BookingCustomer &
        Partial<F> & { readonly name: string; readonly email: string };
    }): AsyncResult<PlacedBooking & F>;
    confirm(input: {
      bookingId: string;
      accessToken: string;
    }): AsyncResult<Booking & F>;
    cancel(input: {
      bookingId: string;
      accessToken: string;
    }): AsyncResult<Booking & F>;
    /** `hold` then `confirm` with the access token the hold returns. */
    book(input: {
      token: string;
      resourceId: string;
      startsAt: Temporal.Instant;
      customer: BookingCustomer &
        Partial<F> & { readonly name: string; readonly email: string };
    }): AsyncResult<Booking & F>;
  };
  /**
   * Holds and confirms a booking in one call. Without `resourceId` it books the
   * resource that has a free slot at `startsAt`, and fails with `not_found`
   * when none has.
   */
  book(input: {
    serviceId: string;
    startsAt: Temporal.Instant;
    resourceId?: string | undefined;
    customer?: (BookingCustomer & Partial<F>) | undefined;
  }): AsyncResult<PlacedBooking & F>;
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

/**
 * The jsonb item a save takes: durations as ISO 8601 strings, undefined keys
 * left out.
 */
function itemOf(input: object): Record<string, unknown> {
  const item: Record<string, unknown> = {};

  for (const [key, value] of Object.entries(input)) {
    if (value === undefined) {
      continue;
    }

    item[key] =
      value !== null && typeof value === "object" && !Array.isArray(value)
        ? String(value)
        : value;
  }

  return item;
}

const CUSTOMER_KEYS: ReadonlySet<string> = new Set([
  "name",
  "email",
  "userId",
  "notes",
]);

export function createBookings<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: BookingsOptions<S>): Bookings<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields: BlockFields<F> = blockFields(options.fields, "booking fields");

  /** The customer object, with its extra fields validated. */
  const customerOf = (
    customer: BookingCustomer | undefined,
  ): AsyncResult<object> =>
    AsyncResult.from(() =>
      fields.write(extraOf(customer ?? {}, CUSTOMER_KEYS)),
    ).map((extra) => ({ ...extra, ...itemOf(customer ?? {}) }));

  const one = (
    fn: string,
    args: Readonly<Record<string, unknown>>,
  ): AsyncResult<Booking & F> =>
    call(fn, args, (value) => value).andThen((value) =>
      withFields(fields, value, bookingOf(value)),
    );

  const placed = (
    fn: string,
    args: Readonly<Record<string, unknown>>,
    customer: BookingCustomer | undefined,
  ): AsyncResult<PlacedBooking & F> =>
    customerOf(customer).andThen((item) =>
      call(fn, { ...args, customer: item }, (value) => value).andThen((value) =>
        withFields(fields, value, placedOf(value)),
      ),
    );

  const service = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );

  const expireHolds: Bookings["expireHolds"] = () =>
    service("expire_booking_holds", {}, Number);

  const many = (value: unknown, what: string): AsyncResult<(Booking & F)[]> =>
    AsyncResult.from(() =>
      allWithFields(
        fields,
        recordsOf(value, what).map((raw) => [raw, bookingOf(raw)] as const),
      ),
    );

  const change = (bookingId: string, accessToken: string, to: BookingStatus) =>
    one("public_change_booking", {
      booking: bookingId,
      access_token: accessToken,
      to_status: to,
    });

  const client: Bookings<F> = {
    saveResource: ({ organizationId, input }) =>
      call(
        "save_booking_resource",
        { tenant: organizationId, item: itemOf(input) },
        idOf,
      ),
    setAvailability: ({ resourceId, hours }) =>
      call(
        "set_booking_availability",
        { resource: resourceId, source: { hours } },
        Number,
      ),
    addException: ({ resourceId, exception }) =>
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
    saveService: ({ organizationId, input }) =>
      call(
        "save_booking_service",
        { tenant: organizationId, item: itemOf(input) },
        idOf,
      ),
    availableSlots: ({ serviceId, range, ...slotOptions }) =>
      call(
        "available_slots",
        {
          service: serviceId,
          range_start: String(range.from),
          range_end: String(range.until),
          tz: slotOptions.tz ?? null,
          resource: slotOptions.resourceId ?? null,
        },
        slotsOf,
      ),
    hold: ({ serviceId, resourceId, startsAt, customer, ...holdOptions }) =>
      placed(
        "hold_booking",
        {
          service: serviceId,
          resource: resourceId,
          starts_at: String(startsAt),
          confirm: holdOptions.confirm ?? false,
        },
        customer,
      ),
    confirm: (bookingId) => one("confirm_booking", { booking: bookingId }),
    cancel: ({ bookingId, reason }) =>
      one("cancel_booking", { booking: bookingId, reason: reason ?? null }),
    list: ({ organizationId, range, ...listOptions }) =>
      call(
        "list_bookings",
        {
          tenant: organizationId,
          range_start: String(range.from),
          range_end: String(range.until),
          resource: listOptions.resourceId ?? null,
        },
        (value) =>
          recordsOf(value, "bookings").map(
            (raw) => [raw, bookingOf(raw)] as const,
          ),
      ).andThen((rows) => allWithFields(fields, rows)),
    expireHolds,
    bookSeries: ({
      serviceId,
      resourceId,
      startsAt,
      rule,
      customer,
      ...seriesOptions
    }) =>
      customerOf(customer).andThen((item) =>
        call(
          "book_series",
          {
            service: serviceId,
            resource: resourceId,
            starts_at: String(startsAt),
            rule: recurrenceItem(rule),
            customer: item,
            skip_conflicts: seriesOptions.skipConflicts ?? false,
          },
          (value) => recordOf(value, "booked series"),
        ).andThen((row) =>
          many(row["bookings"], "bookings").map((bookings) => ({
            series: bookingSeriesOf(row["series"]),
            bookings,
            skipped: (Array.isArray(row["skipped"]) ? row["skipped"] : []).map(
              (at) => requiredInstant(at, "skipped"),
            ),
          })),
        ),
      ),
    reschedule: ({ bookingId, startsAt, ...moveOptions }) =>
      call(
        "reschedule_booking",
        {
          booking: bookingId,
          starts_at: String(startsAt),
          scope: moveOptions.scope ?? "one",
        },
        (value) => value,
      ).andThen((value) => many(value, "bookings")),
    cancelSeries: ({ bookingId, ...cancelOptions }) =>
      call(
        "cancel_booking_series",
        {
          booking: bookingId,
          scope: cancelOptions.scope ?? "following",
          reason: cancelOptions.reason ?? null,
        },
        Number,
      ),
    series: (seriesId) =>
      call("get_booking_series", { series_id: seriesId }, (value) =>
        recordOf(value, "booking series"),
      ).andThen((row) =>
        many(row["bookings"], "bookings").map((bookings) => ({
          ...bookingSeriesOf(row),
          bookings,
        })),
      ),
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
            duration: intervalOf(row["duration"]),
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
      slots: ({ token, range, ...slotOptions }) =>
        call(
          "public_available_slots",
          {
            token,
            range_start: String(range.from),
            range_end: String(range.until),
            tz: slotOptions.tz ?? null,
          },
          slotsOf,
        ),
      hold: ({ token, resourceId, startsAt, customer }) =>
        placed(
          "public_hold_booking",
          { token, resource: resourceId, starts_at: String(startsAt) },
          customer,
        ),
      confirm: ({ bookingId, accessToken }) =>
        change(bookingId, accessToken, "confirmed"),
      cancel: ({ bookingId, accessToken }) =>
        change(bookingId, accessToken, "cancelled"),
      book: (input) =>
        client.public
          .hold(input)
          .andThen((held) =>
            client.public.confirm({
              bookingId: held.id,
              accessToken: held.accessToken,
            }),
          ),
    },
    book: ({ serviceId, startsAt, resourceId, customer }) =>
      AsyncResult.from(async () => {
        let chosen = resourceId;

        if (chosen === undefined) {
          const slots = await hooked.availableSlots({
            serviceId,
            range: { from: startsAt, until: startsAt.add({ seconds: 1 }) },
          });

          if (!slots.ok) {
            return slots;
          }

          chosen = slots.data.find((slot) =>
            slot.startsAt.equals(startsAt),
          )?.resourceId;

          if (chosen === undefined) {
            return err(
              dbError("not_found", "No resource is free at that time"),
            );
          }
        }

        return hooked.hold({
          serviceId,
          resourceId: chosen,
          startsAt,
          confirm: true,
          customer,
        });
      }),
  };

  // Helpers call the hooked client, so app hooks see each step.
  const hooked: Bookings<F> = withBlockHooks(client, options.hooks, {
    block: "bookings",
    ...(options.logger ? { logger: options.logger } : {}),
  });

  return hooked;
}
