import { describe, expect, it } from "vitest";

import * as client from "../../../../src/blocks/permissions/react/index.ts";
import * as server from "../../../../src/blocks/permissions/react/server.ts";

describe("access react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("throws from every hook and from Can", () => {
    const message = "runs in Client Components only";

    expect(() => server.usePermissions(["a"])).toThrow(message);
    expect(() => server.usePermission("a")).toThrow(message);
    expect(() => server.Can({ permission: "a" })).toThrow(message);
  });
});
