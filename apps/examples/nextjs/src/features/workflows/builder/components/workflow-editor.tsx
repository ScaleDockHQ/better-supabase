"use client";

import type { Connection } from "@xyflow/react";
import type {
  WorkflowGraph,
  WorkflowNodeRun,
} from "better-supabase/blocks/workflow-editor";
import type { DragEvent } from "react";

import {
  addEdge,
  Background,
  Controls,
  MiniMap,
  ReactFlow,
  ReactFlowProvider,
  useEdgesState,
  useNodesState,
  useReactFlow,
} from "@xyflow/react";
import "@xyflow/react/dist/style.css";
import { useAction, useErrorMessage } from "better-supabase/react";
import { useExtracted, useFormatter } from "next-intl";
import {
  useDeferredValue,
  useEffect,
  useEffectEvent,
  useMemo,
  useRef,
  useState,
} from "react";

import { Badge } from "@/components/reui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useWorkflowCanvasRun } from "@/hooks/use-workflow-editor";
import { useWorkflowRuns } from "@/hooks/use-workflows";
import { toast } from "@/lib/toast";

import type { BuilderDetail } from "../builder-queries";
import type { PaletteEntry } from "../editor-model";
import type { GraphFlowNode, GraphNodeData } from "./graph-node";

import { isFinished } from "../../workflow-labels";
import {
  completeHumanTask,
  decideNode,
  publishGraph,
  runDefinition,
  saveDraft,
  testRun,
} from "../builder-actions";
import {
  autoLayout,
  buildPalette,
  copySelection,
  defaultConfig,
  EMPTY_HISTORY,
  entryOf,
  freshId,
  pasteClipboard,
  pickerGroups,
  recordHistory,
  redoHistory,
  undoHistory,
  validateEditor,
} from "../editor-model";
import { parseStubs } from "../run-input";
import { EditorToolbar } from "./editor-toolbar";
import { fromFlow, nodeTypes, toFlow } from "./graph-node";
import { NodeInspector } from "./node-inspector";
import { NodePalette, PALETTE_DRAG } from "./node-palette";
import { ProblemsPanel } from "./problems-panel";
import { RunPanel } from "./run-panel";
import { VersionsPanel } from "./versions-panel";

const PANELS = ["node", "problems", "versions", "run"] as const;

type Panel = (typeof PANELS)[number];

const isPanel = (value: unknown): value is Panel =>
  PANELS.some((panel) => panel === value);

const shortId = () => crypto.randomUUID().slice(0, 8);

