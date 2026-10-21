import type * as ReactModule from "react";

import { afterEach, describe, expect, it, vi } from "vitest";

import { useAvailableSlots } from "../../../../src/blocks/bookings/react/index.ts";
import {
  BetterSupabaseProvider,
  type ClientLike,
} from "../../../../src/react/hooks.ts";
import { renderHook } from "../../../fixtures/hook-runtime.ts";

const rpc = vi.hoisted(() => {
  const calls: { schema: string; fn: string; args: unknown }[] = [];
  const results = new Map<string, unknown>();

  const client = {
    schema: (schema: string) => ({
      rpc: async (fn: string, args: unknown) => {
        calls.push({ schema, fn, args });
        const result = results.get(fn);

        return result instanceof Error
          ? { data: null, error: result }
          : { data: result ?? null, error: null };
      },
    }),
  };

  return { calls, results, client };
});

// vi.mock factories run before the imports above, so they load modules themselves.
vi.mock("react", async (importOriginal) => ({
  ...(await importOriginal<typeof ReactModule>()),
  ...(await import("../../../fixtures/hook-runtime.ts")).reactHooks,
}));

// SAFETY: the hooks read only `supabase` from the client.
const client = { supabase: rpc.client } as unknown as ClientLike;

const provide = (): void => {
  void BetterSupabaseProvider({ client });
};

const SLOT = {
  resourceId: "r1",
  startsAt: "2030-03-04T08:00:00+00:00",
  endsAt: "2030-03-04T08:30:00+00:00",
  localStart: "2030-03-04T09:00:00",
  seats: 1,
};

const BOOKING = {
  id: "b1",
  resourceId: "r1",
  serviceId: "s1",
  seat: 1,
  startsAt: SLOT.startsAt,
  endsAt: SLOT.endsAt,
  status: "hold",
  holdExpiresAt: "2030-03-04T07:10:00+00:00",
  customerName: "Bo",
  customerEmail: "bo@example.test",
  createdAt: "2030-03-04T07:00:00+00:00",
  accessToken: "t".repeat(48),
};

const range = {
  start: new Date("2030-03-04T00:00:00Z"),
  end: new Date("2030-03-05T00:00:00Z"),
};

const settle = async (view: { result: { loading: boolean } }) => {
  await vi.waitFor(() => {
    expect(view.result.loading).toBe(false);
  });
};

afterEach(() => {
  rpc.calls.length = 0;
  rpc.results.clear();
});

describe("useAvailableSlots", () => {
  it("loads a service's slots by day and holds one", async () => {
    rpc.results.set("available_slots", [SLOT]);
    rpc.results.set("hold_booking", BOOKING);

    const view = renderHook(
      useAvailableSlots,
      {
        serviceId: "s1",
        range,
        tz: "Europe/Amsterdam",
        resourceId: "r1",
        schema: "app",
      },
      provide,
    );

    expect(view.result.loading).toBe(true);
    await settle(view);
    expect(view.result.slots).toHaveLength(1);
    expect(view.result.days.get("2030-03-04")).toHaveLength(1);
    expect(rpc.calls[0]).toMatchObject({
      schema: "app",
      fn: "available_slots",
      args: { service: "s1", tz: "Europe/Amsterdam", resource: "r1" },
    });
    const placed = await view.result.hold(view.result.slots![0]!);
    expect(placed?.id).toBe("b1");
    expect(rpc.calls.map((call) => call.fn)).toEqual([
      "available_slots",
      "hold_booking",
      "available_slots",
    ]);
    view.unmount();
  });

  it("loads and holds through a share-link token", async () => {
    rpc.results.set("public_available_slots", [SLOT]);
    rpc.results.set("public_hold_booking", BOOKING);

    const view = renderHook(
      useAvailableSlots,
      { serviceId: "s1", range, token: "share" },
      provide,
    );

    await settle(view);
    const placed = await view.result.hold(view.result.slots![0]!);
    expect(placed?.accessToken).toBe("t".repeat(48));
    expect(rpc.calls[1]).toMatchObject({
      fn: "public_hold_booking",
      args: { token: "share", customer: { name: "", email: "" } },
    });
    view.unmount();
  });

  it("keeps the error of a failed load or hold", async () => {
    rpc.results.set(
      "available_slots",
      Object.assign(new Error("service not found"), { code: "P0002" }),
    );

    const view = renderHook(
      useAvailableSlots,
      { serviceId: "s1", range },
      provide,
    );

    await settle(view);
    expect(view.result.slots).toBeUndefined();
    expect(view.result.error?.message).toBe("service not found");

    rpc.results.set("available_slots", [SLOT]);
    await view.result.refresh();
    expect(view.result.error).toBeUndefined();
    rpc.results.set(
      "hold_booking",
      Object.assign(new Error("slot taken"), {
        code: "23P01",
        hint: "BOOKING_SLOT_UNAVAILABLE",
      }),
    );
    expect(await view.result.hold(view.result.slots![0]!)).toBeUndefined();
    expect(view.result.error?.message).toBe("slot taken");
    view.unmount();
  });

  it("drops a load that finishes after the range changed", async () => {
    rpc.results.set("available_slots", [SLOT]);

    const view = renderHook(
      useAvailableSlots,
      { serviceId: "s1", range },
      provide,
    );

    view.rerender({ serviceId: "s2", range });
    await settle(view);
    expect(rpc.calls.at(-1)?.args).toMatchObject({ service: "s2" });
    view.unmount();
  });
});
