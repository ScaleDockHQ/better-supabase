import type {
  WorkflowGraph,
  WorkflowNodeKindRow,
} from "better-supabase/blocks/workflow-editor";

import { describe, expect, it } from "vitest";

import {
  autoLayout,
  buildPalette,
  copySelection,
  EMPTY_HISTORY,
  freshId,
  pasteClipboard,
  recordHistory,
  redoHistory,
  undoHistory,
  validateEditor,
} from "@/features/workflows/builder/editor-model";
import { nodeKinds } from "@/features/workflows/builder/node-kinds";
import { stepLibrary } from "@/features/workflows/builder/step-library";
import { workflowTemplates } from "@/features/workflows/builder/workflow-templates";

const kinds: readonly WorkflowNodeKindRow[] = nodeKinds.map(
  (kind): WorkflowNodeKindRow => ({
    kind: kind.kind,
    title: kind.title,
    description: kind.description,
    configSchema: kind.configSchema ?? {},
    branches: kind.branches ?? false,
  }),
);

const palette = buildPalette(stepLibrary, kinds);

const graph: WorkflowGraph = {
  nodes: [
    { id: "trigger", kind: "trigger", config: { trigger: "manual" } },
    { id: "a", kind: "delay", config: { seconds: 1 } },
    { id: "b", kind: "delay", config: { seconds: 1 } },
  ],
  edges: [
    { id: "e1", source: "trigger", target: "a" },
    { id: "e2", source: "a", target: "b" },
  ],
};

describe("editor model", () => {
  it("makes fresh ids", () => {
    expect(freshId("a", new Set(["a"]))).not.toBe("a");
    expect(freshId("z", new Set())).toBe("z");
  });

  it("undoes and redoes", () => {
    const next: WorkflowGraph = { nodes: [], edges: [] };
    const history = recordHistory(EMPTY_HISTORY, graph);
    const undone = undoHistory(history, next);

    expect(undone?.graph).toBe(graph);

    const redone = undone && redoHistory(undone.history, graph);

    expect(redone?.graph).toBe(next);
    expect(undoHistory(EMPTY_HISTORY, graph)).toBeUndefined();
  });

  it("lays nodes out top to bottom", () => {
    const placed = autoLayout(graph);
    const x = (id: string) => placed.get(id)?.y ?? Number.NaN;

    expect(x("trigger")).toBeLessThan(x("a"));
    expect(x("a")).toBeLessThan(x("b"));
  });

  it("copies the selection without the trigger and pastes fresh ids", () => {
    const clip = copySelection(graph, new Set(["trigger", "a", "b"]));

    expect(clip.nodes.map((node) => node.id)).toEqual(["a", "b"]);
    expect(clip.edges).toHaveLength(1);

    let n = 0;
    const pasted = pasteClipboard(clip, graph, () => `p${(n += 1)}`);
    const ids = new Set(graph.nodes.map((node) => node.id));

    expect(pasted.nodes.every((node) => !ids.has(node.id))).toBe(true);
    expect(pasted.edges).toHaveLength(1);
  });

  it("accepts every template", () => {
    for (const template of workflowTemplates) {
      const errors = validateEditor(
        template.graph,
        palette,
        stepLibrary,
        kinds,
      ).filter((issue) => issue.severity === "error");

      expect({ id: template.id, errors }).toEqual({
        id: template.id,
        errors: [],
      });
    }
  });

  it("warns about a node nothing reaches", () => {
    const issues = validateEditor(
      { ...graph, edges: [graph.edges[0]!] },
      palette,
      stepLibrary,
      kinds,
    );

    expect(issues.some((issue) => issue.node === "b")).toBe(true);
  });
});
