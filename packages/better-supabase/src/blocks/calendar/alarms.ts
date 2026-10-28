import type { ContentLine } from "./ics-text.ts";

import { temporal } from "../../core/temporal-required.ts";
import { oneOf, optionalInstant, optionalText } from "../shared.ts";
import { escapeText, unescapeText, utc } from "./ics-text.ts";

/** RFC 5545 `ACTION`, in lowercase. */
export type CalendarAlarmAction = "display" | "email" | "audio";

/**
 * One `VALARM` of an event: event data that every reader of the event gets
 * (exported in iCalendar files and feeds, read from imports), fired by the
 * reader's calendar client. A reminder the server sends to one user lives in
 * the reminders block instead.
 */
export interface CalendarAlarm {
  readonly id?: string;
  /** Default `display`. */
  readonly action: CalendarAlarmAction;
  /**
   * Minutes from the event's start (or end, with `related: "end"`), with the
   * RFC 5545 sign: `-15` fires 15 minutes before. Set this or `triggerAt`.
   */
  readonly triggerMinutes?: number;
  /** What `triggerMinutes` counts from. Default `start`. */
  readonly related?: "start" | "end";
  /** An absolute trigger time, instead of `triggerMinutes`. */
  readonly triggerAt?: Temporal.Instant;
  /** How many more times it fires after the first (`REPEAT`). Default 0. */
  readonly repeat?: number;
  /** Minutes between repeats (`DURATION`), required with `repeat`. */
  readonly repeatMinutes?: number;
  /** The alarm's text. Export falls back to the event's title. */
  readonly description?: string;
  /** An email alarm's subject. Export falls back to the event's title. */
  readonly summary?: string;
}

const ACTIONS: readonly CalendarAlarmAction[] = ["display", "email", "audio"];

const DURATION =
  /^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/u;

const UTC_DATE_TIME = /^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$/u;

const whole = (value: unknown): number | undefined =>
  typeof value === "number" && Number.isFinite(value)
    ? Math.trunc(value)
    : undefined;

/** An RFC 5545 duration in whole minutes (seconds are dropped). */
function durationMinutes(value: string): number | undefined {
  const match = DURATION.exec(value.trim().toUpperCase());

  if (match === null || value.trim().length < 3) {
    return undefined;
  }

  const [, sign, weeks, days, hours, minutes, seconds] = match;
  const number = (part: string | undefined) => Number(part ?? "0");

  const total =
    number(weeks) * 10_080 +
    number(days) * 1440 +
    number(hours) * 60 +
    number(minutes) +
    Math.trunc(number(seconds) / 60);

  return sign === "-" && total !== 0 ? -total : total;
}

function minutesDuration(minutes: number): string {
  return `${minutes < 0 ? "-" : ""}PT${String(Math.abs(minutes))}M`;
}

function utcInstant(value: string): Temporal.Instant | undefined {
  const match = UTC_DATE_TIME.exec(value.trim());

  if (match === null) {
    return undefined;
  }

  const [, year, month, day, hour, minute, second] = match;

  try {
    return temporal().Instant.from(
      `${year}-${month}-${day}T${hour}:${minute}:${second}Z`,
    );
  } catch {
    return undefined;
  }
}

/** A `calendar_event_alarms` row, as `list_calendar_events` returns it. */
export function alarmOf(
  value: Readonly<Record<string, unknown>>,
): CalendarAlarm {
  const triggerMinutes = whole(value["triggerMinutes"]);
  const triggerAt = optionalInstant(value["triggerAt"]);
  const repeat = whole(value["repeat"]) ?? 0;
  const repeatMinutes = whole(value["repeatMinutes"]);
  const id = optionalText(value["id"]);
  const description = optionalText(value["description"]);
  const summary = optionalText(value["summary"]);

  return {
    ...(id === undefined ? {} : { id }),
    action: oneOf(value["action"], ACTIONS, "display"),
    ...(triggerMinutes === undefined ? {} : { triggerMinutes }),
    related: value["related"] === "end" ? "end" : "start",
    ...(triggerAt === undefined ? {} : { triggerAt }),
    ...(repeat > 0 && repeatMinutes !== undefined
      ? { repeat, repeatMinutes }
      : {}),
    ...(description === undefined ? {} : { description }),
    ...(summary === undefined ? {} : { summary }),
  };
}

