import { describe, expect, it } from "vitest";

import {
  approvalToken,
  executeGraph,
} from "../../../src/blocks/workflow-builder/executor.ts";
import {
  approved,
  conditionOf,
  diffGraphs,
  durationMs,
  edgeOf,
  evaluateCondition,
  graphOf,
  nodeOf,
  readPath,
  topologicalOrder,
  validateGraph,
  type WorkflowCondition,
  type WorkflowGraph,
} from "../../../src/blocks/workflow-builder/graph.ts";
import { fakeRuntime, GRAPH } from "./fixture.ts";

describe("durationMs", () => {
  it("reads numbers and unit strings", () => {
    expect(durationMs(1500.4)).toBe(1500);
    expect(durationMs("250ms")).toBe(250);
    expect(durationMs(" 3s ")).toBe(3000);
    expect(durationMs("2m")).toBe(120_000);
    expect(durationMs("1h")).toBe(3_600_000);
    expect(durationMs("1d")).toBe(86_400_000);
    for (const bad of [0, -1, Number.NaN, "0s", "1w", "soon", null, {}]) {
      expect(durationMs(bad)).toBeUndefined();
    }
  });
});

describe("conditions", () => {
  const scope = {
    input: { email: "a@x.test", tags: ["vip", { n: 1 }] },
    results: { lookup: { plan: "pro", seats: 5 } },
  };
  const holds = (op: WorkflowCondition["op"], path: string, value?: unknown) =>
    evaluateCondition({ path, op, value }, scope);

  it("reads paths into input and results", () => {
    expect(readPath(scope, "input.tags.1.n")).toBe(1);
    expect(readPath(scope, "results.lookup.plan")).toBe("pro");
    expect(readPath(scope, "results.lookup.plan.x")).toBeUndefined();
  });

  it("evaluates every operator", () => {
    expect(holds("equals", "results.lookup.plan", "pro")).toBe(true);
    expect(holds("notEquals", "results.lookup.plan", "pro")).toBe(false);
    expect(holds("exists", "input.email")).toBe(true);
    expect(holds("exists", "input.missing")).toBe(false);
    expect(holds("truthy", "results.lookup.seats")).toBe(true);
    expect(holds("greaterThan", "results.lookup.seats", 4)).toBe(true);
    expect(holds("greaterThan", "results.lookup.plan", 4)).toBe(false);
    expect(holds("lessThan", "results.lookup.seats", 4)).toBe(false);
    expect(holds("contains", "input.email", "@x")).toBe(true);
    expect(holds("contains", "input.email", 1)).toBe(false);
    expect(holds("contains", "input.tags", { n: 1 })).toBe(true);
    expect(holds("contains", "results.lookup.seats", 5)).toBe(false);
  });

  it("reads a node's condition only when it is well formed", () => {
    expect(conditionOf({ id: "c", kind: "condition" })).toBeUndefined();
    expect(
      conditionOf({
        id: "c",
        kind: "condition",
        config: { path: "env.x", op: "equals" },
      }),
    ).toBeUndefined();
    expect(
      conditionOf({
        id: "c",
        kind: "condition",
        config: { path: "input.x", op: "near" },
      }),
    ).toBeUndefined();
    expect(
      conditionOf({
        id: "c",
        kind: "condition",
        config: { path: "input.x", op: "truthy" },
      }),
    ).toEqual({ path: "input.x", op: "truthy", value: undefined });
  });

  it("approves anything but approved: false", () => {
    expect(approved(undefined)).toBe(true);
    expect(approved({ approved: true })).toBe(true);
    expect(approved({ approved: false })).toBe(false);
  });
});

