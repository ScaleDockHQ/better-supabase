"use server";

import type { BookingCustomer } from "better-supabase/blocks/bookings";

import { dbError, err, ok } from "better-supabase";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import { can } from "@/features/user/user-permissions";
import { blocks } from "@/lib/blocks";
import { refreshCaller } from "@/lib/refresh-caller";
import { bs } from "@/lib/supabase/server";

import {
  BOOKING_PAGE_OWNER,
  BOOKING_SERVICE_SUBJECT,
  findBookingPage,
} from "./bookings-queries";

type Writable<T> = { -readonly [K in keyof T]: T[K] };

const Clock = v.pipe(v.string(), v.regex(/^([01]\d|2[0-3]):[0-5]\d$/));

const DEFAULT_HOURS = ([1, 2, 3, 4, 5] as const).map((weekday) => ({
  weekday,
  start: "09:00",
  end: "17:00",
}));

const notSetUp = () =>
  err(dbError("not_found", "Set up your booking page first"));

/**
 * Creates the signed-in member's booking page: a bookable resource only its
 * service uses, a 30 minute service, weekday hours from 09:00 to 17:00, and the
 * calendar that indexes them.
 */
export const setUpBookingPage = bs.action(
  {
    input: v.object({
      tz: v.pipe(v.string(), v.minLength(1), v.maxLength(64)),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "bookings.manage"),
  },
  async ({ tz }, { tenant, supabase, session, auth }) => {
    if (session.kind !== "user") {
      return notSetUp();
    }

    const userId = session.user.id;

    if (await findBookingPage(supabase, tenant, userId)) {
      return ok(null);
    }

    const { bookings, calendar } = blocks(supabase);
    const kind = `person:${userId}`;
    const name = session.user.email ?? "Booking page";
    const resource = await bookings.saveResource(tenant, { name, kind, tz });

    if (!resource.ok) {
      return resource;
    }

    const service = await bookings.saveService(tenant, {
      name: "Meeting",
      duration: "PT30M",
      resourceKinds: [kind],
    });

    if (!service.ok) {
      return service;
    }

    const hours = await bookings.setAvailability(
      resource.data.id,
      DEFAULT_HOURS,
    );

    if (!hours.ok) {
      return hours;
    }

    const index = await calendar.createCalendar(tenant, "Booking page", {
      tz,
      ownerType: BOOKING_PAGE_OWNER,
      ownerId: `${userId}/${resource.data.id}/${service.data.id}`,
    });

    if (!index.ok) {
      return index;
    }

    refreshCaller(auth);

    return ok(null);
  },
);

/** Replaces the weekly hours of the member's own booking page. */
export const saveWeeklyHours = bs.action(
  {
    input: v.object({
      hours: v.pipe(
        v.array(
          v.pipe(
            v.object({
              weekday: v.picklist([1, 2, 3, 4, 5, 6, 7]),
              start: Clock,
              end: Clock,
            }),
            v.check((day) => day.start < day.end, "End after the start"),
          ),
        ),
        v.maxLength(7),
      ),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "bookings.manage"),
  },
  async ({ hours }, { tenant, supabase, session, auth }) => {
    const page =
      session.kind === "user"
        ? await findBookingPage(supabase, tenant, session.user.id)
        : null;

    if (!page) {
      return notSetUp();
    }

    const saved = await blocks(supabase).bookings.setAvailability(
      page.resourceId,
      hours,
    );

    if (!saved.ok) {
      return saved;
    }

    refreshCaller(auth);

    return ok({ days: saved.data });
  },
);

/** A new public link to the member's booking page. The token shows only once. */
export const createBookingLink = bs.action(
  {
    input: v.object({}),
    requireTenant: true,
    authorize: (session) =>
      can(session, "bookings.manage") && can(session, "share_links.create"),
  },
  async (_input, { tenant, supabase, session, auth }) => {
    const page =
      session.kind === "user"
        ? await findBookingPage(supabase, tenant, session.user.id)
        : null;

    if (!page) {
      return notSetUp();
    }

    const created = await blocks(supabase, tenant).shareLinks.create(
      { type: BOOKING_SERVICE_SUBJECT, id: page.serviceId },
      { role: "view" },
    );

    if (!created.ok) {
      return created;
    }

    refreshCaller(auth);

    return ok({ token: created.data.token });
  },
);

/** Books a slot for a visitor of a booking link, signed in or not. */
export const bookSlot = bs.action(
  {
    input: v.object({
      token: v.pipe(v.string(), v.regex(/^[0-9a-f]{32,128}$/)),
      resourceId: v.pipe(v.string(), v.uuid()),
      startsAt: v.pipe(v.string(), v.isoTimestamp()),
      name: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
      email: v.pipe(v.string(), v.trim(), v.email(), v.maxLength(320)),
      notes: v.optional(v.pipe(v.string(), v.trim(), v.maxLength(2000))),
    }),
    allow: ["anon", "user"],
  },
  async (
    { token, resourceId, startsAt, name, email, notes },
    { supabase, auth },
  ) => {
    const booking = blocks(supabase).bookings.public;

    const customer: Writable<BookingCustomer> & {
      name: string;
      email: string;
    } = { name, email: email.toLowerCase() };

    if (notes) {
      customer.notes = notes;
    }

    const held = await booking.hold(
      token,
      resourceId,
      Temporal.Instant.from(startsAt),
      customer,
    );

    if (!held.ok) {
      return held;
    }

    const confirmed = await booking.confirm(
      held.data.id,
      held.data.accessToken,
    );

    if (!confirmed.ok) {
      return confirmed;
    }

    refreshCaller(auth);

    return ok({
      startsAt: confirmed.data.startsAt.toString(),
      endsAt: confirmed.data.endsAt.toString(),
    });
  },
);
