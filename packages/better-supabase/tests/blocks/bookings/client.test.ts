import { describe, expect, it, vi } from "vitest";

import type {
  BookingSlot,
  PlacedBooking,
} from "../../../src/blocks/bookings/bookings.ts";

import { createAvailableSlotsController } from "../../../src/blocks/bookings/client.ts";
import { failed, flush, held, mount, resolved } from "../../fixtures/ports.ts";

const slot = (at: string): BookingSlot => ({
  resourceId: "r1",
  startsAt: Temporal.Instant.from(`${at}Z`),
  endsAt: Temporal.Instant.from(`${at}Z`).add({ minutes: 30 }),
  localStart: Temporal.PlainDateTime.from(at),
  seats: 1,
});

// SAFETY: the controller passes the booking through.
const booking = { id: "b1" } as unknown as PlacedBooking;

const range = {
  start: new Date("2030-03-04T00:00:00Z"),
  end: new Date("2030-03-06T00:00:00Z"),
};

function fakeClient() {
  return {
    availableSlots: vi.fn(() =>
      resolved([slot("2030-03-05T09:00"), slot("2030-03-04T09:00")]),
    ),
    hold: vi.fn(() => resolved(booking)),
    public: {
      slots: vi.fn(() => resolved([slot("2030-03-04T10:00")])),
      hold: vi.fn(() => resolved(booking)),
    },
  };
}

describe("createAvailableSlotsController", () => {
  it("loads the range by day, holds a slot and follows the range", async () => {
    const client = fakeClient();

    const controller = createAvailableSlotsController({
      client,
      serviceId: "s1",
      range,
      tz: "Europe/Amsterdam",
      resourceId: "r1",
    });

    expect(controller.getSnapshot().loading).toBe(true);
    const { view, unmount } = mount(controller);
    await flush();
    expect(view().loading).toBe(false);
    expect([...view().days.keys()]).toEqual(["2030-03-04", "2030-03-05"]);
    expect(client.availableSlots).toHaveBeenCalledWith({
      serviceId: "s1",
      range: {
        from: Temporal.Instant.from("2030-03-04T00:00:00Z"),
        until: Temporal.Instant.from("2030-03-06T00:00:00Z"),
      },
      tz: "Europe/Amsterdam",
      resourceId: "r1",
    });

    expect(
      await view().hold({ slot: view().slots![0]!, customer: { name: "Ada" } }),
    ).toBe(booking);
    expect(client.availableSlots).toHaveBeenCalledTimes(2);

    view().setRange({ ...range });
    expect(client.availableSlots).toHaveBeenCalledTimes(2);
    view().setRange({
      start: range.start,
      end: new Date("2030-03-08T00:00:00Z"),
    });
    expect(view().loading).toBe(true);
    expect(view().slots).toHaveLength(2);
    await flush();
    expect(view().loading).toBe(false);

    client.hold.mockReturnValue(failed("taken"));
    expect(await view().hold({ slot: view().slots![0]! })).toBeUndefined();
    expect(view().error?.message).toBe("taken");
    client.availableSlots.mockReturnValue(failed("closed"));
    await view().refresh();
    expect(view().error?.message).toBe("closed");
    unmount();
  });

  it("loads and holds as a guest with a token, and drops an overtaken load", async () => {
    const client = fakeClient();
    const slow = held([slot("2030-03-09T09:00")]);
    client.public.slots.mockReturnValueOnce(slow.result);

    const { view, unmount } = mount(
      createAvailableSlotsController({
        client,
        serviceId: "s1",
        range,
        token: "share",
      }),
    );

    view().setRange({
      start: range.start,
      end: new Date("2030-03-07T00:00:00Z"),
    });
    await flush();
    slow.release();
    await flush();
    expect(view().slots?.map((each) => each.localStart.hour)).toEqual([10]);
    expect(client.public.slots).toHaveBeenLastCalledWith({
      token: "share",
      range: expect.anything(),
    });
    await view().hold({ slot: view().slots![0]! });
    expect(client.public.hold).toHaveBeenCalledWith({
      token: "share",
      resourceId: "r1",
      startsAt: view().slots![0]!.startsAt,
      customer: { name: "", email: "" },
    });
    unmount();
  });
});
