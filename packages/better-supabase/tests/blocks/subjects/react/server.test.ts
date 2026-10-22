import { describe, expect, it } from "vitest";

import * as client from "../../../../src/blocks/subjects/react/index.ts";
import * as server from "../../../../src/blocks/subjects/react/server.ts";

describe("subjects react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("throws from every hook", () => {
    const message = "runs in Client Components only";

    expect(() => server.useSubjects([])).toThrow(message);
    expect(() => server.useSubject(null)).toThrow(message);
  });
});
