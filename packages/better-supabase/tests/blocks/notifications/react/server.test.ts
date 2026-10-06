import { describe, expect, it } from "vitest";

import * as client from "../../../../src/blocks/notifications/react/index.ts";
import * as server from "../../../../src/blocks/notifications/react/server.ts";

describe("notifications react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("throws from useNotifications", () => {
    expect(() =>
      server.useNotifications({ topic: "t", load: async () => [] }),
    ).toThrow("useNotifications() runs in Client Components only");
  });
});
