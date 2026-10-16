import { describe, expect, it } from "vitest";

import * as client from "../../../../src/blocks/billing/react/index.ts";
import * as server from "../../../../src/blocks/billing/react/server.ts";
import { ok } from "../../../../src/core/result.ts";

describe("billing react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("throws from usePlanPicker", () => {
    expect(() =>
      server.usePlanPicker({
        load: async () => ({ plans: [], current: undefined }),
        checkout: async () => ok({ url: undefined }),
        open: () => undefined,
      }),
    ).toThrow("usePlanPicker() runs in Client Components only");
  });
});
