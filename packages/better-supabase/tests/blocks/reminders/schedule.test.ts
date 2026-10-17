import { describe, expect, it } from "vitest";

import {
  deliverReminder,
  planReminderDeliveries,
} from "../../../src/blocks/reminders/schedule.ts";

const start = Temporal.Instant.from("1997-09-02T09:00:00Z").toZonedDateTimeISO(
  "UTC",
);

describe("reminder deliveries", () => {
  it("plans one delayed job per occurrence inside the horizon", () => {
    const planned = planReminderDeliveries(
      [
        {
          id: "rem-1",
          dtstart: start,
          rrule: "FREQ=DAILY;COUNT=5",
          offsetMinutes: 15,
        },
      ],
      { from: start.subtract({ minutes: 15 }), until: start.add({ days: 2 }) },
    );

    expect(planned.map((item) => item.occurrenceAt)).toEqual([
      "1997-09-02T09:00:00Z",
      "1997-09-03T09:00:00Z",
      "1997-09-04T09:00:00Z",
    ]);
    expect(planned[0]?.runAt.toString()).toBe("1997-09-02T08:45:00Z");
    expect(new Set(planned.map((item) => item.dedupeKey)).size).toBe(3);
  });

  it("marks the occurrence sent and then notifies", async () => {
    const seen: string[] = [];
    await deliverReminder(
      {
        reminderId: "rem-1",
        occurrenceAt: "1997-09-02T09:00:00Z",
        organizationId: "org-1",
      },
      {
        markSent: async (id, at) => {
          seen.push(`sent:${id}:${at}`);
        },
        notify: async (payload) => {
          seen.push(`notify:${payload.organizationId}`);
        },
      },
    );
    expect(seen).toEqual(["sent:rem-1:1997-09-02T09:00:00Z", "notify:org-1"]);
  });
});
