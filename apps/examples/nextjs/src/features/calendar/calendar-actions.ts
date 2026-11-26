"use server";

import { dbError, err, ok } from "better-supabase";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

import { EVENT_SUBJECT, REMINDER_OFFSETS } from "./calendar-subjects";

const Id = v.pipe(v.string(), v.uuid());

/** Reminds the caller `offsetMinutes` before each occurrence of an event. */
export const addEventReminder = bsb.blockAction(
  ({ db }) => db.reminders,
  "upsert",
  {
    input: v.object({
      eventId: Id,
      offsetMinutes: v.picklist(REMINDER_OFFSETS),
    }),
    requireTenant: true,
    permission: "reminders.manage",
    tags: () => [tags.calendar(), tags.bookings()],
    refresh: true,
    args: ({ eventId, offsetMinutes }) => [
      { subject: { type: EVENT_SUBJECT, id: eventId }, when: offsetMinutes },
    ],
  },
  () => null,
);

/** Removes one of the caller's reminders. */
export const removeEventReminder = bsb.action(
  {
    input: v.object({ reminderId: Id }),
    requireTenant: true,
    permission: "reminders.manage",
    tags: () => [tags.calendar(), tags.bookings()],
    refresh: true,
  },
  async ({ reminderId }, { db }) => {
    const removed = await db.reminders.remove(reminderId);

    if (!removed.ok) {
      return removed;
    }

    if (!removed.data) {
      return err(dbError("not_found", "Reminder not found"));
    }

    return ok(null);
  },
);

const WORKDAYS = [1, 2, 3, 4, 5] as const;

const Clock = v.pipe(v.string(), v.regex(/^([01]\d|2[0-3]):[0-5]\d$/));

/** Creates the organization's team calendar, in the zone the browser reports. */
export const createCalendar = bsb.blockAction(
  ({ db }) => db.calendar,
  "createCalendar",
  {
    input: v.object({
      name: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(100)),
      tz: v.pipe(v.string(), v.minLength(1), v.maxLength(64)),
    }),
    requireTenant: true,
    permission: "calendar.manage",
    tags: () => [tags.calendar(), tags.bookings()],
    refresh: true,
    args: ({ name, tz }, { tenant }) => [
      { organizationId: tenant, name, options: { tz } },
    ],
  },
  (created) => ({ id: created.id }),
);

/**
 * Adds an event on a day, timed or all day, in the calendar's zone. An all-day
 * event ends at the start of the next day.
 */
export const createEvent = bsb.action(
  {
    input: v.pipe(
      v.object({
        calendarId: v.pipe(v.string(), v.uuid()),
        tz: v.pipe(v.string(), v.minLength(1), v.maxLength(64)),
        title: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
        date: v.pipe(v.string(), v.isoDate()),
        allDay: v.optional(v.literal("on")),
        start: v.optional(Clock, "09:00"),
        end: v.optional(Clock, "10:00"),
        location: v.optional(v.pipe(v.string(), v.trim(), v.maxLength(200))),
      }),
      v.check(
        (input) => input.allDay === "on" || input.start < input.end,
        "End after the start",
      ),
    ),
    requireTenant: true,
    permission: "calendar.write",
    tags: () => [tags.calendar(), tags.bookings()],
    refresh: true,
  },
  async (input, { db }) => {
    const day = Temporal.PlainDate.from(input.date);
    const allDay = input.allDay === "on";

    const at = (date: Temporal.PlainDate, time?: string) =>
      (time === undefined
        ? date.toZonedDateTime(input.tz)
        : date.toZonedDateTime({
            timeZone: input.tz,
            plainTime: Temporal.PlainTime.from(time),
          })
      ).toInstant();

    const saved = await db.calendar.upsert({
      calendarId: input.calendarId,
      input: {
        title: input.title,
        allDay,
        tz: input.tz,
        startsAt: allDay ? at(day) : at(day, input.start),
        endsAt: allDay ? at(day.add({ days: 1 })) : at(day, input.end),
        location: input.location === "" ? null : (input.location ?? null),
      },
    });

    if (!saved.ok) {
      return saved;
    }

    return ok({ id: saved.data.id });
  },
);

/**
 * Replaces the caller's working hours with the same hours Monday to Friday, in
 * their browser's zone.
 */
export const setWorkingHours = bsb.blockAction(
  ({ db }) => db.calendar,
  "setWorkingHours",
  {
    input: v.pipe(
      v.object({
        tz: v.pipe(v.string(), v.minLength(1), v.maxLength(64)),
        start: Clock,
        end: Clock,
      }),
      v.check((input) => input.start < input.end, "End after the start"),
    ),
    requireTenant: true,
    permission: "calendar.read",
    tags: () => [tags.calendar(), tags.bookings()],
    refresh: true,
    args: ({ tz, start, end }, { tenant }) => [
      {
        organizationId: tenant,
        input: {
          tz,
          hours: WORKDAYS.map((weekday) => ({ weekday, start, end })),
        },
      },
    ],
  },
  (saved) => ({ rows: saved }),
);
