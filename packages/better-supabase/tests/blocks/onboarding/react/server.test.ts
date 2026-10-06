import { describe, expect, it } from "vitest";

import { defineChecklist } from "../../../../src/blocks/onboarding/index.ts";
import * as client from "../../../../src/blocks/onboarding/react/index.ts";
import * as server from "../../../../src/blocks/onboarding/react/server.ts";

describe("onboarding react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("throws from useOnboarding", () => {
    const checklist = defineChecklist({ id: "a", scope: "user", steps: [] });
    expect(() => server.useOnboarding(checklist)).toThrow(
      "useOnboarding() runs in Client Components only",
    );
  });
});
