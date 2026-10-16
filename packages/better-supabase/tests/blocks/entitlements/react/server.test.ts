import { describe, expect, it } from "vitest";

import * as client from "../../../../src/blocks/entitlements/react/index.ts";
import * as server from "../../../../src/blocks/entitlements/react/server.ts";

describe("entitlements react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("throws from useFeatureGate", () => {
    expect(() => server.useFeatureGate("exports")).toThrow(
      "useFeatureGate() runs in Client Components only",
    );
  });
});
