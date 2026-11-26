import { describe, expect, it } from "vitest";

import {
  DEFAULT_CHANGE_GRAPH,
  readLifecycle,
} from "@/features/change-requests/change-request-lifecycle";

describe("readLifecycle", () => {
  it("reads the default graph's stages, first stage and moves", () => {
    const lifecycle = readLifecycle(DEFAULT_CHANGE_GRAPH);

    expect(lifecycle.stages.map((stage) => stage.label)).toStrictEqual([
      "Submitted",
      "CAB review",
      "Scheduled",
      "Done",
    ]);
    expect(lifecycle.initial).toBe("submitted");
    expect(lifecycle.moves).toStrictEqual({
      submitted: ["review"],
      review: ["submitted", "scheduled"],
      scheduled: ["done"],
      done: [],
    });
  });

  it("walks through nodes without a stage to the next stage", () => {
    const lifecycle = readLifecycle({
      nodes: [
        { id: "t", kind: "trigger" },
        { id: "a", kind: "approval", config: { stage: "open" } },
        { id: "wait", kind: "sleep", config: { duration: "1d" } },
        { id: "b", kind: "approval", config: { stage: "closed" } },
      ],
      edges: [
        { id: "e1", source: "t", target: "a" },
        { id: "e2", source: "a", target: "wait" },
        { id: "e3", source: "wait", target: "b" },
      ],
    });

    expect(lifecycle.initial).toBe("open");
    expect(lifecycle.moves).toStrictEqual({ open: ["closed"], closed: [] });
  });

  it("ignores a returnsTo stage the graph does not have", () => {
    const lifecycle = readLifecycle({
      nodes: [
        {
          id: "t",
          kind: "trigger",
          config: { stage: "draft", returnsTo: ["gone"] },
        },
      ],
      edges: [],
    });

    expect(lifecycle.moves).toStrictEqual({ draft: [] });
  });
});