describe("validateGraph", () => {
  it("accepts a valid graph and checks steps against a library", () => {
    expect(validateGraph(GRAPH)).toEqual([]);
    expect(validateGraph(GRAPH, ["crm.lookup", "email.send"])).toEqual([
      "Node rejected uses step slack.post, which is not in the step library",
    ]);
  });

  it("accepts only letters, digits, underscores and hyphens in node ids", () => {
    const graphWith = (id: string) => ({
      nodes: [{ id, kind: "trigger" }],
      edges: [],
    });
    expect(validateGraph(graphWith("start_1-a"))).toEqual([]);
    expect(validateGraph(graphWith("x".repeat(100)))).toEqual([]);
    for (const id of ["a\u2028b", "a\u2029b", "a b", "a.b", "x".repeat(101)]) {
      expect(validateGraph(graphWith(id))).toContain(
        "Every node has an id of 1 to 100 letters, digits, underscores or hyphens",
      );
    }
  });

  it("reports each problem", () => {
    expect(validateGraph(null)).toEqual([
      "A graph has a nodes array and an edges array",
    ]);
    expect(
      validateGraph({
        nodes: [
          { id: "", kind: "step" },
          { id: "a", kind: "trigger" },
          { id: "a", kind: "trigger" },
          { id: "b", kind: "teleport" },
          { id: "s", kind: "step" },
          { id: "z", kind: "sleep", config: { duration: "soon" } },
          { id: "c", kind: "condition" },
          { id: "p", kind: "approval" },
        ],
        edges: [
          { id: "x", source: "a", target: "nope" },
          { id: "y", source: "s", target: "z", branch: "true" },
          { id: "y", source: "p", target: "z", branch: "maybe" },
          { id: "w", source: "s", target: "a" },
        ],
      }),
    ).toEqual([
      "Every node has an id of 1 to 100 letters, digits, underscores or hyphens",
      "Node a appears twice",
      "Node b has an unknown kind",
      "Node s names no step",
      "Node z has no valid duration",
      "Node c has no valid condition",
      "A graph has exactly one trigger node",
      "Edge x joins a node that does not exist",
      "Edge y branches from a step node",
      "Edge y appears twice",
      'Edge y has a branch other than "true" or "false"',
      "Edge w leads into the trigger node",
    ]);
  });

  it("finds cycles", () => {
    const cyclic = {
      nodes: [
        { id: "t", kind: "trigger" },
        { id: "a", kind: "approval" },
        { id: "b", kind: "approval" },
      ],
      edges: [
        { id: "1", source: "t", target: "a" },
        { id: "2", source: "a", target: "b" },
        { id: "3", source: "b", target: "a" },
      ],
    };
    expect(validateGraph(cyclic)).toEqual(["The graph has a cycle"]);
    expect(topologicalOrder(graphOf(cyclic))).toBeUndefined();
  });
});

describe("graph parsing and diffs", () => {
  it("parses nodes and edges and drops what isn't one", () => {
    expect(
      nodeOf({
        id: "a",
        kind: "step",
        step: "s",
        label: "A",
        config: {},
        position: { x: 1, y: 2 },
      }),
    ).toEqual({
      id: "a",
      kind: "step",
      step: "s",
      label: "A",
      config: {},
      position: { x: 1, y: 2 },
    });
    expect(nodeOf({ id: "a", kind: "step", position: { x: "1" } })).toEqual({
      id: "a",
      kind: "step",
    });
    expect(nodeOf("a")).toBeUndefined();
    expect(edgeOf({ source: "a", target: "b", branch: "x" })).toEqual({
      id: "a->b",
      source: "a",
      target: "b",
    });
    expect(edgeOf({ source: "a" })).toBeUndefined();
    expect(edgeOf(1)).toBeUndefined();
    expect(
      graphOf({ nodes: [{ id: "a", kind: "trigger" }, 1], edges: "x" }),
    ).toEqual({
      nodes: [{ id: "a", kind: "trigger" }],
      edges: [],
    });
    expect(graphOf(undefined)).toEqual({ nodes: [], edges: [] });
  });

  it("diffs nodes by id and edges by their ends", () => {
    const after: WorkflowGraph = {
      nodes: [
        ...GRAPH.nodes
          .filter((node) => node.id !== "nudge")
          .map((node) =>
            node.id === "welcome"
              ? { ...node, config: { template: "vip" } }
              : node.id === "lookup"
                ? { ...node, position: { x: 9, y: 9 } }
                : node,
          ),
        { id: "log", kind: "step", step: "log" },
      ],
      edges: [
        ...GRAPH.edges.filter((edge) => edge.id !== "e7"),
        { id: "e8", source: "isPro", target: "log", branch: "false" },
      ],
    };
    expect(diffGraphs(GRAPH, after)).toEqual({
      nodes: { added: ["log"], removed: ["nudge"], changed: ["welcome"] },
      edges: { added: ["isPro->log:false"], removed: ["isPro->nudge:false"] },
    });
  });
});

describe("executeGraph", () => {
  it("follows the true branches through sleep and approval", async () => {
    const runtime = fakeRuntime("pro", { approved: true, by: "u1" });
    const results = await executeGraph(GRAPH, { email: "a@x.test" }, runtime);
    expect(runtime.log).toEqual([
      "step lookup crm.lookup {}",
      "sleep 7200000",
      "approval run-1:ok ok",
      'step welcome email.send {"template":"pro"}',
    ]);
    expect(results).toEqual({
      start: { email: "a@x.test" },
      lookup: { plan: "pro" },
      isPro: true,
      wait: null,
      ok: { approved: true, by: "u1" },
      welcome: null,
    });
    expect(approvalToken("k", "n")).toBe("k:n");
  });

  it("takes the false branches", async () => {
    const free = fakeRuntime("free", undefined);
    await executeGraph(GRAPH, {}, free);
    expect(free.log).toEqual([
      "step lookup crm.lookup {}",
      'step nudge email.send {"template":"free"}',
    ]);
    const rejected = fakeRuntime("pro", { approved: false });
    await executeGraph(GRAPH, {}, rejected);
    expect(rejected.log.at(-1)).toBe("step rejected slack.post {}");
  });

  it("refuses an invalid graph", async () => {
    await expect(
      executeGraph({ nodes: [], edges: [] }, {}, fakeRuntime("pro", undefined)),
    ).rejects.toThrow("exactly one trigger");
  });
});
