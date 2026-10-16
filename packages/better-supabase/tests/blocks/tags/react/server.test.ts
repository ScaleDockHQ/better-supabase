import { describe, expect, it } from "vitest";

import * as client from "../../../../src/blocks/tags/react/index.ts";
import * as server from "../../../../src/blocks/tags/react/server.ts";

describe("tags react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("throws from useTagInput", () => {
    expect(() =>
      server.useTagInput({
        organizationId: "org-1",
        subjectType: "customer",
        subjectId: "cu1",
        kind: "customer",
      }),
    ).toThrow("useTagInput() runs in Client Components only");
  });
});
