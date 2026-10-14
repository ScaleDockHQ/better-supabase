import { temporal } from "../../core/temporal-required.ts";

/** How an attendee takes part (RFC 5545 `ROLE`), in lowercase. */
export type AttendeeRole =
  | "chair"
  | "required"
  | "optional"
  | "non-participant";

/** An attendee's answer (RFC 5545 `PARTSTAT`), in lowercase. */
export type AttendeeResponse =
  | "needs-action"
  | "accepted"
  | "declined"
  | "tentative";

export type CalendarEventStatus = "confirmed" | "tentative" | "cancelled";

export interface CalendarAttendee {
  readonly email: string;
  readonly name?: string;
  readonly userId?: string;
  readonly role: AttendeeRole;
  readonly response: AttendeeResponse;
}

/** One `VEVENT`, ready for `importIcs` or `save`. */
export interface IcsEvent {
  readonly uid: string;
  readonly title: string;
  readonly description?: string;
  readonly location?: string;
  readonly startsAt: Temporal.Instant;
  /** Exclusive, as in `DTEND`. */
  readonly endsAt: Temporal.Instant;
  readonly allDay: boolean;
  /** The IANA zone the event's wall-clock times and recurrence follow. */
  readonly tz: string;
  readonly status: CalendarEventStatus;
  readonly rrule?: string;
  readonly exdates: readonly Temporal.Instant[];
  /** `RECURRENCE-ID`: the occurrence of the series this event overrides. */
  readonly originalStart?: Temporal.Instant;
  readonly attendees: readonly CalendarAttendee[];
}

export interface ParsedIcs {
  /** `X-WR-CALNAME`, when the file has one. */
  readonly name?: string;
  /** `X-WR-TIMEZONE`, else `UTC`: the zone of floating and all-day times. */
  readonly tz: string;
  readonly events: readonly IcsEvent[];
  /** `VEVENT`s without a `UID` or `DTSTART`, which are left out. */
  readonly skipped: number;
}

interface ContentLine {
  readonly name: string;
  readonly params: Readonly<Record<string, string>>;
  readonly value: string;
}

const ROLES: Readonly<Record<string, AttendeeRole>> = {
  CHAIR: "chair",
  "REQ-PARTICIPANT": "required",
  "OPT-PARTICIPANT": "optional",
  "NON-PARTICIPANT": "non-participant",
};

const RESPONSES: Readonly<Record<string, AttendeeResponse>> = {
  "NEEDS-ACTION": "needs-action",
  ACCEPTED: "accepted",
  DECLINED: "declined",
  TENTATIVE: "tentative",
};

const STATUSES: readonly CalendarEventStatus[] = [
  "confirmed",
  "tentative",
  "cancelled",
];

const DATE = /^(\d{4})(\d{2})(\d{2})$/;
const DATE_TIME = /^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)$/;

/** Splits a content line at the first `:` and its `;` that are outside quotes. */
function contentLine(line: string): ContentLine | undefined {
  const parts: string[] = [];
  let quoted = false;
  let start = 0;
  for (let index = 0; index < line.length; index += 1) {
    const char = line[index];
    if (char === '"') quoted = !quoted;
    else if (!quoted && char === ";") {
      parts.push(line.slice(start, index));
      start = index + 1;
    } else if (!quoted && char === ":") {
      parts.push(line.slice(start, index));
      const [name = "", ...rest] = parts;
      const params: Record<string, string> = {};
      for (const param of rest) {
        const equals = param.indexOf("=");
        if (equals < 1) continue;
        params[param.slice(0, equals).toUpperCase()] = param
          .slice(equals + 1)
          .replaceAll('"', "");
      }
      return { name: name.toUpperCase(), params, value: line.slice(index + 1) };
    }
  }
  return undefined;
}

