import { assertCron, nextCronRun } from "../../core/cron.ts";
import { isRecord } from "../../core/guards.ts";
import { temporal } from "../../core/temporal-required.ts";

/** The `ce-type` of a Vercel Schedules run on a function or path target. */
export const VERCEL_SCHEDULE_EVENT_TYPE = "com.vercel.schedule.v1beta";

/**
 * What a Vercel schedule with a queue target publishes on its topic for each
 * run, as `ScheduleQueueMessage` in `@vercel/schedules` types it.
 */
export interface VercelScheduleQueueMessage<P = unknown> {
  readonly scheduleId: string;
  /** The same for every delivery of one run. */
  readonly executionId: string;
  readonly name: string;
  readonly namespace: string;
  /** ISO 8601 time the expression matched, without jitter. */
  readonly scheduledAt: string;
  readonly expression: string;
  readonly source: "static" | "dynamic";
  /** Omitted for a static schedule and a dynamic one without a payload. */
  readonly payload?: P;
}

/** One run of a Vercel schedule, read from a request or a queue message. */
export interface VercelScheduleRun {
  readonly executionId: string;
  readonly scheduleId: string;
  readonly name: string;
  readonly namespace: string;
  /** When the expression matched; the run can arrive later, within the jitter. */
  readonly scheduledAt: Temporal.Instant;
  readonly source: "static" | "dynamic";
  /** The cron expression, or the local datetime of a one-time schedule. */
  readonly expression: string;
}

const MACROS: Readonly<Record<string, string>> = {
  "@yearly": "0 0 1 1 *",
  "@annually": "0 0 1 1 *",
  "@monthly": "0 0 1 * *",
  "@weekly": "0 0 * * 0",
  "@daily": "0 0 * * *",
  "@midnight": "0 0 * * *",
  "@hourly": "0 * * * *",
};

const MONTHS = [
  "jan",
  "feb",
  "mar",
  "apr",
  "may",
  "jun",
  "jul",
  "aug",
  "sep",
  "oct",
  "nov",
  "dec",
];

const WEEKDAYS = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"];

const INTERVAL = /^\d+\s+(?:second|minute|hour)s?$/i;

function numbered(
  text: string,
  names: readonly string[],
  first: number,
): string {
  return text.replaceAll(/[a-z]{3}/gi, (name) => {
    const index = names.indexOf(name.toLowerCase());

    return index === -1 ? name : String(index + first);
  });
}

/** Expands a day-of-week field that names 7 (Sunday) into a list of 0 to 6. */
function weekdaysOf(field: string): string {
  if (!/(?:^|[^\d])7(?:$|[^\d])/.test(field)) {
    return field;
  }

  const days = new Set<number>();

  for (const part of field.split(",")) {
    const [range = "", stepText] = part.split("/");
    const step = stepText === undefined ? 1 : Number(stepText);
    const [start = "", end] = range === "*" ? ["0", "7"] : range.split("-");
    const from = Number(start);

    const to =
      end === undefined ? (stepText === undefined ? from : 7) : Number(end);

    for (let day = from; day <= to; day += step) {
      days.add(day % 7);
    }
  }

  return [...days].toSorted((a, b) => a - b).join(",");
}

/**
 * The five-field cron Vercel Schedules accepts for `cron`: macros such as
 * `@daily` expand, named months and days (`JAN`, `MON`) become numbers, and a
 * Sunday written as 7 becomes 0. Throws a `TypeError` that names the rule for
 * an interval such as `30 seconds` and for a cron that restricts both the day
 * of month and the day of week, which Vercel rejects.
 */
export function vercelCronOf(cron: string): string {
  const trimmed = cron.trim();

  if (INTERVAL.test(trimmed)) {
    throw new TypeError(
      `Vercel Schedules takes five cron fields, not the interval "${cron}": write it as a cron such as "*/5 * * * *", or use the drain scheduler`,
    );
  }

  assertCron(trimmed);

  const source = MACROS[trimmed.toLowerCase()] ?? trimmed;

  const [minute = "", hour = "", day = "", month = "", weekday = ""] =
    source.split(/\s+/);

  if (day !== "*" && weekday !== "*") {
    throw new TypeError(
      `Vercel Schedules rejects a cron that restricts both the day of month and the day of week ("${cron}"): split it into two schedules`,
    );
  }

  return [
    minute,
    hour,
    day,
    numbered(month, MONTHS, 1),
    weekdaysOf(numbered(weekday, WEEKDAYS, 0)),
  ].join(" ");
}

/**
 * The shortest gap in minutes between two runs of `cron` within a week, or
 * `undefined` when it is at least `floor`.
 */
export function cronGapBelow(cron: string, floor: number): number | undefined {
  const instant = temporal().Instant;
  const start = instant.from("2026-01-05T00:00:00Z");
  const end = start.add({ hours: 24 * 8 });
  let previous = nextCronRun(cron, "UTC", start);

  for (let count = 0; count < 2000; count += 1) {
    const next = nextCronRun(cron, "UTC", previous);

    if (instant.compare(next, end) > 0) {
      return undefined;
    }

    const gap = (next.epochMilliseconds - previous.epochMilliseconds) / 60_000;

    if (gap < floor) {
      return gap;
    }

    previous = next;
  }

  return undefined;
}

const MAX_NAME = 256;
const LITERAL = /^[A-Za-z0-9.-]$/;
const ALNUM = /^[A-Za-z1-9]$/;
const ESCAPE = /^[0-9a-f]{2}$/;

