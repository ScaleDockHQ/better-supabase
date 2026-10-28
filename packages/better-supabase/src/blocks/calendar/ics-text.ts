/** One unfolded iCalendar content line. */
export interface ContentLine {
  readonly name: string;
  readonly params: Readonly<Record<string, string>>;
  readonly value: string;
}

/** RFC 5545 TEXT: `\n`, `\,`, `\;` and `\\`. */
export function unescapeText(value: string): string {
  return value.replaceAll(/\\([nN,;\\])/g, (_, char: string) =>
    char === "n" || char === "N" ? "\n" : char,
  );
}

export function escapeText(value: string): string {
  return value
    .replaceAll("\\", "\\\\")
    .replaceAll(";", "\\;")
    .replaceAll(",", "\\,")
    .replaceAll(/\r?\n/g, "\\n");
}

export const pad = (value: number, size = 2): string =>
  String(value).padStart(size, "0");

export function compact(
  zoned: Temporal.ZonedDateTime | Temporal.PlainDateTime,
): string {
  return `${pad(zoned.year, 4)}${pad(zoned.month)}${pad(zoned.day)}T${pad(zoned.hour)}${pad(zoned.minute)}${pad(zoned.second)}`;
}

export function utc(instant: Temporal.Instant): string {
  return `${compact(instant.toZonedDateTimeISO("UTC"))}Z`;
}
