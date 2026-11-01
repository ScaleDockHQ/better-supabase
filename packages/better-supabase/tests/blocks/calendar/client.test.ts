import { describe, expect, it, vi } from "vitest";

import type { CalendarOccurrence } from "../../../src/blocks/calendar/occurrences.ts";

import { createCalendarController } from "../../../src/blocks/calendar/client.ts";
import { failed, flush, held, mount, resolved } from "../../fixtures/ports.ts";

const occurrence = (key: string): CalendarOccurrence =>
  // SAFETY: the event calendar mapping reads only these fields.
  ({
    key,
    event: { id: key, calendarId: "c1", title: key },
    start: Temporal.Instant.from("2030-03-04T09:00:00Z"),
    end: Temporal.Instant.from("2030-03-04T10:00:00Z"),
    originalStart: Temporal.Instant.from("2030-03-04T09:00:00Z"),
    allDay: false,
    recurring: false,
  }) as unknown as CalendarOccurrence;

const range = {
  start: new Date("2030-03-01T00:00:00Z"),
  end: new Date("2030-04-01T00:00:00Z"),
};

function fakeClient() {
  return {
    occurrences: vi.fn(() => resolved([occurrence("o1")])),
    editOccurrence: vi.fn(() => resolved({ id: "o1" })),
    editFollowing: vi.fn(() => resolved({ id: "s2" })),
    cancelOccurrence: vi.fn(() => resolved(true)),
  };
}

describe("createCalendarController", () => {
  it("loads events for the range and saves, splits and cancels", async () => {
    const client = fakeClient();

    const { view, unmount } = mount(
      createCalendarController({
        // SAFETY: the fake returns what the controller reads.
        client: client as never,
        calendarIds: ["c1"],
        range,
        resourceOf: () => "room",
        readOnly: () => true,
      }),
    );

    await flush();
    expect(view().events[0]).toMatchObject({
      id: "o1",
      resourceId: "room",
      readOnly: true,
    });
    const [first] = view().occurrences!;
    expect(
      await view().editOccurrence({
        occurrence: first!,
        changes: { title: "Moved" },
      }),
    ).toBe(true);
    expect(
      await view().editFollowing({
        occurrence: first!,
        changes: { title: "Later" },
      }),
    ).toBe(true);
    expect(await view().cancelOccurrence(first!)).toBe(true);
    expect(client.occurrences).toHaveBeenCalledTimes(4);

    client.cancelOccurrence.mockReturnValue(failed("gone"));
    expect(await view().cancelOccurrence(first!)).toBe(false);
    expect(view().error?.message).toBe("gone");
    client.occurrences.mockReturnValue(failed("down"));
    await view().refresh();
    expect(view()).toMatchObject({ loading: false });
    expect(view().error?.message).toBe("down");
    unmount();
  });

  it("keeps the shown events while another range loads and drops overtaken loads", async () => {
    const client = fakeClient();
    const slow = held([occurrence("old")]);
    client.occurrences.mockReturnValueOnce(slow.result);

    const { view, unmount } = mount(
      createCalendarController({
        client: client as never,
        calendarIds: [],
        range,
      }),
    );

    view().setRange(range);
    view().setRange({
      start: range.start,
      end: new Date("2030-05-01T00:00:00Z"),
    });
    await flush();
    slow.release();
    await flush();
    expect(view().occurrences?.map((each) => each.key)).toEqual(["o1"]);
    expect(view().events[0]?.resourceId).toBe("c1");
    unmount();
  });
});
