import { describe, expect, it } from "vitest";

import * as client from "../../../../src/blocks/calendar/react/index.ts";
import * as server from "../../../../src/blocks/calendar/react/server.ts";

describe("calendar react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("throws from useCalendar", () => {
    expect(() =>
      server.useCalendar({
        calendarIds: [],
        range: { start: new Date(0), end: new Date(0) },
      }),
    ).toThrow("useCalendar() runs in Client Components only");
  });
});
