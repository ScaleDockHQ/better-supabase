import { describe, expect, it } from "vitest";

import * as client from "../../../../src/blocks/organizations/react/index.ts";
import * as server from "../../../../src/blocks/organizations/react/server.ts";

describe("organizations react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("throws from useOrganizations", () => {
    expect(() => server.useOrganizations()).toThrow(
      "useOrganizations() runs in Client Components only",
    );
  });
});
