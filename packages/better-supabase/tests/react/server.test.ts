import { describe, expect, it } from "vitest";

import * as client from "../../src/react/index.ts";
import * as server from "../../src/react/server.ts";

describe("react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("throws from hooks that need a client", () => {
    expect(() => server.useLiveCount(null)).toThrow(
      "useLiveCount() runs in Client Components only",
    );
  });

  it("keeps hasEntitlement usable on the server", () => {
    expect(server.hasEntitlement).toBe(client.hasEntitlement);
  });
});
