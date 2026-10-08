import { describe, expect, it } from "vitest";

import * as client from "../../../../src/blocks/workflows/react/index.ts";
import * as server from "../../../../src/blocks/workflows/react/server.ts";

describe("workflows react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("throws from the hooks", () => {
    expect(() => server.useWorkflowRuns()).toThrow(
      "useWorkflowRuns() runs in Client Components only",
    );
    expect(() => server.useWorkflowRun("r1")).toThrow(
      "useWorkflowRun() runs in Client Components only",
    );
  });
});
