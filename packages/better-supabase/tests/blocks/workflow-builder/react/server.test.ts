import { describe, expect, it } from "vitest";

import * as client from "../../../../src/blocks/workflow-builder/react/index.ts";
import * as server from "../../../../src/blocks/workflow-builder/react/server.ts";

describe("workflow-builder react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("throws from the hooks", () => {
    expect(() => server.useWorkflowBuilder()).toThrow(
      "useWorkflowBuilder() runs in Client Components only",
    );
    expect(() => server.useWorkflowCanvasRun("r1")).toThrow(
      "useWorkflowCanvasRun() runs in Client Components only",
    );
  });
});
