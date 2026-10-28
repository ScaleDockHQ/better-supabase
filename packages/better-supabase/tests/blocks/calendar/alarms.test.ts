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
    { action: "display", triggerMinutes: -15 },
    { action: "audio", triggerMinutes: 5, related: "end" },
    {
      action: "email",
      triggerAt: at("2026-03-01T18:00:00Z"),
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
      {
        action: "display",
        triggerMinutes: -15,
        related: "start",
        description: "Review",
      },
      { action: "audio", triggerMinutes: 5, related: "end" },
      {
        action: "email",
        triggerAt: at("2026-03-01T18:00:00Z"),
        repeat: 2,
        repeatMinutes: 10,
        description: "Bring the numbers",
        summary: "Review",
      },
    ]);
  });

  it("skips the per-user reminders toIcs writes", () => {
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
    ).toEqual({ action: "display", triggerMinutes: -13_144, related: "start" });
    expect(
      readAlarm([line("ACTION", "DISPLAY"), line("TRIGGER", "-PT0S")]),
    ).toEqual({ action: "display", triggerMinutes: 0, related: "start" });
  });

  it("keeps a repeat only with a positive interval", () => {
    expect(
      readAlarm([
        line("ACTION", "DISPLAY"),
        line("TRIGGER", "PT0M"),
        line("REPEAT", "3"),
        line("DURATION", "PT0M"),
      ]),
    ).toEqual({ action: "display", triggerMinutes: 0, related: "start" });
  });
});

describe("alarm rows", () => {
  it("reads a row and writes an item", () => {
    const alarm = alarmOf({
      id: "a1",
      action: "email",
      triggerMinutes: -60,
      related: "end",
      triggerAt: null,
      repeat: 1,
      repeatMinutes: 5,
      description: "Soon",
      summary: null,
    });

    expect(alarm).toEqual({
      id: "a1",
      action: "email",
      triggerMinutes: -60,
      related: "end",
      repeat: 1,
      repeatMinutes: 5,
      description: "Soon",
    });
    expect(alarmItem(alarm)).toEqual({
      action: "email",
      triggerMinutes: -60,
      related: "end",
      repeat: 1,
      repeatMinutes: 5,
      description: "Soon",
    });
    expect(
      alarmItem({ action: "display", triggerAt: at("2026-03-01T18:00:00Z") }),
    ).toEqual({ action: "display", triggerAt: "2026-03-01T18:00:00Z" });
    expect(alarmOf({ action: "beep", repeat: 0 })).toEqual({
      action: "display",
      related: "start",
    });
  });

  it("leaves an audio alarm without a description", () => {
    expect(
      alarmLines({ action: "audio", triggerMinutes: 0 }, { title: "T" }),
    ).toEqual(["BEGIN:VALARM", "ACTION:AUDIO", "TRIGGER:PT0M", "END:VALARM"]);
  });
});