/** RFC 5545 TEXT: `\n`, `\,`, `\;` and `\\`. */
function unescapeText(value: string): string {
  return value.replaceAll(/\\([nN,;\\])/g, (_, char: string) =>
    char === "n" || char === "N" ? "\n" : char,
  );
}

function escapeText(value: string): string {
  return value
    .replaceAll("\\", "\\\\")
    .replaceAll(";", "\\;")
    .replaceAll(",", "\\,")
    .replaceAll(/\r?\n/g, "\\n");
}

function zoneOr(zone: string | undefined, fallback: string): string {
  if (zone === undefined) return fallback;
  try {
    temporal().Now.zonedDateTimeISO(zone);
    return zone;
  } catch {
    return fallback;
  }
}

interface DateValue {
  readonly instant: Temporal.Instant;
  readonly allDay: boolean;
  readonly tz: string;
}

function dateValue(
  value: string,
  params: Readonly<Record<string, string>>,
  fallback: string,
): DateValue | undefined {
  const time = temporal();
  const tz = zoneOr(params["TZID"], fallback);
  const date = DATE.exec(value);
  if (date !== null || params["VALUE"] === "DATE") {
    if (date === null) return undefined;
    const plain = time.PlainDate.from({
      year: Number(date[1]),
      month: Number(date[2]),
      day: Number(date[3]),
    });
    return {
      instant: plain.toZonedDateTime({ timeZone: tz }).toInstant(),
      allDay: true,
      tz,
    };
  }
  const match = DATE_TIME.exec(value);
  if (match === null) return undefined;
  const fields = {
    year: Number(match[1]),
    month: Number(match[2]),
    day: Number(match[3]),
    hour: Number(match[4]),
    minute: Number(match[5]),
    second: Number(match[6]),
  };
  if (match[7] === "Z") {
    return {
      instant: time.ZonedDateTime.from({
        ...fields,
        timeZone: "UTC",
      }).toInstant(),
      allDay: false,
      tz,
    };
  }
  return {
    instant: time.ZonedDateTime.from({ ...fields, timeZone: tz }).toInstant(),
    allDay: false,
    tz,
  };
}

function attendeeOf(line: ContentLine): CalendarAttendee | undefined {
  const email = line.value
    .replace(/^mailto:/i, "")
    .trim()
    .toLowerCase();
  if (email === "") return undefined;
  const name = line.params["CN"];
  return {
    email,
    ...(name === undefined ? {} : { name }),
    role: ROLES[(line.params["ROLE"] ?? "").toUpperCase()] ?? "required",
    response:
      RESPONSES[(line.params["PARTSTAT"] ?? "").toUpperCase()] ??
      "needs-action",
  };
}