/** An alarm as the jsonb `save_calendar_event` takes in `item.alarms`. */
export function alarmItem(alarm: CalendarAlarm): Record<string, unknown> {
  const item: Record<string, unknown> = { action: alarm.action };

  for (const [key, value] of Object.entries(alarm)) {
    if (value === undefined || key === "id") {
      continue;
    }

    item[key] = key === "triggerAt" ? String(value) : value;
  }

  return item;
}

/**
 * The properties of one `VALARM` as an alarm, or `undefined` for one the
 * calendar block doesn't store: an unknown `ACTION`, a missing or unreadable
 * `TRIGGER`, or a per-user reminder that `toIcs` wrote (`X-BSB-METHOD`).
 */
export function readAlarm(
  lines: readonly ContentLine[],
): CalendarAlarm | undefined {
  let action: CalendarAlarmAction | undefined;
  let trigger: ContentLine | undefined;
  let repeat = 0;
  let repeatMinutes: number | undefined;
  let description: string | undefined;
  let summary: string | undefined;

  for (const line of lines) {
    switch (line.name) {
      case "ACTION": {
        const value = line.value.trim().toLowerCase();
        action = ACTIONS.find((item) => item === value);
        break;
      }

      case "TRIGGER": {
        trigger = line;
        break;
      }

      case "REPEAT": {
        repeat = Math.max(0, Math.trunc(Number(line.value.trim())) || 0);
        break;
      }

      case "DURATION": {
        repeatMinutes = durationMinutes(line.value);
        break;
      }

      case "DESCRIPTION": {
        description = unescapeText(line.value);
        break;
      }

      case "SUMMARY": {
        summary = unescapeText(line.value);
        break;
      }

      case "X-BSB-METHOD": {
        return undefined;
      }

      default: {
        break;
      }
    }
  }

  if (action === undefined || trigger === undefined) {
    return undefined;
  }

  const absolute = trigger.params["VALUE"]?.toUpperCase() === "DATE-TIME";
  const triggerAt = absolute ? utcInstant(trigger.value) : undefined;
  const triggerMinutes = absolute ? undefined : durationMinutes(trigger.value);

  const when =
    triggerAt === undefined
      ? triggerMinutes === undefined
        ? undefined
        : {
            triggerMinutes,
            related:
              trigger.params["RELATED"]?.toUpperCase() === "END"
                ? ("end" as const)
                : ("start" as const),
          }
      : { triggerAt };

  if (when === undefined) {
    return undefined;
  }

  return {
    action,
    ...when,
    ...(repeat > 0 && repeatMinutes !== undefined && repeatMinutes > 0
      ? { repeat, repeatMinutes }
      : {}),
    ...(description === undefined ? {} : { description }),
    ...(summary === undefined ? {} : { summary }),
  };
}

/** The event fields an alarm's export reads. */
export interface AlarmEvent {
  readonly title: string;
  readonly attendees?: readonly { readonly email: string }[];
}

/**
 * One alarm as `VALARM` lines. An email alarm goes to the event's attendees
 * with an address, and the text and subject RFC 5545 requires fall back to the
 * event's title.
 */
export function alarmLines(alarm: CalendarAlarm, event: AlarmEvent): string[] {
  const lines = ["BEGIN:VALARM", `ACTION:${alarm.action.toUpperCase()}`];

  if (alarm.triggerAt === undefined) {
    const related = alarm.related === "end" ? ";RELATED=END" : "";
    lines.push(
      `TRIGGER${related}:${minutesDuration(Math.trunc(alarm.triggerMinutes ?? 0))}`,
    );
  } else {
    lines.push(`TRIGGER;VALUE=DATE-TIME:${utc(alarm.triggerAt)}`);
  }

  if (
    alarm.repeat !== undefined &&
    alarm.repeat > 0 &&
    alarm.repeatMinutes !== undefined
  ) {
    lines.push(
      `REPEAT:${String(Math.trunc(alarm.repeat))}`,
      `DURATION:${minutesDuration(Math.trunc(alarm.repeatMinutes))}`,
    );
  }

  if (alarm.action !== "audio" || alarm.description !== undefined) {
    lines.push(`DESCRIPTION:${escapeText(alarm.description ?? event.title)}`);
  }

  if (alarm.action === "email") {
    lines.push(`SUMMARY:${escapeText(alarm.summary ?? event.title)}`);

    for (const attendee of event.attendees ?? []) {
      if (attendee.email !== "") {
        lines.push(`ATTENDEE:mailto:${attendee.email}`);
      }
    }
  }

  lines.push("END:VALARM");

  return lines;
}
