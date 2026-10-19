import { describe, expect, it } from "vitest";

import * as client from "../../../../src/blocks/rules/react/index.ts";
import * as server from "../../../../src/blocks/rules/react/server.ts";

describe("rules react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("throws from the hook", () => {
    expect(() =>
      server.useRuleBuilder({
        organizationId: "org-1",
        rule: null,
        subjectType: "expense",
      }),
    ).toThrow("useRuleBuilder() runs in Client Components only");
  });
});
