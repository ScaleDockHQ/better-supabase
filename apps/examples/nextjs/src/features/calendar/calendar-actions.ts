"use server";

import { dbError, err, ok } from "better-supabase";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import { can } from "@/features/user/user-permissions";
import { blocks } from "@/lib/blocks";
import { refreshCaller } from "@/lib/refresh-caller";
import { bs } from "@/lib/supabase/server";

import { EVENT_SUBJECT, REMINDER_OFFSETS } from "./calendar-subjects";

const Id = v.pipe(v.string(), v.uuid());

/** Reminds the caller `offsetMinutes` before each occurrence of an event. */
export const addEventReminder = bs.action(
  {
    input: v.object({
      eventId: Id,
      offsetMinutes: v.picklist(REMINDER_OFFSETS),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "reminders.manage"),
  },
  async ({ eventId, offsetMinutes }, { tenant, supabase, auth }) => {
    const saved = await blocks(supabase).reminders.save(
      tenant,
      EVENT_SUBJECT,
      eventId,
      offsetMinutes,
    );

    if (!saved.ok) {
      return saved;
    }

    refreshCaller(auth);

    return ok(null);
  },
);

/** Removes one of the caller's reminders. */
export const removeEventReminder = bs.action(
  {
    input: v.object({ reminderId: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "reminders.manage"),
  },
  async ({ reminderId }, { supabase, auth }) => {
    const removed = await blocks(supabase).reminders.remove(reminderId);

    if (!removed.ok) {
      return removed;
    }

    if (!removed.data) {
      return err(dbError("not_found", "Reminder not found"));
    }

    refreshCaller(auth);

    return ok(null);
  },
);

const Clock = v.pipe(v.string(), v.regex(/^([01]\d|2[0-3]):[0-5]\d$/));

/** Creates the organization's team calendar, in the zone the browser reports. */
export const createCalendar = bs.action(
  {
    input: v.object({
      name: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(100)),
      tz: v.pipe(v.string(), v.minLength(1), v.maxLength(64)),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "calendar.manage"),
  },
  async ({ name, tz }, { tenant, supabase, auth }) => {
    const created = await blocks(supabase).calendar.createCalendar(
      tenant,
      name,
      { tz },
    );

    if (!created.ok) {
      return created;
    }

    refreshCaller(auth);

    return ok({ id: created.data.id });
  },
);

/**
 * Adds an event on a day, timed or all day, in the calendar's zone. An all-day
 * event ends at the start of the next day.
 */
export const createEvent = bs.action(
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
    authorize: (session) => can(session, "calendar.write"),
  },
  async (input, { supabase, auth }) => {
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

    const saved = await blocks(supabase).calendar.save(input.calendarId, {
      title: input.title,
      allDay,
      tz: input.tz,
      startsAt: allDay ? at(day) : at(day, input.start),
      endsAt: allDay ? at(day.add({ days: 1 })) : at(day, input.end),
      location: input.location === "" ? null : (input.location ?? null),
    });

    if (!saved.ok) {
      return saved;
    }

    refreshCaller(auth);

    return ok({ id: saved.data.id });
  },
);