/** One `VEVENT`'s lines as an event, or `undefined` without UID or DTSTART. */
function eventOf(
  lines: readonly ContentLine[],
  fallback: string,
): IcsEvent | undefined {
  const time = temporal();
  let uid: string | undefined;
  let start: DateValue | undefined;
  let end: DateValue | undefined;
  let duration: Temporal.Duration | undefined;
  let title = "";
  let description: string | undefined;
  let location: string | undefined;
  let status: CalendarEventStatus = "confirmed";
  let rrule: string | undefined;
  let originalStart: Temporal.Instant | undefined;
  const exdates: Temporal.Instant[] = [];
  const attendees: CalendarAttendee[] = [];
  for (const line of lines) {
    switch (line.name) {
      case "UID":
        uid = line.value.trim();
        break;
      case "DTSTART":
        start = dateValue(line.value, line.params, fallback);
        break;
      case "DTEND":
        end = dateValue(line.value, line.params, fallback);
        break;
      case "DURATION":
        try {
          duration = time.Duration.from(line.value.trim());
        } catch {
          duration = undefined;
        }
        break;
      case "SUMMARY":
        title = unescapeText(line.value);
        break;
      case "DESCRIPTION":
        description = unescapeText(line.value);
        break;
      case "LOCATION":
        location = unescapeText(line.value);
        break;
      case "STATUS": {
        const value = line.value.trim().toLowerCase();
        status = STATUSES.find((item) => item === value) ?? "confirmed";
        break;
      }
      case "RRULE":
        rrule = line.value.trim();
        break;
      case "EXDATE":
        for (const value of line.value.split(",")) {
          const date = dateValue(value.trim(), line.params, fallback);
          if (date !== undefined) exdates.push(date.instant);
        }
        break;
      case "RECURRENCE-ID":
        originalStart = dateValue(line.value, line.params, fallback)?.instant;
        break;
      case "ATTENDEE": {
        const attendee = attendeeOf(line);
        if (attendee !== undefined) attendees.push(attendee);
        break;
      }
      default:
        break;
    }
  }
  if (uid === undefined || uid === "" || start === undefined) return undefined;
  const zoned = start.instant.toZonedDateTimeISO(start.tz);
  const endsAt =
    end?.instant ??
    (duration === undefined
      ? start.allDay
        ? zoned.add({ days: 1 }).toInstant()
        : start.instant
      : zoned.add(duration).toInstant());
  return {
    uid,
    title,
    ...(description === undefined ? {} : { description }),
    ...(location === undefined ? {} : { location }),
    startsAt: start.instant,
    endsAt,
    allDay: start.allDay,
    tz: start.tz,
    status,
    ...(rrule === undefined ? {} : { rrule }),
    exdates,
    ...(originalStart === undefined ? {} : { originalStart }),
    attendees,
  };
}

/**
 * Reads an iCalendar file (RFC 5545): unfolds lines, unescapes TEXT values
 * and reads each `VEVENT`'s times, recurrence (`RRULE`, `EXDATE`,
 * `RECURRENCE-ID`) and attendees. Times in a zone Temporal does not know,
 * floating times and dates use `X-WR-TIMEZONE`, else UTC.
 */
export function parseIcs(text: string): ParsedIcs {
  const lines = text
    .replaceAll(/\r?\n[ \t]/g, "")
    .split(/\r?\n/)
    .flatMap((raw) => {
      const line = contentLine(raw);
      return line === undefined ? [] : [line];
    });
  let name: string | undefined;
  let tz = "UTC";
  for (const line of lines) {
    if (line.name === "X-WR-CALNAME") name = unescapeText(line.value);
    if (line.name === "X-WR-TIMEZONE") tz = zoneOr(line.value.trim(), "UTC");
  }
  const events: IcsEvent[] = [];
  let skipped = 0;
  let current: ContentLine[] | undefined;
  let depth = 0;
  for (const line of lines) {
    if (line.name === "BEGIN" && line.value.toUpperCase() === "VEVENT") {
      current = [];
      depth = 0;
    } else if (current !== undefined && line.name === "BEGIN") {
      depth += 1;
    } else if (current !== undefined && line.name === "END") {
      if (depth > 0) depth -= 1;
      else if (line.value.toUpperCase() === "VEVENT") {
        const event = eventOf(current, tz);
        if (event === undefined) skipped += 1;
        else events.push(event);
        current = undefined;
      }
    } else if (current !== undefined && depth === 0) {
      current.push(line);
    }
  }
  return { ...(name === undefined ? {} : { name }), tz, events, skipped };
}

/** The event fields `toIcs` writes. `CalendarEvent` has all of them. */
export interface IcsSource {
  readonly uid: string;
  readonly title: string;
  readonly description?: string;
  readonly location?: string;
  readonly startsAt: Temporal.Instant;
  readonly endsAt: Temporal.Instant;
  readonly allDay: boolean;
  readonly tz: string;
  readonly status: CalendarEventStatus;
  readonly rrule?: string;
  readonly exdates: readonly Temporal.Instant[];
  readonly originalStart?: Temporal.Instant;
  readonly attendees?: readonly CalendarAttendee[];
  readonly updatedAt?: Temporal.Instant;
}

