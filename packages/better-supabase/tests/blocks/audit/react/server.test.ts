import { describe, expect, it } from "vitest";

import * as client from "../../../../src/blocks/audit/react/index.ts";
import * as server from "../../../../src/blocks/audit/react/server.ts";

describe("audit react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("throws from useAuditLog", () => {
    expect(() => server.useAuditLog({ organizationId: "org-1" })).toThrow(
      "useAuditLog() runs in Client Components only",
    );
  });
});
