import { describe, expect, it } from "vitest";

import * as client from "../../../src/blocks/undo/react/index.ts";
import * as server from "../../../src/blocks/undo/react/server.ts";

describe("undo react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("throws from useUndoStack", () => {
    expect(() => server.useUndoStack({ apply: async () => undefined })).toThrow(
      "useUndoStack() runs in Client Components only",
    );
  });
});
