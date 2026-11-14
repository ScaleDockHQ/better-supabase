import { describe, expect, it } from "vitest";

import type {
  GraphNodeCall,
  GraphWaitCall,
} from "../../../src/blocks/workflow-editor/executor.ts";
import type {
  WorkflowGraph,
  WorkflowNodeKindInfo,
} from "../../../src/blocks/workflow-editor/graph.ts";

import {
  executeGraph,
  nodeWaitToken,
} from "../../../src/blocks/workflow-editor/executor.ts";
import { fakeRuntime } from "./fixture.ts";

const GRAPH: WorkflowGraph = {
  nodes: [
    { id: "start", kind: "trigger" },
    { id: "task", kind: "human-task", config: { title: "Call" } },
    { id: "after", kind: "step", step: "email.send" },
  ],
  edges: [
    { id: "e1", source: "start", target: "task" },
    { id: "e2", source: "task", target: "after" },
  ],
};

const KINDS: readonly WorkflowNodeKindInfo[] = [
  { kind: "human-task", waits: true },
];

describe("nodeWaitToken", () => {
  it("names the hook by the run key and the node", () => {
    expect(nodeWaitToken("run-1", "task")).toBe("node-wait:run-1:task");
  });
});

describe("waiting nodes", () => {
  it("registers the hook, runs the step, waits, then calls the node again with the payload", async () => {
    const runtime = fakeRuntime("pro", undefined);
    const calls: GraphNodeCall[] = [];
    const waits: GraphWaitCall[] = [];

    const results = await executeGraph(
      GRAPH,
      { text: "hi" },
      {
        ...runtime,
        nodes: KINDS,
        waitFor: async (call) => {
          waits.push(call);
          runtime.log.push("hook");

          return { completedBy: "u1" };
        },
        node: async (call) => {
          runtime.log.push(call.resumed === undefined ? "start" : "resume");
          calls.push(call);

          return call.resumed === undefined
            ? { assignee: "u1" }
            : { ...(call.resumed.output as object), done: true };
        },
      },
    );

    expect(waits).toEqual([
      {
        node: "task",
        kind: "human-task",
        token: "node-wait:run-1:task",
        runKey: "run-1",
      },
    ]);
    expect(runtime.log.slice(0, 3)).toEqual(["hook", "start", "resume"]);
    expect(calls[0]?.resumed).toBeUndefined();
    expect(calls[1]?.resumed).toEqual({
      payload: { completedBy: "u1" },
      output: { assignee: "u1" },
    });
    expect(results["task"]).toEqual({ assignee: "u1", done: true });
    expect(results["after"]).toBeNull();
  });

  it("refuses a live run without waitFor", async () => {
    await expect(
      executeGraph(
        GRAPH,
        {},
        { ...fakeRuntime("pro", undefined), nodes: KINDS, node: async () => 1 },
      ),
    ).rejects.toThrow("pass waitFor to the runtime to run node task");
  });

  it("returns the stub and never waits in a test run", async () => {
    const results = await executeGraph(
      GRAPH,
      {},
      {
        ...fakeRuntime("pro", undefined),
        nodes: KINDS,
        stubs: { task: { completedBy: "stub" } },
      },
    );

    expect(results["task"]).toEqual({ completedBy: "stub" });
  });
});