/** Edits inside an input, which the shortcuts leave alone. */
const typing = (target: EventTarget | null): boolean =>
  target instanceof HTMLElement &&
  (target.isContentEditable ||
    ["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName) ||
    target.closest("[role=dialog], [role=listbox], [role=menu]") !== null);

/**
 * The editor: a palette from the node kind registry, the graph on React Flow
 * with undo and redo, copy and paste, auto layout and a minimap, a panel for
 * the selected node, the validation problems, the version history and test runs
 * whose node states show on the canvas, live over `workflow-run:<id>`.
 */
function EditorInner({ detail }: { detail: BuilderDetail }) {
  const t = useExtracted("workflows");
  const format = useFormatter();
  const errorMessage = useErrorMessage();
  const flow = useReactFlow<GraphFlowNode>();
  const [initial] = useState(() => toFlow(detail.graph));

  const [nodes, setNodes, onNodesChange] = useNodesState<GraphFlowNode>(
    initial.nodes,
  );

  const [edges, setEdges, onEdgesChange] = useEdgesState(initial.edges);
  const [history, setHistory] = useState(EMPTY_HISTORY);

  const [saved, setSaved] = useState(() =>
    JSON.stringify(fromFlow(initial.nodes, initial.edges)),
  );

  const [panel, setPanel] = useState<Panel>("node");
  const [runId, setRunId] = useState<string | null>(null);
  const [input, setInput] = useState("");
  const [stubs, setStubs] = useState("");
  const clipboard = useRef<ReturnType<typeof copySelection> | null>(null);
  const lastEdit = useRef({ key: "", at: 0 });

  const definition = detail.definition.id;
  const graph = fromFlow(nodes, edges);
  const draft = { nodes: [...graph.nodes], edges: [...graph.edges] };
  const dirty = JSON.stringify(graph) !== saved;

  const palette = useMemo(
    () => buildPalette(detail.steps, detail.kinds),
    [detail.steps, detail.kinds],
  );

  const checked = useDeferredValue(graph);

  const issues = useMemo(
    () => validateEditor(checked, palette, detail.steps, detail.kinds),
    [checked, palette, detail.steps, detail.kinds],
  );

  const errorCount = issues.filter(
    (issue) => issue.severity === "error",
  ).length;

  const { runs } = useWorkflowRuns({
    tenant: detail.tenant,
    schema: "api",
    mode: "all",
    limit: 50,
  });

  const overlay = useWorkflowCanvasRun(runId, { schema: "api" });

  const options = (runs ?? [])
    .filter((run) => run.attributes["bsb.definition"] === definition)
    .map((run) => ({
      value: run.externalId,
      label: `${
        run.mode === "test" ? `${t("Test run")} · ` : ""
      }${format.dateTime(new Date(run.createdAt.epochMilliseconds), {
        timeStyle: "medium",
      })} · ${run.status}`,
    }));

  const onError = (error: Parameters<typeof errorMessage>[0]) => {
    toast.error(errorMessage(error));
  };

  const save = useAction(saveDraft, {
    onError,
    onSuccess: () => {
      toast.success(t("Draft saved"));
    },
  });

  const publish = useAction(publishGraph, {
    onError,
    onSuccess: (version) => {
      setSaved(JSON.stringify(graph));
      toast.success(
        t("Version {version} published", { version: String(version) }),
      );
    },
  });

  const run = useAction(runDefinition, {
    onError,
    onSuccess: (id) => {
      setRunId(id);
      setPanel("run");
    },
  });

  const test = useAction(testRun, {
    onError,
    onSuccess: (id) => {
      setRunId(id);
      setPanel("run");
    },
  });

  const decide = useAction(decideNode, { onError });
  const complete = useAction(completeHumanTask, { onError });

  // ----------------------------------------------------------- history

  /** Remembers the canvas before a change, so undo can go back to it. */
  const checkpoint = () => {
    setHistory((current) => recordHistory(current, graph));
  };

  const apply = (next: WorkflowGraph) => {
    const placed = toFlow(next);
    setNodes(placed.nodes);
    setEdges(placed.edges);
  };

  const undo = () => {
    const step = undoHistory(history, graph);

    if (step !== undefined) {
      setHistory(step.history);
      apply(step.graph);
    }
  };

  const redo = () => {
    const step = redoHistory(history, graph);

    if (step !== undefined) {
      setHistory(step.history);
      apply(step.graph);
    }
  };

  // ------------------------------------------------------------- edits

  const selectedNodes = nodes.filter((node) => node.selected);
  const selectedEdges = edges.filter((edge) => edge.selected);
  const current = selectedNodes.length === 1 ? selectedNodes[0] : undefined;

  const select = (id: string) => {
    setNodes((all) =>
      all.map((node) => ({ ...node, selected: node.id === id })),
    );
    setEdges((all) => all.map((edge) => ({ ...edge, selected: false })));
    setPanel("node");
    void flow.fitView({ nodes: [{ id }], duration: 200, maxZoom: 1.2 });
  };

  const addEntry = (
    entry: PaletteEntry,
    position?: { x: number; y: number },
  ) => {
    checkpoint();

    const id = freshId(
      entry.step ?? entry.kind,
      new Set(nodes.map((n) => n.id)),
    );

    const lowest = Math.max(-120, ...nodes.map((node) => node.position.y));

    const data: GraphNodeData = {
      kind: entry.kind,
      label: entry.title,
      config: defaultConfig(entry),
      step: entry.step,
    };

    setNodes((all) => [
      ...all.map((node) => ({ ...node, selected: false })),
      {
        id,
        type: "graph",
        position: position ?? { x: 0, y: lowest + 120 },
        selected: true,
        data,
      },
    ]);
    setPanel("node");
  };

  const editNode = (id: string, data: Partial<GraphNodeData>) => {
    const key = `${id}:${Object.keys(data).join(",")}`;
    const now = performance.now();

    // One undo step for a burst of typing in the same field.
    if (lastEdit.current.key !== key || now - lastEdit.current.at > 1000) {
      checkpoint();
    }

    lastEdit.current = { key, at: now };

    setNodes((all) =>
      all.map((node) =>
        node.id === id ? { ...node, data: { ...node.data, ...data } } : node,
      ),
    );
  };

  const removeNodes = (
    ids: ReadonlySet<string>,
    edgeIds: ReadonlySet<string>,
  ) => {
    const triggers = nodes.filter((node) => node.data.kind === "trigger");

    const removable = new Set(
      [...ids].filter(
        (id) =>
          nodes.find((node) => node.id === id)?.data.kind !== "trigger" ||
          triggers.length > 1,
      ),
    );

    if (removable.size === 0 && edgeIds.size === 0) {
      return;
    }

    checkpoint();
    setNodes((all) => all.filter((node) => !removable.has(node.id)));

    setEdges((all) =>
      all.filter(
        (edge) =>
          !edgeIds.has(edge.id) &&
          !removable.has(edge.source) &&
          !removable.has(edge.target),
      ),
    );
  };

  const removeSelected = () => {
    removeNodes(
      new Set(selectedNodes.map((node) => node.id)),
      new Set(selectedEdges.map((edge) => edge.id)),
    );
  };

  const copy = () => {
    clipboard.current = copySelection(
      graph,
      new Set(selectedNodes.map((node) => node.id)),
    );
  };

  const paste = () => {
    if (clipboard.current === null || clipboard.current.nodes.length === 0) {
      return;
    }

    checkpoint();

    const pasted = pasteClipboard(
      clipboard.current,
      graph,
      () => `e-${shortId()}`,
    );

    const placed = toFlow({ nodes: pasted.nodes, edges: pasted.edges });

    setNodes((all) => [
      ...all.map((node) => ({ ...node, selected: false })),
      ...placed.nodes.map((node) => ({ ...node, selected: true })),
    ]);
    setEdges((all) => [...all, ...placed.edges]);
  };

  const layout = () => {
    checkpoint();
    const positions = autoLayout(graph);

    setNodes((all) =>
      all.map((node) => ({
        ...node,
        position: positions.get(node.id) ?? node.position,
      })),
    );

    requestAnimationFrame(() => {
      void flow.fitView({ duration: 200 });
    });
  };

  const onConnect = (connection: Connection) => {
    checkpoint();

    setEdges((all) =>
      addEdge(
        connection.sourceHandle
          ? {
              ...connection,
              id: `e-${shortId()}`,
              label: connection.sourceHandle,
            }
          : { ...connection, id: `e-${shortId()}` },
        all,
      ),
    );
  };

  // --------------------------------------------------------- run, save

  const saveNow = () => {
    void save.run({ definition, graph: draft }).then((result) => {
      if (result.ok) {
        setSaved(JSON.stringify(graph));
      }
    });
  };

  const startTest = () => {
    const parsed = parseStubs(stubs);

    if (!parsed.ok) {
      toast.error(t("The test stubs are not a JSON object"));

      return;
    }

    // The test runs the draft the server holds, so the canvas is saved first.
    void save.run({ definition, graph: draft }).then((result) => {
      if (!result.ok) {
        return;
      }

      setSaved(JSON.stringify(graph));
      void test.run({ definition, text: input, stubs: parsed.stubs });
    });
  };

  const onKeyDown = useEffectEvent((event: KeyboardEvent) => {
    const meta = event.metaKey || event.ctrlKey;
    const key = event.key.toLowerCase();

    if (meta && key === "s") {
      event.preventDefault();
      saveNow();

      return;
    }

    if (typing(event.target)) {
      return;
    }

    if (meta && key === "z") {
      event.preventDefault();

      if (event.shiftKey) {
        redo();
      } else {
        undo();
      }
    } else if (meta && key === "y") {
      event.preventDefault();
      redo();
    } else if (meta && key === "c") {
      copy();
    } else if (meta && key === "v") {
      event.preventDefault();
      paste();
    } else if (meta && key === "d") {
      event.preventDefault();
      copy();
      paste();
    } else if (event.shiftKey && key === "l") {
      layout();
    } else if (key === "delete" || key === "backspace") {
      event.preventDefault();
      removeSelected();
    }
  });

  useEffect(() => {
    const listen = (event: KeyboardEvent) => {
      onKeyDown(event);
    };

    window.addEventListener("keydown", listen);

    return () => {
      window.removeEventListener("keydown", listen);
    };
  }, []);

  const onDrop = (event: DragEvent<HTMLDivElement>) => {
    const id = event.dataTransfer.getData(PALETTE_DRAG);
    const entry = palette.find((item) => item.id === id);

    if (entry === undefined) {
      return;
    }

    event.preventDefault();

    addEntry(
      entry,
      flow.screenToFlowPosition({ x: event.clientX, y: event.clientY }),
    );
  };

  // ----------------------------------------------------------- overlay

  const worst = new Map<string, "error" | "warning">();

  for (const issue of issues) {
    if (issue.node !== undefined && worst.get(issue.node) !== "error") {
      worst.set(issue.node, issue.severity);
    }
  }

  const shown = nodes.map((node) => {
    const entry = entryOf(palette, node.data);

    const status = runId === null ? undefined : overlay.nodes[node.id]?.status;
    const issue = worst.get(node.id);

    return {
      ...node,
      data: { ...node.data, branches: entry?.branches === true, status, issue },
    };
  });

  const result: WorkflowNodeRun | undefined =
    current === undefined || runId === null
      ? undefined
      : overlay.nodes[current.id];

  const runOpen = overlay.run !== undefined && !isFinished(overlay.run.status);

  return (
    <div className="flex flex-col gap-3">
      <EditorToolbar
        definition={definition}
        triggers={detail.triggers}
        credentials={detail.credentials}
        published={detail.published}
        graph={graph}
        errors={errorCount}
        dirty={dirty}
        canUndo={history.past.length > 0}
        canRedo={history.future.length > 0}
        saving={save.pending}
        publishing={publish.pending}
        onUndo={undo}
        onRedo={redo}
        onLayout={layout}
        onSave={saveNow}
        onPublish={() => {
          void publish.run({ definition, graph: draft });
        }}
      />
      <div className="flex flex-col gap-3 xl:flex-row">
        <NodePalette entries={palette} onAdd={addEntry} />
        <div
          className="h-150 min-w-0 flex-1 rounded-xl border bg-muted/30"
          data-testid="workflow-canvas"
        >
          <ReactFlow
            nodes={shown}
            edges={edges}
            nodeTypes={nodeTypes}
            onNodesChange={onNodesChange}
            onEdgesChange={onEdgesChange}
            onConnect={onConnect}
            isValidConnection={(connection) =>
              connection.source !== connection.target
            }
            onNodeDragStart={checkpoint}
            onDragOver={(event) => {
              event.preventDefault();
              event.dataTransfer.dropEffect = "move";
            }}
            onDrop={onDrop}
            deleteKeyCode={null}
            multiSelectionKeyCode="Shift"
            fitView
          >
            <Background />
            <Controls />
            <MiniMap pannable zoomable />
          </ReactFlow>
        </div>
        <aside className="w-full shrink-0 xl:w-80" aria-label={t("Inspector")}>
          <Tabs
            value={panel}
            onValueChange={(value) => {
              if (isPanel(value)) {
                setPanel(value);
              }
            }}
          >
            <TabsList className="w-full">
              <TabsTrigger value="node">{t("Node")}</TabsTrigger>
              <TabsTrigger value="problems">
                {t("Problems")}
                {issues.length === 0 ? null : (
                  <Badge
                    variant={
                      errorCount > 0 ? "destructive-light" : "warning-light"
                    }
                  >
                    {issues.length}
                  </Badge>
                )}
              </TabsTrigger>
              <TabsTrigger value="versions">{t("Versions")}</TabsTrigger>
              <TabsTrigger value="run">{t("Run")}</TabsTrigger>
            </TabsList>
            <div className="mt-3 max-h-140 overflow-y-auto pr-1">
              <TabsContent value="node">
                <NodeInspector
                  node={current}
                  entry={
                    current === undefined
                      ? undefined
                      : entryOf(palette, current.data)
                  }
                  context={{
                    steps: detail.steps,
                    definitions: detail.definitions,
                    credentials: detail.credentials,
                    credentialKind: undefined,
                    groups:
                      current === undefined
                        ? []
                        : pickerGroups(graph, current.id, detail.steps),
                  }}
                  result={result}
                  canDecide={runOpen}
                  onChange={editNode}
                  onRemove={(id) => {
                    removeNodes(new Set([id]), new Set());
                  }}
                  onDecide={(node, approved) => {
                    if (runId !== null) {
                      void decide.run({ run: runId, node, approved });
                    }
                  }}
                  onComplete={(node) => {
                    if (runId !== null) {
                      void complete.run({ run: runId, node });
                    }
                  }}
                />
              </TabsContent>
              <TabsContent value="problems">
                <ProblemsPanel issues={issues} onSelect={select} />
              </TabsContent>
              <TabsContent value="versions">
                <VersionsPanel
                  versions={detail.versions}
                  graph={graph}
                  onRestore={(version, restored) => {
                    checkpoint();
                    apply(restored);
                    setPanel("node");

                    toast.success(
                      t(
                        "Version {version} is on the canvas. Save to keep it as the draft.",
                        { version: String(version.version) },
                      ),
                    );
                  }}
                />
              </TabsContent>
              <TabsContent value="run">
                <RunPanel
                  input={input}
                  stubs={stubs}
                  published={detail.published !== null}
                  pending={run.pending || test.pending || save.pending}
                  options={options}
                  runId={runId}
                  run={overlay.run}
                  onInput={setInput}
                  onStubs={setStubs}
                  onRun={() => {
                    void run.run({ definition, text: input });
                  }}
                  onTest={startTest}
                  onPick={setRunId}
                />
              </TabsContent>
            </div>
          </Tabs>
        </aside>
      </div>
    </div>
  );
}

export function WorkflowEditor({ detail }: { detail: BuilderDetail }) {
  return (
    <ReactFlowProvider>
      <EditorInner detail={detail} />
    </ReactFlowProvider>
  );
}
