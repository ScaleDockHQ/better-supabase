import { describe, expect, it } from "vitest";

import type { IcsSource } from "../../../src/blocks/calendar/ics.ts";

import { parseIcs, toIcs } from "../../../src/blocks/calendar/ics.ts";

const at = (text: string): Temporal.Instant => Temporal.Instant.from(text);

const FILE = [
  "BEGIN:VCALENDAR",
  "VERSION:2.0",
  "PRODID:-//Example//EN",
  "X-WR-CALNAME:Team",
  "X-WR-TIMEZONE:Europe/Amsterdam",
  "BEGIN:VTIMEZONE",
  "TZID:Europe/Amsterdam",
  "BEGIN:STANDARD",
  "DTSTART:19701025T030000",
  "TZOFFSETFROM:+0200",
  "TZOFFSETTO:+0100",
  "END:STANDARD",
  "END:VTIMEZONE",
  "BEGIN:VEVENT",
  "UID:standup@example.test",
  "DTSTAMP:20260101T000000Z",
  "DTSTART;TZID=Europe/Amsterdam:20260302T090000",
  "DTEND;TZID=Europe/Amsterdam:20260302T091500",
  "RRULE:FREQ=WEEKLY;BYDAY=MO,WE",
  "EXDATE;TZID=Europe/Amsterdam:20260304T090000,20260309T090000",
  "SUMMARY:Stand-up\\, daily",
  "DESCRIPTION:Line one\\nLine two with a long text that needs folding becau",
  " se it is longer than seventy-five octets",
  'ATTENDEE;CN="Doe, Jane";ROLE=CHAIR;PARTSTAT=ACCEPTED:mailto:Jane@Example.test',
  "ATTENDEE;PARTSTAT=TENTATIVE:mailto:bob@example.test",
  "BEGIN:VALARM",
  "ACTION:DISPLAY",
  "DESCRIPTION:Not the event",
  "END:VALARM",
  "END:VEVENT",
  "BEGIN:VEVENT",
  "UID:standup@example.test",
  "RECURRENCE-ID;TZID=Europe/Amsterdam:20260311T090000",
  "DTSTART;TZID=Europe/Amsterdam:20260311T100000",
  "DURATION:PT30M",
  "SUMMARY:Stand-up (moved)",
  "END:VEVENT",
  "BEGIN:VEVENT",
  "UID:holiday@example.test",
  "DTSTART;VALUE=DATE:20260427",
  "SUMMARY:King's Day",
  "STATUS:TENTATIVE",
  "END:VEVENT",
  "BEGIN:VEVENT",
  "SUMMARY:No uid",
  "DTSTART:20260101T000000Z",
  "END:VEVENT",
  "END:VCALENDAR",
  "",
].join("\r\n");

describe("parseIcs", () => {
  const parsed = parseIcs(FILE);

  it("reads the calendar name and zone, and skips events without a UID", () => {
    expect(parsed.name).toBe("Team");
    expect(parsed.tz).toBe("Europe/Amsterdam");
    expect(parsed.events).toHaveLength(3);
    expect(parsed.skipped).toBe(1);
  });

  it("reads a recurring event in its zone with EXDATEs and attendees", () => {
    const [series] = parsed.events;
    expect(series).toMatchObject({
      uid: "standup@example.test",
      title: "Stand-up, daily",
      tz: "Europe/Amsterdam",
      allDay: false,
      rrule: "FREQ=WEEKLY;BYDAY=MO,WE",
      status: "confirmed",
    });
    expect(series?.description).toBe(
      "Line one\nLine two with a long text that needs folding because it is longer than seventy-five octets",
    );
    expect(series?.startsAt.toString()).toBe("2026-03-02T08:00:00Z");
    expect(series?.endsAt.toString()).toBe("2026-03-02T08:15:00Z");
    expect(series?.exdates.map(String)).toEqual([
      "2026-03-04T08:00:00Z",
      "2026-03-09T08:00:00Z",
    ]);
    expect(series?.attendees).toEqual([
      {
        email: "jane@example.test",
        name: "Doe, Jane",
        role: "chair",
        response: "accepted",
      },
      { email: "bob@example.test", role: "required", response: "tentative" },
    ]);
  });

  it("reads an override's RECURRENCE-ID and DURATION", () => {
    const override = parsed.events[1];
    expect(override?.originalStart?.toString()).toBe("2026-03-11T08:00:00Z");
    expect(override?.startsAt.toString()).toBe("2026-03-11T09:00:00Z");
    expect(override?.endsAt.toString()).toBe("2026-03-11T09:30:00Z");
  });

  it("reads an all-day date in the calendar zone and ends it a day later", () => {
    const holiday = parsed.events[2];
    expect(holiday).toMatchObject({ allDay: true, status: "tentative" });
    expect(holiday?.startsAt.toString()).toBe("2026-04-26T22:00:00Z");
    expect(holiday?.endsAt.toString()).toBe("2026-04-27T22:00:00Z");
  });

  it("falls back to the calendar zone for an unknown TZID", () => {
    const { events } = parseIcs(
      [
        "BEGIN:VCALENDAR",
        "BEGIN:VEVENT",
        "UID:x",
        "DTSTART;TZID=W. Europe Standard Time:20260601T120000",
        "END:VEVENT",
        "END:VCALENDAR",
      ].join("\n"),
    );
    expect(events[0]?.tz).toBe("UTC");
    expect(events[0]?.startsAt.toString()).toBe("2026-06-01T12:00:00Z");
    expect(events[0]?.endsAt.toString()).toBe("2026-06-01T12:00:00Z");
  });
});

