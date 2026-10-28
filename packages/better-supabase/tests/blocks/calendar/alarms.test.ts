import { describe, expect, it } from "vitest";

import type { IcsSource } from "../../../src/blocks/calendar/ics.ts";

import {
  alarmItem,
  alarmLines,
  alarmOf,
  readAlarm,
} from "../../../src/blocks/calendar/alarms.ts";
import { parseIcs, toIcs } from "../../../src/blocks/calendar/ics.ts";

const at = (text: string): Temporal.Instant => Temporal.Instant.from(text);

const line = (name: string, value: string, params = {}) => ({
  name,
  value,
  params,
});

const EVENT: IcsSource = {
  uid: "review@example.test",
  title: "Review",
  startsAt: at("2026-03-02T09:00:00Z"),
  endsAt: at("2026-03-02T10:00:00Z"),
  allDay: false,
  tz: "UTC",
  status: "confirmed",
  exdates: [],
  attendees: [
    { email: "jane@example.test", role: "required", response: "accepted" },
  ],
  alarms: [
    { method: "display", offsetMinutes: 15 },
    { method: "audio", offsetMinutes: -5, related: "end" },
    {
      method: "email",
      offsetMinutes: 0,
      at: at("2026-03-01T18:00:00Z"),
      repeat: 2,
      repeatMinutes: 10,
      description: "Bring the numbers",
    },
  ],
};

describe("calendar alarms in iCalendar", () => {
  it("writes each alarm as a VALARM", () => {
    const text = toIcs([EVENT], { now: at("2026-01-01T00:00:00Z") });

    expect(text).toContain(
      "ACTION:DISPLAY\r\nTRIGGER:-PT15M\r\nDESCRIPTION:Review\r\n",
    );
    expect(text).toContain(
      "ACTION:AUDIO\r\nTRIGGER;RELATED=END:PT5M\r\nEND:VALARM",
    );
    expect(text).toContain("TRIGGER;VALUE=DATE-TIME:20260301T180000Z\r\n");
    expect(text).toContain("REPEAT:2\r\nDURATION:PT10M\r\n");
    expect(text).toContain("SUMMARY:Review\r\n");
    expect(text).toContain("ATTENDEE:mailto:jane@example.test\r\nEND:VALARM");
  });

  it("reads back what it writes", () => {
    const text = toIcs([EVENT], { now: at("2026-01-01T00:00:00Z") });
    const [event] = parseIcs(text).events;

    expect(event?.alarms).toEqual([
      { method: "display", offsetMinutes: 15, description: "Review" },
      { method: "audio", offsetMinutes: -5, related: "end" },
      {
        method: "email",
        offsetMinutes: 0,
        at: at("2026-03-01T18:00:00Z"),
        repeat: 2,
        repeatMinutes: 10,
        description: "Bring the numbers",
        summary: "Review",
      },
    ]);
  });

  it("writes reminders through the same VALARM path and skips them on import", () => {
    const text = toIcs(
      [
        {
          ...EVENT,
          alarms: [],
          reminders: [{ method: "notification", offsetMinutes: 15 }],
        },
      ],
      { now: at("2026-01-01T00:00:00Z") },
    );

    expect(text).toContain(
      "ACTION:DISPLAY\r\nTRIGGER:-PT15M\r\nDESCRIPTION:Review\r\nX-BSB-METHOD:notification\r\nEND:VALARM",
    );
    expect(parseIcs(text).events[0]?.alarms).toBeUndefined();
  });
});

describe("readAlarm", () => {
  it("returns undefined for an alarm the block doesn't store", () => {
    expect(readAlarm([line("TRIGGER", "-PT5M")])).toBeUndefined();
    expect(
      readAlarm([line("ACTION", "PROCEDURE"), line("TRIGGER", "-PT5M")]),
    ).toBeUndefined();
    expect(readAlarm([line("ACTION", "DISPLAY")])).toBeUndefined();
    expect(
      readAlarm([line("ACTION", "DISPLAY"), line("TRIGGER", "soon")]),
    ).toBeUndefined();
    expect(
      readAlarm([
        line("ACTION", "DISPLAY"),
        line("TRIGGER", "2026", { VALUE: "DATE-TIME" }),
      ]),
    ).toBeUndefined();
  });

  it("reads weeks, days, hours and seconds as whole minutes", () => {
    expect(
      readAlarm([line("ACTION", "display"), line("TRIGGER", "-P1W2DT3H4M59S")]),
    ).toEqual({ method: "display", offsetMinutes: 13_144 });
    expect(
      readAlarm([line("ACTION", "DISPLAY"), line("TRIGGER", "-PT0S")]),
    ).toEqual({ method: "display", offsetMinutes: 0 });
  });

  it("keeps a repeat only with a positive interval", () => {
    expect(
      readAlarm([
        line("ACTION", "DISPLAY"),
        line("TRIGGER", "PT0M"),
        line("REPEAT", "3"),
        line("DURATION", "PT0M"),
      ]),
    ).toEqual({ method: "display", offsetMinutes: 0 });
  });
});

describe("alarm rows", () => {
  it("reads a row and writes an item", () => {
    const alarm = alarmOf({
      id: "a1",
      method: "email",
      offsetMinutes: 60,
      related: "end",
      at: null,
      repeat: 1,
      repeatMinutes: 5,
      description: "Soon",
      summary: null,
    });

    expect(alarm).toEqual({
      method: "email",
      offsetMinutes: 60,
      id: "a1",
      related: "end",
      repeat: 1,
      repeatMinutes: 5,
      description: "Soon",
    });
    expect(alarmItem(alarm)).toEqual({
      method: "email",
      offsetMinutes: 60,
      related: "end",
      repeat: 1,
      repeatMinutes: 5,
      description: "Soon",
    });
    expect(
      alarmItem({
        method: "display",
        offsetMinutes: 0,
        at: at("2026-03-01T18:00:00Z"),
      }),
    ).toEqual({ method: "display", at: "2026-03-01T18:00:00Z" });
    expect(alarmOf({ method: "beep", repeat: 0 })).toEqual({
      method: "display",
      offsetMinutes: 0,
    });
  });

  it("leaves an audio alarm without a description", () => {
    expect(
      alarmLines({ method: "audio", offsetMinutes: 0 }, { title: "T" }),
    ).toEqual(["BEGIN:VALARM", "ACTION:AUDIO", "TRIGGER:PT0M", "END:VALARM"]);
  });
});
