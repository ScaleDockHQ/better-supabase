import { describe, expect, it } from "vitest";

import * as client from "../../../../src/blocks/sessions/react/index.ts";
import * as server from "../../../../src/blocks/sessions/react/server.ts";

describe("sessions react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("throws from useOAuthConsent and useOAuthGrants", () => {
    expect(() => server.useOAuthConsent({ authorizationId: "auth-1" })).toThrow(
      "useOAuthConsent() runs in Client Components only",
    );
    expect(() => server.useOAuthGrants()).toThrow(
      "useOAuthGrants() runs in Client Components only",
    );
  });
});
