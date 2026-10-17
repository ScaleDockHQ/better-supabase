import type * as ReactModule from "react";

import { afterEach, describe, expect, it, vi } from "vitest";

import { useCalendar } from "../../../../src/blocks/calendar/react/index.ts";
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
  BetterSupabaseProvider({ client });
};

const SERIES = {
  id: "s1",
  calendarId: "c1",
  uid: "s1",
  title: "Stand-up",
  startsAt: "2026-03-23T08:00:00+00:00",
  endsAt: "2026-03-23T08:15:00+00:00",
  allDay: false,
  tz: "Europe/Amsterdam",
  status: "confirmed",
  rrule: "FREQ=WEEKLY;BYDAY=MO;COUNT=4",
  exdates: [],
  attendees: [],
};

const range = {
  start: new Date("2026-03-23T00:00:00Z"),
  end: new Date("2026-04-30T00:00:00Z"),
};

const fail = (message: string) =>
  Object.assign(new Error(message), { code: "P0002" });

const settle = async (view: { result: { loading: boolean } }) => {
  await vi.waitFor(() => {
    expect(view.result.loading).toBe(false);
  });
};

afterEach(() => {
  rpc.calls.length = 0;
  rpc.results.clear();
});

describe("useCalendar", () => {
  it("loads the range's occurrences as event calendar events", async () => {
    rpc.results.set("list_calendar_events", [SERIES]);

    const view = renderHook(
      useCalendar,
      {
        calendarIds: ["c1"],
        range,
        schema: "app",
        resourceOf: () => "room-1",
        readOnly: () => true,
      },
      provide,
    );

    expect(view.result.loading).toBe(true);
    await settle(view);
    expect(view.result.occurrences).toHaveLength(4);
    expect(view.result.events[0]).toMatchObject({
      title: "Stand-up",
      resourceId: "room-1",
      readOnly: true,
    });
    expect(rpc.calls[0]).toMatchObject({
      schema: "app",
      fn: "list_calendar_events",
      args: { calendar_ids: ["c1"] },
    });
    view.unmount();
  });

  it("saves an occurrence, a split and a cancellation, then loads again", async () => {
    rpc.results.set("list_calendar_events", [SERIES]);
    rpc.results.set("save_calendar_event", {
      id: "o1",
      uid: "s1",
      created: true,
    });
    rpc.results.set("split_calendar_event", { id: "s2" });
    rpc.results.set("cancel_calendar_occurrence", true);

    const view = renderHook(
      useCalendar,
      { calendarIds: ["c1"], range },
      provide,
    );

    await settle(view);
    const [, second, third] = view.result.occurrences!;
    expect(await view.result.editOccurrence(second!, { title: "Moved" })).toBe(
      true,
    );
    expect(await view.result.editFollowing(third!, { title: "Later" })).toBe(
      true,
    );
    expect(await view.result.cancelOccurrence(second!)).toBe(true);
    expect(rpc.calls.map((call) => call.fn)).toEqual([
      "list_calendar_events",
      "save_calendar_event",
      "list_calendar_events",
      "split_calendar_event",
      "list_calendar_events",
      "cancel_calendar_occurrence",
      "list_calendar_events",
    ]);
    expect(view.result.loading).toBe(false);
    view.unmount();
  });

  it("keeps the error of a failed load or edit", async () => {
    rpc.results.set("list_calendar_events", fail("calendar not found"));
    const view = renderHook(useCalendar, { calendarIds: [], range }, provide);
    await settle(view);
    expect(view.result.occurrences).toBeUndefined();
    expect(view.result.error?.message).toBe("calendar not found");
    expect(rpc.calls[0]?.args).toMatchObject({ calendar_ids: [] });

    rpc.results.set("list_calendar_events", [SERIES]);
    await view.result.refresh();
    expect(view.result.error).toBeUndefined();
    rpc.results.set("cancel_calendar_occurrence", fail("event not found"));
    expect(
      await view.result.cancelOccurrence(view.result.occurrences![0]!),
    ).toBe(false);
    expect(view.result.error?.message).toBe("event not found");
    view.unmount();
  });

  it("drops a load that finishes after the range changed", async () => {
    rpc.results.set("list_calendar_events", [SERIES]);

    const view = renderHook(
      useCalendar,
      { calendarIds: ["c1"], range },
      provide,
    );

    view.rerender({
      calendarIds: ["c1"],
      range: { start: range.start, end: new Date("2026-03-24T00:00:00Z") },
    });
    await settle(view);
    expect(view.result.occurrences).toHaveLength(1);
    view.unmount();
  });
});