describe("toIcs", () => {
  const event: IcsSource = {
    uid: "standup@example.test",
    title: "Stand-up; with, commas",
    description:
      "Ünïcödé text that is long enough to need folding at seventy-five octets",
    startsAt: at("2026-03-02T08:00:00Z"),
    endsAt: at("2026-03-02T08:15:00Z"),
    allDay: false,
    tz: "Europe/Amsterdam",
    status: "confirmed",
    rrule: "FREQ=WEEKLY;BYDAY=MO",
    exdates: [at("2026-03-09T08:00:00Z")],
    attendees: [
      {
        email: "jane@example.test",
        name: "Doe, Jane",
        role: "chair",
        response: "accepted",
      },
    ],
  };
  const text = toIcs([event], {
    name: "Team",
    tz: "Europe/Amsterdam",
    now: at("2026-01-01T00:00:00Z"),
  });
  const lines = text.split("\r\n");

  it("ends every line with CRLF and folds at 75 octets", () => {
    expect(text.endsWith("END:VCALENDAR\r\n")).toBe(true);
    expect(text.replaceAll("\r\n", "")).not.toContain("\n");
    const encoder = new TextEncoder();
    for (const line of lines) {
      expect(encoder.encode(line).length).toBeLessThanOrEqual(75);
    }
  });

  it("writes times in the event zone with a VTIMEZONE that has its DST rules", () => {
    expect(lines).toContain("DTSTART;TZID=Europe/Amsterdam:20260302T090000");
    expect(lines).toContain("EXDATE;TZID=Europe/Amsterdam:20260309T090000");
    expect(lines).toContain("TZID:Europe/Amsterdam");
    expect(lines).toContain("BEGIN:DAYLIGHT");
    expect(lines).toContain("DTSTART:20260329T020000");
    expect(lines).toContain("TZOFFSETTO:+0200");
    expect(lines).toContain("DTSTAMP:20260101T000000Z");
  });

  it("escapes TEXT and quotes parameter values", () => {
    expect(lines).toContain("SUMMARY:Stand-up\\; with\\, commas");
    expect(text).toContain(
      'ATTENDEE;CN="Doe, Jane";ROLE=CHAIR;PARTSTAT=ACCEPTED:mailto:jane@example',
    );
  });

  it("round-trips through parseIcs", () => {
    const [back] = parseIcs(text).events;
    expect(back).toMatchObject({
      uid: event.uid,
      title: event.title,
      description: event.description,
      tz: event.tz,
      rrule: event.rrule,
      status: "confirmed",
    });
    expect(back?.startsAt.equals(event.startsAt)).toBe(true);
    expect(back?.endsAt.equals(event.endsAt)).toBe(true);
    expect(back?.exdates.map(String)).toEqual(event.exdates.map(String));
    expect(back?.attendees).toEqual(event.attendees);
  });

  it("writes all-day events as dates and UTC events with Z", () => {
    const { rrule: _rrule, originalStart: _originalStart, ...single } = event;
    const out = toIcs(
      [
        {
          ...single,
          exdates: [],
          allDay: true,
          startsAt: at("2026-04-26T22:00:00Z"),
          endsAt: at("2026-04-27T22:00:00Z"),
        },
        { ...single, uid: "u2", tz: "UTC", exdates: [] },
      ],
      { now: at("2026-01-01T00:00:00Z") },
    );
    expect(out).toContain("DTSTART;VALUE=DATE:20260427\r\n");
    expect(out).toContain("DTEND;VALUE=DATE:20260428\r\n");
    expect(out).toContain("DTSTART:20260302T080000Z\r\n");
    expect(out).not.toContain("BEGIN:VTIMEZONE");
  });
});
