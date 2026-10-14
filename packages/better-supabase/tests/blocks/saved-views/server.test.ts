import { describe, expect, it } from "vitest";

import * as client from "../../../src/blocks/saved-views/react/index.ts";
import * as server from "../../../src/blocks/saved-views/react/server.ts";

describe("saved views react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("throws from useSavedViews", () => {
    expect(() =>
      server.useSavedViews({
        load: async () => [],
        urlState: {},
        setUrlState: () => undefined,
      }),
    ).toThrow("useSavedViews() runs in Client Components only");
  });
});
