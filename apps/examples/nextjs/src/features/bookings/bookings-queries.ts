import "server-only";
import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";
import { Temporal } from "temporal-polyfill";

import { blocks } from "@/lib/blocks";
import { bs } from "@/lib/supabase/server";

/** What a loader gives a component: the data, a failed read, or nothing to show. */
export type Loaded<T> =
  | { readonly kind: "ok"; readonly data: T }
  | { readonly kind: "error" }
  | { readonly kind: "missing" };

/**
 * Runs a loader and turns a thrown read into `{ kind: "error" }`, so the
 * component shows Retry. A failed read is never cached.
 */
export async function settle<T>(
  load: () => Promise<T | null>,
): Promise<Loaded<T>> {
  try {
    const data = await load();

    return data === null ? { kind: "missing" } : { kind: "ok", data };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}

/** Marks the calendar that indexes a member's booking page. */
export const BOOKING_PAGE_OWNER = "booking_page";
export const BOOKING_SERVICE_SUBJECT = "booking_service";

export interface BookingPageRef {
  readonly resourceId: string;
  readonly serviceId: string;
  readonly tz: string;
}

/**
 * The booking page of the signed-in member. The bookings block can't list
 * resources or services, so setup creates a calendar owned by `booking_page`
 * whose `ownerId` is `<userId>/<resourceId>/<serviceId>`.
 */
export async function findBookingPage(
  supabase: Parameters<typeof blocks>[0],
  tenant: string,
  userId: string,
): Promise<BookingPageRef | null> {
  const calendars = await blocks(supabase)
    .calendar.listCalendars(tenant)
    .orThrow();

  for (const calendar of calendars) {
    const [owner, resourceId, serviceId] = (calendar.ownerId ?? "").split("/");

    if (
      calendar.ownerType === BOOKING_PAGE_OWNER &&
      owner === userId &&
      resourceId &&
      serviceId
    ) {
      return { resourceId, serviceId, tz: calendar.tz };
    }
  }

  return null;
}

export interface DayHours {
  readonly weekday: 1 | 2 | 3 | 4 | 5 | 6 | 7;
  /** `HH:MM`, or `null` when the day has no hours. */
  readonly start: string | null;
  readonly end: string | null;
}

export interface BookingSetup {
  /** `null` until the member sets up a booking page. */
  readonly page: (BookingPageRef & { readonly liveLinks: number }) | null;
  /** Monday first. */
  readonly hours: readonly DayHours[];
}

const WEEKDAYS = [1, 2, 3, 4, 5, 6, 7] as const;

/**
 * The member's booking page and its weekly hours. The block has no read for
 * hours, so they come from the open slots of a week from next Monday: each day
 * spans its first slot's start to its last slot's end. Bookings at a day's
 * edges narrow it, and a break inside a day doesn't show.
 */
export async function loadBookingSetup(): Promise<BookingSetup | null> {
  "use cache: private";
  const { session, supabase } = await bs.cached();
  const tenant = tenantOf(session);

  if (!tenant || session.kind !== "user") {
    return null;
  }

  const page = await findBookingPage(supabase, tenant, session.user.id);

  if (!page) {
    return {
      page: null,
      hours: WEEKDAYS.map((weekday) => ({ weekday, start: null, end: null })),
    };
  }

  const today = Temporal.Now.plainDateISO(page.tz);
  const monday = today.add({ days: 8 - today.dayOfWeek });

  const at = (date: Temporal.PlainDate) =>
    date.toZonedDateTime(page.tz).toInstant();

  const { bookings, shareLinks } = blocks(supabase, tenant);

  const [slots, links] = await Promise.all([
    bookings
      .availableSlots(
        page.serviceId,
        { from: at(monday), until: at(monday.add({ days: 7 })) },
        { tz: page.tz, resourceId: page.resourceId },
      )
      .orThrow(),
    shareLinks
      .list({ type: BOOKING_SERVICE_SUBJECT, id: page.serviceId })
      .orThrow(),
  ]);

  const now = Temporal.Now.instant();

  return {
    page: {
      ...page,
      liveLinks: links.filter(
        (link) =>
          link.revokedAt === null &&
          (link.expiresAt === null ||
            Temporal.Instant.compare(link.expiresAt, now) > 0),
      ).length,
    },
    hours: WEEKDAYS.map((weekday) => {
      const day = slots.filter((slot) => slot.localStart.dayOfWeek === weekday);
      const first = day[0];
      const last = day.at(-1);

      return {
        weekday,
        start: first
          ? first.localStart.toPlainTime().toString({ smallestUnit: "minute" })
          : null,
        end: last
          ? last.endsAt
              .toZonedDateTimeISO(page.tz)
              .toPlainTime()
              .toString({ smallestUnit: "minute" })
          : null,
      };
    }),
  };
}

export interface PublicSlot {
  readonly resourceId: string;
  /** ISO 8601 instant. */
  readonly startsAt: string;
  /** `HH:MM` in the page's zone. */
  readonly time: string;
}

export interface PublicBookingDay {
  /** `YYYY-MM-DD` in the page's zone. */
  readonly date: string;
  readonly slots: readonly PublicSlot[];
}

/**
 * Minutes in a Postgres interval as it prints, such as `00:30:00` or `1 day
 * 02:00:00`.
 */
function intervalMinutes(interval: string): number {
  const days = /(\d+) days?/.exec(interval)?.[1];

  const [hours = "0", minutes = "0"] =
    /(\d+):(\d+):\d+/.exec(interval)?.slice(1) ?? [];

  return Number(days ?? 0) * 24 * 60 + Number(hours) * 60 + Number(minutes);
}

export interface PublicBookingPage {
  readonly serviceName: string;
  readonly hostName: string;
  /** The service's length in minutes. */
  readonly minutes: number;
  readonly tz: string;
  readonly from: string;
  readonly days: readonly PublicBookingDay[];
}

/**
 * The service a booking link points at and its open slots for the 7 days from
 * `from` (`YYYY-MM-DD`, today when it is earlier or missing). `null` when the
 * token doesn't resolve.
 */
export async function loadPublicBooking(
  token: string,
  from: string | undefined,
): Promise<PublicBookingPage | null> {
  "use cache: private";
  const { supabase } = await bs.cached();
  const { bookings } = blocks(supabase);
  const service = await bookings.public.service(token);

  if (!service.ok) {
    if (service.error.hint === "BOOKING_LINK_INVALID") {
      return null;
    }

    throw new Error(service.error.message);
  }

  const resource = service.data.resources[0];
  const tz = resource?.tz ?? "UTC";
  const today = Temporal.Now.plainDateISO(tz);

  const asked =
    from && /^\d{4}-\d{2}-\d{2}$/.test(from)
      ? Temporal.PlainDate.from(from, { overflow: "constrain" })
      : today;

  const start = Temporal.PlainDate.compare(asked, today) > 0 ? asked : today;
  const at = (date: Temporal.PlainDate) => date.toZonedDateTime(tz).toInstant();

  const slots = await bookings.public
    .slots(
      token,
      { from: at(start), until: at(start.add({ days: 7 })) },
      { tz },
    )
    .orThrow();

  const days = new Map<string, PublicSlot[]>();

  for (const slot of slots) {
    const date = slot.localStart.toPlainDate().toString();

    days.set(date, [
      ...(days.get(date) ?? []),
      {
        resourceId: slot.resourceId,
        startsAt: slot.startsAt.toString(),
        time: slot.localStart
          .toPlainTime()
          .toString({ smallestUnit: "minute" }),
      },
    ]);
  }

  return {
    serviceName: service.data.name,
    hostName: resource?.name ?? service.data.name,
    minutes: intervalMinutes(service.data.duration),
    tz,
    from: start.toString(),
    days: [...days].map(([date, items]) => ({ date, slots: items })),
  };
}
