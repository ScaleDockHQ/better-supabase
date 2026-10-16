import { describe, expect, it } from "vitest";

import { defineSettings } from "../../../../src/blocks/settings/index.ts";
import * as client from "../../../../src/blocks/settings/react/index.ts";
import * as server from "../../../../src/blocks/settings/react/server.ts";

describe("settings react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("throws from useSettings", () => {
    expect(() =>
      server.useSettings(defineSettings({}), { scope: "user" }),
    ).toThrow("useSettings() runs in Client Components only");
  });
});
