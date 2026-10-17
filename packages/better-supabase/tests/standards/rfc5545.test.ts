import { describe, expect, it } from "vitest";

import { parseIcs, toIcs } from "../../src/blocks/calendar/ics.ts";
import { expandRule } from "../../src/blocks/reminders/rrule.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

describe("RFC 5545", () => {
  it("pins the recurrence rule version", () => {
    expect(SPEC_PINS.rfc5545).toBe("2009-09");
  });

  it("expands the daily count example", () => {
    const found = expandRule({
      dtstart: Temporal.Instant.from("1997-09-02T09:00:00Z").toZonedDateTimeISO(
        "UTC",
      ),
      rrule: "FREQ=DAILY;COUNT=3",
    });
    expect(found.map((item) => item.toPlainDate().toString())).toEqual([
      "1997-09-02",
      "1997-09-03",
      "1997-09-04",
    ]);
  });

  it("parses the VEVENT example of section 3.6.1", () => {
    const parsed = parseIcs(
      [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//hacksw/handcal//NONSGML v1.0//EN",
        "BEGIN:VEVENT",
        "UID:19970610T172345Z-AF23B2@example.com",
        "DTSTAMP:19970610T172345Z",
        "DTSTART:19970714T170000Z",
        "DTEND:19970715T040000Z",
        "SUMMARY:Bastille Day Party",
        "END:VEVENT",
        "END:VCALENDAR",
      ].join("\r\n"),
    );
    expect(parsed.events).toMatchObject([
      {
        uid: "19970610T172345Z-AF23B2@example.com",
        title: "Bastille Day Party",
        allDay: false,
      },
    ]);
    expect(parsed.events[0]?.startsAt.toString()).toBe("1997-07-14T17:00:00Z");
    expect(parsed.events[0]?.endsAt.toString()).toBe("1997-07-15T04:00:00Z");
  });

  it("unfolds lines (3.1) and unescapes TEXT (3.3.11)", () => {
    const parsed = parseIcs(
      [
        "BEGIN:VCALENDAR",
        "BEGIN:VEVENT",
        "UID:fold@example.com",
        "DTSTART;VALUE=DATE:19970714",
        "SUMMARY:Project XYZ Final Review\\nConference Room - 3B\\, a",
        " nd more",
        "END:VEVENT",
        "END:VCALENDAR",
      ].join("\r\n"),
    );
    expect(parsed.events[0]).toMatchObject({
      title: "Project XYZ Final Review\nConference Room - 3B, and more",
      allDay: true,
    });
  });

  it("writes octet-folded CRLF lines with a VTIMEZONE for each TZID", () => {
    const text = toIcs(
      [
        {
          uid: "zone@example.com",
          title: "é".repeat(60),
          startsAt: Temporal.Instant.from("2026-07-01T08:00:00Z"),
          endsAt: Temporal.Instant.from("2026-07-01T09:00:00Z"),
          allDay: false,
          tz: "America/New_York",
          status: "confirmed",
          exdates: [],
          attendees: [],
        },
      ],
      { now: Temporal.Instant.from("2026-01-01T00:00:00Z") },
    );
    const lines = text.split("\r\n");
    expect(text.endsWith("\r\n")).toBe(true);
    for (const line of lines) {
      expect(new TextEncoder().encode(line).length).toBeLessThanOrEqual(75);
    }
    expect(lines).toContain("BEGIN:VTIMEZONE");
    expect(lines).toContain("TZID:America/New_York");
    expect(lines).toContain("DTSTART;TZID=America/New_York:20260701T040000");
    expect(parseIcs(text).events[0]?.title).toBe("é".repeat(60));
  });
});
