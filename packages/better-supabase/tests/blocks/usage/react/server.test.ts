import { describe, expect, it } from "vitest";

import * as client from "../../../../src/blocks/usage/react/index.ts";
import * as server from "../../../../src/blocks/usage/react/server.ts";

describe("usage react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("throws from useUsageMeter", () => {
    expect(() => server.useUsageMeter({ organizationId: "org-1" })).toThrow(
      "useUsageMeter() runs in Client Components only",
    );
  });
});
