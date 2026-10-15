import { describe, expect, it } from "vitest";

import * as client from "../../../../src/blocks/comments/react/index.ts";
import * as server from "../../../../src/blocks/comments/react/server.ts";

describe("comments react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("throws from useComments", () => {
    expect(() =>
      server.useComments({
        organizationId: "org-1",
        subjectType: "customer",
        subjectId: "cu1",
      }),
    ).toThrow("useComments() runs in Client Components only");
  });
});