export interface ToIcsOptions {
  readonly name?: string;
  /** `X-WR-TIMEZONE`. */
  readonly tz?: string;
  readonly prodId?: string;
  /** `DTSTAMP` for events without `updatedAt`. Default now. */
  readonly now?: Temporal.Instant;
}

const pad = (value: number, size = 2): string =>
  String(value).padStart(size, "0");

function compact(
  zoned: Temporal.ZonedDateTime | Temporal.PlainDateTime,
): string {
  return `${pad(zoned.year, 4)}${pad(zoned.month)}${pad(zoned.day)}T${pad(zoned.hour)}${pad(zoned.minute)}${pad(zoned.second)}`;
}

function utc(instant: Temporal.Instant): string {
  return `${compact(instant.toZonedDateTimeISO("UTC"))}Z`;
}

function day(instant: Temporal.Instant, tz: string): string {
  const date = instant.toZonedDateTimeISO(tz);
  return `${pad(date.year, 4)}${pad(date.month)}${pad(date.day)}`;
}

/** A property whose value is a date or date-time in the event's zone. */
function timeProperty(
  name: string,
  instant: Temporal.Instant,
  event: IcsSource,
): string {
  if (event.allDay) return `${name};VALUE=DATE:${day(instant, event.tz)}`;
  if (event.tz === "UTC") return `${name}:${utc(instant)}`;
  return `${name};TZID=${event.tz}:${compact(instant.toZonedDateTimeISO(event.tz))}`;
}

function offset(nanoseconds: number): string {
  const minutes = Math.round(nanoseconds / 60e9);
  const sign = minutes < 0 ? "-" : "+";
  const abs = Math.abs(minutes);
  return `${sign}${pad(Math.floor(abs / 60))}${pad(abs % 60)}`;
}

/**
 * A `VTIMEZONE` with one observance per transition between `from` and
 * `until`, from Temporal's zone data, so `TZID` references resolve
 * without an external database.
 */
function vtimezone(
  tz: string,
  from: Temporal.Instant,
  until: Temporal.Instant,
): string[] {
  let zoned = from.toZonedDateTimeISO(tz);
  const lines = [
    "BEGIN:VTIMEZONE",
    `TZID:${tz}`,
    "BEGIN:STANDARD",
    `DTSTART:${compact(zoned.toPlainDateTime())}`,
    `TZOFFSETFROM:${offset(zoned.offsetNanoseconds)}`,
    `TZOFFSETTO:${offset(zoned.offsetNanoseconds)}`,
    "END:STANDARD",
  ];
  for (let count = 0; count < 80; count += 1) {
    const next = zoned.getTimeZoneTransition("next");
    if (
      next === null ||
      temporal().Instant.compare(next.toInstant(), until) > 0
    ) {
      break;
    }
    const before = zoned.offsetNanoseconds;
    const after = next.offsetNanoseconds;
    const kind = after > before ? "DAYLIGHT" : "STANDARD";
    const onset = next
      .toInstant()
      .toZonedDateTimeISO("UTC")
      .add({ nanoseconds: before })
      .toPlainDateTime();
    lines.push(
      `BEGIN:${kind}`,
      `DTSTART:${compact(onset)}`,
      `TZOFFSETFROM:${offset(before)}`,
      `TZOFFSETTO:${offset(after)}`,
      `END:${kind}`,
    );
    zoned = next;
  }
  lines.push("END:VTIMEZONE");
  return lines;
}

/** Folds a content line to 75 octets, never inside a UTF-8 sequence. */
function fold(line: string): string {
  const encoder = new TextEncoder();
  if (encoder.encode(line).length <= 75) return line;
  const parts: string[] = [];
  let current = "";
  let size = 0;
  for (const char of line) {
    const bytes = encoder.encode(char).length;
    const limit = parts.length === 0 ? 75 : 74;
    if (size + bytes > limit) {
      parts.push(current);
      current = "";
      size = 0;
    }
    current += char;
    size += bytes;
  }
  parts.push(current);
  return parts.join("\r\n ");
}

