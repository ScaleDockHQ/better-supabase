import { describe, expect, it } from "vitest";

import * as client from "../../../../src/blocks/bookings/react/index.ts";
import * as server from "../../../../src/blocks/bookings/react/server.ts";

describe("bookings react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("throws from useAvailableSlots", () => {
    expect(() =>
      server.useAvailableSlots({
        serviceId: "s1",
        range: { start: new Date(0), end: new Date(0) },
      }),
    ).toThrow("useAvailableSlots() runs in Client Components only");
  });
});
