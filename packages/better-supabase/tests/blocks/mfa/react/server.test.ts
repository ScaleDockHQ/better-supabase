import { describe, expect, it } from "vitest";

import * as client from "../../../../src/blocks/mfa/react/index.ts";
import * as server from "../../../../src/blocks/mfa/react/server.ts";

describe("mfa react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("throws from useMfa and useStepUp", () => {
    expect(() => server.useMfa()).toThrow(
      "useMfa() runs in Client Components only",
    );
    expect(() => server.useStepUp()).toThrow(
      "useStepUp() runs in Client Components only",
    );
  });
});