const ROLE_OUT: Readonly<Record<AttendeeRole, string>> = {
  chair: "CHAIR",
  required: "REQ-PARTICIPANT",
  optional: "OPT-PARTICIPANT",
  "non-participant": "NON-PARTICIPANT",
};

function paramValue(value: string): string {
  const clean = value.replaceAll('"', "");
  return /[:;,]/.test(clean) ? `"${clean}"` : clean;
}

function eventLines(event: IcsSource, stamp: Temporal.Instant): string[] {
  const lines = [
    "BEGIN:VEVENT",
    `UID:${event.uid}`,
    `DTSTAMP:${utc(event.updatedAt ?? stamp)}`,
    timeProperty("DTSTART", event.startsAt, event),
    timeProperty("DTEND", event.endsAt, event),
  ];
  if (event.originalStart !== undefined) {
    lines.push(timeProperty("RECURRENCE-ID", event.originalStart, event));
  }
  if (event.rrule !== undefined) lines.push(`RRULE:${event.rrule}`);
  for (const exdate of event.exdates) {
    lines.push(timeProperty("EXDATE", exdate, event));
  }
  lines.push(`SUMMARY:${escapeText(event.title)}`);
  if (event.description !== undefined) {
    lines.push(`DESCRIPTION:${escapeText(event.description)}`);
  }
  if (event.location !== undefined) {
    lines.push(`LOCATION:${escapeText(event.location)}`);
  }
  lines.push(`STATUS:${event.status.toUpperCase()}`);
  for (const attendee of event.attendees ?? []) {
    const cn =
      attendee.name === undefined ? "" : `;CN=${paramValue(attendee.name)}`;
    lines.push(
      `ATTENDEE${cn};ROLE=${ROLE_OUT[attendee.role]};PARTSTAT=${attendee.response.toUpperCase()}:mailto:${attendee.email}`,
    );
  }
  lines.push("END:VEVENT");
  return lines;
}

/**
 * Writes events as an iCalendar file (RFC 5545): CRLF line ends, lines
 * folded at 75 octets, escaped TEXT, and a `VTIMEZONE` for every zone a
 * timed event uses, so recurrence keeps its wall-clock time across DST.
 */
export function toIcs(
  events: readonly IcsSource[],
  options: ToIcsOptions = {},
): string {
  const time = temporal();
  const stamp = options.now ?? time.Now.instant();
  const zones = new Map<
    string,
    { from: Temporal.Instant; until: Temporal.Instant }
  >();
  for (const event of events) {
    if (event.allDay || event.tz === "UTC") continue;
    const from = event.startsAt.subtract({ hours: 24 });
    const until =
      event.rrule === undefined
        ? event.endsAt.add({ hours: 24 })
        : event.startsAt.add({ hours: 24 * 366 * 3 });
    const known = zones.get(event.tz);
    zones.set(event.tz, {
      from:
        known === undefined || time.Instant.compare(from, known.from) < 0
          ? from
          : known.from,
      until:
        known === undefined || time.Instant.compare(until, known.until) > 0
          ? until
          : known.until,
    });
  }
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    `PRODID:${options.prodId ?? "-//better-supabase//calendar//EN"}`,
    "CALSCALE:GREGORIAN",
  ];
  if (options.name !== undefined) {
    lines.push(`X-WR-CALNAME:${escapeText(options.name)}`);
  }
  if (options.tz !== undefined) lines.push(`X-WR-TIMEZONE:${options.tz}`);
  for (const [tz, range] of zones) {
    lines.push(...vtimezone(tz, range.from, range.until));
  }
  for (const event of events) lines.push(...eventLines(event, stamp));
  lines.push("END:VCALENDAR");
  return `${lines.map(fold).join("\r\n")}\r\n`;
}
