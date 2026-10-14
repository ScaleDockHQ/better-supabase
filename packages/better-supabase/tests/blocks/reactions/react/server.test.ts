import { describe, expect, it } from "vitest";

import * as client from "../../../../src/blocks/reactions/react/index.ts";
import * as server from "../../../../src/blocks/reactions/react/server.ts";

describe("reactions react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("throws from useReactions", () => {
    expect(() =>
      server.useReactions({
        organizationId: "org-1",
        subjectType: "comment",
        subjectIds: [],
      }),
    ).toThrow("useReactions() runs in Client Components only");
  });
});