const hex = (byte: number): string => byte.toString(16).padStart(2, "0");

const escaped = (char: string): string =>
  Array.from(new TextEncoder().encode(char), (byte) => `_${hex(byte)}`).join(
    "",
  );

/**
 * The reversible encoding: `[A-Za-z0-9.-]` stay, every other UTF-8 byte
 * (including `_`) becomes `_hh`. A first character that isn't a letter or 1 to
 * 9 is escaped behind a `0`, so the result starts with a letter or digit.
 */
function encoded(text: string): string {
  let first = "";
  let rest = "";

  for (const char of text) {
    if (first === "") {
      first = char;
    } else {
      rest += LITERAL.test(char) ? char : escaped(char);
    }
  }

  return ALNUM.test(first) ? `${first}${rest}` : `0${escaped(first)}${rest}`;
}

async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(text),
  );

  return Array.from(new Uint8Array(digest), hex).join("");
}

async function vercelNameOf(text: string, what: string): Promise<string> {
  if (text.length === 0) {
    throw new TypeError(`A Vercel ${what} can't be empty`);
  }

  const name = encoded(text);

  // `_x` never appears in an encoding, so a hashed name can't be decoded.
  return name.length <= MAX_NAME ? name : `h_x${await sha256Hex(text)}`;
}

/**
 * The Vercel schedule name for a queue schedule name such as `block:sla.check`.
 * Vercel takes 1 to 256 of `[A-Za-z0-9._-]`, starting with a letter or digit,
 * so other characters are escaped (`block_3asla.check`) and a name whose
 * encoding is longer than 256 characters becomes a SHA-256 hash.
 * `vercelScheduleNameFrom` reverses it.
 */
export function vercelScheduleNameOf(name: string): Promise<string> {
  return vercelNameOf(name, "schedule name");
}

/**
 * The Vercel namespace that holds a tenant's schedules, in the encoding of
 * `vercelScheduleNameOf`: a tenant id such as a UUID stays as it is.
 */
export function vercelNamespaceOf(tenant: string): Promise<string> {
  return vercelNameOf(tenant, "namespace");
}

/**
 * The queue schedule name behind a Vercel schedule name, or `null` for a hashed
 * name or one `vercelScheduleNameOf` didn't write.
 */
export function vercelScheduleNameFrom(name: string): string | null {
  const text = name.startsWith("0") ? name.slice(1) : name;
  const bytes: number[] = [];

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index]!;

    if (char !== "_") {
      bytes.push(char.codePointAt(0) ?? 0);
      continue;
    }

    const code = text.slice(index + 1, index + 3);

    if (!ESCAPE.test(code)) {
      return null;
    }

    bytes.push(Number.parseInt(code, 16));
    index += 2;
  }

  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(
      new Uint8Array(bytes),
    );
  } catch {
    return null;
  }
}

const SOURCES = new Set(["static", "dynamic"]);

const instantOf = (text: string): Temporal.Instant | undefined => {
  try {
    return temporal().Instant.from(text);
  } catch {
    return undefined;
  }
};

/**
 * The run a Vercel schedule delivered to a function or path target, read from
 * its `ce-*` headers, or `null` when the request isn't a schedule run.
 */
export function parseVercelScheduleRun(
  request: Request,
): VercelScheduleRun | null {
  const header = (name: string): string | null => request.headers.get(name);

  if (header("ce-type") !== VERCEL_SCHEDULE_EVENT_TYPE) {
    return null;
  }

  const executionId = header("ce-id");
  const scheduleId = header("ce-vssscheduleid");
  const name = header("ce-vssschedulename");
  const namespace = header("ce-vssnamespace");
  const scheduledAt = instantOf(header("ce-vssscheduledat") ?? "");
  const source = header("ce-vssschedulesource");
  const expression = header("ce-vssexpression");

  if (
    !executionId ||
    !scheduleId ||
    !name ||
    !namespace ||
    scheduledAt === undefined ||
    source === null ||
    !SOURCES.has(source) ||
    expression === null
  ) {
    return null;
  }

  return {
    executionId,
    scheduleId,
    name,
    namespace,
    scheduledAt,
    // SAFETY: SOURCES holds exactly "static" and "dynamic".
    source: source as VercelScheduleRun["source"],
    expression,
  };
}

/** Whether a queue message is the run a Vercel schedule published. */
export function isVercelScheduleMessage(
  body: unknown,
): body is VercelScheduleQueueMessage {
  return (
    isRecord(body) &&
    typeof body["scheduleId"] === "string" &&
    typeof body["executionId"] === "string" &&
    typeof body["name"] === "string" &&
    typeof body["namespace"] === "string" &&
    typeof body["scheduledAt"] === "string" &&
    typeof body["expression"] === "string" &&
    typeof body["source"] === "string" &&
    SOURCES.has(body["source"])
  );
}

/** The run a schedule message describes, or `null` for an invalid time. */
export function vercelScheduleRunOf(
  message: VercelScheduleQueueMessage,
): VercelScheduleRun | null {
  const scheduledAt = instantOf(message.scheduledAt);

  return scheduledAt === undefined
    ? null
    : {
        executionId: message.executionId,
        scheduleId: message.scheduleId,
        name: message.name,
        namespace: message.namespace,
        scheduledAt,
        source: message.source,
        expression: message.expression,
      };
}
