import { describe, expect, it } from "vitest";

import * as client from "../../../../src/blocks/api-keys/react/index.ts";
import * as server from "../../../../src/blocks/api-keys/react/server.ts";

describe("api-keys react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("throws from useApiKeys", () => {
    expect(() => server.useApiKeys({ organizationId: "org-1" })).toThrow(
      "useApiKeys() runs in Client Components only",
    );
  });
});
